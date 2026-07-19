///|
/// Mooncast-owned evidence describing a completed production master. This is
/// evidence for an external handoff; it is not a Bookkeeper decision.
pub(all) struct FinalDeliverableEvidence {
  contract : String
  record : RecordRef
  project_id : String
  episode_id : String
  export_job_id : String
  editor_output_digest : String
  render_plan_digest : String
  lineage_evidence_digest : String
  duration_seconds : Int
  source_refs : Array[RecordRef]
  publication_authority : Bool
  external_effect_authorized : Bool
  prepared_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Mooncast-owned observation about a delivered production. Classification,
/// Three-Gap assessment, learning, and capability changes remain external.
pub(all) struct ProductionOutcomeEvidence {
  contract : String
  record : RecordRef
  final_deliverable_ref : RecordRef
  status : String
  observation_digest : String
  evidence_refs : Array[RecordRef]
  inference_used : Bool
  observed_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Opaque request for MoonFlow to carry Mooncast evidence to an external
/// authority. Mooncast cannot execute or interpret the destination contract.
pub(all) struct ExternalHandoffRequest {
  contract : String
  record : RecordRef
  transport_contract : String
  destination_product : String
  destination_contract : String
  record_kind : String
  subject_ref : RecordRef
  evidence_refs : Array[RecordRef]
  authority_request_ref : RecordRef?
  review_receipt_ref : RecordRef?
  payload_digest : String
  requested_at : String
  external_effect_authorized : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A local pointer to a receipt issued by MoonFlow or MoonBook. The canonical
/// receipt payload remains owned by its issuer and is never rewritten here.
pub(all) struct ExternalHandoffReceiptReference {
  contract : String
  record : RecordRef
  request_ref : RecordRef
  issuer_product : String
  issuer_contract : String
  external_receipt_ref : RecordRef
  recorded_at : String
  authoritative_payload_stored : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Exact identity shape consumed by MoonBook's generic Bookkeeper store. It is
/// mirrored here so Mooncast never imports or owns MoonBook implementation.
pub(all) struct BookkeeperRecordReference {
  record_id : String
  record_version : String
  record_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BookkeeperEvidenceReference {
  reference_id : String
  reference_version : String
  digest : String
  provenance_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Domain-neutral durable record value for MoonFlow to submit to MoonBook.
/// Mooncast-specific production semantics remain opaque in `payload`.
pub(all) struct BookkeeperDurableRecord {
  contract_version : String
  record : BookkeeperRecordReference
  stage : String
  subject : BookkeeperRecordReference?
  links : Array[BookkeeperRecordReference]
  title : String
  summary : String
  owner_route : String
  status : String
  evidence_refs : Array[BookkeeperEvidenceReference]
  issue_refs : Array[String]
  requires_human_review : Bool
  next_action : String
  source_product : String
  recorded_at : Int
  payload : Json
  side_effects_applied : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Domain-neutral ingress envelope value for MoonFlow to submit only after the
/// exact durable subject record has been accepted by MoonBook.
pub(all) struct BookkeeperTransportEnvelope {
  contract_version : String
  envelope : BookkeeperRecordReference
  direction : String
  source_product : String
  destination_product : String
  message_kind : String
  subject : BookkeeperRecordReference
  links : Array[BookkeeperRecordReference]
  evidence_refs : Array[BookkeeperEvidenceReference]
  authority_ref : String
  recorded_at : Int
  payload : Json
  external_activation_allowed : Bool
  side_effects_applied : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One inert, canonically digested submission bundle. The ordered paths make
/// the subject-before-envelope requirement explicit without executing either
/// request from Mooncast.
pub(all) struct BookkeeperIngressBundle {
  contract : String
  request_ref : RecordRef
  record : BookkeeperDurableRecord
  envelope : BookkeeperTransportEnvelope
  post_order : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
fn record_ref_complete(value : RecordRef) -> Bool {
  exact_ref(value, value)
}

///|
fn optional_ref_complete(value : RecordRef?) -> Bool {
  match value {
    None => true
    Some(reference) => record_ref_complete(reference)
  }
}

///|
pub fn final_deliverable_evidence_valid(
  value : FinalDeliverableEvidence,
) -> Bool {
  value.contract == "mooncast.final-deliverable-evidence.v1" &&
  record_ref_complete(value.record) &&
  value.project_id != "" &&
  value.episode_id != "" &&
  value.export_job_id != "" &&
  value.editor_output_digest != "" &&
  value.render_plan_digest != "" &&
  value.lineage_evidence_digest != "" &&
  value.duration_seconds >= 180 &&
  value.duration_seconds <= 480 &&
  value.source_refs.length() > 0 &&
  value.source_refs.all(reference => record_ref_complete(reference)) &&
  !value.publication_authority &&
  !value.external_effect_authorized &&
  value.prepared_at != ""
}

///|
pub fn production_outcome_evidence_valid(
  value : ProductionOutcomeEvidence,
) -> Bool {
  value.contract == "mooncast.production-outcome-evidence.v1" &&
  record_ref_complete(value.record) &&
  record_ref_complete(value.final_deliverable_ref) &&
  value.status != "" &&
  value.observation_digest != "" &&
  value.evidence_refs.length() > 0 &&
  value.evidence_refs.all(reference => record_ref_complete(reference)) &&
  value.observed_at != ""
}

///|
pub fn external_handoff_request_valid(value : ExternalHandoffRequest) -> Bool {
  value.contract == "mooncast.external-handoff-request.v1" &&
  record_ref_complete(value.record) &&
  record_ref_complete(value.subject_ref) &&
  value.transport_contract == "moonflow.pack-handoff.v1" &&
  value.destination_product == "moonbook" &&
  value.destination_contract == "moonbook.bookkeeper.v1" &&
  (
    value.record_kind == "PackDeliverableCandidateV1" ||
    value.record_kind == "PackOutcomeObservationV1"
  ) &&
  value.evidence_refs.length() > 0 &&
  value.evidence_refs.all(reference => record_ref_complete(reference)) &&
  optional_ref_complete(value.authority_request_ref) &&
  optional_ref_complete(value.review_receipt_ref) &&
  value.payload_digest != "" &&
  value.requested_at != "" &&
  !value.external_effect_authorized
}

///|
pub fn external_handoff_receipt_reference_valid(
  value : ExternalHandoffReceiptReference,
) -> Bool {
  value.contract == "mooncast.external-handoff-receipt-reference.v1" &&
  record_ref_complete(value.record) &&
  record_ref_complete(value.request_ref) &&
  record_ref_complete(value.external_receipt_ref) &&
  (value.issuer_product == "moonflow" || value.issuer_product == "moonbook") &&
  value.issuer_contract != "" &&
  value.recorded_at != "" &&
  !value.authoritative_payload_stored
}
