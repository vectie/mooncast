///|
pub(all) struct AudioTrack {
  index : Int
  codec : String
  language : String
  title : String
  channels : Int
  sample_rate : Int
  start_ms : Double
  duration_ms : Double?
} derive(Eq, ToJson)

///|
pub(all) struct Source {
  format : String
  duration_ms : Double
  audio_tracks : Array[AudioTrack]
  stream_indices : Array[Int]
} derive(ToJson)

///|
pub(all) struct Plan {
  track : AudioTrack
  duration_ms : Int
  omitted_stream_indices : Array[Int]
  output_codec : String
  output_sample_rate : Int
  target_bitrate : Int
} derive(ToJson)

///|
fn text(value : Json, key : String) -> String raise {
  guard value is Object(fields) && fields.get(key) is Some(String(value)) else {
    fail("missing probe string: " + key)
  }
  value
}

///|
fn optional_seconds(value : Json, key : String) -> Double? raise {
  guard value is Object(fields) else { fail("expected probe object") }
  match fields.get(key) {
    None => None
    Some(String(value)) => {
      let n = @string.parse_double(value) * 1000.0
      guard n >= -7200050.0 && n <= 7200050.0 else {
        fail("invalid or unbounded media timestamp: " + key)
      }
      Some(n)
    }
    _ => fail("expected timestamp string: " + key)
  }
}

///|
/// Inspect an actual local container. Other streams are listed so the user can
/// see what the listening edition deliberately omits; no stream is auto-picked.
pub fn inspect_source(probe : Json) -> Source raise {
  guard probe is { "format": format, "streams": Array(streams), .. } else {
    fail("source requires format and streams")
  }
  let name = text(format, "format_name")
  guard name == "mov,mp4,m4a,3gp,3g2,mj2" ||
    name == "matroska,webm" ||
    name == "wav" ||
    name == "flac" else {
    fail("supported input containers: MP4/M4A, Matroska, WAV and FLAC")
  }
  guard optional_seconds(format, "duration") is Some(duration_ms) &&
    duration_ms > 0.0 else {
    fail("source requires a positive duration up to two hours")
  }
  let start = optional_seconds(format, "start_time")
  guard (start is Some(n) && n >= -1.0 && n <= 1.0) ||
    (start is None && (name == "wav" || name == "flac")) else {
    fail("source must start at zero; shifted containers require an edit")
  }
  guard !streams.is_empty() && streams.length() <= 32 else {
    fail("source must contain 1–32 streams")
  }
  let indices : Array[Int] = []
  let tracks : Array[AudioTrack] = []
  for stream in streams {
    guard stream is { "index": Number(index), "codec_type": String(kind), .. } &&
      index >= 0.0 &&
      index <= 1000.0 &&
      index == index.to_int().to_double() &&
      !indices.contains(index.to_int()) else {
      fail("invalid or duplicate stream index")
    }
    indices.push(index.to_int())
    if kind != "audio" {
      continue
    }
    guard stream is { "channels": Number(channels), .. } &&
      channels >= 1.0 &&
      channels <= 64.0 &&
      channels == channels.to_int().to_double() else {
      fail("audio stream has invalid channel count")
    }
    let sample_rate = @string.parse_int(text(stream, "sample_rate"))
    guard sample_rate > 0 && sample_rate <= 384000 else {
      fail("invalid sample rate")
    }
    let language = match stream {
      { "tags": { "language": String(language), .. }, .. } => language
      _ => "und"
    }
    let title = match stream {
      { "tags": { "title": String(title), .. }, .. } => title
      _ => ""
    }
    let start = optional_seconds(stream, "start_time")
    let start_ms = match start {
      Some(n) => n
      None =>
        if name == "wav" || name == "flac" {
          0.0
        } else {
          fail("audio stream requires a known start time")
        }
    }
    tracks.push({
      index: index.to_int(),
      codec: text(stream, "codec_name"),
      language,
      title,
      channels: channels.to_int(),
      sample_rate,
      start_ms,
      duration_ms: optional_seconds(stream, "duration"),
    })
  }
  guard !tracks.is_empty() && tracks.length() <= 16 else {
    fail("source must contain 1–16 audio tracks")
  }
  { format: name, duration_ms, audio_tracks: tracks, stream_indices: indices, }
}

///|
pub fn prepare(
  draft : @chapters.Draft,
  source : Source,
  index : Int,
) -> Plan raise {
  @chapter_media.validate_draft(draft)
  guard draft.markers[0].start_tick == 0 else {
    fail("the listening edition's first chapter must start at zero")
  }
  let duration_ms = (draft.duration_ticks.to_int64() *
  1000L /
  draft.ticks_per_second.to_int64()).to_int()
  let expected = duration_ms.to_double()
  guard source.duration_ms >= expected - 50.0 &&
    source.duration_ms <= expected + 50.0 else {
    fail("source and chapter durations differ by more than 50 ms")
  }
  let selected = source.audio_tracks.filter(track => track.index == index)
  guard selected.length() == 1 else {
    fail("choose one listed audio stream index")
  }
  let track = selected[0]
  guard track.channels == 1 || track.channels == 2 else {
    fail("choose mono or stereo audio; surround downmix is not implicit")
  }
  guard track.start_ms >= -1.0 && track.start_ms <= 1.0 else {
    fail("selected audio must start at zero")
  }
  if track.duration_ms is Some(duration) {
    guard duration >= expected - 50.0 && duration <= expected + 50.0 else {
      fail("selected audio duration differs from chapters by more than 50 ms")
    }
  }
  guard track.language.length() == 3 &&
    track.language.iter().all(c => c >= 'a' && c <= 'z') else {
    fail("M4A requires a three-letter lowercase language tag (or und)")
  }
  {
    track,
    duration_ms,
    omitted_stream_indices: source.stream_indices.filter(i => i != index),
    output_codec: "aac",
    output_sample_rate: 48000,
    target_bitrate: 160000,
  }
}
