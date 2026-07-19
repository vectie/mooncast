///|
pub(all) struct ConcatInvocation {
  contract : String
  segment_paths : Array[String]
  concat_manifest_path : String
  output_path : String
  manifest_text : String
  command : @process.CommandSpec
} derive(Debug)

///|
fn concat_escape(value : String) -> String {
  value.replace_all(old="'", new="'\\''")
}

///|
pub fn compile_concat(
  ffmpeg : String,
  segment_paths : Array[String],
  concat_manifest_path : String,
  output_path : String,
  timeout_ms : Int,
) -> ConcatInvocation raise {
  guard !segment_paths.is_empty() else {
    fail("preview concat requires segments")
  }
  let lines = segment_paths.map(path => "file '" + concat_escape(path) + "'")
  {
    contract: "mooncast.editor-preview-concat-invocation.v1",
    segment_paths,
    concat_manifest_path,
    output_path,
    manifest_text: lines.join("\n") + "\n",
    command: {
      executable: ffmpeg,
      arguments: [
        "-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-f", "concat", "-safe",
        "0", "-i", concat_manifest_path, "-c", "copy", "-movflags", "+faststart",
        output_path,
      ],
      working_directory: None,
      timeout_ms,
      max_output_bytes: 2097152,
    },
  }
}

///|
pub async fn execute_concat(value : ConcatInvocation) -> RenderReceipt {
  let result = @process.run_capture(value.command)
  let stderr = @utf8.decode(result.stderr)
  let exit_code = match result.exit_code {
    Some(code) => code
    None => -1
  }
  {
    contract: "mooncast.editor-render-receipt.v1",
    plan_digest: "preview-segment-concat",
    output_path: value.output_path,
    exit_code,
    stderr_tail: if stderr.length() > 4000 {
      stderr[stderr.length() - 4000:].to_owned()
    } else {
      stderr
    },
    timed_out: result.timed_out,
    output_truncated: result.output_truncated,
    succeeded: exit_code == 0 && !result.timed_out,
    publication_authority: false,
  }
}
