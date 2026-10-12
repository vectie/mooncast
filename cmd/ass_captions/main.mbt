///|
async fn read_local(path : String) -> Bytes {
  guard !path.contains(":") && @fs.kind(path, follow_symlink=false) is Regular else {
    fail("expected a regular local ASS/SSA file")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= 2097152L else {
    fail("ASS/SSA input must be 1 byte to 2 MiB")
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

///|
async fn main {
  let help = "usage:\n  ass_captions preview INPUT.ass DURATION_MS\n  ass_captions import INPUT.ass DURATION_MS NEW_FOLDER\n\nImport ASS/SSA as editable plain captions. Styles, placement and karaoke are flattened.\nCreates captions.json, captions.srt, captions.vtt, the exact original and import.json.\nSee docs/ass-captions.md; nothing is overwritten."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "help") {
    println(help)
    return
  }
  guard (args.length() == 4 && args[1] == "preview") ||
    (args.length() == 5 && args[1] == "import") else {
    fail(help)
  }
  let folder = if args[1] == "import" {
    Some(new_folder(args[4]))
  } else {
    None
  }
  let bytes = read_local(args[2])
  let result = @ass.import_plain(bytes, args[2], @string.parse_int(args[3]))
  // Prepare every output before creating the destination.
  let srt = result.draft.srt()
  let vtt = result.draft.vtt()
  let report : Json = {
    "contract": "mooncast.ass-plain-import.v1",
    "source_file": args[2],
    "source_sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    "import": result,
    "omissions": [
      "styles, fonts, colors, layers, speaker metadata, margins and positioning",
      "karaoke animation, visual effects and inline comments", "script resolution and Aegisub project metadata",
    ],
    "boundary": "plain caption conversion, not visual equivalence, translation, accessibility certification or approval",
  }
  let report_text = report.stringify(indent=2) + "\n"
  guard folder is Some(folder) else {
    println(report_text)
    return
  }
  guard read_local(args[2]) == bytes else {
    fail("source changed before import")
  }
  @fs.mkdir(folder, recursive=false)
  let original = if result.script_type == "v4.00+" {
    "original.ass"
  } else {
    "original.ssa"
  }
  @fs.write_file(folder + "/" + original, bytes, create_mode=CreateNew)
  for
    (name, text) in [
      ("captions.json", result.draft.to_json().stringify(indent=2) + "\n"),
      ("captions.srt", srt),
      ("captions.vtt", vtt),
      ("import.json", report_text),
    ] {
    @fs.write_file(
      folder + "/" + name,
      @utf8.encode(text),
      create_mode=CreateNew,
    )
  }
  println(
    "Imported " +
    result.draft.cues.length().to_string() +
    " plain cues into " +
    folder,
  )
  println(
    "Styles, placement and karaoke are flattened. Retain " +
    original +
    " for the styled source.",
  )
}
