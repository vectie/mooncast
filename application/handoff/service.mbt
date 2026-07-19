///|
/// Mooncast's handoff application is an immutable outbox. It owns only
/// Mooncast evidence and references to externally issued receipts. It does not
/// finalize deliverables, classify Three-Gap findings, review learning, propose
/// capabilities, or apply ability changes.
pub struct OutboundHandoffService {
  outbox : ImmutableRecordStore
}

///|
pub fn OutboundHandoffService::new(root : String) -> OutboundHandoffService {
  { outbox: ImmutableRecordStore::new(root) }
}

///|
async fn OutboundHandoffService::materialize_bookkeeper_bundle(
  self : OutboundHandoffService,
  request : @handoff_domain.ExternalHandoffRequest,
) -> @handoff_domain.BookkeeperIngressBundle {
  if request.record_kind == "PackDeliverableCandidateV1" {
    guard self.outbox.get(
        "final-deliverable-evidence",
        request.subject_ref.record_id,
      )
      is Some(stored) else {
      raise ImmutableRecordConflict("missing-final-deliverable-evidence")
    }
    let evidence : @handoff_domain.FinalDeliverableEvidence = @json.from_json(
      stored.payload,
    ) catch {
      _ => raise ImmutableRecordCorrupt("final-deliverable-evidence")
    }
    return final_deliverable_bookkeeper_bundle(request, evidence).unwrap_or_else(() => {
        raise ImmutableRecordConflict(
          "bookkeeper-deliverable-materialization-rejected",
        )
      },
    )
  }
  guard self.outbox.get(
      "production-outcome-evidence",
      request.subject_ref.record_id,
    )
    is Some(stored_outcome) else {
    raise ImmutableRecordConflict("missing-production-outcome-evidence")
  }
  let outcome : @handoff_domain.ProductionOutcomeEvidence = @json.from_json(
    stored_outcome.payload,
  ) catch {
    _ => raise ImmutableRecordCorrupt("production-outcome-evidence")
  }
  guard self.outbox.get(
      "final-deliverable-evidence",
      outcome.final_deliverable_ref.record_id,
    )
    is Some(stored_deliverable) else {
    raise ImmutableRecordConflict("missing-linked-final-deliverable-evidence")
  }
  let deliverable : @handoff_domain.FinalDeliverableEvidence = @json.from_json(
    stored_deliverable.payload,
  ) catch {
    _ => raise ImmutableRecordCorrupt("linked-final-deliverable-evidence")
  }
  outcome_bookkeeper_bundle(request, outcome, deliverable).unwrap_or_else(() => {
    raise ImmutableRecordConflict("bookkeeper-outcome-materialization-rejected")
  })
}

///|
pub async fn OutboundHandoffService::record_final_deliverable_evidence(
  self : OutboundHandoffService,
  value : @handoff_domain.FinalDeliverableEvidence,
) -> ImmutablePutResult {
  guard @handoff_domain.final_deliverable_evidence_valid(value) else {
    raise ImmutableRecordConflict("invalid-final-deliverable-evidence")
  }
  self.outbox.put(
    "final-deliverable-evidence",
    value.record.record_id,
    value.record.record_id + "-" + value.record.record_version,
    value.to_json(),
  )
}

///|
pub async fn OutboundHandoffService::record_production_outcome_evidence(
  self : OutboundHandoffService,
  value : @handoff_domain.ProductionOutcomeEvidence,
) -> ImmutablePutResult {
  guard @handoff_domain.production_outcome_evidence_valid(value) else {
    raise ImmutableRecordConflict("invalid-production-outcome-evidence")
  }
  self.outbox.put(
    "production-outcome-evidence",
    value.record.record_id,
    value.record.record_id + "-" + value.record.record_version,
    value.to_json(),
  )
}

///|
pub async fn OutboundHandoffService::prepare_request(
  self : OutboundHandoffService,
  value : @handoff_domain.ExternalHandoffRequest,
) -> ImmutablePutResult {
  guard @handoff_domain.external_handoff_request_valid(value) else {
    raise ImmutableRecordConflict("invalid-external-handoff-request")
  }
  let bundle = self.materialize_bookkeeper_bundle(value)
  let bundle_digest = canonical_record_digest(value.to_json())
  ignore(
    self.outbox.put(
      "bookkeeper-ingress-bundle",
      value.record.record_id,
      "bk-" + bundle_digest[7:31].to_owned(),
      bundle.to_json(),
    ),
  )
  self.outbox.put(
    "external-handoff-request",
    value.record.record_id,
    value.record.record_id + "-" + value.record.record_version,
    value.to_json(),
  )
}

///|
pub async fn OutboundHandoffService::record_receipt_reference(
  self : OutboundHandoffService,
  value : @handoff_domain.ExternalHandoffReceiptReference,
) -> ImmutablePutResult {
  guard @handoff_domain.external_handoff_receipt_reference_valid(value) else {
    raise ImmutableRecordConflict("invalid-external-handoff-receipt-reference")
  }
  self.outbox.put(
    "external-handoff-receipt-reference",
    value.record.record_id,
    value.record.record_id + "-" + value.record.record_version,
    value.to_json(),
  )
}

///|
pub async fn OutboundHandoffService::get(
  self : OutboundHandoffService,
  record_type : String,
  record_id : String,
) -> ImmutableRecordEnvelope? {
  guard [
    "final-deliverable-evidence", "production-outcome-evidence", "external-handoff-request",
    "external-handoff-receipt-reference", "bookkeeper-ingress-bundle",
  ].any(value => value == record_type) else {
    return None
  }
  self.outbox.get(record_type, record_id)
}

///|
/// Lists Mooncast-owned final-deliverable evidence for Studio projections.
/// This is an outbox query only: it does not contact MoonFlow or MoonBook and
/// it does not reinterpret any external acceptance receipt.
pub async fn OutboundHandoffService::list_final_deliverable_evidence(
  self : OutboundHandoffService,
) -> Array[@handoff_domain.FinalDeliverableEvidence] {
  self.outbox
  .list("final-deliverable-evidence")
  .map(envelope => {
    @json.from_json(envelope.payload) catch {
      _ => raise ImmutableRecordCorrupt("final-deliverable-evidence")
    }
  })
}

///|
/// Lists immutable Mooncast production-outcome observations. Classification,
/// learning and capability changes remain external responsibilities.
pub async fn OutboundHandoffService::list_production_outcome_evidence(
  self : OutboundHandoffService,
) -> Array[@handoff_domain.ProductionOutcomeEvidence] {
  self.outbox
  .list("production-outcome-evidence")
  .map(envelope => {
    @json.from_json(envelope.payload) catch {
      _ => raise ImmutableRecordCorrupt("production-outcome-evidence")
    }
  })
}

///|
/// Lists inert external handoff requests already prepared in the local outbox.
pub async fn OutboundHandoffService::list_external_handoff_requests(
  self : OutboundHandoffService,
) -> Array[@handoff_domain.ExternalHandoffRequest] {
  self.outbox
  .list("external-handoff-request")
  .map(envelope => {
    @json.from_json(envelope.payload) catch {
      _ => raise ImmutableRecordCorrupt("external-handoff-request")
    }
  })
}

///|
/// Read-only access to records written by the retired MC-7 service. This
/// adapter deliberately has no put/remove method and is not exposed as a
/// runtime HTTP mutation surface.
pub struct LegacyBookkeeperReadOnlyAdapter {
  state_store : @store.AtomicStore
  learning_store : @store.AtomicStore
  immutable_store : ImmutableRecordStore
}

///|
pub fn LegacyBookkeeperReadOnlyAdapter::new(
  legacy_handoff_root : String,
  legacy_learning_root : String,
) -> LegacyBookkeeperReadOnlyAdapter {
  {
    state_store: @store.AtomicStore::new(
      legacy_handoff_root,
      max_read_bytes=33554432,
    ),
    learning_store: @store.AtomicStore::new(
      legacy_learning_root,
      max_read_bytes=16777216,
    ),
    immutable_store: ImmutableRecordStore::new(
      legacy_handoff_root + "/immutable",
    ),
  }
}

///|
pub async fn LegacyBookkeeperReadOnlyAdapter::snapshot(
  self : LegacyBookkeeperReadOnlyAdapter,
) -> Json? {
  self.state_store.get_json("closed-loop-snapshot.json")
}

///|
pub async fn LegacyBookkeeperReadOnlyAdapter::learning_record(
  self : LegacyBookkeeperReadOnlyAdapter,
  key : String,
) -> Json? {
  self.learning_store.get_json(key)
}

///|
pub async fn LegacyBookkeeperReadOnlyAdapter::immutable_record(
  self : LegacyBookkeeperReadOnlyAdapter,
  record_type : String,
  record_id : String,
) -> ImmutableRecordEnvelope? {
  self.immutable_store.get(record_type, record_id)
}
