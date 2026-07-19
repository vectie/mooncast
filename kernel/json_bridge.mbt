///|
pub fn evaluate_json(input : StringView) -> String raise {
  let command : ProjectCommand = @json.from_json(@json.parse(input))
  handle(command).to_json().stringify()
}

///|
pub fn snapshot_to_json(snapshot : ProjectSnapshot) -> String {
  snapshot.to_json().stringify()
}

///|
pub fn snapshot_from_json(input : StringView) -> ProjectSnapshot raise {
  let snapshot : ProjectSnapshot = @json.from_json(@json.parse(input))
  if snapshot.schema_version != "mooncast.project-snapshot.v2" {
    fail("unsupported Mooncast project snapshot version")
  }
  snapshot
}

///|
pub fn event_to_json(event : ProjectEvent) -> String {
  event.to_json().stringify()
}

///|
pub fn event_from_json(input : StringView) -> ProjectEvent raise {
  let event : ProjectEvent = @json.from_json(@json.parse(input))
  if event.schema_version != "mooncast.project-event.v2" {
    fail("unsupported Mooncast project event version")
  }
  event
}
