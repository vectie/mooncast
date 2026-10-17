///|
async fn local_file(path : String) -> String {
  guard !path.contains(":") && @fs.kind(path, follow_symlink=false) is Regular else {
    fail("expected a regular local file: " + path)
  }
  @fs.realpath(path)
}

///|
async fn hash_file(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  let modified = file.mtime()
  guard size > 0L && size <= 2147483647L else {
    fail("media must be 1 byte to 2 GiB")
  }
  let hash = @crypto.SHA256::new()
  for offset = 0L; offset < size; {
    let count = if size - offset > 1048576L {
      1048576
    } else {
      (size - offset).to_int()
    }
    hash.update(file.read_exactly_at(count, position=offset))
    continue offset + count.to_int64()
  }
  guard file.size() == size && file.mtime() == modified else {
    fail("media changed while hashing")
  }
  @crypto.bytes_to_hex_string(hash.finalize())
}

///|
async fn new_folder(path : String) -> String {
  guard !path.is_empty() &&
    !path.contains(":") &&
    !path.iter().any(c => c < ' ') else {
    fail("choose a new local output folder")
  }
  let parts = path.split("/").map(p => p.to_owned()).to_array()
  let name = parts.pop().unwrap()
  guard !name.is_empty() && name != "." && name != ".." else {
    fail("invalid output folder")
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
  let parent = @fs.realpath(parent)
  guard @fs.kind(parent) is Directory &&
    !@fs.readdir(parent, include_hidden=true).contains(name) else {
    fail("output already exists; choose a fresh folder")
  }
  parent + "/" + name
}

///|
async fn write_new(path : String, value : String) -> Unit {
  @fs.write_file(path, @utf8.encode(value), create_mode=CreateNew)
}

///|
async fn probe(path : String) -> Json {
  let result = @process.run_capture(@render.compile_review_probe(path))
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail("local media probe failed: " + @utf8.decode(result.stderr))
  }
  @json.parse(@utf8.decode(result.stdout))
}
