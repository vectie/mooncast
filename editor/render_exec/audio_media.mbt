///|
/// Encode only the explicit soundtrack stream. This standalone rendition lets
/// the application verify actual selected duration before creating a new master.
pub fn compile_audio_rendition(
  source : String,
  index : Int,
  channels : Int,
  codec : String,
  output : String,
) -> @process.CommandSpec {
  let arguments = [
    "-hide_banner",
    "-v",
    "error",
    "-nostdin",
    "-n",
    "-threads",
    "1",
    "-protocol_whitelist",
    "file,pipe",
    "-i",
    source,
    "-map",
    "0:" + index.to_string(),
    "-map_metadata",
    "-1",
    "-map_chapters",
    "-1",
    "-c:a",
    codec,
    "-ar",
    "48000",
    "-ac",
    channels.to_string(),
  ]
  if codec == "aac" {
    arguments.append(["-b:a", "160k"])
  }
  arguments.append(["-threads", "1", output])
  {
    executable: "ffmpeg",
    arguments,
    working_directory: None,
    timeout_ms: 600000,
    max_output_bytes: 2097152,
  }
}

///|
/// Preserve all existing compressed streams and chapter navigation, then append
/// the measured rendition as a selectable audio track with explicit metadata.
pub fn compile_audio_attachment(
  source : String,
  rendition : String,
  indices : Array[Int],
  dispositions : Array[Array[String]],
  language : String,
  title : String,
  is_default : Bool,
  output : String,
) -> @process.CommandSpec {
  let arguments = [
    "-hide_banner", "-v", "error", "-nostdin", "-n", "-threads", "1", "-protocol_whitelist",
    "file,pipe", "-i", source, "-protocol_whitelist", "file,pipe", "-i", rendition,
  ]
  for index in indices {
    arguments.append(["-map", "0:" + index.to_string()])
  }
  arguments.append([
    "-map", "1:0", "-map_metadata", "0", "-map_chapters", "0", "-c", "copy",
  ])
  for i, index in indices {
    arguments.append([
      "-map_metadata:s:" + i.to_string(),
      "0:s:" + index.to_string(),
    ])
    arguments.append([
      "-disposition:" + i.to_string(),
      if dispositions[i].is_empty() {
        "0"
      } else {
        dispositions[i].join("+")
      },
    ])
  }
  let added = indices.length().to_string()
  arguments.append([
    "-map_metadata:s:" + added,
    "-1",
    "-metadata:s:" + added,
    "language=" + language,
    "-metadata:s:" + added,
    "title=" + title,
    "-metadata:s:" + added,
    "handler_name=" + title,
    "-disposition:" + added,
    if is_default {
      "default"
    } else {
      "0"
    },
    output,
  ])
  {
    executable: "ffmpeg",
    arguments,
    working_directory: None,
    timeout_ms: 600000,
    max_output_bytes: 2097152,
  }
}
