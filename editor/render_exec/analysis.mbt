///|
pub(all) struct AnalysisInvocation {
  contract : String
  kind : String
  source_digest : String
  output_path : String
  command : @process.CommandSpec
} derive(Debug)

///|
pub fn compile_thumbnail(
  ffmpeg : String,
  source_digest : String,
  source_path : String,
  output_path : String,
) -> AnalysisInvocation {
  {
    contract: "mooncast.editor-media-analysis-invocation.v1",
    kind: "thumbnail",
    source_digest,
    output_path,
    command: {
      executable: ffmpeg,
      arguments: [
        "-hide_banner", "-nostdin", "-y", "-ss", "0", "-i", source_path, "-frames:v",
        "1", "-vf", "scale=320:-2", "-f", "image2", output_path,
      ],
      working_directory: None,
      timeout_ms: 60000,
      max_output_bytes: 1048576,
    },
  }
}

///|
pub fn compile_waveform(
  ffmpeg : String,
  source_digest : String,
  source_path : String,
) -> AnalysisInvocation {
  {
    contract: "mooncast.editor-media-analysis-invocation.v1",
    kind: "waveform",
    source_digest,
    output_path: "stdout:pcm-s16le",
    command: {
      executable: ffmpeg,
      arguments: [
        "-hide_banner", "-nostdin", "-v", "error", "-i", source_path, "-vn", "-ac",
        "1", "-ar", "8000", "-f", "s16le", "pipe:1",
      ],
      working_directory: None,
      timeout_ms: 60000,
      max_output_bytes: 16777216,
    },
  }
}

///|
pub async fn execute_analysis(
  value : AnalysisInvocation,
) -> @process.CommandResult {
  @process.run_capture(value.command)
}
