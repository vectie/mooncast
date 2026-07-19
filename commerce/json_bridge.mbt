///|
pub fn commercial_command_json(input : StringView) -> String raise {
  let command : CommercialCommand = @json.from_json(@json.parse(input))
  reduce_commercial_command(command).to_json().stringify()
}

///|
pub fn commercial_snapshot_json(snapshot : CommercialSnapshot) -> String {
  snapshot.to_json().stringify()
}

///|
pub fn commercial_snapshot_from_json(
  input : StringView,
) -> CommercialSnapshot raise {
  let snapshot : CommercialSnapshot = @json.from_json(@json.parse(input))
  if snapshot.contract != "mooncast.commercial-snapshot.v1" {
    fail("unsupported commercial snapshot")
  }
  snapshot
}
