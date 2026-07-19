///|
pub(all) struct TickRange {
  start_tick : Int
  duration_ticks : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlanFinding {
  code : String
  severity : String
  message : String
  track_id : String
  clip_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FrozenClip {
  clip_id : String
  media_ref_id : String
  identity : @domain.ProductionIdentity
  start_tick : Int
  duration_ticks : Int
  source_in_tick : Int
  source_out_tick : Int
  settings : @domain.ClipSettings
  keyframes : @domain.KeyframeSet
  effects : Array[@domain.Effect]
  effect_stack_digest : String
  audio_bus_id : String?
  original_digest : String
  selected_digest : String
  selection : String
  original_source_refs : Array[String]
  original_provenance_refs : Array[String]
  original_rights_refs : Array[String]
  selected_source_refs : Array[String]
  selected_provenance_refs : Array[String]
  selected_rights_refs : Array[String]
  local_media : @domain.LocalMediaBinding?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FrozenTrack {
  track_id : String
  kind : String
  order : Int
  mix : @domain.TrackMix?
  clips : Array[FrozenClip]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FrozenTransition {
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
  relationship : String
  cut_tick : Int
  range : TickRange
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RenderPlan {
  contract : String
  project_id : String
  timeline_id : String
  project_revision : Int
  timeline_revision : Int
  timebase : @domain.Timebase
  output : @domain.OutputSettings
  range : TickRange
  quality : String
  tracks : Array[FrozenTrack]
  transitions : Array[FrozenTransition]
  audio_buses : Array[@domain.AudioBus]
  delivery_audio : @domain.DeliveryAudio
  findings : Array[PlanFinding]
  ready : Bool
  publication_authority : Bool
  plan_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CacheClipProjection {
  clip_id : String
  selected_digest : String
  start_tick : Int
  duration_ticks : Int
  source_in_tick : Int
  source_out_tick : Int
  effect_stack_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Stable, inspectable input to segment-cache identity. It is useful before hashing.
pub(all) struct CacheKeyProjection {
  contract : String
  plan_digest : String
  project_revision : Int
  timeline_revision : Int
  quality : String
  range : TickRange
  output : @domain.OutputSettings
  clips : Array[CacheClipProjection]
  transition_digests : Array[String]
  audio_bus_digests : Array[String]
  delivery_audio_digest : String
  cache_key : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProxyReadiness {
  source_digest : String
  proxy_digest : String
  state : String
  cache_hit : Bool
  profile : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CacheQuota {
  maximum_bytes : Int
  maximum_segments : Int
  current_bytes : Int
  current_segments : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewCacheReport {
  contract : String
  profile : String
  segment_count : Int
  cache_hit_ranges : Array[TickRange]
  cache_miss_ranges : Array[TickRange]
  rebuilt_ranges : Array[TickRange]
  proxy_readiness : Array[ProxyReadiness]
  evicted_segment_keys : Array[String]
  invalidated_segment_keys : Array[String]
  segment_keys : Array[String]
  quota : CacheQuota
  report_digest : String
} derive(Debug, Eq, ToJson, FromJson)
