///|
async fn read_local(path : String, limit : Int) -> String {
  guard !path.contains("://") && @fs.kind(path) is Regular else {
    fail("expected a local regular input: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= limit.to_int64() else {
    fail("input is empty or exceeds size limit: " + path)
  }
  @utf8.decode(file.read_exactly_at(size.to_int(), position=0))
}

///|
async fn require_absent_output(path : String) -> Unit {
  guard !path.is_empty() && !path.contains("://") else {
    fail("output must be a new local path: " + path)
  }
  // lstat-style lookup: a dangling symlink still occupies an output name.
  // Only ENOENT means absent; permission and other filesystem errors propagate.
  let occupied = try @fs.kind(path, follow_symlink=false) catch {
    @os_error.OSError(_) as err if err.is_ENOENT() => false
    err => raise err
  } noraise {
    _ => true
  }
  guard !occupied else { fail("output already exists: " + path) }
}

///|
async fn write_new(path : String, text : String) -> Unit {
  require_absent_output(path)
  @fs.write_file(path, @utf8.encode(text), create_mode=CreateNew)
}

///|
struct VerifiedFile {
  media_ref_id : String
  uri : String
  sha256 : String
  size_bytes : Int
} derive(ToJson)

///|
/// Root is supplied by the operator; media URIs cannot escape it or traverse
/// symlinks. Hash in 1 MiB chunks, never invoke a shell or a media decoder.
async fn verify_file(root : String, media : @domain.MediaRef) -> VerifiedFile {
  let uri = media.locator.uri
  guard @relink.safe_uri(uri) else { fail("unsafe media URI") }
  let mut path = root
  let parts = uri.split("/").to_array()
  for i, part in parts {
    path = path + "/" + part.to_string()
    let kind = @fs.kind(path, follow_symlink=false)
    let expected_kind = if i == parts.length() - 1 {
      @fs.Regular
    } else {
      @fs.Directory
    }
    guard kind == expected_kind else {
      fail(
        "missing, nonregular or symlinked media path: " +
        media.media_ref_id +
        " at " +
        uri,
      )
    }
  }
  let expected_path = if root == "/" { "/" + uri } else { root + "/" + uri }
  guard @fs.realpath(path) == expected_path else {
    fail("media must remain within the chosen root: " + uri)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular else { fail("media is not a regular file") }
  let size = file.size()
  guard size <= 268435456L && size == media.metadata.size_bytes.to_int64() else {
    fail("media size mismatch or file exceeds 256 MiB: " + media.media_ref_id)
  }
  let modified = file.mtime()
  let hash = @crypto.SHA256::new()
  for offset = 0L; offset < size; {
    let remaining = size - offset
    let chunk_size = if remaining > 1048576L {
      1048576
    } else {
      remaining.to_int()
    }
    hash.update(file.read_exactly_at(chunk_size, position=offset))
    continue offset + chunk_size.to_int64()
  }
  guard file.size() == size && file.mtime() == modified else {
    fail("media changed during verification: " + media.media_ref_id)
  }
  let sha256 = @crypto.bytes_to_hex_string(hash.finalize())
  guard sha256 == media.metadata.sha256 else {
    fail("media SHA-256 mismatch: " + media.media_ref_id)
  }
  { media_ref_id: media.media_ref_id, uri, sha256, size_bytes: size.to_int(), }
}

///|
async fn main {
  let help = "usage:\n  media_relink inventory PROJECT.json\n  media_relink seed PROJECT.json NEW_MAP.json\n  media_relink preview PROJECT.json MEDIA_ROOT MAP.json\n  media_relink apply PROJECT.json MEDIA_ROOT MAP.json NEW_PREFIX\n\nInventory only reads project metadata. Preview/apply read every resulting media file within the explicit root. Apply creates .project.json and .relink.json. See docs/media-relinking.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard args.length() >= 3 else { fail(help) }
  let project = @domain.snapshot_from_json(read_local(args[2], 16777216))
  match args[1] {
    "inventory" => {
      guard args.length() == 3 else { fail(help) }
      println(@relink.inventory(project).to_json().stringify(indent=2))
    }
    "seed" => {
      guard args.length() == 4 else { fail(help) }
      write_new(
        args[3],
        @relink.seed(project).to_json().stringify(indent=2) + "\n",
      )
      println("Created source-bound map: " + args[3])
    }
    "preview" | "apply" => {
      let applying = args[1] == "apply"
      guard args.length() == (if applying { 6 } else { 5 }) else { fail(help) }
      guard !args[3].contains("://") && @fs.kind(args[3]) is Directory else {
        fail("MEDIA_ROOT must be an existing local directory")
      }
      let root = @fs.realpath(args[3])
      let map = @relink.read_map(read_local(args[4], 2097152))
      let result = @relink.prepare(project, map)
      let mut total = 0L
      for media in result.project.media_refs {
        total += media.metadata.size_bytes.to_int64()
      }
      guard total <= 4294967296L else {
        fail("verification exceeds 4 GiB total")
      }
      let verified = []
      for media in result.project.media_refs {
        verified.push(verify_file(root, media))
      }
      let report : Json = {
        "contract": "mooncast.media-relink-receipt.v1",
        "project_id": project.project_id,
        "source_binding": @relink.binding(project),
        "output_binding": @relink.binding(result.project),
        "source_revision": project.revision,
        "output_revision": result.project.revision,
        "media_root": root,
        "changed_media": result.changes.length(),
        "changes": result.changes,
        "verified_files": verified,
        "publication_authority": false,
        "provider_authority": false,
      }
      if applying {
        let prefix = args[5]
        guard !prefix.is_empty() && !prefix.contains("://") else {
          fail("output prefix must be local and nonempty")
        }
        let outputs = [
          (
            prefix + ".project.json",
            @domain.snapshot_to_json(result.project) + "\n",
          ),
          (prefix + ".relink.json", report.stringify(indent=2) + "\n"),
        ]
        for (path, _) in outputs {
          require_absent_output(path)
        }
        for (path, text) in outputs {
          write_new(path, text)
        }
      }
      println(report.stringify(indent=2))
    }
    _ => fail(help)
  }
}
