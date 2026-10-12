///|
fn mime(path : String) -> String {
  if path.has_suffix(".json") {
    "application/json"
  } else if path.has_suffix(".tsv") {
    "text/tab-separated-values"
  } else if path.has_suffix(".vtt") {
    "text/vtt"
  } else {
    "text/plain"
  }
}

///|
async fn local_file(path : String, limit : Int) -> Bytes {
  guard !path.contains("://") && @fs.exists(path) && @fs.kind(path) is Regular else {
    fail("expected an existing local file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= limit.to_int64() else {
    fail("input exceeds supported size: " + path)
  }
  file.read_exactly_at(size.to_int(), position=0)
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "help") {
    println(reel_help())
    return
  }
  if args.length() >= 2 && args[1] == "export-edl" {
    guard args.length() == 6 else {
      fail("export-edl requires RECIPE_JSON FPS exact|cover OUTPUT_PREFIX")
    }
    export_recipe_edl(args[2], @string.parse_int(args[3]), args[4], args[5])
    return
  }
  if args.length() >= 2 &&
    (args[1] == "render-recipe" || args[1] == "render-record") {
    guard args.length() == 4 else {
      fail("render-recipe/render-record requires INPUT_JSON OUTPUT_PREFIX")
    }
    render_recipe(args[2], args[3], from_record=args[1] == "render-record")
    return
  }
  guard args.length() >= 3 else { fail(reel_help()) }
  let transcript = local_file(args[2], 2097152)
  let parsed = @media.parse_subtitles(transcript, mime(args[2]), 7200000, 1000)
  if args[1] == "inspect" {
    guard args.length() <= 4 else {
      fail("inspect accepts an optional search string")
    }
    let query = if args.length() == 4 { args[3].to_lower() } else { "" }
    for i, cue in parsed.cues {
      if cue.text.to_lower().contains(query) {
        println(
          (i + 1).to_string() +
          "\t" +
          cue.start_tick.to_string() +
          "-" +
          cue.end_tick.to_string() +
          " ms\t" +
          cue.text.replace_all(old="\n", new=" "),
        )
      }
    }
    return
  }
  guard args[1] == "render" && args.length() == 6 else {
    fail("render requires TRANSCRIPT MEDIA SELECTION OUTPUT_PREFIX")
  }
  let input = args[3]
  guard !input.contains("://") &&
    @fs.exists(input) &&
    @fs.kind(input) is Regular else {
    fail("media must be an existing local file")
  }
  let prefix = args[5]
  guard !prefix.is_empty() && !prefix.has_prefix("-") && !prefix.contains("://") else {
    fail("invalid output prefix")
  }
  for suffix in [".mp4", ".srt", ".json"] {
    guard !@fs.exists(prefix + suffix) else {
      fail("output exists; choose a new prefix: " + prefix + suffix)
    }
  }
  let reel = @render.transcript_reel(parsed.cues, args[4])
  let probe = @render.probe_reel_source(input)
  guard probe
    is {
      "streams": Array(streams),
      "format": { "duration": String(duration), .. },
      ..
    } else {
    fail("media requires a known duration")
  }
  guard streams.any(s => s is { "codec_type": String("video"), .. }) else {
    fail("reel source must contain video")
  }
  let source_ms = (@string.parse_double(duration) * 1000.0).to_int()
  guard reel.excerpts.all(e => e.source_end_ms <= source_ms) else {
    fail("selected transcript extends beyond source media")
  }
  let has_audio = streams.any(s => s is { "codec_type": String("audio"), .. })
  @fs.write_file(
    prefix + ".srt",
    @utf8.encode(reel.srt()),
    create_mode=CreateNew,
  )
  let receipt = @render.render_transcript_reel(
    reel,
    input,
    prefix + ".srt",
    prefix + ".mp4",
    has_audio,
  )
  guard receipt.succeeded else {
    fail("render failed; partial outputs retained: " + receipt.stderr_tail)
  }
  let output_probe = @render.probe_reel_source(prefix + ".mp4")
  guard output_probe
    is {
      "streams": Array(output_streams),
      "format": { "duration": String(output_duration), .. },
      ..
    } else {
    fail("rendered media has no measurable duration")
  }
  let measured = @string.parse_double(output_duration) * 1000.0
  let expected = reel.duration_ms.to_double()
  guard measured >= expected - 100.0 &&
    measured <= expected + 100.0 &&
    output_streams.any(s => s is { "codec_name": String("h264"), .. }) &&
    output_streams.any(s => s is { "codec_name": String("mov_text"), .. }) &&
    (
      !has_audio ||
      output_streams.any(s => s is { "codec_name": String("aac"), .. })
    ) else {
    fail(
      "rendered duration or streams do not match the reel; partial output retained",
    )
  }
  let manifest : Json = {
    "contract": "mooncast.transcript-reel-delivery.v1",
    "source_media": input,
    "source_transcript": args[2],
    "transcript_sha256": @crypto.bytes_to_hex_string(@crypto.sha256(transcript)),
    "parser_version": parsed.parser_version,
    "selection": args[4],
    "reel": reel.to_json(),
    "render_receipt": receipt.to_json(),
    "output_probe": output_probe,
    "publication_authority": false,
  }
  @fs.write_file(
    prefix + ".json",
    @utf8.encode(manifest.stringify(indent=2)),
    create_mode=CreateNew,
  )
  println(
    "Created " +
    prefix +
    ".mp4, .srt and .json (" +
    reel.duration_ms.to_string() +
    " ms, " +
    reel.excerpts.length().to_string() +
    " excerpts)",
  )
}

///|
fn reel_help() -> String {
  "usage:\n" +
  "  transcript_reel inspect TRANSCRIPT [SEARCH]\n" +
  "  transcript_reel render TRANSCRIPT MEDIA SELECTION OUTPUT_PREFIX\n" +
  "  transcript_reel render-recipe RECIPE_JSON OUTPUT_PREFIX\n" +
  "  transcript_reel render-record EDIT_RECORD_JSON OUTPUT_PREFIX\n" +
  "  transcript_reel export-edl RECIPE_JSON FPS exact|cover OUTPUT_PREFIX\n" +
  "EDL export is video-only, integer 1–60 fps, zero-based source time and 01:00:00:00 record origin.\n" +
  "Media is not opened or verified; see docs/transcript-edl-handoff.md."
}
