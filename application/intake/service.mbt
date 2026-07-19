///|
pub(all) struct IntakeDecisionRequest {
  packet_version : Int
  expected_provenance_digest : String
  decision : String
  actor : String
  actor_role : String
  note : String
  decided_at : String
  human_confirmed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectBindingRequest {
  packet_version : Int
  expected_provenance_digest : String
  project_id : String
  project_revision : Int
  bound_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct NeedsIntakeService {
  store : @store.AtomicStore
}

///|
pub suberror IntakeApplicationError {
  IntakeInvalid(String)
  IntakeConflict(String)
  IntakeNotFound(String)
  IntakeApprovalRequired(String)
} derive(Debug)

///|
pub fn NeedsIntakeService::new(root : String) -> NeedsIntakeService {
  { store: @store.AtomicStore::new(root, max_read_bytes=33554432) }
}

///|
fn sha256_text(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn portable_id(value : String) -> Bool {
  if value.length() < 3 || value.length() > 128 {
    return false
  }
  for char in value {
    match char {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' => ()
      _ => return false
    }
  }
  true
}

///|
fn intake_key(packet_id : String, packet_version : Int) -> String {
  "moonwiki-intake-" + packet_id + "-v" + packet_version.to_string() + ".json"
}

///|
fn decision_key(value : @intake_domain.IntakeDecision) -> String {
  "moonwiki-decision-" +
  value.packet_id +
  "-v" +
  value.packet_version.to_string() +
  "-" +
  value.decision_digest[7:31].to_owned() +
  ".json"
}

///|
fn binding_key(project_id : String) -> String {
  "moonwiki-binding-" + project_id + ".json"
}

///|
pub async fn NeedsIntakeService::import_packet(
  self : NeedsIntakeService,
  packet : @intake_domain.MoonWikiNeedsPacket,
  imported_at : String,
) -> @intake_domain.ImportedIntake {
  guard portable_id(packet.packet_id) && !imported_at.trim().is_empty() else {
    raise IntakeInvalid(
      "packet identity and import time must be portable and explicit",
    )
  }
  let validation = @intake_domain.validate_intake(packet)
  let record : @intake_domain.ImportedIntake = {
    contract: "mooncast.imported-needs-intake.v1",
    packet,
    validation,
    imported_at,
    immutable: true,
  }
  let key = intake_key(packet.packet_id, packet.packet_version)
  match self.store.get_json(key) {
    Some(existing) => {
      let prior : @intake_domain.ImportedIntake = @json.from_json(existing) catch {
        _ => raise IntakeConflict("stored intake is corrupt")
      }
      guard prior == record else {
        raise IntakeConflict(
          "packet id/version is already bound to different evidence",
        )
      }
      prior
    }
    None => {
      for existing in self.list_intakes() {
        if existing.packet.packet_id == packet.packet_id &&
          existing.packet.packet_version > packet.packet_version {
          raise IntakeConflict(
            "an older packet version cannot follow a newer immutable version",
          )
        }
      }
      ignore(self.store.put_json(key, record.to_json()))
      record
    }
  }
}

///|
pub async fn NeedsIntakeService::list_intakes(
  self : NeedsIntakeService,
) -> Array[@intake_domain.ImportedIntake] {
  let values : Array[@intake_domain.ImportedIntake] = []
  for key in self.store.list_keys(prefix="moonwiki-intake-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let record : @intake_domain.ImportedIntake = @json.from_json(value) catch {
          _ => continue
        }
        values.push(record)
      }
      None => ()
    }
  }
  values
}

///|
pub async fn NeedsIntakeService::get_intake(
  self : NeedsIntakeService,
  packet_id : String,
  packet_version? : Int,
) -> @intake_domain.ImportedIntake? {
  if !portable_id(packet_id) {
    return None
  }
  match packet_version {
    Some(version) =>
      match self.store.get_json(intake_key(packet_id, version)) {
        Some(value) => Some(@json.from_json(value))
        None => None
      }
    None => {
      let candidates = self
        .list_intakes()
        .filter(value => value.packet.packet_id == packet_id)
      if candidates.is_empty() {
        return None
      }
      let mut latest = candidates[0]
      for candidate in candidates {
        if candidate.packet.packet_version > latest.packet.packet_version {
          latest = candidate
        }
      }
      Some(latest)
    }
  }
}

///|
pub async fn NeedsIntakeService::record_decision(
  self : NeedsIntakeService,
  packet_id : String,
  request : IntakeDecisionRequest,
) -> @intake_domain.IntakeDecision {
  guard self.get_intake(packet_id, packet_version=request.packet_version)
    is Some(record) else {
    raise IntakeNotFound(packet_id)
  }
  guard record.validation.provenance_digest ==
    request.expected_provenance_digest else {
    raise IntakeConflict(
      "decision does not bind the exact displayed intake evidence",
    )
  }
  let digest = sha256_text(
    packet_id +
    ":" +
    request.packet_version.to_string() +
    ":" +
    request.expected_provenance_digest +
    ":" +
    request.decision +
    ":" +
    request.actor +
    ":" +
    request.actor_role +
    ":" +
    request.note +
    ":" +
    request.decided_at,
  )
  let decision : @intake_domain.IntakeDecision = {
    contract: "mooncast.needs-intake-decision.v1",
    packet_id,
    packet_version: request.packet_version,
    provenance_digest: request.expected_provenance_digest,
    decision: request.decision,
    actor: request.actor,
    actor_role: request.actor_role,
    note: request.note,
    decided_at: request.decided_at,
    human_confirmed: request.human_confirmed,
    decision_digest: digest,
    publication_authority: false,
    provider_execution_authority: false,
  }
  guard @intake_domain.decision_valid(record, decision) else {
    raise IntakeInvalid(
      "decision requires exact complete evidence and named-human confirmation",
    )
  }
  let key = decision_key(decision)
  match self.store.get_json(key) {
    Some(value) => {
      let prior : @intake_domain.IntakeDecision = @json.from_json(value) catch {
        _ => raise IntakeConflict("stored intake decision is corrupt")
      }
      guard prior == decision else {
        raise IntakeConflict(
          "decision identity conflicts with durable evidence",
        )
      }
      prior
    }
    None => {
      ignore(self.store.put_json(key, decision.to_json()))
      decision
    }
  }
}

///|
pub async fn NeedsIntakeService::list_decisions(
  self : NeedsIntakeService,
) -> Array[@intake_domain.IntakeDecision] {
  let values : Array[@intake_domain.IntakeDecision] = []
  for key in self.store.list_keys(prefix="moonwiki-decision-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let record : @intake_domain.IntakeDecision = @json.from_json(value) catch {
          _ => continue
        }
        values.push(record)
      }
      None => ()
    }
  }
  values
}

///|
pub async fn NeedsIntakeService::approved_decision(
  self : NeedsIntakeService,
  intake : @intake_domain.ImportedIntake,
) -> @intake_domain.IntakeDecision? {
  let candidates = self
    .list_decisions()
    .filter(value => {
      value.packet_id == intake.packet.packet_id &&
      value.packet_version == intake.packet.packet_version &&
      value.provenance_digest == intake.validation.provenance_digest
    })
  if candidates.is_empty() {
    return None
  }
  let mut latest = candidates[0]
  for candidate in candidates {
    if candidate.decided_at > latest.decided_at ||
      (
        candidate.decided_at == latest.decided_at &&
        candidate.decision_digest > latest.decision_digest
      ) {
      latest = candidate
    }
  }
  if latest.decision == "approve" {
    Some(latest)
  } else {
    None
  }
}

///|
pub async fn NeedsIntakeService::bind_intake_to_project(
  self : NeedsIntakeService,
  packet_id : String,
  request : ProjectBindingRequest,
) -> @intake_domain.ProjectIntakeBinding {
  guard portable_id(request.project_id) &&
    request.project_revision >= 0 &&
    !request.bound_at.trim().is_empty() else {
    raise IntakeInvalid("project binding identity is invalid")
  }
  guard self.get_intake(packet_id, packet_version=request.packet_version)
    is Some(record) else {
    raise IntakeNotFound(packet_id)
  }
  guard record.validation.provenance_digest ==
    request.expected_provenance_digest else {
    raise IntakeConflict("project binding does not match the exact intake")
  }
  guard self.approved_decision(record) is Some(approval) else {
    raise IntakeApprovalRequired("named-human intake approval is required")
  }
  let binding_id = "intake-binding-" +
    sha256_text(
      packet_id +
      ":" +
      request.packet_version.to_string() +
      ":" +
      request.project_id +
      ":" +
      request.project_revision.to_string() +
      ":" +
      approval.decision_digest,
    )[7:31].to_owned()
  let binding : @intake_domain.ProjectIntakeBinding = {
    contract: "mooncast.project-needs-intake-binding.v1",
    binding_id,
    project_id: request.project_id,
    project_revision: request.project_revision,
    intake_id: packet_id,
    intake_version: request.packet_version,
    intake_provenance_digest: record.validation.provenance_digest,
    approval_digest: approval.decision_digest,
    brief_intent_ref: record.packet.intent_refs.brief,
    bible_intent_ref: record.packet.intent_refs.bible,
    script_intent_ref: record.packet.intent_refs.script,
    bound_at: request.bound_at,
    publication_authority: false,
    provider_execution_authority: false,
    immutable: true,
  }
  let key = binding_key(request.project_id)
  match self.store.get_json(key) {
    Some(value) => {
      let prior : @intake_domain.ProjectIntakeBinding = @json.from_json(value) catch {
        _ => raise IntakeConflict("stored project intake binding is corrupt")
      }
      guard prior == binding else {
        raise IntakeConflict(
          "project is already bound to different intake evidence",
        )
      }
      prior
    }
    None => {
      ignore(self.store.put_json(key, binding.to_json()))
      binding
    }
  }
}

///|
pub async fn NeedsIntakeService::list_bindings(
  self : NeedsIntakeService,
) -> Array[@intake_domain.ProjectIntakeBinding] {
  let values : Array[@intake_domain.ProjectIntakeBinding] = []
  for key in self.store.list_keys(prefix="moonwiki-binding-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let record : @intake_domain.ProjectIntakeBinding = @json.from_json(
          value,
        ) catch {
          _ => continue
        }
        values.push(record)
      }
      None => ()
    }
  }
  values
}

///|
pub async fn NeedsIntakeService::workspace(
  self : NeedsIntakeService,
) -> @intake_domain.IntakeWorkspace {
  {
    contract: "mooncast.needs-intake-workspace.v1",
    intakes: self.list_intakes(),
    decisions: self.list_decisions(),
    bindings: self.list_bindings(),
    publication_authority: false,
    provider_execution_authority: false,
  }
}
