///|
fn title(chapter : Json) -> String {
  match chapter {
    { "tags": { "title": String(value), .. }, .. } => value
    _ => ""
  }
}

///|
fn time(chapter : Json, key : String) -> Double raise {
  guard chapter is Object(fields) && fields.get(key) is Some(String(value)) else {
    fail("missing chapter timestamp")
  }
  @string.parse_double(value)
}

///|
/// Check actual stream order, labels, all dispositions, codec, duration and
/// chapter navigation. The appended stream never replaces the original mix.
pub fn verify_output(plan : Plan, probe : Json) -> @media.Track raise {
  let before = plan.media
  let after = @media.inspect_media(probe)
  guard before.suffix == after.suffix &&
    (before.duration_ms - after.duration_ms).abs() <= 50 &&
    after.tracks.length() == before.tracks.length() + 1 else {
    fail("output container, duration or stream count differs")
  }
  for i, old in before.tracks {
    let got = after.tracks[i]
    guard old.kind == got.kind &&
      old.codec == got.codec &&
      old.language == got.language &&
      old.title == got.title &&
      dispositions(probe, got.index) == plan.dispositions[i] else {
      fail("an original stream changed codec, labels or dispositions")
    }
  }
  guard before.chapters.length() == after.chapters.length() else {
    fail("chapter count changed")
  }
  for i, old in before.chapters {
    let got = after.chapters[i]
    guard title(old) == title(got) &&
      (time(old, "start_time") - time(got, "start_time")).abs() <= 0.001 &&
      (time(old, "end_time") - time(got, "end_time")).abs() <= 0.001 else {
      fail("chapter title or timing changed")
    }
  }
  let added = after.tracks[before.tracks.length()]
  guard added.kind == "audio" &&
    added.codec == plan.codec &&
    added.language == plan.language &&
    added.title == plan.title &&
    dispositions(probe, added.index) ==
    (if plan.is_default { ["default"] } else { [] }) else {
    fail("imported audio labels, codec or disposition differ")
  }
  let source = @audio.inspect_source(probe)
  guard source.audio_tracks.iter().find_first(t => t.index == added.index)
    is Some(audio) &&
    audio.channels == plan.audio.channels &&
    audio.sample_rate == 48000 &&
    audio.start_ms.abs() <= 1.0 else {
    fail("imported audio channel count, sample rate or start changed")
  }
  added
}
