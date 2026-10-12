///|
/// A visual-change candidate measured by FFmpeg, not a semantic scene label.
pub(all) struct Detection {
  start_ms : Int
  score : Double
} derive(Eq, ToJson)

///|
pub(all) struct Input {
  duration_ms : Int
  video_index : Int
} derive(Eq, ToJson)

///|
/// Use the existing local MP4/Matroska profile and one explicitly selected
/// video stream. Detection never chooses among alternate video angles.
pub fn inspect_probe(probe : Json) -> Input raise {
  let media = @media.inspect_media(probe)
  guard media.duration_ms <= 1800000 else {
    fail("scene indexing supports at most 30 minutes per local video")
  }
  guard probe is { "streams": Array(streams), .. } else {
    fail("missing video stream")
  }
  for stream in streams {
    if stream is { "codec_type": String("video"), .. } {
      guard stream
        is {
          "index": Number(index, ..),
          "width": Number(width, ..),
          "height": Number(height, ..),
          "start_time": String(start),
          ..
        } &&
        width >= 16.0 &&
        width <= 4096.0 &&
        height >= 16.0 &&
        height <= 4096.0 &&
        @string.parse_double(start).abs() <= 0.001 else {
        fail("video must start at zero and be 16–4096 pixels per dimension")
      }
      if stream is { "color_transfer": String(transfer), .. } {
        guard transfer != "smpte2084" && transfer != "arib-std-b67" else {
          fail("HDR scene analysis needs a separate color-managed workflow")
        }
      }
      return { duration_ms: media.duration_ms, video_index: index.to_int(), }
    }
  }
  fail("missing video stream")
}

///|
pub fn validate_options(threshold : Int, min_scene_ms : Int) -> Unit raise {
  guard threshold >= 1 && threshold <= 100 else {
    fail("scene threshold must be an integer from 1 to 100")
  }
  guard min_scene_ms >= 100 && min_scene_ms <= 60000 else {
    fail("minimum scene length must be 100–60000 milliseconds")
  }
}

///|
/// FFmpeg converts only analysis frames to a fixed 320×180 yuv420p profile.
/// settb gives metadata integer millisecond PTS; audio and source bytes stay
/// untouched. No shell, network protocols, scene names or provider are used.
pub fn command(
  source : String,
  video_index : Int,
  threshold : Int,
) -> @process.CommandSpec raise {
  validate_options(threshold, 100)
  guard source.has_prefix("/") &&
    !source.contains(":") &&
    video_index >= 0 &&
    video_index <= 1000 else {
    fail("detector requires an absolute local file and valid video index")
  }
  {
    executable: "ffmpeg",
    arguments: [
      "-hide_banner",
      "-v",
      "error",
      "-nostdin",
      "-threads",
      "1",
      "-protocol_whitelist",
      "file,pipe",
      "-i",
      source,
      "-map",
      "0:" + video_index.to_string(),
      "-an",
      "-sn",
      "-dn",
      "-filter_threads",
      "1",
      "-vf",
      "scale=320:180,format=yuv420p,settb=expr=1/1000,scdet=threshold=" +
      threshold.to_string() +
      ":sc_pass=1,metadata=mode=print:key=lavfi.scd.score:file=-",
      "-fps_mode",
      "passthrough",
      "-f",
      "null",
      "/dev/null",
    ],
    working_directory: None,
    timeout_ms: 300000,
    max_output_bytes: 2097152,
  }
}

///|
/// Parse exactly the paired metadata records emitted by command. Empty output
/// is a valid video with no above-threshold visual changes. Header PTS are
/// integer milliseconds; pts_time is descriptive and is never used for timing.
pub fn parse_detections(
  text : String,
  duration_ms : Int,
) -> Array[Detection] raise {
  guard text.length() <= 2097152 && duration_ms > 0 && duration_ms <= 1800000 else {
    fail("invalid detector output size or duration")
  }
  let detections : Array[Detection] = []
  let mut pending : Int? = None
  let mut previous = -1
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.is_empty() {
      continue
    }
    if line.has_prefix("frame:") {
      guard pending is None else { fail("detector frame is missing its score") }
      let fields = line.split(" ").filter(s => !s.is_empty()).to_array()
      guard fields.length() == 3 &&
        fields[1].has_prefix("pts:") &&
        fields[2].has_prefix("pts_time:") else {
        fail("unsupported detector frame metadata")
      }
      let value = fields[1][4:]
      guard !value.is_empty() && value.iter().all(c => c >= '0' && c <= '9') else {
        fail("detector timestamps must be nonnegative integer milliseconds")
      }
      let ms = @string.parse_int(value)
      guard ms >= previous && ms < duration_ms else {
        fail(
          "detector timestamps must be ordered and inside the media duration",
        )
      }
      pending = Some(ms)
    } else if line.has_prefix("lavfi.scd.score=") {
      guard pending is Some(ms) else { fail("detector score has no frame") }
      let score = @string.parse_double(line[16:])
      guard score >= 0.0 && score <= 100.0 else {
        fail("invalid detector score")
      }
      detections.push({ start_ms: ms, score, })
      guard detections.length() <= 10000 else {
        fail("more than 10000 scene candidates; split the media")
      }
      previous = ms
      pending = None
    } else {
      fail("unexpected detector metadata")
    }
  }
  guard pending is None else { fail("incomplete detector output") }
  detections
}
