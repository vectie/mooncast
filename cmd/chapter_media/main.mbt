///|
async fn main {
  let help = "usage:\n  chapter_media preview DRAFT.json MEDIA.mp4|mkv\n  chapter_media embed DRAFT.json MEDIA.mp4|mkv NEW_FOLDER\n  chapter_media extract TEMPLATE.json MEDIA.mp4|mkv NEW_FOLDER\n\nEmbed authored chapters without re-encoding; extract actual chapters into an editable draft.\nSee docs/chapter-media.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 4 && args[1] == "preview") ||
    (args.length() == 5 && (args[1] == "embed" || args[1] == "extract")) else {
    fail(help)
  }
  let bytes = read_draft(args[2])
  let draft = @chapters.read_draft(@utf8.decode(bytes))
  let source = local_file(args[3])
  let suffix = if source.has_suffix(".mp4") {
    ".mp4"
  } else if source.has_suffix(".mkv") {
    ".mkv"
  } else {
    fail("select a local .mp4 or .mkv file; output keeps its container")
  }
  let before = hash_file(source)
  let source_probe = probe(source)
  guard source_probe is { "format": { "format_name": String(format), .. }, .. } &&
    (
      (suffix == ".mp4" && format == "mov,mp4,m4a,3gp,3g2,mj2") ||
      (suffix == ".mkv" && format == "matroska,webm")
    ) else {
    fail("media filename suffix does not match its actual container")
  }
  let plan = @media.prepare(draft, source_probe)
  let preview : Json = {
    "contract": "mooncast.chapter-media-preview.v1",
    "source_media": source,
    "source_sha256": before,
    "draft_sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    "plan": plan,
    "chapters": draft,
    "output_container": suffix,
    "video_audio_subtitle_action": "copy all listed streams without re-encoding",
    "chapter_action": "replace existing chapters with the selected draft",
  }
  if args[1] == "preview" {
    println(preview.stringify(indent=2))
    return
  }
  let result = if args[1] == "extract" {
    @media.extract(draft, source_probe)
  } else {
    draft
  }
  let metadata = result.ffmetadata()
  let folder = new_folder(args[4])
  @fs.mkdir(folder, recursive=false)
  write_new(
    folder + "/chapters.json",
    result.to_json().stringify(indent=2) + "\n",
  )
  write_new(folder + "/chapters.ffmetadata", metadata)
  let output : Json = if args[1] == "embed" {
    let path = folder + "/media" + suffix
    let argv = @media.remux_arguments(
      plan,
      source,
      folder + "/chapters.ffmetadata",
      path,
    )
    let remux = @process.run_capture({
      executable: "ffmpeg",
      arguments: argv,
      working_directory: None,
      timeout_ms: 300000,
      max_output_bytes: 2097152,
    })
    write_new(folder + "/ffmpeg.log", @utf8.decode(remux.stderr))
    guard remux.exit_code == Some(0) &&
      !remux.timed_out &&
      !remux.output_truncated else {
      fail(
        "chapter remux failed; partial output retained: " +
        @utf8.decode(remux.stderr),
      )
    }
    let output_probe = probe(path)
    @media.verify_output(plan, draft, output_probe)
    {
      "media": "media" + suffix,
      "sha256": hash_file(path),
      "probe": output_probe,
      "ffmpeg_arguments": argv,
    }
  } else {
    { "draft": "chapters.json", "imported_chapters": result.markers.length() }
  }
  guard hash_file(source) == before && read_draft(args[2]) == bytes else {
    fail("source changed during operation; partial output retained")
  }
  let receipt : Json = {
    "contract": "mooncast.chapter-media-result.v1",
    "operation": args[1],
    "source": preview,
    "result": output,
    "publication_authority": false,
    "client_acceptance": false,
  }
  // Last file marks completed local output, never a Studio or client decision.
  write_new(folder + "/result.json", receipt.stringify(indent=2) + "\n")
  println(receipt.stringify(indent=2))
}
