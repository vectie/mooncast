///|
/// A deliberately selected chapter draft whose clock starts at this media's zero.
pub(all) struct SourceChapters {
  media_ref_id : String
  draft : @chapters.Draft
} derive(Eq)

///|
/// One surviving part of a source chapter. Each cut retains its own marker.
pub(all) struct ChapterOrigin {
  output_marker_id : String
  clip_id : String
  media_ref_id : String
  source_marker_id : String
  source_start_tick : Int
  source_end_tick : Int
  source_ticks_per_second : Int
  output_start_tick : Int
  output_end_tick : Int
  clipped_at_start : Bool
  clipped_at_end : Bool
} derive(Eq, ToJson)

///|
/// Zero occurrences means the source chapter was removed by the selected cut.
pub(all) struct ChapterUse {
  media_ref_id : String
  source_marker_id : String
  output_marker_ids : Array[String]
} derive(Eq, ToJson)

///|
pub(all) struct ConformedChapters {
  contract : String
  draft : @chapters.Draft
  origins : Array[ChapterOrigin]
  source_uses : Array[ChapterUse]
} derive(Eq, ToJson)
