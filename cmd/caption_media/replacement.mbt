///|
/// Revise one explicitly selected embedded text track into a new media version.
/// Source bytes and the replaced captions are retained for continued editing.
async fn replace_captions(args : Array[String]) -> Unit {
  let folder = if args[1] == "replace" {
    Some(new_folder(args[5]))
  } else {
    None
  }
  let source = local_file(args[3])
  let before = hash_file(source)
  let source_probe = probe(source)
  let bytes = read_draft(args[2])
  let draft = @captions.read_draft(@utf8.decode(bytes))
  let plan = @media.prepare_replacement(
    source_probe,
    draft,
    @string.parse_int(args[4]),
  )
  guard source.has_suffix(plan.media.suffix) else {
    fail("filename must end in the actual container's .mp4 or .mkv suffix")
  }
  let previous = decode_track(
    source,
    plan.selected.index,
    plan.media.duration_ms,
  )
  let preview : Json = {
    "contract": "mooncast.caption-replacement-preview.v1",
    "source_media": source,
    "source_sha256": before,
    "draft_sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    "plan": plan,
    "previous_captions": previous,
    "replacement_captions": draft,
    "operation": "replace one text track in place within a new media file",
    "other_tracks": "copy; retain order, codecs, labels and dispositions",
    "chapters": "retain titles and times",
    "alignment": "creator-selected draft; matching duration does not establish source alignment",
  }
  guard hash_file(source) == before && read_draft(args[2]) == bytes else {
    fail("input changed during replacement preview")
  }
  guard folder is Some(folder) else {
    println(preview.stringify(indent=2))
    return
  }
  @fs.mkdir(folder, recursive=false)
  save_captions(folder, draft)
  write_new(
    folder + "/previous-captions.json",
    previous.to_json().stringify(indent=2) + "\n",
  )
  let output = folder + "/media" + plan.media.suffix
  let command = @render.compile_caption_replacement(
    plan.media.tracks.map(t => t.index),
    plan.output_position,
    plan.media.suffix,
    plan.stream_dispositions,
    source,
    folder + "/captions.srt",
    output,
  )
  let remux = @process.run_capture(command)
  write_new(folder + "/ffmpeg.log", @utf8.decode(remux.stderr))
  guard remux.exit_code == Some(0) &&
    !remux.timed_out &&
    !remux.output_truncated else {
    fail(
      "caption replacement failed; partial folder retained: " +
      @utf8.decode(remux.stderr),
    )
  }
  let output_probe = probe(output)
  let selected = @media.verify_replacement(plan, output_probe)
  let roundtrip = decode_track(output, selected.index, draft.duration_ms)
  guard roundtrip.cues == draft.cues else {
    fail(
      "container changed replacement text or timing; partial folder retained",
    )
  }
  guard hash_file(source) == before && read_draft(args[2]) == bytes else {
    fail("input changed during replacement; partial folder retained")
  }
  let receipt : Json = {
    "contract": "mooncast.caption-replacement-result.v1",
    "source": preview,
    "output_media": "media" + plan.media.suffix,
    "output_sha256": hash_file(output),
    "replaced_track": plan.selected,
    "replacement_track": selected,
    "output_probe": output_probe,
    "ffmpeg_arguments": command.arguments,
    "verified_cues": roundtrip.cues.length(),
    "previous_draft": "previous-captions.json",
    "publication_authority": false,
    "client_acceptance": false,
  }
  write_new(folder + "/result.json", receipt.stringify(indent=2) + "\n")
  println(receipt.stringify(indent=2))
}
