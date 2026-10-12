///|
async fn local_file(path : String) -> String {
  guard !path.contains(":") && @fs.kind(path, follow_symlink=false) is Regular else {
    fail("expected a regular local file: " + path)
  }
  @fs.realpath(path)
}

///|
async fn read_draft(path : String) -> Bytes {
  let file = @fs.open(local_file(path), mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= 16777216L else { fail("draft exceeds 16 MiB") }
  file.read_exactly_at(size.to_int(), position=0)
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
/// Copy in bounded chunks, preserving the input's exact bytes.
async fn copy_media(
  source_path : String,
  output_path : String,
  expected_hash : String,
) -> Unit {
  let source = @fs.open(source_path, mode=ReadOnly)
  defer source.close()
  let size = source.size()
  let modified = source.mtime()
  guard size > 0L && size <= 2147483647L else {
    fail("media must be 1 byte to 2 GiB")
  }
  let output = @fs.open(output_path, mode=WriteOnly, create_mode=CreateNew)
  defer output.close()
  let hash = @crypto.SHA256::new()
  for offset = 0L; offset < size; {
    let count = if size - offset > 1048576L {
      1048576
    } else {
      (size - offset).to_int()
    }
    let bytes = source.read_exactly_at(count, position=offset)
    output.write_at(bytes, position=offset)
    hash.update(bytes)
    continue offset + count.to_int64()
  }
  guard source.size() == size &&
    source.mtime() == modified &&
    @crypto.bytes_to_hex_string(hash.finalize()) == expected_hash else {
    fail("source changed while copying; partial folder retained")
  }
  output.sync()
}
