///|
/// A source-clock transcript, or an explicit choice to leave this media silent.
pub(all) struct SourceCaptions {
  media_ref_id : String
  draft : @captions.CaptionDraft?
} derive(Debug, Eq)

///|
pub(all) struct CueOrigin {
  output_cue : Int
  clip_id : String
  media_ref_id : String
  source_file : String
  source_cue : Int
  source_start_ms : Int
  source_end_ms : Int
  clipped_at_cut : Bool
  rounded_inward : Bool
} derive(Debug, Eq, ToJson)

///|
pub(all) struct ConformedCaptions {
  contract : String
  project_id : String
  project_revision : Int
  timeline_id : String
  timeline_revision : Int
  ticks_per_second : Int
  silent_media_ref_ids : Array[String]
  draft : @captions.CaptionDraft
  origins : Array[CueOrigin]
} derive(Debug, Eq, ToJson)

///|
/// Whole milliseconds available inside the media, with the same two-hour bound
/// as caption editing. Source captions are relative to media file time zero.
pub fn media_duration_ms(
  project : @domain.EditorProject,
  media_ref_id : String,
) -> Int raise {
  let tps = project.timeline.timebase.ticks_per_second
  guard tps > 0 else { fail("timeline ticks_per_second must be positive") }
  let matches = project.media_refs.filter(m => m.media_ref_id == media_ref_id)
  guard matches.length() == 1 &&
    matches[0].metadata.mime_type.has_prefix("video/") &&
    matches[0].metadata.duration_ticks > 0 else {
    fail(
      "expected one video media reference with known duration: " + media_ref_id,
    )
  }
  let ms = matches[0].metadata.duration_ticks.to_int64() *
    1000L /
    tps.to_int64()
  guard ms > 0L && ms <= 7200000L else {
    fail("caption source duration must be 1 ms to two hours: " + media_ref_id)
  }
  ms.to_int()
}
