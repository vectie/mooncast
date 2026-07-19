///|
/// Bind Mooncast evidence into an opaque transport request. The destination
/// system owns every decision made after this request is handed off.
pub fn moonbook_handoff_request(
  record : @handoff_domain.RecordRef,
  record_kind : String,
  subject_ref : @handoff_domain.RecordRef,
  evidence_refs : Array[@handoff_domain.RecordRef],
  payload_digest : String,
  requested_at : String,
  authority_request_ref? : @handoff_domain.RecordRef,
  review_receipt_ref? : @handoff_domain.RecordRef,
) -> @handoff_domain.ExternalHandoffRequest? {
  let value : @handoff_domain.ExternalHandoffRequest = {
    contract: "mooncast.external-handoff-request.v1",
    record,
    transport_contract: "moonflow.pack-handoff.v1",
    destination_product: "moonbook",
    destination_contract: "moonbook.bookkeeper.v1",
    record_kind,
    subject_ref,
    evidence_refs,
    authority_request_ref,
    review_receipt_ref,
    payload_digest,
    requested_at,
    external_effect_authorized: false,
  }
  if @handoff_domain.external_handoff_request_valid(value) {
    Some(value)
  } else {
    None
  }
}
