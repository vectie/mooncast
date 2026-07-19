///|
pub(all) struct CommandActor {
  actor_id : String
  provenance : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MoveSpec {
  clip_id : String
  track_id : String
  start_tick : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TrimSpec {
  clip_id : String
  source_in_tick : Int
  source_out_tick : Int
  start_tick : Int?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Commands carry explicit clip identifiers: UI selection is never reducer input.
pub(all) enum EditOperation {
  Add(track_id~ : String, clip~ : Clip)
  Move(clip_id~ : String, track_id~ : String, start_tick~ : Int)
  Trim(
    clip_id~ : String,
    source_in_tick~ : Int,
    source_out_tick~ : Int,
    start_tick~ : Int?
  )
  Split(
    clip_id~ : String,
    split_tick~ : Int,
    left_clip_id~ : String,
    right_clip_id~ : String
  )
  Delete(clip_id~ : String)
  RippleInsert(track_id~ : String, clip~ : Clip, before_clip_id~ : String?)
  RippleMove(clip_id~ : String, track_id~ : String, before_clip_id~ : String?)
  RippleTrim(clip_id~ : String, source_in_tick~ : Int, source_out_tick~ : Int)
  RippleDelete(clip_id~ : String)
  GroupMove(Array[MoveSpec])
  GroupRippleMove(
    clip_ids~ : Array[String],
    track_id~ : String,
    before_clip_id~ : String?
  )
  GroupDelete(Array[String])
  GroupTrim(Array[TrimSpec])
  ConfigureClip(clip_id~ : String, settings~ : ClipSettings)
  ConfigureTrack(track_id~ : String, mix~ : TrackMix)
  ConfigureOutput(OutputSettings)
  SetKeyframes(clip_id~ : String, keyframes~ : KeyframeSet)
  ConfigureTransition(Transition)
  RemoveTransition(String)
  ConfigureEffectStack(
    clip_id~ : String,
    effects~ : Array[Effect],
    effect_stack_digest~ : String
  )
  ConfigureAudioRoute(clip_id~ : String, bus_id~ : String)
  ConfigureAudioBus(AudioBus)
  ConfigureDeliveryAudio(DeliveryAudio)
  Undo(target_command_id~ : String?)
  Redo(target_command_id~ : String?)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditCommand {
  contract : String
  command_id : String
  expected_revision : Int
  actor : CommandActor
  operation : EditOperation
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommandLogRecord {
  contract : String
  command : EditCommand
  before : EditorProject
  after : EditorProject
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorSession {
  initial : EditorProject
  snapshot : EditorProject
  command_log : Array[CommandLogRecord]
  active_command_ids : Array[String]
  redo_command_ids : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn EditorSession::new(initial : EditorProject) -> EditorSession {
  {
    initial,
    snapshot: initial,
    command_log: [],
    active_command_ids: [],
    redo_command_ids: [],
  }
}
