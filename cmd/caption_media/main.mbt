///|
async fn decode_track(
  source : String,
  index : Int,
  duration_ms : Int,
) -> @captions.CaptionDraft {
  let decoded = @process.run_capture({
    executable: "ffmpeg",
    arguments: @media.extract_arguments(source, index),
    working_directory: None,
    timeout_ms: 300000,
    max_output_bytes: 2097152,
  })
  guard decoded.exit_code == Some(0) &&
    !decoded.timed_out &&
    !decoded.output_truncated else {
    fail("text subtitle extraction failed: " + @utf8.decode(decoded.stderr))
  }
  @captions.import_draft(
    decoded.stdout,
    "text/plain",
    source + "#stream=" + index.to_string(),
    duration_ms,
  )
}

///|
async fn save_captions(folder : String, draft : @captions.CaptionDraft) -> Unit {
  // Generate both formats before writing, preserving the original editable text.
  let srt = draft.srt()
  let vtt = draft.vtt()
  write_new(
    folder + "/captions.json",
    draft.to_json().stringify(indent=2) + "\n",
  )
  write_new(folder + "/captions.srt", srt)
  write_new(folder + "/captions.vtt", vtt)
}

///|
async fn main {
  let help = "usage:\n  caption_media inspect MEDIA.mp4|mkv\n  caption_media preview DRAFT.json MEDIA.mp4|mkv LANGUAGE TITLE\n  caption_media attach DRAFT.json MEDIA.mp4|mkv LANGUAGE TITLE NEW_FOLDER\n  caption_media extract MEDIA.mp4|mkv STREAM_INDEX NEW_FOLDER\n\nAppend a selectable text-caption track without re-encoding video/audio.\nExtract a specific stream into caption_edit-compatible JSON, SRT and WebVTT.\nSee docs/caption-media.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 3 && args[1] == "inspect") ||
    (args.length() == 6 && args[1] == "preview") ||
    (args.length() == 7 && args[1] == "attach") ||
    (args.length() == 5 && args[1] == "extract") else {
    fail(help)
  }
  let attaching = args[1] == "attach" || args[1] == "preview"
  let source = local_file(if attaching { args[3] } else { args[2] })
  let before = hash_file(source)
  let source_probe = probe(source)
  let media = @media.inspect_media(source_probe)
  guard source.has_suffix(media.suffix) else {
    fail("filename must end in the actual container's .mp4 or .mkv suffix")
  }
  let source_info : Json = {
    "media": source,
    "sha256": before,
    "inspection": media,
  }
  if args[1] == "inspect" {
    println(source_info.stringify(indent=2))
    return
  }
  if attaching {
    let bytes = read_draft(args[2])
    let draft = @captions.read_draft(@utf8.decode(bytes))
    let language = args[4]
    let title = args[5]
    @media.validate_attachment(media, draft, language, title)
    let preview : Json = {
      "contract": "mooncast.caption-media-preview.v1",
      "source": source_info,
      "draft_sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
      "captions": draft,
      "language": language,
      "title": title,
      "existing_tracks": "copy",
      "new_track": "append",
      "new_track_default": @media.appended_track_is_default(media),
      "new_track_forced": false,
    }
    if args[1] == "preview" {
      println(preview.stringify(indent=2))
      return
    }
    let folder = new_folder(args[6])
    @fs.mkdir(folder, recursive=false)
    save_captions(folder, draft)
    let output = folder + "/media" + media.suffix
    let argv = @media.attach_arguments(
      media,
      source,
      folder + "/captions.srt",
      language,
      title,
      output,
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
        "caption attachment failed; partial folder retained: " +
        @utf8.decode(remux.stderr),
      )
    }
    let output_probe = probe(output)
    let added = @media.verify_attachment(
      media,
      @media.inspect_media(output_probe),
      language,
      title,
    )
    let roundtrip = decode_track(output, added.index, draft.duration_ms)
    guard roundtrip.cues == draft.cues else {
      fail("container changed caption text or timing; partial folder retained")
    }
    guard hash_file(source) == before && read_draft(args[2]) == bytes else {
      fail("input changed during operation; partial folder retained")
    }
    let receipt : Json = {
      "contract": "mooncast.caption-media-result.v1",
      "operation": "attach",
      "source": preview,
      "output_media": "media" + media.suffix,
      "output_sha256": hash_file(output),
      "added_track": added,
      "output_probe": output_probe,
      "ffmpeg_arguments": argv,
      "verified_cues": roundtrip.cues.length(),
      "client_acceptance": false,
    }
    write_new(folder + "/result.json", receipt.stringify(indent=2) + "\n")
    println(receipt.stringify(indent=2))
  } else {
    let index = @string.parse_int(args[3])
    let track = @media.select_track(media, index)
    // Decode and validate the entire selected track before creating a folder.
    let draft = decode_track(source, index, media.duration_ms)
    let folder = new_folder(args[4])
    @fs.mkdir(folder, recursive=false)
    save_captions(folder, draft)
    guard hash_file(source) == before else {
      fail("input changed during operation; partial folder retained")
    }
    let receipt : Json = {
      "contract": "mooncast.caption-media-result.v1",
      "operation": "extract",
      "source": source_info,
      "selected_track": track,
      "draft": "captions.json",
      "cue_count": draft.cues.length(),
      "conversion": "plain text at millisecond resolution",
      "client_acceptance": false,
    }
    write_new(folder + "/result.json", receipt.stringify(indent=2) + "\n")
    println(receipt.stringify(indent=2))
  }
}
