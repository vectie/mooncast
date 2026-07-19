///|
fn sha256_text(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn text_present(value : String) -> Bool {
  !value.trim().is_empty()
}

///|
fn digest_valid(value : String) -> Bool {
  value.has_prefix("sha256:") && value.length() == 71
}

///|
pub fn evidence_ref_valid(value : MoonWikiEvidenceRef) -> Bool {
  text_present(value.source_id) &&
  text_present(value.source_version) &&
  digest_valid(value.source_digest) &&
  text_present(value.provenance_ref)
}

///|
fn exact_evidence_member(
  values : ArrayView[MoonWikiEvidenceRef],
  expected : MoonWikiEvidenceRef,
) -> Bool {
  values.filter(value => value == expected).length() == 1
}

///|
fn duplicate_evidence(values : ArrayView[MoonWikiEvidenceRef]) -> Bool {
  for index = 0; index < values.length(); index = index + 1 {
    for other = index + 1; other < values.length(); other = other + 1 {
      if values[index].source_id == values[other].source_id &&
        values[index].source_version == values[other].source_version {
        return true
      }
    }
  }
  false
}

///|
pub fn intake_provenance_digest(packet : MoonWikiNeedsPacket) -> String {
  sha256_text(packet.to_json().stringify())
}

///|
fn require_text(errors : Array[String], label : String, value : String) -> Unit {
  if !text_present(value) {
    errors.push(label + " is required")
  }
}

///|
fn require_items(
  errors : Array[String],
  label : String,
  values : ArrayView[String],
) -> Unit {
  if values.is_empty() || values.any(value => !text_present(value)) {
    errors.push(label + " requires non-empty values")
  }
}

///|
pub fn validate_intake(packet : MoonWikiNeedsPacket) -> IntakeValidation {
  let errors : Array[String] = []
  if packet.contract != "moonwiki.mooncast-needs-export.v1" {
    errors.push("unsupported MoonWiki export contract")
  }
  require_text(errors, "packet_id", packet.packet_id)
  if packet.packet_version < 1 {
    errors.push("packet_version must be positive")
  }
  require_text(errors, "exported_at", packet.exported_at)
  if packet.evidence_refs.is_empty() ||
    packet.evidence_refs.any(value => !evidence_ref_valid(value)) {
    errors.push(
      "every evidence reference requires exact id, version, sha256 digest, and provenance",
    )
  }
  if duplicate_evidence(packet.evidence_refs) {
    errors.push("evidence id/version pairs must be unique")
  }
  for
    intent in [
      packet.intent_refs.brief,
      packet.intent_refs.bible,
      packet.intent_refs.script,
    ] {
    if !evidence_ref_valid(intent) ||
      !exact_evidence_member(packet.evidence_refs, intent) {
      errors.push(
        "brief, bible, and script intents must each copy one exact packet evidence reference",
      )
      break
    }
  }
  require_text(errors, "customer", packet.client_need.customer)
  require_text(errors, "payable_problem", packet.client_need.payable_problem)
  require_text(errors, "audience", packet.client_need.audience)
  require_items(errors, "channels", packet.client_need.channels)
  require_text(
    errors,
    "acceptance_method",
    packet.client_need.acceptance_method,
  )
  require_text(
    errors,
    "repeat_purchase_hypothesis",
    packet.client_need.repeat_purchase_hypothesis,
  )
  require_text(errors, "contract_ref", packet.contract_boundary.contract_ref)
  if packet.contract_boundary.budget_ceiling_cny <= 0.0 {
    errors.push("budget_ceiling_cny must be positive")
  }
  if packet.contract_boundary.revision_limit < 0 ||
    packet.contract_boundary.revision_limit > 2 {
    errors.push("revision_limit must be between zero and two")
  }
  if packet.contract_boundary.target_duration_seconds < 180 ||
    packet.contract_boundary.target_duration_seconds > 480 {
    errors.push("target_duration_seconds must be between 180 and 480")
  }
  require_items(errors, "deliverables", packet.contract_boundary.deliverables)
  require_items(
    errors,
    "payment_milestones",
    packet.contract_boundary.payment_milestones,
  )
  require_text(errors, "rights_owner", packet.constraints.rights_owner)
  if !packet.constraints.rights_confirmed {
    errors.push("rights ownership must be explicitly confirmed")
  }
  require_items(
    errors,
    "rights_constraints",
    packet.constraints.rights_constraints,
  )
  require_text(
    errors,
    "confidentiality_class",
    packet.constraints.confidentiality_class,
  )
  require_text(
    errors,
    "permitted_data_class",
    packet.constraints.permitted_data_class,
  )
  require_text(errors, "project_title", packet.creative_strategy.project_title)
  require_text(errors, "objective", packet.creative_strategy.objective)
  require_text(
    errors,
    "narrative_proposition",
    packet.creative_strategy.narrative_proposition,
  )
  require_text(errors, "tone", packet.creative_strategy.tone)
  require_items(
    errors,
    "success_metrics",
    packet.creative_strategy.success_metrics,
  )
  if packet.publication_authority || packet.provider_execution_authority {
    errors.push(
      "MoonWiki intake cannot grant publication or provider execution authority",
    )
  }
  {
    contract: "mooncast.needs-intake-validation.v1",
    complete: errors.is_empty() && packet.unresolved_questions.is_empty(),
    errors,
    unresolved_questions: packet.unresolved_questions.copy(),
    provenance_digest: intake_provenance_digest(packet),
  }
}

///|
pub fn decision_valid(
  intake : ImportedIntake,
  decision : IntakeDecision,
) -> Bool {
  decision.contract == "mooncast.needs-intake-decision.v1" &&
  decision.packet_id == intake.packet.packet_id &&
  decision.packet_version == intake.packet.packet_version &&
  decision.provenance_digest == intake.validation.provenance_digest &&
  (decision.decision == "approve" || decision.decision == "reject") &&
  text_present(decision.actor) &&
  text_present(decision.actor_role) &&
  text_present(decision.decided_at) &&
  decision.human_confirmed &&
  !decision.decision_digest.is_empty() &&
  !decision.publication_authority &&
  !decision.provider_execution_authority &&
  (decision.decision != "approve" || intake.validation.complete)
}
