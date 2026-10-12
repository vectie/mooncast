///|
/// Metadata-only NLE handoff. Media paths remain locators: no media is opened,
/// probed, copied or rendered. Transcript bytes provide the actual edit times.
async fn export_recipe_edl(
  recipe_path : String,
  fps : Int,
  rounding : String,
  prefix : String,
) -> Unit {
  let recipe_bytes = local_file(recipe_path, 1048576)
  let recipe = @render.parse_reel_recipe(@utf8.decode(recipe_bytes))
  let parent = parent_path(@fs.realpath(recipe_path))
  let transcripts = []
  let identities : Array[Json] = []
  let sources : Array[@render.ReelSource] = []
  for source in recipe.sources {
    let transcript = recipe_source_path(parent, source.transcript)
    let bytes = local_file(transcript, 2097152)
    let parsed = @media.parse_subtitles(
      bytes,
      mime(source.transcript),
      7200000,
      1000,
    )
    transcripts.push(parsed.cues)
    sources.push({
      ..source,
      media: if source.media.has_prefix("/") {
        source.media
      } else {
        parent + "/" + source.media
      },
      transcript,
    })
    identities.push({
      "source_id": source.id,
      "transcript": transcript,
      "transcript_sha256": digest(bytes),
      "parser_version": parsed.parser_version,
      "cue_digest": parsed.cue_digest,
    })
  }
  let normalized : @render.ReelRecipe = { ..recipe, sources, }
  let plan = @reel_edl.export_reel_edl(normalized, transcripts, fps, rounding)
  let edl = @utf8.encode(plan.edl)
  let report : Json = {
    "contract": "mooncast.transcript-edl-handoff.v1",
    "input_recipe_sha256": digest(recipe_bytes),
    "recipe": normalized.to_json(),
    "transcripts": identities.to_json(),
    "plan": plan.to_json(),
    "edl_sha256": digest(edl),
    "source_timecode_policy": "zero-based file time; conform media to the selected integer fps before using this EDL",
    "media_validation": "media locators only; files, duration, frame rate and playback are not verified",
    "track_policy": "video-only cuts; no audio, captions, canvas or effects are encoded in the EDL",
  }
  let report_bytes = @utf8.encode(report.stringify(indent=2) + "\n")
  guard report_bytes.length() <= 33554432 else {
    fail("handoff exceeds 32 MiB")
  }
  guard !prefix.is_empty() &&
    !prefix.contains(":") &&
    !prefix.iter().any(c => c < ' ') else {
    fail("invalid local output prefix")
  }
  let output_parent = @fs.realpath(parent_path(prefix))
  let name = prefix.split("/").last().unwrap().to_string()
  guard !name.is_empty() && name != "." && name != ".." else {
    fail("invalid output filename")
  }
  let names = @fs.readdir(output_parent, include_hidden=true)
  for suffix in [".edl", ".handoff.json"] {
    guard !names.contains(name + suffix) else {
      fail("output exists; choose a fresh prefix")
    }
  }
  let output = output_parent + "/" + name
  @fs.write_file(output + ".edl", edl, create_mode=CreateNew)
  @fs.write_file(output + ".handoff.json", report_bytes, create_mode=CreateNew)
  println(
    "Created " +
    output +
    ".edl and .handoff.json (" +
    plan.excerpts.length().to_string() +
    " cuts, " +
    plan.duration_frames.to_string() +
    " frames at " +
    fps.to_string() +
    " fps; video-only, media not verified)",
  )
}
