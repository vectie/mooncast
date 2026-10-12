///|
async fn main {
  let help = "usage:\n  bilingual_captions preview PRIMARY.json SECONDARY.json\n  bilingual_captions export PRIMARY.json SECONDARY.json NEW_FOLDER\n\nStack two existing caption drafts with independently timed cues. Primary text comes first.\nCreates captions.json, captions.srt, captions.vtt, exact primary.json/secondary.json and composition.json.\nSee docs/bilingual-captions.md; inputs must have equal duration and no within-track overlap."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "help") {
    println(help)
    return
  }
  guard (args.length() == 4 && args[1] == "preview") ||
    (args.length() == 5 && args[1] == "export") else {
    fail(help)
  }
  let folder = if args[1] == "export" {
    Some(new_folder(args[4]))
  } else {
    None
  }
  let primary_bytes = read_local(args[2])
  let secondary_bytes = read_local(args[3])
  let result = @bilingual.compose(
    @captions.read_draft(@utf8.decode(primary_bytes)),
    @captions.read_draft(@utf8.decode(secondary_bytes)),
  )
  // Validate all derivatives before creating a destination, even in preview.
  let srt = result.draft.srt()
  let vtt = result.draft.vtt()
  let report : Json = {
    "contract": "mooncast.bilingual-export.v1",
    "primary_input": args[2],
    "secondary_input": args[3],
    "primary_sha256": @crypto.bytes_to_hex_string(@crypto.sha256(primary_bytes)),
    "secondary_sha256": @crypto.bytes_to_hex_string(
      @crypto.sha256(secondary_bytes),
    ),
    "composition": result,
    "policy": "half-open intervals; primary text then secondary text; preserve every boundary and gap",
    "boundary": "existing text composition; no translation, language identification or semantic alignment",
  }
  let report_text = report.stringify(indent=2) + "\n"
  guard folder is Some(folder) else {
    println(report_text)
    return
  }
  guard read_local(args[2]) == primary_bytes &&
    read_local(args[3]) == secondary_bytes else {
    fail("an input changed before export; no output written")
  }
  @fs.mkdir(folder, recursive=false)
  @fs.write_file(folder + "/primary.json", primary_bytes, create_mode=CreateNew)
  @fs.write_file(
    folder + "/secondary.json",
    secondary_bytes,
    create_mode=CreateNew,
  )
  for
    (name, text) in [
      ("captions.json", result.draft.to_json().stringify(indent=2) + "\n"),
      ("captions.srt", srt),
      ("captions.vtt", vtt),
      ("composition.json", report_text),
    ] {
    @fs.write_file(
      folder + "/" + name,
      @utf8.encode(text),
      create_mode=CreateNew,
    )
  }
  println(
    "Created " +
    result.draft.cues.length().to_string() +
    " bilingual display intervals in " +
    folder,
  )
}
