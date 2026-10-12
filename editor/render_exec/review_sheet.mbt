///|
/// Fixed, bounded review image. Exact timestamp is a seek request, not a claim
/// of frame PTS. Accurate input seeking decodes forward to the first eligible
/// frame. Source must have square pixels and start at zero (checked by CLI).
pub fn compile_review_frame(
  source : String,
  video_index : Int,
  requested_ms : Int,
  output : String,
) -> @process.CommandSpec {
  {
    executable: "ffmpeg",
    arguments: [
      "-hide_banner",
      "-v",
      "error",
      "-nostdin",
      "-n",
      "-threads",
      "1",
      "-ss",
      (requested_ms.to_double() / 1000.0).to_string(),
      "-protocol_whitelist",
      "file,pipe",
      "-i",
      source,
      "-map",
      "0:" + video_index.to_string(),
      "-frames:v",
      "1",
      "-an",
      "-sn",
      "-dn",
      "-vf",
      "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2,setsar=1",
      "-c:v",
      "png",
      "-threads",
      "1",
      "-f",
      "image2",
      "-update",
      "1",
      output,
    ],
    working_directory: None,
    timeout_ms: 120000,
    max_output_bytes: 1048576,
  }
}

///|
pub fn compile_review_probe(source : String) -> @process.CommandSpec {
  {
    executable: "ffprobe",
    arguments: [
      "-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_chapters",
      "-show_format", "-of", "json", source,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 2097152,
  }
}
