///|
/// Typed transport and canonical editor snapshot contracts shared by Mooncast
/// Rabbita surfaces. Domain state remains owned by the Mooncast pack server.
pub(all) struct ApiErrorBody {
  code : String
  message : String
} derive(FromJson, ToJson)

///|
pub(all) struct ProjectSummary {
  project_id : String
  revision : Int
  title : String
  fixture : Bool
  publication_authority : Bool
  provider_authority : Bool
} derive(FromJson)

///|
pub(all) struct ProjectListEnvelope {
  ok : Bool
  data : Array[ProjectSummary]
  conflict : Bool
  error : ApiErrorBody?
} derive(FromJson)

///|
pub(all) struct Identity {
  project_id : String
  episode_id : String
  scene_id : String
  shot_id : String
  asset_id : String
} derive(FromJson, ToJson)

///|
pub(all) struct StatusRecord {
  status : String
  findings : Array[String]?
} derive(FromJson)

///|
pub(all) struct SourceBinding {
  state : String
  mime : String?
  media_url : String?
  analysis_url : String?
  thumbnail_url : String?
  proxy_state : String?
  proxy_digest : String?
  proxy_profile : String?
  proxy_url : String?
  digest : String?
} derive(FromJson)

///|
pub(all) struct LocalMediaBinding {
  role : String?
  file_name : String?
  rights_ref : String?
} derive(FromJson)

///|
pub(all) struct IntentBinding {
  intent_ref : String
} derive(FromJson, ToJson)

///|
pub(all) struct TransitionSettings {
  name : String
  duration_ticks : Int
} derive(FromJson, ToJson)

///|
pub(all) struct ColorSettings {
  brightness : Double
  contrast : Double
  saturation : Double
  gamma : Double
} derive(FromJson, ToJson)

///|
pub(all) struct EffectSettings {
  opacity : Double
  scale : Double
  x : Double
  y : Double
} derive(FromJson, ToJson)

///|
pub(all) struct OverlaySettings {
  text : String
  font_size : Int
  color : String
  background : String
  position : String
} derive(FromJson, ToJson)

///|
pub(all) struct ClipSettings {
  transition : TransitionSettings?
  color : ColorSettings?
  effect : EffectSettings?
  overlay : OverlaySettings?
} derive(FromJson, ToJson)

///|
pub(all) struct KeyframePoint {
  tick : Int
  value : Double
  interpolation : String
} derive(FromJson, ToJson)

///|
pub(all) struct Clip {
  clip_id : String
  media_ref_id : String
  identity : Identity
  intent : IntentBinding
  start_tick : Int
  duration_ticks : Int
  source_in_tick : Int
  source_out_tick : Int
  settings : ClipSettings?
  keyframes : Json?
  effects : Array[Json]?
  effect_stack_digest : String?
} derive(FromJson, ToJson)

///|
pub(all) struct TrackMix {
  volume_db : Double
  pan : Double
  muted : Bool
} derive(FromJson, ToJson)

///|
pub(all) struct Track {
  track_id : String
  kind : String
  label : String?
  clips : Array[Clip]
  mix : TrackMix?
} derive(FromJson)

///|
pub(all) struct Timebase {
  ticks_per_second : Int
} derive(FromJson, ToJson)

///|
pub(all) struct FrameRate {
  numerator : Int
  denominator : Int
} derive(FromJson, ToJson)

///|
pub(all) struct OutputSettings {
  preset : String?
  fps : FrameRate?
  background : String?
} derive(FromJson)

///|
pub(all) struct Timeline {
  timeline_id : String
  revision : Int
  timebase : Timebase
  tracks : Array[Track]
  transitions : Array[TimelineTransition]
  output : OutputSettings?
} derive(FromJson)

///|
pub(all) struct TimelineTransition {
  transition_id : String
  from_clip_id : String
  to_clip_id : String
  kind : String
  duration_ticks : Int
  track_id : String?
  outgoing_handle_ticks : Int?
  incoming_handle_ticks : Int?
  color : String?
  direction : String?
  start_tick : Int?
  end_tick : Int?
} derive(FromJson)

///|
pub(all) struct AddClipTemplate {
  track_id : String
  clip : Clip
} derive(FromJson)

///|
pub(all) struct TakeVariant {
  take_id : String
  role : String
  variant : String
  project_id : String
  episode_id : String
  scene_id : String
  shot_id : String
  asset_id : String
  duration_ticks : Int
  qc : StatusRecord
  rights : StatusRecord
  provider_ref : String?
  model_ref : String?
  model_version : String?
  prompt_digest : String?
  attempt_id : String?
  media_ref_id : String
  registry_digest : String
  local_media : LocalMediaBinding?
  track_id : String
  track_kind : String
  already_placed : Bool
  approved : Bool
  intent_ref : String
  source : SourceBinding
  add_clip_template : AddClipTemplate?
} derive(FromJson)

///|
pub(all) struct TimelineRange {
  start_tick : Int
  end_tick : Int
} derive(FromJson)

///|
pub(all) struct Annotation {
  annotation_id : String?
  comment_id : String?
  kind : String
  start_tick : Int?
  end_tick : Int?
  range : TimelineRange?
  text : String?
} derive(FromJson)

///|
pub(all) struct DeliveryIntent {
  delivery_id : String
  orientation : String?
  width : Int?
  height : Int?
} derive(FromJson)

///|
pub(all) struct ProductionSource {
  contract : String?
  project_id : String?
  episode_id : String?
  production_revision : Int?
  production_digest : String?
  g4_evidence_digest : String?
  g4_receipt_digest : String?
  g4_snapshot_revision : Int?
  provenance_ref : String?
  binding_digest : String?
  publication_authority : Bool?
  provider_authority : Bool?
} derive(FromJson)

///|
pub(all) struct MasterPromotion {
  contract : String
  master_id : String
  project_id : String
  project_revision : Int
  editor_revision : Int
  job_id : String
  digest : String
  size : Int
  video_ref : String
  subtitle_ref : String
  plan_digest : String
  actor : String
  authority_ref : String
  promoted_at : String
  publication_authority : Bool
} derive(FromJson)

///|
pub(all) struct CommandRecord {
  command : Json
} derive(FromJson)

///|
pub(all) struct WorkspaceSnapshot {
  project_id : String?
  revision : Int
  navigator : Array[Identity]?
  identity_graph : Array[Identity]?
  take_variants : Array[TakeVariant]?
  timeline : Timeline?
  snapshot : CanonicalSnapshot?
  command_log : Array[CommandRecord]?
  continuity_qc_overlays : Array[Annotation]?
  review_comments : Array[Annotation]?
  delivery_intents : Array[DeliveryIntent]?
  production_source : ProductionSource?
  master_promotion : MasterPromotion?
  publication_authority : Bool?
  provider_authority : Bool?
} derive(FromJson)

///|
pub(all) struct CanonicalSnapshot {
  project_id : String
  revision : Int
  identity_graph : Array[Identity]?
  timeline : Timeline
} derive(FromJson)

///|
pub(all) struct WorkspaceEnvelope {
  ok : Bool
  revision : Int?
  conflict : Bool
  error : ApiErrorBody?
  data : WorkspaceSnapshot
} derive(FromJson)

///|
pub(all) struct MutationData {
  snapshot : CanonicalSnapshot
  revision : Int
  idempotency_key : String?
} derive(FromJson)

///|
pub(all) struct MutationEnvelope {
  ok : Bool
  revision : Int?
  conflict : Bool
  error : ApiErrorBody?
  data : MutationData
} derive(FromJson)

///|
pub(all) struct MediaAnalysis {
  contract : String
  state : String
  source_digest : String
  analysis_digest : String?
  thumbnail_url : String?
  duration_seconds : Double?
  thumbnail : Json?
  waveform : WaveformAnalysis?
  video : Json?
  audio : Json?
} derive(FromJson)

///|
pub(all) struct WaveformAnalysis {
  state : String
  peaks : Array[Double]
} derive(FromJson)

///|
pub(all) struct AnalysisEnvelope {
  ok : Bool
  conflict : Bool
  error : ApiErrorBody?
  data : MediaAnalysis
} derive(FromJson)

///|
pub(all) struct PreviewJob {
  session_id : String?
  job_id : String?
  state : String?
  status : String?
  attempts : Int?
  max_attempts : Int?
  revision : Int?
  error : ApiErrorBody?
  output : PreviewOutput?
} derive(FromJson)

///|
pub(all) struct PreviewOutput {
  cache : CacheReport?
  validated_media : Json?
  plan_digest : String?
  spec_digest : String?
  provenance_digest : String?
} derive(FromJson)

///|
pub(all) struct CacheRange {
  start_tick : Int
  duration_ticks : Int?
  end_tick : Int?
} derive(FromJson)

///|
pub(all) struct ProxyReadiness {
  source_digest : String
  proxy_digest : String?
  state : String
  profile : String?
} derive(FromJson)

///|
pub(all) struct CacheReport {
  contract : String
  profile : String?
  segment_count : Int?
  cache_hit_ranges : Array[CacheRange]
  cache_miss_ranges : Array[CacheRange]
  rebuilt_ranges : Array[CacheRange]?
  proxy_readiness : Array[ProxyReadiness]
  report_digest : String?
} derive(FromJson)

///|
pub(all) struct PreviewEnvelope {
  ok : Bool
  conflict : Bool
  error : ApiErrorBody?
  data : PreviewJob
} derive(FromJson)

///|
pub(all) struct IntakeCreated {
  intake_id : String
  upload_url : String
  expected_editor_revision : Int
} derive(FromJson)

///|
pub(all) struct IntakeCompleted {
  intake_id : String
  track_id : String
  registry_digest : String
} derive(FromJson)

///|
pub(all) struct IntakeEnvelope {
  ok : Bool
  conflict : Bool
  error : ApiErrorBody?
  data : IntakeCreated
} derive(FromJson)

///|
pub(all) struct IntakeCompletionEnvelope {
  ok : Bool
  conflict : Bool
  error : ApiErrorBody?
  data : IntakeCompleted
} derive(FromJson)

///|
pub(all) struct ExportResult {
  job_id : String?
  export_id : String?
  state : String?
  status : String?
  project_revision : Int?
  download_url : String?
  result : Json?
  project : Json?
} derive(FromJson)

///|
pub(all) struct ExportEnvelope {
  ok : Bool
  conflict : Bool
  error : ApiErrorBody?
  data : ExportResult
} derive(FromJson)

///|
pub(all) struct GenericEnvelope {
  ok : Bool
  conflict : Bool
  error : ApiErrorBody?
  data : Json
} derive(FromJson)

///|
pub(all) struct EditorCommand {
  command_type : String
  payload : Json
}

///|
pub impl ToJson for EditorCommand with fn to_json(self : EditorCommand) -> Json {
  { "type": self.command_type, "payload": self.payload }
}

///|
pub(all) struct CommandRequest {
  command : EditorCommand
  expected_revision : Int
  idempotency_key : String
} derive(ToJson)

///|
pub(all) struct PreviewRequest {
  session_id : String
  project_id : String
  timeline_id : String
  project_revision : Int
  timeline_revision : Int
  timebase : Timebase
  range : PreviewRange
  quality : String
  created_at : String
} derive(ToJson)

///|
pub(all) struct PreviewRange {
  start_tick : Int
  duration_ticks : Int
} derive(ToJson)

///|
pub(all) struct ReviewComment {
  comment_id : String
  kind : String
  start_tick : Int
  end_tick : Int
  text : String
  revision_round : Int
} derive(ToJson)

///|
pub(all) struct ReviewCommentRequest {
  comment : ReviewComment
  expected_revision : Int
  idempotency_key : String
} derive(ToJson)
