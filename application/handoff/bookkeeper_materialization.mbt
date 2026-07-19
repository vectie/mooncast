///|
fn bookkeeper_reference(
  id : String,
  version : String,
  payload : Json,
) -> @handoff_domain.BookkeeperRecordReference {
  {
    record_id: id,
    record_version: version,
    record_digest: canonical_record_digest(payload),
  }
}

///|
fn bookkeeper_evidence(
  references : ArrayView[@handoff_domain.RecordRef],
) -> Array[@handoff_domain.BookkeeperEvidenceReference] {
  references.map(reference => {
    reference_id: reference.record_id,
    reference_version: reference.record_version,
    digest: reference.record_digest,
    provenance_ref: reference.provenance_ref,
  })
}

///|
fn handoff_authority_ref(
  request : @handoff_domain.ExternalHandoffRequest,
) -> String {
  match request.authority_request_ref {
    Some(reference) => reference.record_id
    None => "mooncast.handoff:" + request.record.record_id
  }
}

///|
fn envelope_payload(
  request : @handoff_domain.ExternalHandoffRequest,
  subject : @handoff_domain.BookkeeperRecordReference,
) -> Json {
  {
    "contract_version": "moonflow.pack-handoff.v1",
    "source_request": request.to_json(),
    "subject": subject.to_json(),
  }
}

///|
fn ingress_bundle(
  request : @handoff_domain.ExternalHandoffRequest,
  record : @handoff_domain.BookkeeperDurableRecord,
  message_kind : String,
) -> @handoff_domain.BookkeeperIngressBundle {
  let payload = envelope_payload(request, record.record)
  let envelope_reference = bookkeeper_reference(
    "mooncast-envelope-" + request.record.record_id,
    request.record.record_version,
    payload,
  )
  let envelope : @handoff_domain.BookkeeperTransportEnvelope = {
    contract_version: "moonbook.bookkeeper.transport.v1",
    envelope: envelope_reference,
    direction: "Ingress",
    source_product: "mooncast",
    destination_product: "moonbook",
    message_kind,
    subject: record.record,
    links: record.links.copy(),
    evidence_refs: record.evidence_refs.copy(),
    authority_ref: handoff_authority_ref(request),
    recorded_at: record.recorded_at,
    payload,
    external_activation_allowed: false,
    side_effects_applied: false,
  }
  {
    contract: "mooncast.bookkeeper-ingress-bundle.v1",
    request_ref: request.record,
    record,
    envelope,
    post_order: ["/api/bookkeeper/records", "/api/bookkeeper/envelopes/ingress"],
  }
}

///|
pub fn final_deliverable_bookkeeper_bundle(
  request : @handoff_domain.ExternalHandoffRequest,
  evidence : @handoff_domain.FinalDeliverableEvidence,
) -> @handoff_domain.BookkeeperIngressBundle? {
  guard @handoff_domain.external_handoff_request_valid(request) &&
    @handoff_domain.final_deliverable_evidence_valid(evidence) &&
    request.record_kind == "PackDeliverableCandidateV1" &&
    request.subject_ref == evidence.record else {
    return None
  }
  let payload : Json = {
    "contract_version": "moonbook.bookkeeper.v1",
    "source_contract": evidence.contract,
    "source_record": evidence.record.to_json(),
    "mooncast_evidence": evidence.to_json(),
  }
  let reference = bookkeeper_reference(
    "mooncast-deliverable-" + evidence.record.record_id,
    evidence.record.record_version,
    payload,
  )
  let record : @handoff_domain.BookkeeperDurableRecord = {
    contract_version: "moonbook.bookkeeper.store.v1",
    record: reference,
    stage: "DeliverableAcceptance",
    subject: None,
    links: [],
    title: "Mooncast final deliverable",
    summary: "Guarded Mooncast final-deliverable evidence awaiting named human review.",
    owner_route: "moonbook.bookkeeper",
    status: "awaiting_review",
    evidence_refs: bookkeeper_evidence(request.evidence_refs),
    issue_refs: [],
    requires_human_review: true,
    next_action: "review deliverable acceptance",
    source_product: "mooncast",
    recorded_at: 0,
    payload,
    side_effects_applied: false,
  }
  Some(ingress_bundle(request, record, "deliverable.candidate"))
}

///|
pub fn outcome_bookkeeper_bundle(
  request : @handoff_domain.ExternalHandoffRequest,
  outcome : @handoff_domain.ProductionOutcomeEvidence,
  deliverable : @handoff_domain.FinalDeliverableEvidence,
) -> @handoff_domain.BookkeeperIngressBundle? {
  guard @handoff_domain.external_handoff_request_valid(request) &&
    @handoff_domain.production_outcome_evidence_valid(outcome) &&
    @handoff_domain.final_deliverable_evidence_valid(deliverable) &&
    request.record_kind == "PackOutcomeObservationV1" &&
    request.subject_ref == outcome.record &&
    outcome.final_deliverable_ref == deliverable.record else {
    return None
  }
  let deliverable_payload : Json = {
    "contract_version": "moonbook.bookkeeper.v1",
    "source_contract": deliverable.contract,
    "source_record": deliverable.record.to_json(),
    "mooncast_evidence": deliverable.to_json(),
  }
  let deliverable_reference = bookkeeper_reference(
    "mooncast-deliverable-" + deliverable.record.record_id,
    deliverable.record.record_version,
    deliverable_payload,
  )
  let payload : Json = {
    "contract_version": "moonbook.bookkeeper.three_gap.v1",
    "source_contract": outcome.contract,
    "source_record": outcome.record.to_json(),
    "mooncast_outcome": outcome.to_json(),
    "handoff_request": request.to_json(),
    "accepted_deliverable_ref": deliverable_reference.to_json(),
  }
  let reference = bookkeeper_reference(
    "mooncast-outcome-" + outcome.record.record_id,
    outcome.record.record_version,
    payload,
  )
  let record : @handoff_domain.BookkeeperDurableRecord = {
    contract_version: "moonbook.bookkeeper.store.v1",
    record: reference,
    stage: "OutcomeBinding",
    subject: Some(deliverable_reference),
    links: [deliverable_reference],
    title: "Mooncast production outcome",
    summary: "Mooncast outcome evidence bound to an exact reviewed deliverable.",
    owner_route: "moonbook.bookkeeper",
    status: "awaiting_binding",
    evidence_refs: bookkeeper_evidence(request.evidence_refs),
    issue_refs: [],
    requires_human_review: false,
    next_action: "assess Three-Gap findings",
    source_product: "mooncast",
    recorded_at: 0,
    payload,
    side_effects_applied: false,
  }
  Some(ingress_bundle(request, record, "outcome.observation"))
}
