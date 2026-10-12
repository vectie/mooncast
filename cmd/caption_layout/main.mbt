///|
async fn read_local(path : String, limit : Int) -> String {
  guard !path.contains("://") && @fs.exists(path) && @fs.kind(path) is Regular else {
    fail("expected an existing local file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= limit.to_int64() else {
    fail("input is empty or too large: " + path)
  }
  @utf8.decode(file.read_exactly_at(size.to_int(), position=0))
}

///|
fn digest(text : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))
}

///|
fn show(
  draft : @captions.CaptionDraft,
  profile : @layout.Profile,
) -> Unit raise {
  let feedback = @layout.review(draft, profile)
  println(
    "Cues: " +
    feedback.cue_count.to_string() +
    "; review flags: " +
    feedback.flagged_cues.to_string(),
  )
  for i, cue in feedback.cues {
    println(
      "\n" +
      cue.cue.to_string() +
      "  " +
      cue.start_ms.to_string() +
      "–" +
      cue.end_ms.to_string() +
      " ms  " +
      cue.issues.join(", "),
    )
    println(draft.cues[i].text)
  }
  println(
    "\nReview against playback. These preferences do not certify accessibility or delivery.",
  )
}

///|
async fn main {
  let help = "usage:\n  caption_layout profile\n  caption_layout inspect DRAFT.json [PROFILE.json]\n  caption_layout preview DRAFT.json reflow|paginate [PROFILE.json]\n  caption_layout export DRAFT.json reflow|paginate NEW_PREFIX [PROFILE.json]\n\nReflow wraps words without changing cue times. Paginate explicitly estimates new page timings.\nExport creates .draft.json, .srt, .vtt, .layout.json and .tsv. Existing files are never overwritten.\nSee docs/caption-layout.md."
  let args = @env.args()
  guard args.length() >= 2 else { fail(help) }
  if args.length() == 2 && (args[1] == "--help" || args[1] == "help") {
    println(help)
    return
  }
  if args.length() == 2 && args[1] == "profile" {
    println(@layout.default_profile().to_json().stringify(indent=2))
    return
  }
  let profile_index = match args[1] {
    "inspect" => {
      guard args.length() == 3 || args.length() == 4 else { fail(help) }
      3
    }
    "preview" => {
      guard args.length() == 4 || args.length() == 5 else { fail(help) }
      4
    }
    "export" => {
      guard args.length() == 5 || args.length() == 6 else { fail(help) }
      5
    }
    _ => fail(help)
  }
  let source = read_local(args[2], 16777216)
  let draft = @captions.read_draft(source)
  let profile = if args.length() > profile_index {
    @layout.read_profile(read_local(args[profile_index], 65536))
  } else {
    @layout.default_profile()
  }
  if args[1] == "inspect" {
    show(draft, profile)
    return
  }
  let result = match args[3] {
    "reflow" => @layout.reflow(draft, profile)
    "paginate" => @layout.paginate(draft, profile)
    _ => fail("mode must be reflow or paginate")
  }
  if args[1] == "export" {
    let prefix = args[4]
    guard !prefix.is_empty() && !prefix.contains("://") else {
      fail("output prefix must be local and nonempty")
    }
    let result_json = result.draft.to_json().stringify(indent=2) + "\n"
    let report : Json = {
      "contract": "mooncast.caption-layout-report.v1",
      "source_draft": args[2],
      "source_sha256": digest(source),
      "output_draft_sha256": digest(result_json),
      "mode": args[3],
      "source_cue_count": draft.cues.length(),
      "origins": result.origins.to_json(),
      "before": @layout.review(draft, profile).to_json(),
      "after": @layout.review(result.draft, profile).to_json(),
    }
    // Materialize and validate every payload, then preflight every destination
    // before any write. CreateNew independently protects each write from races.
    let outputs = [
      (prefix + ".draft.json", result_json),
      (prefix + ".srt", result.draft.srt()),
      (prefix + ".vtt", result.draft.vtt()),
      (prefix + ".layout.json", report.stringify(indent=2) + "\n"),
      (prefix + ".tsv", @layout.tsv(result.draft, profile)),
    ]
    for (path, _) in outputs {
      guard !@fs.exists(path) else { fail("output already exists: " + path) }
    }
    for (path, text) in outputs {
      @fs.write_file(path, @utf8.encode(text), create_mode=CreateNew)
    }
    println(
      "Created " + prefix + ".draft.json, .srt, .vtt, .layout.json and .tsv",
    )
  }
  if args[3] == "paginate" {
    println(
      "Pagination timing is estimated from text length. Listen and correct before use.",
    )
  }
  show(result.draft, profile)
}
