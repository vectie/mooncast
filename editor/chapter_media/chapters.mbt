///|
/// A local, same-container remux plan. Only the listed streams are copied.
pub(all) struct MediaPlan {
  duration_ms : Double
  stream_indices : Array[Int]
  stream_signatures : Array[String]
  replaced_chapters : Int
  replaced_chapter_data_streams : Int
} derive(ToJson)

///|
fn string_field(value : Json, key : String) -> String raise {
  guard value is Object(fields) && fields.get(key) is Some(String(text)) else {
    fail("missing media probe string: " + key)
  }
  text
}

///|
fn number_text(value : Json, key : String) -> String raise {
  guard value is Object(fields) && fields.get(key) is Some(item) else {
    fail("missing chapter field: " + key)
  }
  match item {
    Number(n) => {
      guard n >= 0.0 && n <= 9007199254740991.0 && n == n.to_int64().to_double() else {
        fail("chapter number must be an exact nonnegative integer")
      }
      n.to_int64().to_string()
    }
    String(text) => text
    _ => fail("expected chapter integer")
  }
}

///|
fn chapter_entries(probe : Json) -> Array[Json] raise {
  guard probe is { "chapters": Array(chapters), .. } else {
    fail("media probe omitted chapters")
  }
  guard chapters.length() <= 1000 else { fail("media has too many chapters") }
  chapters
}

///|
/// Container chapter navigation uses a bounded whole-millisecond profile.
pub fn validate_draft(draft : @chapters.Draft) -> Unit raise {
  draft.validate()
  let clock = draft.ticks_per_second.to_int64()
  let duration = draft.duration_ticks.to_int64() * 1000L
  guard duration % clock == 0L && duration / clock <= 7200000L else {
    fail("chapter duration must be exact milliseconds and at most two hours")
  }
  for marker in draft.markers {
    guard marker.start_tick.to_int64() * 1000L % clock == 0L else {
      fail("container chapter starts must be exact whole milliseconds")
    }
  }
  ignore(draft.ffmetadata())
}

///|
/// Inspect the selected file before copying any bytes or replacing chapters.
pub fn prepare(draft : @chapters.Draft, probe : Json) -> MediaPlan raise {
  validate_draft(draft)
  guard probe is { "streams": Array(streams), "format": format, .. } else {
    fail("media requires stream and format information")
  }
  let format_name = string_field(format, "format_name")
  guard format_name == "mov,mp4,m4a,3gp,3g2,mj2" ||
    format_name == "matroska,webm" else {
    fail("expected an actual MP4 or Matroska container")
  }
  let duration_ms = @string.parse_double(string_field(format, "duration")) *
    1000.0
  let expected = draft.duration_ticks.to_double() *
    1000.0 /
    draft.ticks_per_second.to_double()
  guard duration_ms > 0.0 &&
    duration_ms <= 7200050.0 &&
    duration_ms >= expected - 50.0 &&
    duration_ms <= expected + 50.0 else {
    fail("media duration differs from chapter draft by more than 50 ms")
  }
  let start = @string.parse_double(string_field(format, "start_time"))
  guard start >= -0.001 && start <= 0.001 else {
    fail("media must start at zero; shifted containers require a separate edit")
  }
  let chapters = chapter_entries(probe)
  let indices : Array[Int] = []
  let signatures : Array[String] = []
  let mut videos = 0
  let mut chapter_data = 0
  for stream in streams {
    guard stream
      is {
        "index": Number(index),
        "codec_type": String(kind),
        "codec_name": String(codec),
        ..
      } &&
      index >= 0.0 &&
      index <= 1000.0 &&
      index == index.to_int().to_double() else {
      fail("media has incomplete stream metadata")
    }
    if kind == "data" &&
      !chapters.is_empty() &&
      codec == "bin_data" &&
      stream is { "codec_tag_string": String("text"), .. } {
      chapter_data += 1
      continue
    }
    guard kind == "video" || kind == "audio" || kind == "subtitle" else {
      fail(
        "unsupported stream type; it will not be silently discarded: " + kind,
      )
    }
    if kind == "video" {
      videos += 1
      guard stream is { "disposition": { "attached_pic": Number(0), .. }, .. } else {
        fail("attached pictures are outside this media profile")
      }
    }
    let language = match stream {
      { "tags": { "language": String(language), .. }, .. } => language
      _ => "und"
    }
    guard !indices.contains(index.to_int()) else {
      fail("duplicate stream index")
    }
    indices.push(index.to_int())
    signatures.push(kind + ":" + codec + ":" + language)
  }
  guard videos == 1 && indices.length() <= 17 else {
    fail("expected one video and at most 17 video/audio/subtitle streams")
  }
  {
    duration_ms,
    stream_indices: indices,
    stream_signatures: signatures,
    replaced_chapters: chapters.length(),
    replaced_chapter_data_streams: chapter_data,
  }
}

///|
fn escape_title(title : String) -> String {
  title
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="=", new="\\=")
  .replace_all(old=";", new="\\;")
  .replace_all(old="#", new="\\#")
}

///|
/// Import actual embedded chapters into the explicitly selected draft identity.
/// Exact rational chapter boundaries must survive its clock and duration.
pub fn extract(draft : @chapters.Draft, probe : Json) -> @chapters.Draft raise {
  ignore(prepare(draft, probe))
  let chapters = chapter_entries(probe)
  guard !chapters.is_empty() else { fail("media has no embedded chapters") }
  let metadata = StringBuilder::new()
  metadata.write_string(";FFMETADATA1\n")
  for chapter in chapters {
    guard chapter is { "tags": { "title": String(title), .. }, .. } else {
      fail("each embedded chapter requires a title")
    }
    metadata.write_string(
      "[CHAPTER]\nTIMEBASE=" +
      string_field(chapter, "time_base") +
      "\nSTART=" +
      number_text(chapter, "start") +
      "\nEND=" +
      number_text(chapter, "end") +
      "\ntitle=" +
      escape_title(title) +
      "\n",
    )
  }
  let result = draft.import_ffmetadata(metadata.to_string())
  validate_draft(result)
  result
}

///|
/// Verify streams and every output chapter after the container is written.
pub fn verify_output(
  before : MediaPlan,
  draft : @chapters.Draft,
  probe : Json,
) -> Unit raise {
  let after = prepare(draft, probe)
  guard before.stream_signatures == after.stream_signatures else {
    fail("remux changed media stream codecs, order or languages")
  }
  let actual = extract(draft, probe)
  guard actual.markers.length() == draft.markers.length() else {
    fail("container chapter count changed")
  }
  for i, marker in actual.markers {
    guard marker.start_tick == draft.markers[i].start_tick &&
      marker.title == draft.markers[i].title else {
      fail("container changed chapter timing or title")
    }
  }
}

///|
/// Explicit same-container stream copy; arguments are passed without a shell.
pub fn remux_arguments(
  plan : MediaPlan,
  source : String,
  metadata : String,
  output : String,
) -> Array[String] {
  let args = [
    "-hide_banner", "-v", "error", "-nostdin", "-n", "-protocol_whitelist", "file,pipe",
    "-i", source, "-protocol_whitelist", "file,pipe", "-f", "ffmetadata", "-i", metadata,
  ]
  for index in plan.stream_indices {
    args.append(["-map", "0:" + index.to_string()])
  }
  args.append(["-map_metadata", "0", "-map_chapters", "1", "-c", "copy", output])
  args
}
