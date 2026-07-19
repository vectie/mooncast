/// Explicit native application contracts for the governed G3-G7 lifecycle.
/// These adapters only append canonical facts; they never execute providers,
/// publish content, or move money.

///|
struct RoutingPlanRecordInput {
  expected_project_revision : Int
  expected_plan_version : Int?
  expected_plan_digest : String?
  routes : Array[@governance.ModelRoute]
  total_cost_ceiling_cny : Double
  human_confirmed : Bool
  actor : String
} derive(FromJson)

///|
struct RoutingDecisionInput {
  expected_project_revision : Int
  expected_plan_version : Int
  expected_plan_digest : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  decision : String
  note : String
} derive(FromJson)

///|
struct GenerationAttemptInput {
  expected_project_revision : Int
  expected_routing_plan_version : Int
  expected_routing_plan_digest : String
  attempt_id : String
  route_id : String
  prompt_digest : String
  source_asset_digests : Array[String]
  seed : Int?
  cost_cny : Double
  output_digest : String
  status : String
  actor : String
} derive(FromJson)

///|
struct QcFindingInput {
  expected_project_revision : Int
  expected_attempt_digest : String
  expected_finding_version : Int?
  expected_finding_digest : String?
  status : String
  evidence_digest : String
  note : String
  reported_by : String
} derive(FromJson)

///|
struct QcDecisionInput {
  expected_project_revision : Int
  expected_attempt_digest : String
  expected_finding_version : Int
  expected_finding_digest : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  decision : String
  note : String
} derive(FromJson)

///|
struct MasterRecordInput {
  expected_project_revision : Int
  expected_master_version : Int?
  expected_master_digest : String?
  duration_seconds : Int
  video_digest : String
  audio_digest : String
  subtitle_digest : String
  provenance_digest : String
  ai_label : String
  human_confirmed : Bool
  actor : String
} derive(FromJson)

///|
struct MasterDecisionInput {
  expected_project_revision : Int
  expected_master_version : Int
  expected_master_digest : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  decision : String
  note : String
} derive(FromJson)

///|
struct DeliveryPackageRecordInput {
  expected_project_revision : Int
  expected_master_version : Int
  expected_master_digest : String
  expected_delivery_version : Int?
  expected_delivery_digest : String?
  destination_ids : Array[String]
  manifest_digest : String
  rights_ledger_digest : String
  human_confirmed : Bool
  actor : String
} derive(FromJson)

///|
struct DeliveryMilestoneInput {
  expected_project_revision : Int
  expected_delivery_version : Int
  expected_delivery_digest : String
  milestone : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  decision : String
  note : String
} derive(FromJson)

///|
struct PublicationAuthorizationInput {
  expected_project_revision : Int
  expected_delivery_version : Int
  expected_delivery_digest : String
  destination_id : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  decision : String
  scope : String
  expires_at : String?
  note : String
} derive(FromJson)

///|
struct PublicationObservationInput {
  expected_project_revision : Int
  expected_delivery_version : Int
  expected_delivery_digest : String
  destination_id : String
  receipt_digest : String
  external_effect_authority_ref : String
  observed_at : String?
  actor : String
} derive(FromJson)

///|
struct PerformanceMetricsInput {
  reach : Int
  completion_rate : Double
  conversion_rate : Double
} derive(ToJson, FromJson)

///|
struct PerformanceEconomicsInput {
  revenue_cny : Double
  provider_cost_cny : Double
  founder_hours : Double
} derive(ToJson, FromJson)

///|
struct PerformanceReviewInput {
  expected_project_revision : Int
  expected_delivery_version : Int
  expected_delivery_digest : String
  status : String
  evidence_digest : String
  metrics : PerformanceMetricsInput
  economics : PerformanceEconomicsInput
  repeat_purchase_status : String
  human_confirmed : Bool
  actor : String
  actor_role : String
  reviewed_at : String?
} derive(FromJson)

///|
fn governance_decision(value : String) -> String {
  match value {
    "approve" | "pass" | "authorize" => "approved"
    "reject" | "fail" | "deny" => "rejected"
    "request-revision" => "revision-requested"
    other => other
  }
}

///|
fn publication_decision(value : String) -> String {
  match value {
    "authorize" | "approved" => "authorized"
    "deny" | "rejected" => "denied"
    other => other
  }
}

///|
fn delivery_decision(value : String) -> String {
  match value {
    "approve" | "approved" | "accept" => "accepted"
    "reject" => "rejected"
    "request-revision" => "revision-requested"
    other => other
  }
}

///|
fn qc_dimension_from_path(value : String) -> @governance.QcDimension? {
  match value {
    "technical" => Some(Technical)
    "continuity" => Some(Continuity)
    "safety" => Some(Safety)
    "claims" => Some(Claims)
    "rights" => Some(Rights)
    _ => None
  }
}

///|
fn exact_ref(
  reference : @project.VersionRef,
  version : Int,
  digest : String,
) -> Bool {
  reference.version == version &&
  normalized_digest(reference.digest) == normalized_digest(digest)
}

///|
fn governance_command_id(kind : String, evidence : String) -> String {
  kind + "-" + sha256_text(kind + ":" + evidence)[:24].to_owned()
}

///|
fn gate_recorded(snapshot : @kernel.ProjectSnapshot, gate : String) -> Bool {
  snapshot.gate_receipts.any(item => item.gate.to_string() == gate)
}

///|
async fn StudioService::record_routing_plan_feature(
  self : StudioService,
  project_id : String,
  input : RoutingPlanRecordInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    gate_recorded(record.snapshot, "G2") else {
    raise Conflict(
      code="routing_project_conflict",
      message="routing plan must bind the exact project revision",
    )
  }
  let (id, version) = match record.snapshot.routing_plan {
    None => {
      guard input.expected_plan_version == None &&
        input.expected_plan_digest == None else {
        raise Conflict(
          code="routing_plan_conflict",
          message="no prior routing plan exists",
        )
      }
      (project_id + "-routing-plan", 1)
    }
    Some(current) => {
      guard input.expected_plan_version == Some(current.reference.version) &&
        input.expected_plan_digest is Some(digest) &&
        normalized_digest(digest) == normalized_digest(current.reference.digest) else {
        raise Conflict(
          code="routing_plan_conflict",
          message="routing revision must bind the exact current plan",
        )
      }
      (current.reference.id, current.reference.version + 1)
    }
  }
  let evidence = "sha256:" +
    sha256_text(
      project_id +
      ":" +
      version.to_string() +
      ":" +
      input.routes.to_json().stringify() +
      ":" +
      input.total_cost_ceiling_cny.to_string(),
    )
  let plan : @governance.ModelRoutingPlan = {
    reference: { id, version, digest: evidence },
    routes: input.routes,
    total_cost_ceiling_cny: input.total_cost_ceiling_cny,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("routing-plan", evidence),
      "record_routing_plan",
      now_string(),
      evidence,
    ),
    actor: Some(input.actor),
    role: Some("producer"),
    routing_plan: Some(plan),
  }
  self.apply_project_command(project_id, {
    expected_revision: input.expected_project_revision,
    command,
  })
}

///|
async fn StudioService::record_routing_decision_feature(
  self : StudioService,
  project_id : String,
  input : RoutingDecisionInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    (input.actor_role == "producer" || input.actor_role == "finance") &&
    record.snapshot.revision == input.expected_project_revision &&
    record.snapshot.routing_plan is Some(plan) &&
    exact_ref(
      plan.reference,
      input.expected_plan_version,
      input.expected_plan_digest,
    ) else {
    raise Conflict(
      code="routing_decision_conflict",
      message="decision must bind the current plan and an independent producer or finance reviewer",
    )
  }
  let other_role = if input.actor_role == "producer" {
    "finance"
  } else {
    "producer"
  }
  guard !record.snapshot.routing_decisions.any(item => {
    item.plan == plan.reference &&
    item.role == other_role &&
    item.actor == input.actor &&
    item.decision == "approved"
  }) else {
    raise Conflict(
      code="routing_review_not_independent",
      message="producer and finance approvals require different named reviewers",
    )
  }
  let decided_at = now_string()
  let decision_name = governance_decision(input.decision)
  let evidence = "sha256:" +
    sha256_text(
      plan.reference.digest +
      ":" +
      input.actor_role +
      ":" +
      input.actor +
      ":" +
      decision_name +
      ":" +
      input.note +
      ":" +
      decided_at,
    )
  let decision : @governance.RoutingDecision = {
    plan: plan.reference,
    decision: decision_name,
    actor: input.actor,
    role: input.actor_role,
    decided_at,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("routing-decision", evidence),
      "record_routing_decision",
      decided_at,
      evidence,
    ),
    actor: Some(decision.actor),
    role: Some(decision.role),
    routing_decision: Some(decision),
  }
  self.auto_advance_response(
    project_id,
    self.apply_project_command(project_id, {
      expected_revision: input.expected_project_revision,
      command,
    }),
    input.actor,
    input.actor_role,
    evidence,
  )
}

///|
async fn StudioService::record_generation_attempt_feature(
  self : StudioService,
  project_id : String,
  shot_id : String,
  input : GenerationAttemptInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.actor.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    record.snapshot.routing_plan is Some(plan) &&
    exact_ref(
      plan.reference,
      input.expected_routing_plan_version,
      input.expected_routing_plan_digest,
    ) &&
    gate_recorded(record.snapshot, "G3") &&
    @governance.routing_exact_approved(
      record.snapshot.routing_plan,
      record.snapshot.routing_decisions,
      record.snapshot.graph.maximum_budget_cny,
    ) &&
    @project.flattened_shots(record.snapshot.graph)
    .iter()
    .find_first(item => item.shot_id == shot_id)
    is Some(shot) else {
    raise Conflict(
      code="generation_attempt_conflict",
      message="attempt must bind the current route plan and shot",
    )
  }
  let previous = record.snapshot.generation_attempts.filter(item => {
    item.attempt.id == input.attempt_id
  })
  let version = if previous.is_empty() {
    1
  } else {
    previous[previous.length() - 1].attempt.version + 1
  }
  let evidence = "sha256:" +
    sha256_text(
      input.attempt_id +
      ":" +
      version.to_string() +
      ":" +
      shot_id +
      ":" +
      input.route_id +
      ":" +
      input.prompt_digest +
      ":" +
      input.output_digest +
      ":" +
      input.status,
    )
  let attempt : @governance.GenerationAttempt = {
    attempt: { id: input.attempt_id, version, digest: evidence },
    shot_id,
    route_id: input.route_id,
    route_plan: plan.reference,
    prompt_digest: input.prompt_digest,
    source_asset_digests: input.source_asset_digests,
    seed: input.seed,
    duration_ms: shot.duration_ms,
    cost_cny: input.cost_cny,
    output_digest: input.output_digest,
    status: input.status,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("generation-attempt", evidence),
      "record_generation_attempt",
      now_string(),
      evidence,
    ),
    actor: Some(input.actor),
    role: Some("provider-execution-host"),
    generation_attempt: Some(attempt),
  }
  self.apply_project_command(project_id, {
    expected_revision: input.expected_project_revision,
    command,
  })
}

///|
async fn StudioService::record_qc_finding_feature(
  self : StudioService,
  project_id : String,
  shot_id : String,
  dimension : @governance.QcDimension,
  input : QcFindingInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.reported_by.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    record.snapshot.generation_attempts
    .iter()
    .find_first(item => {
      item.shot_id == shot_id &&
      item.status == "succeeded" &&
      normalized_digest(item.output_digest) ==
      normalized_digest(input.expected_attempt_digest)
    })
    is Some(attempt) else {
    raise Conflict(
      code="qc_attempt_conflict",
      message="finding must bind a successful current shot output",
    )
  }
  let current = record.snapshot.qc_findings.filter(item => {
    item.shot_id == shot_id &&
    normalized_digest(item.attempt_digest) ==
    normalized_digest(attempt.output_digest) &&
    item.dimension == dimension
  })
  let (id, version) = if current.is_empty() {
    guard input.expected_finding_version == None &&
      input.expected_finding_digest == None else {
      raise Conflict(
        code="qc_finding_conflict",
        message="no previous finding exists",
      )
    }
    (
      project_id +
      "-" +
      shot_id +
      "-" +
      qc_dimension_name(dimension) +
      "-finding",
      1,
    )
  } else {
    let found = current[current.length() - 1]
    guard input.expected_finding_version == Some(found.finding.version) &&
      input.expected_finding_digest is Some(digest) &&
      exact_ref(found.finding, found.finding.version, digest) else {
      raise Conflict(
        code="qc_finding_conflict",
        message="finding revision must bind the exact current finding",
      )
    }
    (found.finding.id, found.finding.version + 1)
  }
  let evidence = if input.evidence_digest.trim() == "" {
    "sha256:" +
    sha256_text(
      shot_id +
      ":" +
      attempt.output_digest +
      ":" +
      qc_dimension_name(dimension) +
      ":" +
      input.status +
      ":" +
      input.note,
    )
  } else {
    input.evidence_digest
  }
  let finding_digest = "sha256:" +
    sha256_text(id + ":" + version.to_string() + ":" + evidence)
  let finding : @governance.QcFinding = {
    finding: { id, version, digest: finding_digest },
    shot_id,
    attempt_digest: attempt.output_digest,
    dimension,
    status: input.status,
    evidence_digest: evidence,
    note: input.note,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("qc-finding", finding_digest),
      "record_qc_finding",
      now_string(),
      evidence,
    ),
    actor: Some(input.reported_by),
    role: Some("qc-observer"),
    qc_finding: Some(finding),
  }
  self.apply_project_command(project_id, {
    expected_revision: input.expected_project_revision,
    command,
  })
}

///|
async fn StudioService::record_qc_decision_feature(
  self : StudioService,
  project_id : String,
  shot_id : String,
  dimension : @governance.QcDimension,
  input : QcDecisionInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  let findings = record.snapshot.qc_findings.filter(item => {
    item.shot_id == shot_id &&
    normalized_digest(item.attempt_digest) ==
    normalized_digest(input.expected_attempt_digest) &&
    item.dimension == dimension
  })
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    findings.length() > 0 else {
    raise Conflict(
      code="qc_decision_conflict",
      message="named independent QC decision must bind a current finding",
    )
  }
  let finding = findings[findings.length() - 1]
  guard exact_ref(
    finding.finding,
    input.expected_finding_version,
    input.expected_finding_digest,
  ) else {
    raise Conflict(
      code="qc_decision_conflict",
      message="QC finding changed before decision",
    )
  }
  let decided_at = now_string()
  let decision_name = governance_decision(input.decision)
  let evidence = "sha256:" +
    sha256_text(
      finding.finding.digest +
      ":" +
      input.actor +
      ":" +
      input.actor_role +
      ":" +
      decision_name +
      ":" +
      input.note,
    )
  let decision : @governance.QcDecision = {
    finding: finding.finding,
    decision: decision_name,
    actor: input.actor,
    role: input.actor_role,
    decided_at,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("qc-decision", evidence),
      "record_qc_decision",
      decided_at,
      evidence,
    ),
    actor: Some(input.actor),
    role: Some(input.actor_role),
    qc_decision: Some(decision),
  }
  self.auto_advance_response(
    project_id,
    self.apply_project_command(project_id, {
      expected_revision: input.expected_project_revision,
      command,
    }),
    input.actor,
    input.actor_role,
    evidence,
  )
}

///|
async fn StudioService::record_master_feature(
  self : StudioService,
  project_id : String,
  input : MasterRecordInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    gate_recorded(record.snapshot, "G4") else {
    raise Conflict(
      code="master_project_conflict",
      message="master must bind the exact project revision",
    )
  }
  let (id, version) = match record.snapshot.master {
    None => {
      guard input.expected_master_version == None &&
        input.expected_master_digest == None else {
        raise Conflict(
          code="master_conflict",
          message="no previous master exists",
        )
      }
      (project_id + "-master", 1)
    }
    Some(current) => {
      guard input.expected_master_version == Some(current.reference.version) &&
        input.expected_master_digest is Some(digest) &&
        exact_ref(current.reference, current.reference.version, digest) else {
        raise Conflict(
          code="master_conflict",
          message="master revision must bind the exact current master",
        )
      }
      (current.reference.id, current.reference.version + 1)
    }
  }
  let evidence = "sha256:" +
    sha256_text(
      input.video_digest +
      ":" +
      input.audio_digest +
      ":" +
      input.subtitle_digest +
      ":" +
      input.provenance_digest +
      ":" +
      input.ai_label +
      ":" +
      version.to_string(),
    )
  let master : @governance.Master = {
    reference: { id, version, digest: evidence },
    duration_seconds: input.duration_seconds,
    video_digest: input.video_digest,
    audio_digest: input.audio_digest,
    subtitle_digest: input.subtitle_digest,
    provenance_digest: input.provenance_digest,
    ai_label: input.ai_label,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("master", evidence),
      "record_master",
      now_string(),
      evidence,
    ),
    actor: Some(input.actor),
    role: Some("editorial-host"),
    master: Some(master),
  }
  self.apply_project_command(project_id, {
    expected_revision: input.expected_project_revision,
    command,
  })
}

///|
async fn StudioService::record_master_decision_feature(
  self : StudioService,
  project_id : String,
  kind : String,
  input : MasterDecisionInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    record.snapshot.master is Some(master) &&
    exact_ref(
      master.reference,
      input.expected_master_version,
      input.expected_master_digest,
    ) else {
    raise Conflict(
      code="master_decision_conflict",
      message="decision must bind the exact current master",
    )
  }
  let decided_at = now_string()
  let decision_name = governance_decision(input.decision)
  let evidence = "sha256:" +
    sha256_text(
      master.reference.digest +
      ":" +
      kind +
      ":" +
      input.actor +
      ":" +
      decision_name +
      ":" +
      input.note,
    )
  let decision : @governance.MasterDecision = {
    master: master.reference,
    kind,
    decision: decision_name,
    actor: input.actor,
    role: input.actor_role,
    decided_at,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("master-decision", evidence),
      "record_master_decision",
      decided_at,
      evidence,
    ),
    actor: Some(input.actor),
    role: Some(input.actor_role),
    master_decision: Some(decision),
  }
  self.auto_advance_response(
    project_id,
    self.apply_project_command(project_id, {
      expected_revision: input.expected_project_revision,
      command,
    }),
    input.actor,
    input.actor_role,
    evidence,
  )
}

///|
async fn StudioService::record_delivery_package_feature(
  self : StudioService,
  project_id : String,
  input : DeliveryPackageRecordInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.destination_ids.length() > 0 &&
    record.snapshot.revision == input.expected_project_revision &&
    record.snapshot.master is Some(master) &&
    exact_ref(
      master.reference,
      input.expected_master_version,
      input.expected_master_digest,
    ) else {
    raise Conflict(
      code="delivery_package_conflict",
      message="delivery package must bind an exact approved master",
    )
  }
  let (id, version) = match record.snapshot.delivery_package {
    None => {
      guard input.expected_delivery_version == None &&
        input.expected_delivery_digest == None else {
        raise Conflict(
          code="delivery_package_conflict",
          message="no previous delivery package exists",
        )
      }
      (project_id + "-delivery", 1)
    }
    Some(current) => {
      guard input.expected_delivery_version == Some(current.reference.version) &&
        input.expected_delivery_digest is Some(digest) &&
        exact_ref(current.reference, current.reference.version, digest) else {
        raise Conflict(
          code="delivery_package_conflict",
          message="delivery revision must bind the exact current package",
        )
      }
      (current.reference.id, current.reference.version + 1)
    }
  }
  let evidence = "sha256:" +
    sha256_text(
      master.reference.digest +
      ":" +
      input.destination_ids.join(":") +
      ":" +
      input.manifest_digest +
      ":" +
      input.rights_ledger_digest +
      ":" +
      version.to_string(),
    )
  let delivery : @governance.DeliveryPackage = {
    reference: { id, version, digest: evidence },
    master: master.reference,
    destination_ids: input.destination_ids,
    manifest_digest: input.manifest_digest,
    rights_ledger_digest: input.rights_ledger_digest,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("delivery-package", evidence),
      "record_delivery_package",
      now_string(),
      evidence,
    ),
    actor: Some(input.actor),
    role: Some("delivery-producer"),
    delivery_package: Some(delivery),
  }
  self.apply_project_command(project_id, {
    expected_revision: input.expected_project_revision,
    command,
  })
}

///|
async fn StudioService::record_delivery_milestone_feature(
  self : StudioService,
  project_id : String,
  input : DeliveryMilestoneInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    record.snapshot.delivery_package is Some(delivery) &&
    exact_ref(
      delivery.reference,
      input.expected_delivery_version,
      input.expected_delivery_digest,
    ) else {
    raise Conflict(
      code="delivery_acceptance_conflict",
      message="acceptance must bind the exact current delivery package",
    )
  }
  let decided_at = now_string()
  let decision_name = delivery_decision(input.decision)
  let evidence = "sha256:" +
    sha256_text(
      delivery.reference.digest +
      ":" +
      input.milestone +
      ":" +
      decision_name +
      ":" +
      input.actor +
      ":" +
      input.actor_role +
      ":" +
      input.note,
    )
  let acceptance : @governance.DeliveryAcceptance = {
    delivery_package: delivery.reference,
    milestone: input.milestone,
    decision: decision_name,
    actor: input.actor,
    decided_at,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("delivery-acceptance", evidence),
      "record_delivery_acceptance",
      decided_at,
      evidence,
    ),
    actor: Some(input.actor),
    role: Some(input.actor_role),
    delivery_acceptance: Some(acceptance),
  }
  self.auto_advance_response(
    project_id,
    self.apply_project_command(project_id, {
      expected_revision: input.expected_project_revision,
      command,
    }),
    input.actor,
    input.actor_role,
    evidence,
  )
}

///|
async fn StudioService::record_publication_authorization_feature(
  self : StudioService,
  project_id : String,
  input : PublicationAuthorizationInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    gate_recorded(record.snapshot, "G5") &&
    record.snapshot.delivery_package is Some(delivery) &&
    exact_ref(
      delivery.reference,
      input.expected_delivery_version,
      input.expected_delivery_digest,
    ) else {
    raise Conflict(
      code="publication_authorization_conflict",
      message="authorization must bind the exact delivery package and destination",
    )
  }
  let decided_at = now_string()
  let decision_name = publication_decision(input.decision)
  let evidence = "sha256:" +
    sha256_text(
      delivery.reference.digest +
      ":" +
      input.destination_id +
      ":" +
      decision_name +
      ":" +
      input.scope +
      ":" +
      input.expires_at.unwrap_or("") +
      ":" +
      input.actor +
      ":" +
      input.note,
    )
  let authorization : @governance.PublicationAuthorization = {
    delivery_package: delivery.reference,
    destination_id: input.destination_id,
    decision: decision_name,
    actor: input.actor,
    decided_at,
    external_effect_performed: false,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("publication-authorization", evidence),
      "record_publication_authorization",
      decided_at,
      evidence,
    ),
    actor: Some(input.actor),
    role: Some(input.actor_role),
    publication_authorization: Some(authorization),
  }
  self.auto_advance_response(
    project_id,
    self.apply_project_command(project_id, {
      expected_revision: input.expected_project_revision,
      command,
    }),
    input.actor,
    input.actor_role,
    evidence,
  )
}

///|
async fn StudioService::record_publication_observation_feature(
  self : StudioService,
  project_id : String,
  input : PublicationObservationInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.actor.trim() != "" &&
    input.receipt_digest.trim() != "" &&
    input.external_effect_authority_ref.has_prefix("authority:") &&
    record.snapshot.revision == input.expected_project_revision &&
    gate_recorded(record.snapshot, "G6") &&
    record.snapshot.delivery_package is Some(delivery) &&
    exact_ref(
      delivery.reference,
      input.expected_delivery_version,
      input.expected_delivery_digest,
    ) &&
    record.snapshot.publication_authorizations.any(item => {
      item.delivery_package == delivery.reference &&
      item.destination_id == input.destination_id &&
      item.decision == "authorized" &&
      !item.external_effect_performed
    }) else {
    raise Conflict(
      code="publication_observation_conflict",
      message="observation requires prior exact destination authorization and a separate host authority receipt",
    )
  }
  let observed_at = input.observed_at.unwrap_or(now_string())
  let evidence = "sha256:" +
    sha256_text(
      delivery.reference.digest +
      ":" +
      input.destination_id +
      ":" +
      input.receipt_digest +
      ":" +
      input.external_effect_authority_ref +
      ":" +
      input.actor +
      ":" +
      observed_at,
    )
  let observation : @governance.PublicationObservation = {
    delivery_package: delivery.reference,
    destination_id: input.destination_id,
    receipt_digest: input.receipt_digest,
    observed_at,
    external_effect_performed_by_host: true,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("publication-observation", evidence),
      "record_publication_observation",
      observed_at,
      evidence,
    ),
    actor: Some(input.actor),
    role: Some("publication-observer"),
    publication_observation: Some(observation),
  }
  self.apply_project_command(project_id, {
    expected_revision: input.expected_project_revision,
    command,
  })
}

///|
async fn StudioService::record_performance_review_feature(
  self : StudioService,
  project_id : String,
  input : PerformanceReviewInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    gate_recorded(record.snapshot, "G6") &&
    record.snapshot.delivery_package is Some(delivery) &&
    exact_ref(
      delivery.reference,
      input.expected_delivery_version,
      input.expected_delivery_digest,
    ) else {
    raise Conflict(
      code="performance_review_conflict",
      message="review must bind the exact delivered package",
    )
  }
  let reviewed_at = input.reviewed_at.unwrap_or(now_string())
  let evidence = if input.evidence_digest.trim() == "" {
    "sha256:" +
    sha256_text(
      delivery.reference.digest +
      ":" +
      input.status +
      ":" +
      input.metrics.to_json().stringify() +
      ":" +
      input.economics.to_json().stringify() +
      ":" +
      input.repeat_purchase_status,
    )
  } else {
    input.evidence_digest
  }
  let review : @governance.PerformanceReview = {
    delivery_package: delivery.reference,
    status: input.status,
    evidence_digest: evidence,
    reach: input.metrics.reach,
    completion_rate: input.metrics.completion_rate,
    conversion_rate: input.metrics.conversion_rate,
    revenue_cny: input.economics.revenue_cny,
    provider_cost_cny: input.economics.provider_cost_cny,
    founder_hours: input.economics.founder_hours,
    repeat_purchase_status: input.repeat_purchase_status,
    actor: input.actor,
    reviewed_at,
  }
  let command = {
    ..base_command(
      record.snapshot,
      governance_command_id("performance-review", evidence),
      "record_performance_review",
      reviewed_at,
      evidence,
    ),
    actor: Some(input.actor),
    role: Some(input.actor_role),
    performance_review: Some(review),
  }
  self.auto_advance_response(
    project_id,
    self.apply_project_command(project_id, {
      expected_revision: input.expected_project_revision,
      command,
    }),
    input.actor,
    input.actor_role,
    evidence,
  )
}

///|
pub async fn StudioService::governance_stage_projection(
  self : StudioService,
  project_id : String,
  stage : String,
) -> Json {
  let record = self.get_project(project_id)
  let snapshot = record.snapshot
  let payload = match stage {
    "G3" =>
      Json::object({
        "routing_plan": snapshot.routing_plan.to_json(),
        "producer_decisions": snapshot.routing_decisions
        .filter(item => item.role == "producer")
        .to_json(),
        "finance_decisions": snapshot.routing_decisions
        .filter(item => item.role == "finance")
        .to_json(),
        "ready": @governance.routing_exact_approved(
          snapshot.routing_plan,
          snapshot.routing_decisions,
          snapshot.graph.maximum_budget_cny,
        ).to_json(),
        "external_effect_performed": false.to_json(),
      })
    "G4" =>
      Json::object({
        "generation_attempts": snapshot.generation_attempts.to_json(),
        "findings": snapshot.qc_findings.to_json(),
        "independent_decisions": snapshot.qc_decisions.to_json(),
        "ready": @project.flattened_shots(snapshot.graph)
        .all(shot => {
          @governance.shot_passes_qc(
            shot.shot_id,
            snapshot.generation_attempts,
            snapshot.qc_findings,
            snapshot.qc_decisions,
          )
        })
        .to_json(),
        "provider_execution_authority": false.to_json(),
        "publication_authority": false.to_json(),
      })
    "G5" =>
      Json::object({
        "master": snapshot.master.to_json(),
        "technical_creative_rights_client_decisions": snapshot.master_decisions.to_json(),
        "delivery_package": snapshot.delivery_package.to_json(),
        "delivery_acceptances": snapshot.delivery_acceptances.to_json(),
        "delivery_builds": self.delivery_application.list(project_id).to_json(),
        "master_ready": @governance.master_exact_approved(
          snapshot.master,
          snapshot.master_decisions,
        ).to_json(),
        "ready": @governance.delivery_exact_accepted(
          snapshot.delivery_package,
          snapshot.master,
          snapshot.delivery_acceptances,
        ).to_json(),
        "publication_authority": false.to_json(),
      })
    "G6" =>
      Json::object({
        "destination_authorizations": snapshot.publication_authorizations.to_json(),
        "publication_observations": snapshot.publication_observations.to_json(),
        "ready": @governance.publication_exact_authorized(
          snapshot.delivery_package,
          snapshot.publication_authorizations,
        ).to_json(),
        "external_effect_performed": false.to_json(),
        "publication_requires_separate_host_authority": true.to_json(),
      })
    "G7" =>
      Json::object({
        "publication_observations": snapshot.publication_observations.to_json(),
        "performance_reviews": snapshot.performance_reviews.to_json(),
        "ready": @governance.performance_current(
          snapshot.delivery_package,
          snapshot.performance_reviews,
        ).to_json(),
        "economics": if snapshot.performance_reviews.is_empty() {
          Json::null()
        } else {
          let review = snapshot.performance_reviews[snapshot.performance_reviews.length() -
            1]
          Json::object({
            "revenue_cny": review.revenue_cny.to_json(),
            "provider_cost_cny": review.provider_cost_cny.to_json(),
            "gross_margin_cny": (review.revenue_cny - review.provider_cost_cny).to_json(),
            "founder_hours": review.founder_hours.to_json(),
            "repeat_purchase_status": review.repeat_purchase_status.to_json(),
          })
        },
        "external_effect_performed": false.to_json(),
      })
    _ => raise NotFound(entity="governance_stage", id=stage)
  }
  Json::object({
    "contract": "mooncast.governance-stage-projection.v1".to_json(),
    "project_id": project_id.to_json(),
    "project_revision": snapshot.revision.to_json(),
    "stage": stage.to_json(),
    "payload": payload,
    "authority": Json::object({
      "provider_execution": false.to_json(),
      "publication": false.to_json(),
      "payment": false.to_json(),
    }),
  })
}
