///|
/// Durable projection event emitted after an accepted edit command.
pub(all) struct EditorEvent {
  contract : String
  event_id : String
  command_id : String
  project_id : String
  timeline_id : String
  before_revision : Int
  after_revision : Int
  actor : CommandActor
  operation_kind : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn operation_kind(value : EditOperation) -> String {
  match value {
    Add(..) => "add"
    Move(..) => "move"
    Trim(..) => "trim"
    Split(..) => "split"
    Delete(..) => "delete"
    RippleInsert(..) => "ripple_insert"
    RippleMove(..) => "ripple_move"
    RippleTrim(..) => "ripple_trim"
    RippleDelete(..) => "ripple_delete"
    GroupMove(_) => "group_move"
    GroupRippleMove(..) => "group_ripple_move"
    GroupDelete(_) => "group_delete"
    GroupTrim(_) => "group_trim"
    ConfigureClip(..) => "configure_clip"
    ConfigureTrack(..) => "configure_track"
    ConfigureOutput(_) => "configure_output"
    SetKeyframes(..) => "set_keyframes"
    ConfigureTransition(_) => "configure_transition"
    RemoveTransition(_) => "remove_transition"
    ConfigureEffectStack(..) => "configure_effect_stack"
    ConfigureAudioRoute(..) => "configure_audio_route"
    ConfigureAudioBus(_) => "configure_audio_bus"
    ConfigureDeliveryAudio(_) => "configure_delivery_audio"
    Undo(..) => "undo"
    Redo(..) => "redo"
  }
}

///|
pub fn CommandLogRecord::event(self : CommandLogRecord) -> EditorEvent {
  {
    contract: "mooncast.editor-event.v1",
    event_id: "event:" + self.command.command_id,
    command_id: self.command.command_id,
    project_id: self.after.project_id,
    timeline_id: self.after.timeline.timeline_id,
    before_revision: self.before.revision,
    after_revision: self.after.revision,
    actor: self.command.actor,
    operation_kind: operation_kind(self.command.operation),
  }
}
