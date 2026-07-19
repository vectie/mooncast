///|
pub(all) struct ProxyInvocation {
  contract : String
  source_digest : String
  source_path : String
  output_path : String
  profile : String
  command : @process.CommandSpec
} derive(Debug)

///|
pub fn compile_proxy(
  ffmpeg : String,
  source_digest : String,
  source_path : String,
  output_path : String,
  media_kind : String,
) -> ProxyInvocation {
  let arguments = if media_kind == "audio" {
    [
      "-hide_banner", "-nostdin", "-y", "-i", source_path, "-vn", "-c:a", "aac",
      "-b:a", "128k", "-movflags", "+faststart", output_path,
    ]
  } else {
    [
      "-hide_banner", "-nostdin", "-y", "-i", source_path, "-vf", "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2",
      "-r", "24", "-c:v", "libx264", "-preset", "veryfast", "-crf", "28", "-an",
      "-movflags", "+faststart", output_path,
    ]
  }
  {
    contract: "mooncast.editor-proxy-invocation.v1",
    source_digest,
    source_path,
    output_path,
    profile: "mooncast-review-source-proxy@1.0.0",
    command: {
      executable: ffmpeg,
      arguments,
      working_directory: None,
      timeout_ms: 300000,
      max_output_bytes: 2097152,
    },
  }
}

///|
pub async fn execute_proxy(value : ProxyInvocation) -> RenderReceipt {
  let result = @process.run_capture(value.command)
  let stderr = @utf8.decode(result.stderr)
  let exit_code = match result.exit_code {
    Some(code) => code
    None => -1
  }
  {
    contract: "mooncast.editor-render-receipt.v1",
    plan_digest: value.source_digest,
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
