///|
async fn read_local(path : String) -> String {
  guard !path.contains("://") && @fs.exists(path) && @fs.kind(path) is Regular else {
    fail("expected an existing local file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= 16777216L else {
    fail("input is empty or exceeds 16 MiB: " + path)
  }
  @utf8.decode(file.read_exactly_at(size.to_int(), position=0))
}

///|
async fn save(outputs : Array[(String, String)]) -> Unit {
  for (path, _) in outputs {
    guard !path.is_empty() && !path.contains("://") else {
      fail("choose a local output path")
    }
    guard !@fs.exists(path) else { fail("output already exists: " + path) }
  }
  for (path, text) in outputs {
    @fs.write_file(path, @utf8.encode(text), create_mode=CreateNew)
  }
}

///|
async fn main {
  let help = "usage:\n  caption_review export DRAFT.json NEW_SHEET.csv\n  caption_review preview DRAFT.json EDITED_SHEET.csv\n  caption_review apply DRAFT.json EDITED_SHEET.csv NEW_PREFIX\n\nEdit start_ms, end_ms and text after its text: prefix. Keep binding and keys.\nApply creates .draft.json, .srt, .vtt and .changes.json; never overwrites.\nSee docs/caption-review.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "help") {
    println(help)
    return
  }
  guard args.length() >= 4 else { fail(help) }
  guard ((args[1] == "export" || args[1] == "preview") && args.length() == 4) ||
    (args[1] == "apply" && args.length() == 5) else {
    fail(help)
  }
  let draft = @captions.read_draft(read_local(args[2]))
  if args[1] == "export" {
    save([(args[3], @review.export_sheet(draft))])
    println("Created " + args[3])
    return
  }
  let result = @review.apply_sheet(draft, read_local(args[3]))
  let report : Json = {
    "contract": "mooncast.caption-review-changes.v1",
    "source_binding": @review.binding(draft),
    "output_binding": @review.binding(result.draft),
    "cue_count": draft.cues.length(),
    "changed_cues": result.changes.length(),
    "changes": result.changes.to_json(),
  }
  let report_text = report.stringify(indent=2) + "\n"
  if args[1] == "apply" {
    guard !args[4].is_empty() else { fail("choose a nonempty output prefix") }
    save([
      (
        args[4] + ".draft.json",
        result.draft.to_json().stringify(indent=2) + "\n",
      ),
      (args[4] + ".srt", result.draft.srt()),
      (args[4] + ".vtt", result.draft.vtt()),
      (args[4] + ".changes.json", report_text),
    ])
    println("Created " + args[4] + ".draft.json, .srt, .vtt and .changes.json")
  } else {
    println(report_text)
  }
}
