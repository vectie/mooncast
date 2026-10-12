///|
pub async fn reel_tool_versions() -> Json {
  let versions : Map[String, Json] = {}
  for tool in ["ffmpeg", "ffprobe"] {
    let result = @process.run_capture({
      executable: tool,
      arguments: ["-version"],
      working_directory: None,
      timeout_ms: 30000,
      max_output_bytes: 65536,
    })
    guard result.exit_code == Some(0) &&
      !result.timed_out &&
      !result.output_truncated else {
      fail("could not identify local media tools")
    }
    versions[tool] = @utf8.decode(result.stdout).to_json()
  }
  versions.to_json()
}

///|
/// All sources use their first video/audio streams. A missing audio stream is
/// represented by silence; every output has 48 kHz stereo AAC.
pub async fn render_multi_source_reel(
  reel : MultiSourceReel,
  inputs : Array[String],
  has_audio : Array[Bool],
  subtitle_path : String,
  output : String,
  plan_digest : String,
) -> RenderReceipt {
  guard !inputs.is_empty() &&
    inputs.length() <= 8 &&
    has_audio.length() == inputs.length() &&
    !reel.excerpts.is_empty() &&
    reel.excerpts.length() <= 100 else {
    fail("invalid renderer source plan")
  }
  let filters : Array[String] = []
  let labels : Array[String] = []
  for i, excerpt in reel.excerpts {
    guard excerpt.source_index >= 0 && excerpt.source_index < inputs.length() else {
      fail("invalid renderer source index")
    }
    let n = i.to_string()
    let source = excerpt.source_index.to_string()
    let bounds = "start=" +
      reel_seconds(excerpt.source_start_ms) +
      ":end=" +
      reel_seconds(excerpt.source_end_ms)
    let frames = excerpt.output_frames.to_string()
    let samples = (excerpt.output_frames * 1600).to_string()
    let width = reel.canvas.width.to_string()
    let height = reel.canvas.height.to_string()
    filters.push(
      "[" +
      source +
      ":v:0]setpts=PTS-STARTPTS,trim=" +
      bounds +
      ",setpts=PTS-STARTPTS,scale=" +
      width +
      ":" +
      height +
      ":force_original_aspect_ratio=decrease:force_divisible_by=2,pad=" +
      width +
      ":" +
      height +
      ":(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=30,tpad=stop_mode=clone:stop_duration=1,trim=end_frame=" +
      frames +
      ",setpts=N/(30*TB)[v" +
      n +
      "]",
    )
    if has_audio[excerpt.source_index] {
      filters.push(
        "[" +
        source +
        ":a:0]asetpts=PTS-STARTPTS,atrim=" +
        bounds +
        ",asetpts=PTS-STARTPTS,aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,apad,atrim=end_sample=" +
        samples +
        ",asetpts=N/(48000*TB)[a" +
        n +
        "]",
      )
    } else {
      filters.push(
        "anullsrc=r=48000:cl=stereo,atrim=end_sample=" +
        samples +
        ",asetpts=N/(48000*TB)[a" +
        n +
        "]",
      )
    }
    labels.append(["[v" + n + "]", "[a" + n + "]"])
  }
  filters.push(
    labels.join("") +
    "concat=n=" +
    reel.excerpts.length().to_string() +
    ":v=1:a=1[vout][aout]",
  )
  let args = ["-hide_banner", "-nostdin", "-loglevel", "error", "-n"]
  for input in inputs {
    args.append([
      "-threads", "1", "-protocol_whitelist", "file,pipe", "-i", input,
    ])
  }
  args.append([
    "-protocol_whitelist",
    "file,pipe",
    "-i",
    subtitle_path,
    "-filter_complex_threads",
    "1",
    "-filter_complex",
    filters.join(";"),
    "-map",
    "[vout]",
    "-map",
    "[aout]",
    "-map",
    inputs.length().to_string() + ":0",
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-crf",
    "20",
    "-pix_fmt",
    "yuv420p",
    "-threads",
    "1",
    "-c:a",
    "aac",
    "-ar",
    "48000",
    "-ac",
    "2",
    "-c:s",
    "mov_text",
    "-metadata:s:s:0",
    "title=Multi-source transcript reel captions",
    "-movflags",
    "+faststart",
    output,
  ])
  let result = @process.run_capture({
    executable: "ffmpeg",
    arguments: args,
    working_directory: None,
    timeout_ms: 1800000,
    max_output_bytes: 2097152,
  })
  {
    contract: "mooncast.editor-render-receipt.v1",
    plan_digest,
    output_path: output,
    exit_code: result.exit_code.unwrap_or(-1),
    stderr_tail: @utf8.decode(result.stderr),
    timed_out: result.timed_out,
    output_truncated: result.output_truncated,
    succeeded: result.exit_code == Some(0) && !result.timed_out,
    publication_authority: false,
  }
}
