///|
pub(all) struct Chapter {
  title : String
  start_ms : Int
} derive(Eq, ToJson)

///|
pub(all) struct Plan {
  contract : String
  title : String
  duration_ms : Int
  cues : Array[@captions.Caption]
  chapters : Array[Chapter]
} derive(Eq, ToJson)

///|
/// A browser-oriented, local screening profile. It copies bytes, never transcodes.
pub fn plan(
  media : @media.Media,
  title : String,
  captions? : @captions.CaptionDraft,
  chapters? : @chapters.Draft,
) -> Plan raise {
  guard media.suffix == ".mp4" &&
    media.duration_ms > 0 &&
    media.duration_ms <= 7200000 else {
    fail("screening requires an MP4 of at most two hours")
  }
  guard media.tracks.filter(t => t.kind == "video").length() == 1 &&
    media.tracks.filter(t => t.kind == "audio").length() <= 1 &&
    media.tracks.all(t => {
      (t.kind == "video" && t.codec == "h264") ||
      (t.kind == "audio" && t.codec == "aac")
    }) else {
    fail(
      "use one H.264 video and at most one AAC audio track; extract embedded captions to a draft first",
    )
  }
  guard !title.is_blank() &&
    title.length() <= 200 &&
    title.iter().all(c => c >= ' ' && c != '\u{7f}') else {
    fail("title must be a nonblank single line of at most 200 characters")
  }
  let cues = match captions {
    None => []
    Some(draft) => {
      draft.validate()
      guard (draft.duration_ms - media.duration_ms).abs() <= 50 &&
        draft.cues.all(c => c.end_ms <= media.duration_ms) else {
        fail(
          "caption duration must match the video within 50 ms and every cue must fit inside it",
        )
      }
      ignore(draft.vtt())
      draft.cues.copy()
    }
  }
  let markers : Array[Chapter] = []
  if chapters is Some(draft) {
    draft.validate()
    let duration_ms = draft.duration_ticks.to_int64() *
      1000L /
      draft.ticks_per_second.to_int64()
    guard (duration_ms - media.duration_ms.to_int64()).abs() <= 50L else {
      fail("chapter duration must match the video within 50 ms")
    }
    ignore(draft.webvtt())
    for marker in draft.markers {
      let ms = marker.start_tick.to_int64() *
        1000L /
        draft.ticks_per_second.to_int64()
      guard ms >= 0L && ms < media.duration_ms.to_int64() else {
        fail("chapter starts must fit inside the video")
      }
      markers.push({ title: marker.title, start_ms: ms.to_int(), })
    }
  }
  {
    contract: "mooncast.screening-plan.v1",
    title,
    duration_ms: media.duration_ms,
    cues,
    chapters: markers,
  }
}
