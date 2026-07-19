///|
pub(all) struct CommercialAuditReceipt {
  contract : String
  receipt_id : String
  revision : Int
  action : String
  command_id : String
  evidence_digest : String
  recorded_at : String
  external_effect_performed : Bool
  payment_effect_performed : Bool
  publication_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror CommercialApplicationError {
  CommercialStateCorrupt
  CommercialCommandRejected(String)
  ClientPortalNotFound
  ClientPortalUnavailable
  ClientPortalStale
  ClientProjectionDenied
} derive(Debug)

///|
pub struct CommercialApplicationService {
  store : @store.AtomicStore
}

///|
pub fn CommercialApplicationService::new(
  root : String,
) -> CommercialApplicationService {
  { store: @store.AtomicStore::new(root, max_read_bytes=33554432) }
}

///|
fn commercial_state_key() -> String {
  "commercial-snapshot.json"
}

///|
pub async fn CommercialApplicationService::load(
  self : CommercialApplicationService,
) -> @commerce_domain.CommercialSnapshot {
  match self.store.get_json(commercial_state_key()) {
    None => @commerce_domain.empty_commercial_snapshot()
    Some(value) => {
      let snapshot : @commerce_domain.CommercialSnapshot = @json.from_json(
        value,
      ) catch {
        _ => raise CommercialStateCorrupt
      }
      if snapshot.contract != "mooncast.commercial-snapshot.v1" {
        raise CommercialStateCorrupt
      }
      snapshot
    }
  }
}

///|
async fn CommercialApplicationService::save(
  self : CommercialApplicationService,
  snapshot : @commerce_domain.CommercialSnapshot,
) -> Unit {
  ignore(self.store.put_json(commercial_state_key(), snapshot.to_json()))
}

///|
async fn CommercialApplicationService::audit(
  self : CommercialApplicationService,
  command : @commerce_domain.CommercialCommand,
  revision : Int,
) -> Unit {
  self.audit_action(
    command.action,
    command.command_id,
    command.evidence_digest,
    command.recorded_at,
    revision,
  )
}

///|
async fn CommercialApplicationService::audit_action(
  self : CommercialApplicationService,
  action : String,
  command_id : String,
  evidence_digest : String,
  recorded_at : String,
  revision : Int,
) -> Unit {
  let receipt : CommercialAuditReceipt = {
    contract: "mooncast.commercial-intake-audit-receipt.v1",
    receipt_id: @runtime.new_id(prefix="commercial-receipt"),
    revision,
    action,
    command_id,
    evidence_digest,
    recorded_at,
    external_effect_performed: false,
    payment_effect_performed: false,
    publication_effect_performed: false,
  }
  ignore(
    self.store.put_json(
      "commercial-audit-" + revision.to_string() + "-" + command_id + ".json",
      receipt.to_json(),
    ),
  )
}

///|
pub async fn CommercialApplicationService::submit(
  self : CommercialApplicationService,
  command : @commerce_domain.CommercialCommand,
) -> @commerce_domain.CommercialResult {
  let snapshot = self.load()
  if command.expected_revision != snapshot.revision {
    raise CommercialCommandRejected("commercial_revision_conflict")
  }
  let bound = { ..command, snapshot, }
  let result = @commerce_domain.reduce_commercial_command(bound)
  if !result.ok {
    raise CommercialCommandRejected(
      result.error_code.unwrap_or("commercial_command_invalid"),
    )
  }
  self.save(result.snapshot)
  self.audit(bound, result.snapshot.revision)
  result
}

///|
pub async fn CommercialApplicationService::dashboard_json(
  self : CommercialApplicationService,
) -> String {
  let snapshot = self.load()
  snapshot.to_json().stringify()
}
