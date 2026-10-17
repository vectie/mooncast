///|
async fn read_local(path : String, limit : Int) -> Bytes {
  guard !path.contains("://") && @fs.kind(path, follow_symlink=false) is Regular else {
    fail("expected a local regular file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= limit.to_int64() else {
    fail("input size out of bounds")
  }
  file.read_exactly_at(size.to_int(), position=0)
}

///|
async fn local_root(path : String) -> String {
  guard !path.contains("://") && @fs.kind(path) is Directory else {
    fail("expected an existing local root directory")
  }
  @fs.realpath(path)
}

///|
async fn source_path(root : String, uri : String) -> String {
  guard @relink.safe_uri(uri) else { fail("unsafe relative media URI") }
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
      fail("missing, nonregular or symlinked media: " + uri)
    }
  }
  let expected = if root == "/" { "/" + uri } else { root + "/" + uri }
  guard @fs.realpath(path) == expected else {
    fail("media escaped selected root")
  }
  path
}

///|
/// Stream into an exclusive new file when copying; hash the exact bytes written.
async fn inspect_file(
  root : String,
  uri : String,
  sha256 : String,
  size_bytes : Int,
  destination : String?,
) -> Unit {
  let path = source_path(root, uri)
  let source = @fs.open(path, mode=ReadOnly)
  defer source.close()
  guard source.kind() is Regular && source.size() == size_bytes.to_int64() else {
    fail("media size mismatch: " + uri)
  }
  let modified = source.mtime()
  let output = match destination {
    None => None
    Some(path) => Some(@fs.open(path, mode=WriteOnly, create_mode=CreateNew))
  }
  defer (match output {
    Some(file) => file.close()
    None => ()
  })
  let hash = @crypto.SHA256::new()
  for offset = 0L; offset < size_bytes.to_int64(); {
    let remaining = size_bytes.to_int64() - offset
    let count = if remaining > 1048576L { 1048576 } else { remaining.to_int() }
    let bytes = source.read_exactly_at(count, position=offset)
    hash.update(bytes)
    if output is Some(file) {
      file.write_at(bytes, position=offset)
    }
    continue offset + count.to_int64()
  }
  guard source.size() == size_bytes.to_int64() &&
    source.mtime() == modified &&
    @crypto.bytes_to_hex_string(hash.finalize()) == sha256 else {
    fail("media changed or SHA-256 mismatch: " + uri)
  }
  if output is Some(file) {
    file.sync()
  }
}

///|
async fn require_new_directory(path : String) -> String {
  guard !path.is_empty() &&
    !path.contains(":") &&
    !path.iter().any(c => c < ' ') else {
    fail("destination must be a fresh local directory path")
  }
  let parts = path.split("/").map(p => p.to_string()).to_array()
  let name = parts.pop().unwrap()
  guard !name.is_empty() && name != "." && name != ".." else {
    fail("destination must name a new directory")
  }
  let parent = parts.join("/")
  let parent = if parent.is_empty() {
    if path.has_prefix("/") {
      "/"
    } else {
      "."
    }
  } else {
    parent
  }
  let root = local_root(parent)
  guard !@fs.readdir(root, include_hidden=true).contains(name) else {
    fail("destination already exists; choose a fresh directory")
  }
  root + "/" + name
}

///|
async fn verify_bundle(root : String) -> Json {
  let project_bytes = read_local(root + "/project.json", 16777216)
  let manifest = @collect.read_manifest(
    @utf8.decode(read_local(root + "/collection.json", 2097152)),
  )
  let project = @collect.verify_manifest(manifest, project_bytes)
  for file in manifest.files {
    inspect_file(root, file.uri, file.sha256, file.size_bytes, None)
  }
  {
    "contract": "mooncast.project-collection-verification.v1",
    "project_id": project.project_id,
    "project_binding": manifest.project_binding,
    "media_references": project.media_refs.length(),
    "unique_files": manifest.files.length(),
    "verified_bytes": manifest.total_size_bytes,
    "root": root,
  }
}
