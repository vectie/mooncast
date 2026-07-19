///|
struct AddPayload {
  track_id : String
  clip : Clip
} derive(ToJson, FromJson)

///|
struct MovePayload {
  clip_id : String
  track_id : String
  start_tick : Int
} derive(ToJson, FromJson)

///|
struct TrimPayload {
  clip_id : String
  source_in_tick : Int
  source_out_tick : Int
  start_tick : Int?
} derive(ToJson, FromJson)

///|
struct SplitPayload {
  clip_id : String
  split_tick : Int
  left_clip_id : String
  right_clip_id : String
} derive(ToJson, FromJson)

///|
struct ClipIdPayload {
  clip_id : String
} derive(ToJson, FromJson)

///|
struct RippleInsertPayload {
  track_id : String
  clip : Clip
  before_clip_id : String?
} derive(ToJson, FromJson)

///|
struct RippleMovePayload {
  clip_id : String
  track_id : String
  before_clip_id : String?
} derive(ToJson, FromJson)

///|
struct GroupRippleMovePayload {
  clip_ids : Array[String]
  track_id : String
  before_clip_id : String?
} derive(ToJson, FromJson)

///|
struct GroupMovePayload {
  moves : Array[MoveSpec]
} derive(ToJson, FromJson)

///|
struct GroupDeletePayload {
  clip_ids : Array[String]
} derive(ToJson, FromJson)

///|
struct GroupTrimPayload {
  trims : Array[TrimSpec]
} derive(ToJson, FromJson)

///|
struct ConfigureClipPayload {
  clip_id : String
  settings : ClipSettings
} derive(ToJson, FromJson)

///|
struct ConfigureTrackPayload {
  track_id : String
  mix : TrackMix
} derive(ToJson, FromJson)

///|
struct ConfigureOutputPayload {
  output : OutputSettings
} derive(ToJson, FromJson)

///|
struct KeyframesPayload {
  clip_id : String
  keyframes : KeyframeSet
} derive(ToJson, FromJson)

///|
struct TransitionPayload {
  transition : Transition
} derive(ToJson, FromJson)

///|
struct TransitionIdPayload {
  transition_id : String
} derive(ToJson, FromJson)

///|
struct EffectPayload {
  clip_id : String
  effects : Array[Effect]
  effect_stack_digest : String
} derive(ToJson, FromJson)

///|
struct AudioRoutePayload {
  clip_id : String
  bus_id : String
} derive(ToJson, FromJson)

///|
struct AudioBusPayload {
  bus : AudioBus
} derive(ToJson, FromJson)

///|
struct DeliveryAudioPayload {
  delivery_audio : DeliveryAudio
} derive(ToJson, FromJson)

///|
struct ControlPayload {
  target_command_id : String?
} derive(ToJson, FromJson)

///|
fn legacy_payload(operation : EditOperation) -> Json {
  match operation {
    Add(track_id~, clip~) => AddPayload::{ track_id, clip }.to_json()
    Move(clip_id~, track_id~, start_tick~) =>
      MovePayload::{ clip_id, track_id, start_tick }.to_json()
    Trim(clip_id~, source_in_tick~, source_out_tick~, start_tick~) =>
      TrimPayload::{ clip_id, source_in_tick, source_out_tick, start_tick }.to_json()
    Split(clip_id~, split_tick~, left_clip_id~, right_clip_id~) =>
      SplitPayload::{ clip_id, split_tick, left_clip_id, right_clip_id }.to_json()
    Delete(clip_id~) | RippleDelete(clip_id~) =>
      ClipIdPayload::{ clip_id, }.to_json()
    RippleInsert(track_id~, clip~, before_clip_id~) =>
      RippleInsertPayload::{ track_id, clip, before_clip_id }.to_json()
    RippleMove(clip_id~, track_id~, before_clip_id~) =>
      RippleMovePayload::{ clip_id, track_id, before_clip_id }.to_json()
    RippleTrim(clip_id~, source_in_tick~, source_out_tick~) =>
      TrimPayload::{
        clip_id,
        source_in_tick,
        source_out_tick,
        start_tick: None,
      }.to_json()
    GroupMove(moves) => GroupMovePayload::{ moves, }.to_json()
    GroupRippleMove(clip_ids~, track_id~, before_clip_id~) =>
      GroupRippleMovePayload::{ clip_ids, track_id, before_clip_id }.to_json()
    GroupDelete(clip_ids) => GroupDeletePayload::{ clip_ids, }.to_json()
    GroupTrim(trims) => GroupTrimPayload::{ trims, }.to_json()
    ConfigureClip(clip_id~, settings~) =>
      ConfigureClipPayload::{ clip_id, settings }.to_json()
    ConfigureTrack(track_id~, mix~) =>
      ConfigureTrackPayload::{ track_id, mix }.to_json()
    ConfigureOutput(output) => ConfigureOutputPayload::{ output, }.to_json()
    SetKeyframes(clip_id~, keyframes~) =>
      KeyframesPayload::{ clip_id, keyframes }.to_json()
    ConfigureTransition(transition) =>
      TransitionPayload::{ transition, }.to_json()
    RemoveTransition(transition_id) =>
      TransitionIdPayload::{ transition_id, }.to_json()
    ConfigureEffectStack(clip_id~, effects~, effect_stack_digest~) =>
      EffectPayload::{ clip_id, effects, effect_stack_digest }.to_json()
    ConfigureAudioRoute(clip_id~, bus_id~) =>
      AudioRoutePayload::{ clip_id, bus_id }.to_json()
    ConfigureAudioBus(bus) => AudioBusPayload::{ bus, }.to_json()
    ConfigureDeliveryAudio(delivery_audio) =>
      DeliveryAudioPayload::{ delivery_audio, }.to_json()
    Undo(target_command_id~) | Redo(target_command_id~) =>
      ControlPayload::{ target_command_id, }.to_json()
  }
}

///|
pub fn legacy_command_json(command : EditCommand) -> Json {
  Json::object({
    "contract": command.contract,
    "command_id": command.command_id,
    "expected_revision": command.expected_revision,
    "actor": command.actor.to_json(),
    "type": operation_kind(command.operation),
    "payload": legacy_payload(command.operation),
  })
}

///|
fn[T : FromJson] required_field(
  object : Map[String, Json],
  key : String,
) -> T raise {
  guard object.get(key) is Some(value) else {
    fail("missing command field: " + key)
  }
  @json.from_json(value)
}

///|
fn operation_from_payload(kind : String, payload : Json) -> EditOperation raise {
  match kind {
    "add" => {
      let p : AddPayload = @json.from_json(payload)
      Add(track_id=p.track_id, clip=p.clip)
    }
    "move" => {
      let p : MovePayload = @json.from_json(payload)
      Move(clip_id=p.clip_id, track_id=p.track_id, start_tick=p.start_tick)
    }
    "trim" => {
      let p : TrimPayload = @json.from_json(payload)
      Trim(
        clip_id=p.clip_id,
        source_in_tick=p.source_in_tick,
        source_out_tick=p.source_out_tick,
        start_tick=p.start_tick,
      )
    }
    "split" => {
      let p : SplitPayload = @json.from_json(payload)
      Split(
        clip_id=p.clip_id,
        split_tick=p.split_tick,
        left_clip_id=p.left_clip_id,
        right_clip_id=p.right_clip_id,
      )
    }
    "delete" => {
      let p : ClipIdPayload = @json.from_json(payload)
      Delete(clip_id=p.clip_id)
    }
    "ripple_insert" => {
      let p : RippleInsertPayload = @json.from_json(payload)
      RippleInsert(
        track_id=p.track_id,
        clip=p.clip,
        before_clip_id=p.before_clip_id,
      )
    }
    "ripple_move" => {
      let p : RippleMovePayload = @json.from_json(payload)
      RippleMove(
        clip_id=p.clip_id,
        track_id=p.track_id,
        before_clip_id=p.before_clip_id,
      )
    }
    "ripple_trim" => {
      let p : TrimPayload = @json.from_json(payload)
      RippleTrim(
        clip_id=p.clip_id,
        source_in_tick=p.source_in_tick,
        source_out_tick=p.source_out_tick,
      )
    }
    "ripple_delete" => {
      let p : ClipIdPayload = @json.from_json(payload)
      RippleDelete(clip_id=p.clip_id)
    }
    "group_move" => {
      let p : GroupMovePayload = @json.from_json(payload)
      GroupMove(p.moves)
    }
    "group_ripple_move" => {
      let p : GroupRippleMovePayload = @json.from_json(payload)
      GroupRippleMove(
        clip_ids=p.clip_ids,
        track_id=p.track_id,
        before_clip_id=p.before_clip_id,
      )
    }
    "group_delete" => {
      let p : GroupDeletePayload = @json.from_json(payload)
      GroupDelete(p.clip_ids)
    }
    "group_trim" => {
      let p : GroupTrimPayload = @json.from_json(payload)
      GroupTrim(p.trims)
    }
    "configure_clip" => {
      let p : ConfigureClipPayload = @json.from_json(payload)
      ConfigureClip(clip_id=p.clip_id, settings=p.settings)
    }
    "configure_track" => {
      let p : ConfigureTrackPayload = @json.from_json(payload)
      ConfigureTrack(track_id=p.track_id, mix=p.mix)
    }
    "configure_output" => {
      let p : ConfigureOutputPayload = @json.from_json(payload)
      ConfigureOutput(p.output)
    }
    "set_keyframes" => {
      let p : KeyframesPayload = @json.from_json(payload)
      SetKeyframes(clip_id=p.clip_id, keyframes=p.keyframes)
    }
    "configure_transition" => {
      let p : TransitionPayload = @json.from_json(payload)
      ConfigureTransition(p.transition)
    }
    "remove_transition" => {
      let p : TransitionIdPayload = @json.from_json(payload)
      RemoveTransition(p.transition_id)
    }
    "configure_effect_stack" => {
      let p : EffectPayload = @json.from_json(payload)
      ConfigureEffectStack(
        clip_id=p.clip_id,
        effects=p.effects,
        effect_stack_digest=p.effect_stack_digest,
      )
    }
    "configure_audio_route" => {
      let p : AudioRoutePayload = @json.from_json(payload)
      ConfigureAudioRoute(clip_id=p.clip_id, bus_id=p.bus_id)
    }
    "configure_audio_bus" => {
      let p : AudioBusPayload = @json.from_json(payload)
      ConfigureAudioBus(p.bus)
    }
    "configure_delivery_audio" => {
      let p : DeliveryAudioPayload = @json.from_json(payload)
      ConfigureDeliveryAudio(p.delivery_audio)
    }
    "undo" => {
      let p : ControlPayload = @json.from_json(payload)
      Undo(target_command_id=p.target_command_id)
    }
    "redo" => {
      let p : ControlPayload = @json.from_json(payload)
      Redo(target_command_id=p.target_command_id)
    }
    _ => fail("unsupported legacy editor command type: " + kind)
  }
}

///|
pub fn legacy_command_from_json(value : Json) -> EditCommand raise {
  guard value is Object(object) else {
    fail("editor command must be an object")
  }
  let contract : String = required_field(object, "contract")
  guard contract == "mooncast.editor-edit-command.v1" else {
    fail("unsupported editor command contract")
  }
  let command_id : String = required_field(object, "command_id")
  let expected_revision : Int = required_field(object, "expected_revision")
  let actor : CommandActor = required_field(object, "actor")
  let kind : String = required_field(object, "type")
  guard object.get("payload") is Some(payload) else {
    fail("editor command payload is required")
  }
  {
    contract,
    command_id,
    expected_revision,
    actor,
    operation: operation_from_payload(kind, payload),
  }
}
