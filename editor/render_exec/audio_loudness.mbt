///|
/// Analyze or normalize one explicit audio stream. The caller supplies bounded
/// numbers; all file paths remain separate process arguments.
pub fn compile_audio_loudness(
  source : String,
  index : Int,
  target_lufs : Int,
  ceiling_dbtp : Int,
  measured : Array[Double],
  output : String?,
) -> @process.CommandSpec raise {
  guard index >= 0 &&
    index <= 1000 &&
    target_lufs >= -23 &&
    target_lufs <= -14 &&
    ceiling_dbtp >= -3 &&
    ceiling_dbtp <= -1 else {
    fail("invalid loudness selection or target")
  }
  let filter = StringBuilder()
  filter.write_string(
    "loudnorm=I=\{target_lufs}:TP=\{ceiling_dbtp}:LRA=11:dual_mono=false:print_format=json",
  )
  match output {
    None => {
      guard measured.is_empty() else { fail("analysis takes no measurements") }
    }
    Some(_) => {
      guard measured.length() == 5 else {
        fail("two-pass export requires five measurements")
      }
      let names = [
        "measured_I", "measured_TP", "measured_LRA", "measured_thresh", "offset",
      ]
      for i, value in measured {
        guard value >= -99.0 && value <= 99.0 else {
          fail("non-finite loudness measurement")
        }
        filter.write_string(":" + names[i] + "=" + value.to_string())
      }
      filter.write_string(":linear=true")
    }
  }
  let arguments = [
    "-hide_banner",
    "-nostats",
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
    "-af",
    filter.to_string(),
    "-ar",
    "48000",
    "-threads",
    "1",
  ]
  match output {
    None => arguments.append(["-f", "null", "-"])
    Some(path) => arguments.append(["-c:a", "pcm_s24le", "-f", "wav", path])
  }
  {
    executable: "ffmpeg",
    arguments,
    working_directory: None,
    timeout_ms: 600000,
    max_output_bytes: 2097152,
  }
}
