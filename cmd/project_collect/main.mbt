///|
async fn main {
  let help = "usage:\n  project_collect preview PROJECT.json MEDIA_ROOT\n  project_collect collect PROJECT.json MEDIA_ROOT NEW_FOLDER\n  project_collect verify FOLDER\n\nCollect all native snapshot media, preserving the editable cut.\nCreates project.json, collection.json and content-addressed media/.\nSee docs/project-collection.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  if args.length() == 3 && args[1] == "verify" {
    println(verify_bundle(local_root(args[2])).stringify(indent=2))
    return
  }
  guard (args.length() == 4 && args[1] == "preview") ||
    (args.length() == 5 && args[1] == "collect") else {
    fail(help)
  }
  let bytes = read_local(args[2], 16777216)
  let project = @domain.snapshot_from_json(@utf8.decode(bytes))
  let plan = @collect.prepare(project)
  let root = local_root(args[3])
  let destination = if args[1] == "collect" {
    Some(require_new_directory(args[4]))
  } else {
    None
  }
  // Verify every original locator, including aliases and unused library media.
  for media in project.media_refs {
    inspect_file(
      root,
      media.locator.uri,
      media.metadata.sha256,
      media.metadata.size_bytes,
      None,
    )
  }
  let preview : Json = {
    "contract": "mooncast.project-collection-preview.v1",
    "source_binding": plan.source_binding,
    "project_id": project.project_id,
    "source_revision": project.revision,
    "collected_revision": plan.project.revision,
    "media_references": plan.members.length(),
    "unique_files": plan.files.length(),
    "copy_bytes": plan.total_size_bytes,
    "files": plan.files,
    "members": plan.members,
  }
  if destination is Some(folder) {
    @fs.mkdir(folder, recursive=false)
    @fs.mkdir(folder + "/media", recursive=false)
    for file in plan.files {
      inspect_file(
        root,
        file.source_uri,
        file.sha256,
        file.size_bytes,
        Some(folder + "/" + file.uri),
      )
      inspect_file(folder, file.uri, file.sha256, file.size_bytes, None)
    }
    guard @collect.digest(read_local(args[2], 16777216)) ==
      @collect.digest(bytes) else {
      fail("source project changed during collection")
    }
    let output_bytes = @utf8.encode(
      @domain.snapshot_to_json(plan.project) + "\n",
    )
    let manifest = plan.manifest(output_bytes)
    let manifest_bytes = @utf8.encode(
      manifest.to_json().stringify(indent=2) + "\n",
    )
    guard output_bytes.length() <= 16777216 &&
      manifest_bytes.length() <= 2097152 else {
      fail("collection metadata exceeds size limit")
    }
    @fs.write_file(
      folder + "/project.json",
      output_bytes,
      create_mode=CreateNew,
    )
    // Written last: absent collection.json means the bundle is incomplete.
    @fs.write_file(
      folder + "/collection.json",
      manifest_bytes,
      create_mode=CreateNew,
    )
    println(verify_bundle(folder).stringify(indent=2))
  } else {
    println(preview.stringify(indent=2))
  }
}
