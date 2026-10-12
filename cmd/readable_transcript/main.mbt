///|
async fn read_local(path : String, limit : Int) -> Bytes {
  guard !path.is_empty() &&
    !path.contains("://") &&
    @fs.exists(path) &&
    @fs.kind(path) is Regular else {
    fail("expected an existing local file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= limit.to_int64() else {
    fail("input is empty or too large: " + path)
  }
  file.read_exactly_at(size.to_int(), position=0)
}

///|
fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn parent_path(path : String) -> String {
  let parts = path.split("/").map(p => p.to_string()).to_array()
  if parts.length() <= 1 {
    return "."
  }
  parts.pop() |> ignore
  let parent = parts.join("/")
  if parent.is_empty() {
    "/"
  } else {
    parent
  }
}

///|
async fn main {
  let help = "usage:\n  readable_transcript preview CAPTIONS.json CHAPTERS.json TITLE\n  readable_transcript export CAPTIONS.json CHAPTERS.json TITLE NEW_PREFIX\n\nJoin drafts for the same output into an offline readable transcript.\nCreates .transcript.html, .transcript.txt and .transcript.json.\nSee docs/readable-transcript.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 5 && args[1] == "preview") ||
    (args.length() == 6 && args[1] == "export") else {
    fail(help)
  }
  let caption_bytes = read_local(args[2], 16777216)
  let chapter_bytes = read_local(args[3], 2097152)
  let result = @transcript.compose(
    @captions.read_draft(@utf8.decode(caption_bytes)),
    @chapters.read_draft(@utf8.decode(chapter_bytes)),
    args[4],
  )
  let report : Json = {
    "contract": "mooncast.readable-transcript-export.v1",
    "caption_file": @fs.realpath(args[2]),
    "caption_sha256": digest(caption_bytes),
    "chapter_file": @fs.realpath(args[3]),
    "chapter_sha256": digest(chapter_bytes),
    "binding": "operator-selected same-output drafts; matching durations do not verify media identity",
    "result": result.to_json(),
  }
  let outputs = [
    (".transcript.html", result.html()),
    (".transcript.txt", result.plain_text()),
    (".transcript.json", report.stringify(indent=2) + "\n"),
  ]
  for (_, content) in outputs {
    guard @utf8.encode(content).length() <= 33554432 else {
      fail("readable transcript output exceeds 32 MiB")
    }
  }
  if args[1] == "export" {
    let prefix = args[5]
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
    // Directory entries catch existing files, directories and dangling symlinks.
    let names = @fs.readdir(output_parent, include_hidden=true)
    for (suffix, _) in outputs {
      guard !names.contains(name + suffix) else {
        fail("output exists; choose a fresh prefix")
      }
    }
    for (suffix, content) in outputs {
      @fs.write_file(
        output_parent + "/" + name + suffix,
        @utf8.encode(content),
        create_mode=CreateNew,
      )
    }
    println(
      "Created " +
      prefix +
      ".transcript.html, .transcript.txt and .transcript.json",
    )
  }
  println(result.plain_text())
}
