///|
pub(all) struct ReelEdlSource {
  reel : String
  source_id : String
  media : String
  transcript : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct ReelEdlExcerpt {
  source_id : String
  first_cue : Int
  last_cue : Int
  source_start_ms : Int
  source_end_ms : Int
  rounded : Bool
  cut : @edl.Cut
} derive(Debug, Eq, ToJson)

///|
pub(all) struct ReelEdl {
  contract : String
  fps : Int
  rounding : String
  record_start_timecode : String
  duration_frames : Int
  sources : Array[ReelEdlSource]
  excerpts : Array[ReelEdlExcerpt]
  edl : String
} derive(Debug, Eq, ToJson)

///|
/// Create a video-only CMX3600 cut list from transcript selections. Exact mode
/// refuses non-frame boundaries. Cover mode rounds source-in down/source-out up,
/// retaining the selected speech. Neither mode interprets camera timecode.
pub fn export_reel_edl(
  recipe : @render.ReelRecipe,
  transcripts : Array[Array[@domain.SubtitleCue]],
  fps : Int,
  rounding : String,
) -> ReelEdl raise {
  // Reuse the established recipe/selection bounds, cue order and overlap rules.
  let reel = @render.multi_source_reel(recipe, transcripts)
  let origin = @edl.timecode_frames("01:00:00:00", fps)
  guard rounding == "exact" || rounding == "cover" else {
    fail("rounding must be exact or cover")
  }
  let ordered = recipe.sources.copy()
  ordered.sort_by((left, right) => ascii_id_compare(left.id, right.id))
  let sources : Array[ReelEdlSource] = []
  for i, source in ordered {
    sources.push({
      reel: "SRC0000" + (i + 1).to_string(),
      source_id: source.id,
      media: source.media,
      transcript: source.transcript,
    })
  }
  let lines = [
    "TITLE: MoonCast transcript rough cut", "FCM: NON-DROP FRAME", "",
  ]
  let excerpts : Array[ReelEdlExcerpt] = []
  let mut cursor = origin
  for i, excerpt in reel.excerpts {
    let start = excerpt.source_start_ms * fps
    let end = excerpt.source_end_ms * fps
    let rounded = start % 1000 != 0 || end % 1000 != 0
    guard rounding == "cover" || !rounded else {
      fail(
        "excerpt " +
        (i + 1).to_string() +
        " is not frame-aligned; choose cover explicitly or revise the cue times",
      )
    }
    let source_in_frame = start / 1000
    let source_out_frame = (end + 999) / 1000
    let duration = source_out_frame - source_in_frame
    guard cursor - origin <= 7200 * fps - duration else {
      fail("rounded EDL exceeds two hours")
    }
    let source = sources[sources
      .search_by(s => s.source_id == excerpt.source_id)
      .unwrap()]
    let event = i + 1
    let cut : @edl.Cut = {
      event_number: event,
      reel: source.reel,
      source_in_frame,
      source_out_frame,
      record_in_frame: cursor,
      record_out_frame: cursor + duration,
    }
    lines.push(
      "0".repeat(3 - event.to_string().length()) +
      event.to_string() +
      "  " +
      source.reel +
      "  V  C  " +
      @edl.frames_timecode(cut.source_in_frame, fps) +
      " " +
      @edl.frames_timecode(cut.source_out_frame, fps) +
      " " +
      @edl.frames_timecode(cut.record_in_frame, fps) +
      " " +
      @edl.frames_timecode(cut.record_out_frame, fps),
    )
    lines.push(
      "* FROM CLIP NAME: " + source.media.split("/").last().unwrap().to_string(),
    )
    lines.push("* SOURCE FILE: " + source.media)
    excerpts.push({
      source_id: excerpt.source_id,
      first_cue: excerpt.first_cue,
      last_cue: excerpt.last_cue,
      source_start_ms: excerpt.source_start_ms,
      source_end_ms: excerpt.source_end_ms,
      rounded,
      cut,
    })
    cursor += duration
  }
  let edl = lines.join("\n") + "\n"
  // Exercise the same supported CMX3600 profile used by native cut import.
  let parsed = @edl.parse_edl(edl, fps)
  guard parsed.cuts == excerpts.map(e => e.cut) else {
    fail("EDL serialization did not preserve the planned cuts")
  }
  {
    contract: "mooncast.transcript-edl.v1",
    fps,
    rounding,
    record_start_timecode: "01:00:00:00",
    duration_frames: cursor - origin,
    sources,
    excerpts,
    edl,
  }
}

///|
// Source IDs have already been validated as ASCII. String's pinned Ord is
// shortlex, so compare code units explicitly to implement lexical reel order.
fn ascii_id_compare(left : String, right : String) -> Int {
  for i = 0; i < left.length() && i < right.length(); i = i + 1 {
    if left[i] < right[i] {
      return -1
    }
    if left[i] > right[i] {
      return 1
    }
  }
  left.length().compare(right.length())
}
