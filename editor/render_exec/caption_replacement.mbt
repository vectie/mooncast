///|
/// Explicitly map the new SRT in the selected stream's original position.
/// Preserve all other compressed streams, chapters, labels and dispositions.
pub fn compile_caption_replacement(
  indices : Array[Int],
  output_position : Int,
  suffix : String,
  stream_dispositions : Array[Array[String]],
  source : String,
  srt : String,
  output : String,
) -> @process.CommandSpec {
  let args = [
    "-hide_banner", "-v", "error", "-nostdin", "-n", "-protocol_whitelist", "file,pipe",
    "-i", source, "-protocol_whitelist", "file,pipe", "-f", "srt", "-i", srt,
  ]
  for i, index in indices {
    args.append([
      "-map",
      if i == output_position {
        "1:0"
      } else {
        "0:" + index.to_string()
      },
    ])
  }
  let position = output_position.to_string()
  args.append([
    "-map_metadata",
    "0",
    "-map_chapters",
    "0",
    "-c",
    "copy",
    "-c:" + position,
    if suffix == ".mp4" {
      "mov_text"
    } else {
      "srt"
    },
  ])
  // One explicit stream-metadata mapping disables FFmpeg's automatic copies
  // for every stream, so map each original stream's tags deliberately.
  for i, index in indices {
    args.append(["-map_metadata:s:" + i.to_string(), "0:s:" + index.to_string()])
  }
  for i, dispositions in stream_dispositions {
    args.append([
      "-disposition:" + i.to_string(),
      if dispositions.is_empty() {
        "0"
      } else {
        dispositions.join("+")
      },
    ])
  }
  args.push(output)
  {
    executable: "ffmpeg",
    arguments: args,
    working_directory: None,
    timeout_ms: 300000,
    max_output_bytes: 2097152,
  }
}
