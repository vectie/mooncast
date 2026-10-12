///|
async fn read_local(path : String) -> Bytes {
  guard !path.contains(":") && @fs.kind(path, follow_symlink=false) is Regular else {
    fail("expected a regular local caption draft")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= 2097152L else {
    fail("caption input must be 1 byte to 2 MiB")
  }
  file.read_exactly_at(size.to_int(), position=0)
}

///|
async fn new_folder(path : String) -> String {
  guard !path.is_empty() &&
    !path.contains(":") &&
    !path.iter().any(c => c < ' ') else {
    fail("choose a new local output folder")
  }
  let parts = path.split("/").map(p => p.to_string()).to_array()
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
