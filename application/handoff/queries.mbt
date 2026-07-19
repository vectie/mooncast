///|
/// Returns the immutable Mooncast-owned payload, never an interpreted or
/// rewritten copy of a MoonFlow/MoonBook record.
pub async fn OutboundHandoffService::record_json(
  self : OutboundHandoffService,
  record_type : String,
  record_id : String,
) -> Json? {
  self.get(record_type, record_id).map(record => record.payload)
}
