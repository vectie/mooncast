///|
async fn main {
  let help = "usage:\n  scene_index preview MEDIA THRESHOLD MIN_SCENE_MS\n  scene_index export MEDIA THRESHOLD MIN_SCENE_MS NEW_PREFIX\n\nDetect visual changes in a local MP4/Matroska video. Threshold: 1–100; minimum scene: 100–60000 ms.\nExport creates .scenes.json, .chapters.json, .chapters.vtt and .ffmetadata.\nSee docs/scene-index.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 5 && args[1] == "preview") ||
    (args.length() == 6 && args[1] == "export") else {
    fail(help)
  }
  let threshold = @string.parse_int(args[3])
  let min_scene_ms = @string.parse_int(args[4])
  @scenes.validate_options(threshold, min_scene_ms)
  let paths = if args[1] == "export" {
    guard !args[5].is_empty() else { fail("choose a nonempty output prefix") }
    [".scenes.json", ".chapters.json", ".chapters.vtt", ".ffmetadata"].map(s => {
      args[5] + s
    })
  } else {
    []
  }
  for path in paths {
    unused(path)
  }
  let source = local_file(args[2])
  let source_sha256 = hash_file(source)
  let probe = @process.run_capture(@render.compile_review_probe(source))
  guard probe.exit_code == Some(0) &&
    !probe.timed_out &&
    !probe.output_truncated else {
    fail("local media probe failed: " + @utf8.decode(probe.stderr))
  }
  let input = @scenes.inspect_probe(@json.parse(@utf8.decode(probe.stdout)))
  let scan = @process.run_capture(
    @scenes.command(source, input.video_index, threshold),
  )
  guard scan.exit_code == Some(0) && !scan.timed_out && !scan.output_truncated else {
    fail(
      "scene detection failed, timed out or exceeded output limit: " +
      @utf8.decode(scan.stderr),
    )
  }
  let detections = @scenes.parse_detections(
    @utf8.decode(scan.stdout),
    input.duration_ms,
  )
  let index = @scenes.index(
    source_sha256,
    input.duration_ms,
    threshold,
    min_scene_ms,
    detections,
  )
  guard hash_file(source) == source_sha256 else {
    fail("media changed during analysis; no output written")
  }
  let result : Json = {
    "contract": "mooncast.scene-index-result.v1",
    "source_name": source.split("/").last().unwrap().to_owned(),
    "video_index": input.video_index,
    "analysis": "FFmpeg scdet on fixed 320x180 yuv420p frames; millisecond PTS",
    "selection": "earliest eligible boundary; minimum gap from kept boundary and media end",
    "boundary": "visual-change suggestions, not semantic scenes or editorial approval",
    "index": index,
  }
  let report = result.stringify(indent=2) + "\n"
  if args[1] == "export" {
    // Validate every derivative before writing any file. The report is last so
    // its presence indicates all three chapter outputs were created.
    let chapter_json = index.chapters.to_json().stringify(indent=2) + "\n"
    let vtt = index.chapters.webvtt()
    let metadata = index.chapters.ffmetadata()
    for path in paths {
      unused(path)
    }
    write_new(paths[1], chapter_json)
    write_new(paths[2], vtt)
    write_new(paths[3], metadata)
    write_new(paths[0], report)
  }
  println(report)
}
