///|
async fn main {
  let help = "usage:\n  audio_media inspect SOUNDTRACK_OR_MEDIA_WITH_AUDIO\n  audio_media preview MEDIA.mp4|mkv SOUNDTRACK AUDIO_STREAM_INDEX LANGUAGE TITLE\n  audio_media attach MEDIA.mp4|mkv SOUNDTRACK AUDIO_STREAM_INDEX LANGUAGE TITLE NEW_FOLDER\n\nAppend a synchronized selectable soundtrack. WAV, FLAC, M4A, MP4 and MKV audio sources.\nOriginal video, mixes, captions and chapters are retained. See docs/audio-media.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 3 && args[1] == "inspect") ||
    (args.length() == 7 && args[1] == "preview") ||
    (args.length() == 8 && args[1] == "attach") else {
    fail(help)
  }
  let folder = if args[1] == "attach" {
    Some(new_folder(args[7]))
  } else {
    None
  }
  let media_path = local_file(args[2])
  let media_hash = hash_file(media_path)
  let media_probe = probe(media_path)
  if args[1] == "inspect" {
    let source = @audio.inspect_source(media_probe)
    guard hash_file(media_path) == media_hash else {
      fail("source changed during inspection")
    }
    let report : Json = {
      "contract": "mooncast.audio-media-inspect.v1",
      "source": media_path,
      "sha256": media_hash,
      "audio": source,
      "selection": "choose the absolute index of the intended synchronized mono/stereo soundtrack",
    }
    println(report.stringify(indent=2))
    return
  }
  let audio_path = local_file(args[3])
  let audio_hash = hash_file(audio_path)
  let audio_probe = probe(audio_path)
  let plan = @attachment.prepare(
    media_probe,
    audio_probe,
    @string.parse_int(args[4]),
    args[5],
    args[6],
  )
  let preview : Json = {
    "contract": "mooncast.audio-media-preview.v1",
    "media": { "path": media_path, "sha256": media_hash },
    "soundtrack": { "path": audio_path, "sha256": audio_hash },
    "plan": plan,
    "action": "encode only the selected soundtrack at 48 kHz; append it while stream-copying every original media track",
    "encoding": if plan.codec == "aac" {
      "lossy AAC, 160 kb/s target; original mono/stereo channel count, resampled to 48 kHz"
    } else {
      "FLAC lossless encoding after conversion to 48 kHz; original mono/stereo channel count"
    },
    "timing": "no shift, trim, padding or time stretch; a duration match does not establish editorial synchronization",
    "selection": "existing audio dispositions stay unchanged; imported audio is default only if the media has no audio",
    "duration_check": "preview checks declared timing; attach measures the encoded selected track before muxing",
    "boundary": "no automatic translation, mixing, timing repair, loudness normalization, rights approval or client acceptance",
  }
  guard hash_file(media_path) == media_hash &&
    hash_file(audio_path) == audio_hash else {
    fail("input changed during preview")
  }
  guard folder is Some(folder) else {
    println(preview.stringify(indent=2))
    return
  }
  @fs.mkdir(folder, recursive=false)
  write_new(folder + "/preview.json", preview.stringify(indent=2) + "\n")
  let rendition = folder + "/soundtrack" + plan.rendition_suffix
  let encode = @render.compile_audio_rendition(
    audio_path,
    plan.audio.index,
    plan.audio.channels,
    plan.codec,
    rendition,
  )
  run_media(encode, folder + "/encode.log")
  let rendition_probe = probe(rendition)
  @attachment.verify_rendition(plan, rendition_probe)
  let output = folder + "/media" + plan.media.suffix
  let mux = @render.compile_audio_attachment(
    media_path,
    rendition,
    plan.media.tracks.map(t => t.index),
    plan.dispositions,
    plan.language,
    plan.title,
    plan.is_default,
    output,
  )
  run_media(mux, folder + "/mux.log")
  let output_probe = probe(output)
  let added = @attachment.verify_output(plan, output_probe)
  guard hash_file(media_path) == media_hash &&
    hash_file(audio_path) == audio_hash else {
    fail("input changed during attachment; partial output retained")
  }
  let receipt : Json = {
    "contract": "mooncast.audio-media-result.v1",
    "source": preview,
    "media": "media" + plan.media.suffix,
    "sha256": hash_file(output),
    "added_track": added,
    "rendition": {
      "file": "soundtrack" + plan.rendition_suffix,
      "sha256": hash_file(rendition),
      "probe": rendition_probe,
    },
    "probe": output_probe,
    "commands": [encode.arguments, mux.arguments],
    "publication_authority": false,
    "client_acceptance": false,
  }
  write_new(folder + "/result.json", receipt.stringify(indent=2) + "\n")
  println(receipt.stringify(indent=2))
}

///|
async fn run_media(command : @process.CommandSpec, log : String) -> Unit {
  let result = @process.run_capture(command)
  write_new(log, @utf8.decode(result.stderr))
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail(
      "media command failed; partial output retained: " +
      @utf8.decode(result.stderr),
    )
  }
}
