///|
pub fn snapshot_to_json(snapshot : EditorProject) -> String {
  snapshot.to_json().stringify()
}

///|
pub fn snapshot_from_json(input : StringView) -> EditorProject raise {
  let value : EditorProject = @json.from_json(@json.parse(input))
  if value.contract != "mooncast.editor-project.v1" {
    fail("unsupported editor project contract")
  }
  if value.timeline.contract != "mooncast.editor-timeline.v1" {
    fail("unsupported editor timeline contract")
  }
  value
}

///|
pub fn event_to_json(event : EditorEvent) -> String {
  event.to_json().stringify()
}

///|
pub fn event_from_json(input : StringView) -> EditorEvent raise {
  let value : EditorEvent = @json.from_json(@json.parse(input))
  if value.contract != "mooncast.editor-event.v1" {
    fail("unsupported editor event contract")
  }
  value
}

///|
pub fn command_to_json(command : EditCommand) -> String {
  legacy_command_json(command).stringify()
}

///|
pub fn command_from_json(input : StringView) -> EditCommand raise {
  legacy_command_from_json(@json.parse(input))
}

///|
pub fn command_log_to_json(log : Array[CommandLogRecord]) -> String {
  log.to_json().stringify()
}

///|
pub fn command_log_from_json(
  input : StringView,
) -> Array[CommandLogRecord] raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn session_to_json(session : EditorSession) -> String {
  session.to_json().stringify()
}

///|
pub fn session_from_json(input : StringView) -> EditorSession raise {
  @json.from_json(@json.parse(input))
}
