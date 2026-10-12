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
async fn unused(path : String) -> Unit {
  guard !path.is_empty() && !path.contains(":") && !@fs.exists(path) else {
    fail("output must be a new local path: " + path)
  }
}

///|
async fn write_new(path : String, value : String) -> Unit {
  @fs.write_file(path, @utf8.encode(value), create_mode=CreateNew)
}
