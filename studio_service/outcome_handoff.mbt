///|
/// Explicit Studio command for preparing the post-delivery operating evidence
/// outbox. The command records no acceptance, invokes no agent runtime and
/// performs no MoonFlow, Bookkeeper, publication or payment side effect.
struct OutcomeHandoffPrepareInput {
  expected_project_revision : Int
  final_deliverable_record_id : String
  human_confirmed : Bool
  actor : String
  actor_role : String
} derive(FromJson)

///|
struct OutcomeHandoffPrepareProjection {
  outcome : @handoff.ProductionOutcomeEvidence
  request : @handoff.ExternalHandoffRequest
  bookkeeper_ingress_bundle : @handoff.BookkeeperIngressBundle
  outcome_created : Bool
  request_created : Bool
  publication_authority : Bool
  payment_authority : Bool
  external_effect_authorized : Bool
} derive(ToJson)

///|
async fn StudioService::final_deliverable_matches_accepted_project(
  self : StudioService,
  project_id : String,
  evidence : @handoff.FinalDeliverableEvidence,
) -> Bool {
  let canonical = self.get_project(project_id)
  guard evidence.project_id == project_id &&
    canonical.snapshot.master is Some(master) &&
    canonical.snapshot.delivery_package is Some(delivery) &&
    gate_recorded(canonical.snapshot, "G5") &&
    @governance.master_exact_approved(
      canonical.snapshot.master,
      canonical.snapshot.master_decisions,
    ) &&
    @governance.delivery_exact_accepted(
      canonical.snapshot.delivery_package,
      canonical.snapshot.master,
      canonical.snapshot.delivery_acceptances,
    ) &&
    normalized_digest(evidence.editor_output_digest) ==
    normalized_digest(master.video_digest) &&
    evidence.duration_seconds ==
    canonical.snapshot.graph.target_duration_seconds else {
    return false
  }
  let commerce = self.commerce_application.load()
  for build in self.delivery_application.list(project_id) {
    if build.state == "completed" &&
      normalized_digest(build.master_sha256) ==
      normalized_digest(master.video_digest) &&
      build.delivery_version == delivery.reference.version &&
      normalized_digest(build.delivery_digest) ==
      normalized_digest(delivery.reference.digest) &&
      self.delivery_application.acceptance(build.build_id) is Some(acceptance) &&
      acceptance.acceptance.decision == "accept" &&
      acceptance.acceptance.actor_role == "client" &&
      commerce.portals.any(portal => {
        portal.project_id == project_id &&
        portal.build_id == build.build_id &&
        portal.decisions.any(decision => decision.decision == "accept")
      }) {
      return true
    }
  }
  false
}

///|
async fn StudioService::outcome_handoff_projection(
  self : StudioService,
  project_id : String,
) -> Json {
  let candidates : Array[@handoff.FinalDeliverableEvidence] = []
  for evidence in self.handoff_outbox.list_final_deliverable_evidence() {
    if evidence.project_id == project_id &&
      self.final_deliverable_matches_accepted_project(project_id, evidence) {
      candidates.push(evidence)
    }
  }
  let outcomes = self.handoff_outbox
    .list_production_outcome_evidence()
    .filter(outcome => {
      candidates.any(candidate => {
        candidate.record == outcome.final_deliverable_ref
      })
    })
  let requests = self.handoff_outbox
    .list_external_handoff_requests()
    .filter(request => {
      request.record_kind == "PackOutcomeObservationV1" &&
      outcomes.any(outcome => outcome.record == request.subject_ref)
    })
  Json::object({
    "contract": "mooncast.studio-outcome-handoff.v1".to_json(),
    "eligible_final_deliverables": candidates.to_json(),
    "production_outcomes": outcomes.to_json(),
    "external_handoff_requests": requests.to_json(),
    "publication_authority": false.to_json(),
    "payment_authority": false.to_json(),
    "external_effect_authorized": false.to_json(),
  })
}

///|
async fn StudioService::prepare_production_outcome_handoff(
  self : StudioService,
  project_id : String,
  input : OutcomeHandoffPrepareInput,
) -> OutcomeHandoffPrepareProjection {
  let canonical = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    canonical.snapshot.revision == input.expected_project_revision &&
    gate_recorded(canonical.snapshot, "G7") &&
    canonical.snapshot.delivery_package is Some(delivery) &&
    !canonical.snapshot.performance_reviews.is_empty() else {
    raise Conflict(
      code="outcome_handoff_not_ready",
      message="G7 operating evidence must be recorded for the exact current project revision",
    )
  }
  let matches = self.handoff_outbox
    .list_final_deliverable_evidence()
    .filter(item => item.record.record_id == input.final_deliverable_record_id)
  guard matches.length() == 1 else {
    raise Conflict(
      code="final_deliverable_evidence_not_found",
      message="select one immutable final-deliverable evidence record",
    )
  }
  let deliverable_evidence = matches[0]
  guard self.final_deliverable_matches_accepted_project(
    project_id, deliverable_evidence,
  ) else {
    raise Conflict(
      code="final_deliverable_not_accepted",
      message="outcome evidence must bind the exact client-accepted final deliverable",
    )
  }
  let performance = canonical.snapshot.performance_reviews[canonical.snapshot.performance_reviews.length() -
    1]
  guard performance.delivery_package == delivery.reference else {
    raise Conflict(
      code="performance_delivery_conflict",
      message="latest operating evidence does not bind the current delivery package",
    )
  }
  let performance_digest = if performance.evidence_digest.has_prefix("sha256:") {
    performance.evidence_digest
  } else {
    "sha256:" + sha256_text(performance.evidence_digest)
  }
  let performance_ref : @handoff.RecordRef = {
    record_id: "performance-" + sha256_text(project_id)[:24].to_owned(),
    record_version: canonical.snapshot.revision.to_string(),
    record_digest: performance_digest,
    provenance_ref: "/api/v2/projects/" +
    project_id +
    "/governance/performance-reviews",
  }
  let observation_digest = "sha256:" +
    sha256_text(
      deliverable_evidence.record.record_digest +
      ":" +
      performance.to_json().stringify(),
    )
  let outcome_id = "outcome-" +
    sha256_text(
      deliverable_evidence.record.record_id + ":" + observation_digest,
    )[:32].to_owned()
  let outcome : @handoff.ProductionOutcomeEvidence = {
    contract: "mooncast.production-outcome-evidence.v1",
    record: {
      record_id: outcome_id,
      record_version: "1",
      record_digest: "sha256:" +
      sha256_text(outcome_id + ":" + observation_digest),
      provenance_ref: "/api/v2/projects/" +
      project_id +
      "/delivery/outcome-handoff",
    },
    final_deliverable_ref: deliverable_evidence.record,
    status: performance.status,
    observation_digest,
    evidence_refs: [deliverable_evidence.record, performance_ref],
    inference_used: false,
    observed_at: performance.reviewed_at,
  }
  let outcome_put = self.handoff_outbox.record_production_outcome_evidence(
    outcome,
  )
  let request_id = outcome_id + "-moonflow-handoff"
  let request : @handoff.ExternalHandoffRequest = {
    contract: "mooncast.external-handoff-request.v1",
    record: {
      record_id: request_id,
      record_version: "1",
      record_digest: "sha256:" +
      sha256_text(request_id + ":" + outcome.record.record_digest),
      provenance_ref: outcome.record.provenance_ref,
    },
    transport_contract: "moonflow.pack-handoff.v1",
    destination_product: "moonbook",
    destination_contract: "moonbook.bookkeeper.v1",
    record_kind: "PackOutcomeObservationV1",
    subject_ref: outcome.record,
    evidence_refs: [
      outcome.record,
      deliverable_evidence.record,
      performance_ref,
    ],
    authority_request_ref: None,
    review_receipt_ref: None,
    payload_digest: outcome.record.record_digest,
    requested_at: performance.reviewed_at,
    external_effect_authorized: false,
  }
  let request_put = self.handoff_outbox.prepare_request(request)
  guard self.handoff_outbox.get(
      "bookkeeper-ingress-bundle",
      request.record.record_id,
    )
    is Some(stored_bundle) else {
    fail("outcome handoff did not materialize its Bookkeeper ingress bundle")
  }
  let bundle : @handoff.BookkeeperIngressBundle = @json.from_json(
    stored_bundle.payload,
  )
  {
    outcome,
    request,
    bookkeeper_ingress_bundle: bundle,
    outcome_created: outcome_put.created,
    request_created: request_put.created,
    publication_authority: false,
    payment_authority: false,
    external_effect_authorized: false,
  }
}
