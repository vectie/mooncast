///|
struct OutputProbeStream {
  codec_type : String
  codec_name : String
  width : Int?
  height : Int?
  r_frame_rate : String?
} derive(FromJson)

///|
struct OutputProbeFormat {
  duration : String
  size : String
  format_name : String
} derive(FromJson)

///|
struct OutputProbeDocument {
  streams : Array[OutputProbeStream]
  format : OutputProbeFormat
} derive(FromJson)

///|
pub(all) struct OutputExpectation {
  project_id : String
  plan_digest : String
  duration_seconds : Double
  width : Int
  height : Int
  fps : @domain.FrameRate
  container : String
  video_codec : String
  audio_codec : String
  audio_required : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OutputInspection {
  contract : String
  project_id : String
  plan_digest : String
  output_digest : String
  output_size : Int
  duration_seconds : Double
  width : Int
  height : Int
  frame_rate : String
  format_name : String
  video_codec : String
  audio_codec : String
  passed : Bool
  checks : Array[String]
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn expected_probe_codec(value : String) -> String {
  match value {
    "h264" => "h264"
    "vp9" => "vp9"
    "aac" => "aac"
    "opus" => "opus"
    _ => value
  }
}

///|
/// Runs the bounded probe and rejects a technically incomplete delivery.
pub async fn inspect_render_output(
  ffprobe : String,
  source_path : String,
  output_digest : String,
  output_size : Int,
  expected : OutputExpectation,
) -> OutputInspection {
  guard output_digest.has_prefix("sha256:") && output_size > 0 else {
    fail("render output content receipt is invalid")
  }
  let result = @process.run_capture({
    executable: ffprobe,
    arguments: [
      "-v", "error", "-show_streams", "-show_format", "-of", "json", source_path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 1048576,
  })
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail("render output probe failed")
  }
  let document : OutputProbeDocument = @json.from_json(
    @json.parse(@utf8.decode(result.stdout)),
  )
  let mut video_codec = ""
  let mut audio_codec = ""
  let mut width = 0
  let mut height = 0
  let mut frame_rate = ""
  for stream in document.streams {
    if stream.codec_type == "video" {
      video_codec = stream.codec_name
      if stream.width is Some(value) {
        width = value
      }
      if stream.height is Some(value) {
        height = value
      }
      if stream.r_frame_rate is Some(value) {
        frame_rate = value
      }
    }
    if stream.codec_type == "audio" {
      audio_codec = stream.codec_name
    }
  }
  let duration = @string.parse_double(document.format.duration) catch {
    _ => fail("render output duration is invalid")
  }
  let reported_size = @string.parse_int(document.format.size) catch {
    _ => fail("render output size is invalid")
  }
  let frame_duration = expected.fps.denominator.to_double() /
    expected.fps.numerator.to_double()
  let checks : Array[String] = []
  guard (duration - expected.duration_seconds).abs() <= frame_duration * 2.0 else {
    fail("render output duration mismatch")
  }
  checks.push("duration")
  guard width == expected.width && height == expected.height else {
    fail("render output dimensions mismatch")
  }
  checks.push("dimensions")
  guard video_codec == expected_probe_codec(expected.video_codec) else {
    fail("render output video codec mismatch")
  }
  checks.push("video-codec")
  if expected.audio_required {
    guard audio_codec == expected_probe_codec(expected.audio_codec) else {
      fail("render output audio codec mismatch")
    }
    checks.push("audio-codec")
  }
  guard reported_size == output_size else {
    fail("render output size receipt mismatch")
  }
  checks.push("content-size")
  let format_ok = match expected.container {
    "mp4" =>
      document.format.format_name.contains("mp4") ||
      document.format.format_name.contains("mov")
    "webm" => document.format.format_name.contains("webm")
    "mkv" => document.format.format_name.contains("matroska")
    _ => false
  }
  guard format_ok else { fail("render output container mismatch") }
  checks.push("container")
  {
    contract: "mooncast.editor-output-inspection.v1",
    project_id: expected.project_id,
    plan_digest: expected.plan_digest,
    output_digest,
    output_size,
    duration_seconds: duration,
    width,
    height,
    frame_rate,
    format_name: document.format.format_name,
    video_codec,
    audio_codec,
    passed: true,
    checks,
    publication_authority: false,
  }
}
