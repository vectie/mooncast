///|
/// Pure editor-domain failure. No host or provider error is represented here.
#warnings("-unused_constructor")
pub suberror EditorError {
  InvalidCommand(String)
  RevisionConflict(expected~ : Int, actual~ : Int)
  DuplicateId(String)
  UnknownTrack(String)
  UnknownClip(String)
  UnknownTransition(String)
  IncompatibleTrack(String)
  InvalidTimeline(String)
  NothingToUndo
  NothingToRedo
} derive(Debug, Eq)

///|
pub(all) struct Timebase {
  ticks_per_second : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FrameRate {
  numerator : Int
  denominator : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OutputSettings {
  preset : String
  orientation : String
  width : Int
  height : Int
  fps : FrameRate
  background : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionIdentity {
  project_id : String
  episode_id : String
  scene_id : String
  shot_id : String
  asset_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IntentRef {
  intent_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaLocator {
  kind : String
  uri : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaMetadata {
  sha256 : String
  mime_type : String
  size_bytes : Int
  duration_ticks : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaRef {
  contract : String
  media_ref_id : String
  locator : MediaLocator
  metadata : MediaMetadata
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AigcArtifact {
  contract : String
  artifact_id : String
  source_refs : Array[String]
  output_media_ref_ids : Array[String]
  provider : String
  model : String
  prompt_digest : String
  rights_state : String
  review_state : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct KeyframePoint {
  tick : Int
  value : Double
  interpolation : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Fixed fields keep all editable curves typed and make deterministic traversal explicit.
pub(all) struct KeyframeSet {
  opacity : Array[KeyframePoint]
  scale : Array[KeyframePoint]
  position_x : Array[KeyframePoint]
  position_y : Array[KeyframePoint]
  brightness : Array[KeyframePoint]
  contrast : Array[KeyframePoint]
  saturation : Array[KeyframePoint]
  gamma : Array[KeyframePoint]
  volume_db : Array[KeyframePoint]
  pan : Array[KeyframePoint]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn empty_keyframes() -> KeyframeSet {
  {
    opacity: [],
    scale: [],
    position_x: [],
    position_y: [],
    brightness: [],
    contrast: [],
    saturation: [],
    gamma: [],
    volume_db: [],
    pan: [],
  }
}

///|
pub(all) struct CropParameters {
  left : Double
  top : Double
  right : Double
  bottom : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TransformParameters {
  scale : Double
  x : Double
  y : Double
  rotation_degrees : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MaskParameters {
  shape : String
  x : Double
  y : Double
  width : Double
  height : Double
  feather : Double
  invert : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SpeedPoint {
  timeline_tick : Int
  source_tick : Int
  interpolation : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A typed superset of effect parameters. Only the field selected by `kind` is used.
pub(all) struct EffectParameters {
  crop : CropParameters?
  transform : TransformParameters?
  opacity : Double?
  blend_mode : String?
  mask : MaskParameters?
  speed_points : Array[SpeedPoint]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Effect {
  effect_id : String
  kind : String
  enabled : Bool
  parameters : EffectParameters
  effect_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClipSettings {
  fit : String
  opacity : Double
  scale : Double
  position_x : Double
  position_y : Double
  rotation_degrees : Double
  brightness : Double
  contrast : Double
  saturation : Double
  gamma : Double
  volume_db : Double
  pan : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn default_clip_settings() -> ClipSettings {
  {
    fit: "contain",
    opacity: 1.0,
    scale: 1.0,
    position_x: 0.0,
    position_y: 0.0,
    rotation_degrees: 0.0,
    brightness: 0.0,
    contrast: 1.0,
    saturation: 1.0,
    gamma: 1.0,
    volume_db: 0.0,
    pan: 0.0,
  }
}

///|
pub(all) struct Clip {
  clip_id : String
  media_ref_id : String
  identity : ProductionIdentity
  intent : IntentRef
  artifact_id : String?
  start_tick : Int
  duration_ticks : Int
  source_in_tick : Int
  source_out_tick : Int
  settings : ClipSettings
  keyframes : KeyframeSet
  effects : Array[Effect]
  effect_stack_digest : String
  audio_bus_id : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TrackMix {
  volume_db : Double
  pan : Double
  muted : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Track {
  track_id : String
  kind : String
  order : Int
  mix : TrackMix?
  clips : Array[Clip]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Transition {
  transition_id : String
  track_id : String
  from_clip_id : String
  to_clip_id : String
  kind : String
  duration_ticks : Int
  outgoing_handle_ticks : Int
  incoming_handle_ticks : Int
  color : String
  direction : String
  transition_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AutomationPoint {
  tick : Int
  value : Double
  interpolation : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BusAutomation {
  gain_db : Array[AutomationPoint]
  pan : Array[AutomationPoint]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AudioBus {
  bus_id : String
  kind : String
  output_bus_id : String?
  gain_db : Double
  pan : Double
  muted : Bool
  solo : Bool
  automation : BusAutomation
  bus_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryAudio {
  target_lufs : Double
  true_peak_limit_dbtp : Double
  limiter_enabled : Bool
  delivery_audio_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AudioMeter {
  bus_id : String
  tick : Int
  peak_dbfs : Double
  rms_dbfs : Double
  integrated_lufs : Double
  true_peak_dbtp : Double
  clipped : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Timeline {
  contract : String
  timeline_id : String
  revision : Int
  timebase : Timebase
  output : OutputSettings
  tracks : Array[Track]
  transitions : Array[Transition]
  audio_buses : Array[AudioBus]
  delivery_audio : DeliveryAudio
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorProject {
  contract : String
  project_id : String
  revision : Int
  identity_graph : Array[ProductionIdentity]
  media_refs : Array[MediaRef]
  artifacts : Array[AigcArtifact]
  intent_refs : Array[IntentRef]
  timeline : Timeline
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SubtitleCue {
  cue_id : String
  start_tick : Int
  end_tick : Int
  text : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RightsAttestation {
  confirmed : Bool
  rights_ref : String
  owner : String
  basis : String
  territory : String
  channels : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaSourceAttestation {
  kind : String
  source_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Typed completed form of `mooncast.editor-local-media-intake.v1`.
pub(all) struct LocalMediaReceipt {
  contract : String
  intake_id : String
  project_id : String
  expected_editor_revision : Int
  idempotency_key : String
  role : String
  file_name : String
  mime_type : String
  size_bytes : Int
  sha256 : String
  duration_ticks : Int
  identity : ProductionIdentity
  rights : RightsAttestation
  source : MediaSourceAttestation
  created_by : String
  request_digest : String
  status : String
  created_at : String
  completed_at : String
  media_ref_id : String
  registry_digest : String
  track_id : String
  track_kind : String
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Durable binding between an editor media reference and rights-cleared local intake.
pub(all) struct LocalMediaBinding {
  contract : String
  project_id : String
  intake_id : String
  intake_receipt_digest : String
  intake_receipt : LocalMediaReceipt
  request_digest : String
  role : String
  rights_ref : String
  media_digest : String
  parser_version : String
  cue_digest : String
  cues : Array[SubtitleCue]
  width : Int
  height : Int
  inspector_version : String
} derive(Debug, Eq, ToJson, FromJson)
