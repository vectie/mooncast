///|
fn integer_text(value : Json, key : String) -> String raise {
  guard value is Object(fields) && fields.get(key) is Some(item) else {
    fail("missing chapter number: " + key)
  }
  match item {
    Number(n) => {
      guard n >= 0.0 && n <= 9007199254740991.0 && n == n.to_int64().to_double() else {
        fail("chapter number is not an exact nonnegative integer")
      }
      n.to_int64().to_string()
    }
    String(s) => s
    _ => fail("invalid chapter number")
  }
}

///|
fn escaped(title : String) -> String {
  title
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="=", new="\\=")
  .replace_all(old=";", new="\\;")
  .replace_all(old="#", new="\\#")
}

///|
/// Require one AAC audio stream and only recognized chapter-navigation data.
/// Verify the actual audio duration, not just the chapter-extended container.
pub fn verify_output(
  plan : Plan,
  draft : @chapters.Draft,
  probe : Json,
) -> Unit raise {
  let after = inspect_source(probe)
  guard after.format == "mov,mp4,m4a,3gp,3g2,mj2" &&
    after.audio_tracks.length() == 1 else {
    fail("listening edition must be one audio stream in M4A")
  }
  let track = after.audio_tracks[0]
  let expected = plan.duration_ms.to_double()
  guard track.codec == "aac" &&
    track.channels == plan.track.channels &&
    track.sample_rate == 48000 &&
    track.language == plan.track.language &&
    track.start_ms >= -1.0 &&
    track.start_ms <= 1.0 &&
    after.duration_ms >= expected - 50.0 &&
    after.duration_ms <= expected + 50.0 &&
    track.duration_ms is Some(duration) &&
    duration >= expected - 50.0 &&
    duration <= expected + 50.0 else {
    fail("output audio format, language or duration differs from plan")
  }
  guard probe is { "streams": Array(streams), "chapters": Array(chapters), .. } &&
    chapters.length() == draft.markers.length() else {
    fail("output chapter count differs")
  }
  for stream in streams {
    guard stream is { "codec_type": String("audio"), .. } ||
      stream
      is {
        "codec_type": String("data"),
        "codec_name": String("bin_data"),
        "codec_tag_string": String("text"),
        ..
      } else {
      fail("output contains an unexpected non-audio stream")
    }
  }
  let metadata = StringBuilder::new()
  metadata.write_string(";FFMETADATA1\n")
  for chapter in chapters {
    guard chapter is { "tags": { "title": String(title), .. }, .. } else {
      fail("output chapter has no title")
    }
    metadata.write_string(
      "[CHAPTER]\nTIMEBASE=" +
      text(chapter, "time_base") +
      "\nSTART=" +
      integer_text(chapter, "start") +
      "\nEND=" +
      integer_text(chapter, "end") +
      "\ntitle=" +
      escaped(title) +
      "\n",
    )
  }
  let actual = draft.import_ffmetadata(metadata.to_string())
  for i, marker in actual.markers {
    guard marker.start_tick == draft.markers[i].start_tick &&
      marker.title == draft.markers[i].title else {
      fail("output chapter title or timing changed")
    }
  }
}
