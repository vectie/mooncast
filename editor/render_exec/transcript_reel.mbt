///|
/// One source excerpt; ticks are milliseconds. Array order is playback order.
pub(all) struct ReelExcerpt {
  first_cue : Int
  last_cue : Int
  source_start_ms : Int
  source_end_ms : Int
  output_start_ms : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TranscriptReel {
  contract : String
  excerpts : Array[ReelExcerpt]
  cues : Array[@domain.SubtitleCue]
  duration_ms : Int
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Select numbered cue ranges in user order, including deliberate repetitions.
pub fn transcript_reel(
  cues : Array[@domain.SubtitleCue],
  selection : String,
) -> TranscriptReel raise {
  guard !cues.is_empty() else { fail("transcript has no timed cues") }
  let excerpts : Array[ReelExcerpt] = []
  let output : Array[@domain.SubtitleCue] = []
  let mut cursor = 0
  for token in selection.split(",") {
    let parts = token.trim().split("-").collect()
    guard parts.length() == 1 || parts.length() == 2 else {
      fail("selection must contain cue numbers or ranges, for example 3-4,1")
    }
    let first = @string.parse_int(parts[0].trim())
    let last = if parts.length() == 2 {
      @string.parse_int(parts[1].trim())
    } else {
      first
    }
    guard first >= 1 && last >= first && last <= cues.length() else {
      fail("cue range is outside the transcript or reversed")
    }
    guard excerpts.length() < 100 else { fail("at most 100 excerpts per reel") }
    let start = cues[first - 1].start_tick
    let end = cues[last - 1].end_tick
    guard start >= 0 && end > start && end <= 7200000 else {
      fail("invalid source cue interval")
    }
    guard end - start >= 34 else {
      fail("an excerpt must be at least one 30 fps frame (34 ms)")
    }
    guard cursor <= 7200000 - (end - start) else {
      fail("reel exceeds two hours")
    }
    excerpts.push({
      first_cue: first,
      last_cue: last,
      source_start_ms: start,
      source_end_ms: end,
      output_start_ms: cursor,
    })
    for i in (first - 1)..<last {
      let cue = cues[i]
      guard cue.start_tick >= start &&
        cue.end_tick <= end &&
        cue.end_tick > cue.start_tick else {
        fail("selected cues must have ordered, bounded intervals")
      }
      output.push({
        cue_id: "reel-" + (output.length() + 1).to_string(),
        start_tick: cursor + cue.start_tick - start,
        end_tick: cursor + cue.end_tick - start,
        text: cue.text,
      })
    }
    cursor += end - start
  }
  {
    contract: "mooncast.transcript-reel.v1",
    excerpts,
    cues: output,
    duration_ms: cursor,
    publication_authority: false,
  }
}

///|
pub fn TranscriptReel::srt(self : TranscriptReel) -> String {
  self.cues
  .mapi((i, cue) => {
    (i + 1).to_string() +
    "\n" +
    srt_time(cue.start_tick.to_int64()) +
    " --> " +
    srt_time(cue.end_tick.to_int64()) +
    "\n" +
    cue.text +
    "\n"
  })
  .join("\n")
}

///|
fn reel_seconds(ms : Int) -> String {
  (ms / 1000).to_string() + "." + pad_left(ms % 1000, 3)
}

///|
/// Local probe used only for this explicit media-editing workflow.
pub async fn probe_reel_source(path : String) -> Json {
  let result = @process.run_capture({
    executable: "ffprobe",
    arguments: [
      "-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format",
      "-of", "json", path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 2097152,
  })
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail("could not probe local reel media")
  }
  @json.parse(@utf8.decode(result.stdout))
}

///|
/// Encode an ordered, frame-accurate rough cut with original audio when present.
pub async fn render_transcript_reel(
  reel : TranscriptReel,
  input : String,
  subtitle_path : String,
  output : String,
  has_audio : Bool,
) -> RenderReceipt {
  let filters : Array[String] = []
  let labels : Array[String] = []
  for i, excerpt in reel.excerpts {
    let n = i.to_string()
    let bounds = "start=" +
      reel_seconds(excerpt.source_start_ms) +
      ":end=" +
      reel_seconds(excerpt.source_end_ms)
    let duration = reel_seconds(excerpt.source_end_ms - excerpt.source_start_ms)
    let frames = ((excerpt.source_end_ms - excerpt.source_start_ms).to_int64() *
    30L /
    1000L).to_string()
    filters.push(
      "[0:v:0]setpts=PTS-STARTPTS,trim=" +
      bounds +
      ",setpts=PTS-STARTPTS,scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=1,fps=30,trim=end_frame=" +
      frames +
      "[v" +
      n +
      "]",
    )
    labels.push("[v" + n + "]")
    if has_audio {
      filters.push(
        "[0:a:0]asetpts=PTS-STARTPTS,atrim=" +
        bounds +
        ",asetpts=PTS-STARTPTS,apad,atrim=duration=" +
        duration +
        "[a" +
        n +
        "]",
      )
    } else {
      // An unexported silent clock keeps fractional cut positions exact.
      filters.push(
        "anullsrc=r=48000:cl=stereo,atrim=duration=" + duration + "[a" + n + "]",
      )
    }
    labels.push("[a" + n + "]")
  }
  filters.push(
    labels.join("") +
    "concat=n=" +
    reel.excerpts.length().to_string() +
    ":v=1:a=1[vjoined][ajoined]",
  )
  filters.push("[vjoined]fps=30[vout]")
  filters.push(
    if has_audio {
      "[ajoined]anull[aout]"
    } else {
      "[ajoined]anullsink"
    },
  )
  let args = [
    "-hide_banner",
    "-nostdin",
    "-loglevel",
    "error",
    "-n",
    "-threads",
    "1",
    "-protocol_whitelist",
    "file,pipe",
    "-i",
    input,
    "-i",
    subtitle_path,
    "-filter_complex_threads",
    "1",
    "-filter_complex",
    filters.join(";"),
    "-map",
    "[vout]",
  ]
  if has_audio {
    args.append(["-map", "[aout]"])
  }
  args.append([
    "-map", "1:0", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt",
    "yuv420p", "-threads", "1", "-c:a", "aac", "-c:s", "mov_text", "-metadata:s:s:0",
    "title=Transcript reel captions", "-movflags", "+faststart", output,
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
    plan_digest: "transcript-reel",
    output_path: output,
    exit_code: result.exit_code.unwrap_or(-1),
    stderr_tail: @utf8.decode(result.stderr),
    timed_out: result.timed_out,
    output_truncated: result.output_truncated,
    succeeded: result.exit_code == Some(0) && !result.timed_out,
    publication_authority: false,
  }
}
