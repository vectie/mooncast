///|
/// A replacement keeps the original stream position, labels and dispositions.
/// Stream positions here exclude regenerated MP4 chapter-navigation data.
pub(all) struct ReplacementPlan {
  media : Media
  selected : Track
  output_position : Int
  stream_dispositions : Array[Array[String]]
} derive(ToJson)

///|
pub extend ReplacementPlan with ToJson::{to_json}

///|
fn stream_dispositions(probe : Json, index : Int) -> Array[String] raise {
  guard probe is { "streams": Array(streams), .. } else {
    fail("missing stream dispositions")
  }
  for stream in streams {
    if stream
      is { "index": Number(found, ..), "disposition": Object(flags), .. } &&
      found == index.to_double() {
      let enabled : Array[String] = []
      for name, value in flags {
        guard !name.is_empty() &&
          name.iter().all(c => (c >= 'a' && c <= 'z') || c == '_') &&
          (value == Json::number(0) || value == Json::number(1)) else {
          fail("unsupported stream disposition metadata")
        }
        if value == Json::number(1) {
          enabled.push(name)
        }
      }
      enabled.sort_by((a, b) => a.lexical_compare(b))
      return enabled
    }
  }
  fail("missing stream dispositions")
}

///|
/// Reuse the caption editor's exact timings; replacement does not require a
/// vacant stream slot and never infers which language the creator intended.
pub fn prepare_replacement(
  probe : Json,
  draft : @captions.CaptionDraft,
  stream_index : Int,
) -> ReplacementPlan raise {
  let media = inspect_media(probe)
  let selected = select_track(media, stream_index)
  validate_caption_timing(media, draft)
  let dispositions : Array[Array[String]] = []
  let mut position = -1
  for i, track in media.tracks {
    dispositions.push(stream_dispositions(probe, track.index))
    if track.index == stream_index {
      position = i
    }
  }
  {
    media,
    selected,
    output_position: position,
    stream_dispositions: dispositions,
  }
}

///|
/// Verification keeps replacement and append semantics distinct: no additional
/// track, no hidden fallback to a different source, no loss of caption labels.
pub fn verify_replacement(plan : ReplacementPlan, probe : Json) -> Track raise {
  let before = plan.media
  let after = inspect_media(probe)
  guard before.suffix == after.suffix &&
    (before.duration_ms - after.duration_ms).abs() <= 50 &&
    after.tracks.length() == before.tracks.length() else {
    fail("replacement changed container, duration or stream count")
  }
  for i, old in before.tracks {
    let got = after.tracks[i]
    let codec = if i == plan.output_position {
      if before.suffix == ".mp4" {
        "mov_text"
      } else {
        "subrip"
      }
    } else {
      old.codec
    }
    guard old.kind == got.kind &&
      codec == got.codec &&
      old.language == got.language &&
      old.title == got.title &&
      stream_dispositions(probe, got.index) == plan.stream_dispositions[i] else {
      fail("replacement changed a stream's codec, labels or dispositions")
    }
  }
  guard before.chapters.length() == after.chapters.length() else {
    fail("replacement changed chapter count")
  }
  for i, old in before.chapters {
    let got = after.chapters[i]
    guard tag(old, "title", "") == tag(got, "title", "") &&
      (chapter_time(old, "start_time") - chapter_time(got, "start_time")).abs() <=
      0.001 &&
      (chapter_time(old, "end_time") - chapter_time(got, "end_time")).abs() <=
      0.001 else {
      fail("replacement changed chapter timing or title")
    }
  }
  after.tracks[plan.output_position]
}
