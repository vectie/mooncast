///|
async fn main {
  let help = "usage:\n  audio_edition inspect MEDIA\n  audio_edition preview MEDIA AUDIO_STREAM_INDEX CHAPTERS.json\n  audio_edition export MEDIA AUDIO_STREAM_INDEX CHAPTERS.json NEW_FOLDER\n\nExport a chaptered M4A/AAC listening copy of one explicit mono/stereo track.\nMP4/M4A, Matroska, WAV and FLAC inputs; see docs/audio-edition.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 3 && args[1] == "inspect") ||
    (args.length() == 5 && args[1] == "preview") ||
    (args.length() == 6 && args[1] == "export") else {
    fail(help)
  }
  // Refuse an existing destination before probing or encoding media.
  let folder = if args[1] == "export" {
    Some(new_folder(args[5]))
  } else {
    None
  }
  let source = local_file(args[2])
  let before = hash_file(source)
  let source_probe = probe(source)
  let input = @audio.inspect_source(source_probe)
  if args[1] == "inspect" {
    let report : Json = {
      "contract": "mooncast.audio-edition-inspect.v1",
      "source_media": source,
      "source_sha256": before,
      "source": input,
      "selection": "choose the absolute stream index of one mono/stereo audio track",
    }
    guard hash_file(source) == before else {
      fail("source changed during inspection")
    }
    println(report.stringify(indent=2))
    return
  }
  let bytes = read_draft(args[4])
  let draft = @chapters.read_draft(@utf8.decode(bytes))
  let plan = @audio.prepare(draft, input, @string.parse_int(args[3]))
  let metadata = draft.ffmetadata()
  let preview : Json = {
    "contract": "mooncast.audio-edition-preview.v1",
    "source_media": source,
    "source_sha256": before,
    "draft_sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    "plan": plan,
    "chapters": draft,
    "audio_action": "lossy AAC transcode at 160 kb/s target, 48 kHz, original mono/stereo channel count",
    "omission": "video, subtitles, attachments, unselected audio and original global container metadata are omitted",
    "boundary": "listening copy only; no loudness normalization, audio description, rights or client decision",
  }
  guard hash_file(source) == before && read_draft(args[4]) == bytes else {
    fail("source changed during preview")
  }
  guard folder is Some(folder) else {
    println(preview.stringify(indent=2))
    return
  }
  @fs.mkdir(folder, recursive=false)
  write_new(
    folder + "/chapters.json",
    draft.to_json().stringify(indent=2) + "\n",
  )
  write_new(folder + "/chapters.ffmetadata", metadata)
  write_new(folder + "/chapters.vtt", draft.webvtt())
  let output = folder + "/audio.m4a"
  let command = @render.compile_audio_edition(
    source,
    plan.track.index,
    plan.track.channels,
    plan.track.language,
    folder + "/chapters.ffmetadata",
    output,
  )
  let encoded = @process.run_capture(command)
  write_new(folder + "/ffmpeg.log", @utf8.decode(encoded.stderr))
  guard encoded.exit_code == Some(0) &&
    !encoded.timed_out &&
    !encoded.output_truncated else {
    fail(
      "audio encoding failed; partial folder retained: " +
      @utf8.decode(encoded.stderr),
    )
  }
  let output_probe = probe(output)
  @audio.verify_output(plan, draft, output_probe)
  guard hash_file(source) == before && read_draft(args[4]) == bytes else {
    fail("source changed during export; partial folder retained")
  }
  let receipt : Json = {
    "contract": "mooncast.audio-edition-result.v1",
    "source": preview,
    "result": {
      "media": "audio.m4a",
      "sha256": hash_file(output),
      "probe": output_probe,
      "ffmpeg_arguments": command.arguments,
    },
    "publication_authority": false,
    "client_acceptance": false,
  }
  write_new(folder + "/result.json", receipt.stringify(indent=2) + "\n")
  println(receipt.stringify(indent=2))
}
