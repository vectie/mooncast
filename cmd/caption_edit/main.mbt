///|
fn mime(path : String) -> String {
  let lower = path.to_lower()
  if lower.has_suffix(".json") {
    "application/json"
  } else if lower.has_suffix(".tsv") {
    "text/tab-separated-values"
  } else if lower.has_suffix(".vtt") {
    "text/vtt"
  } else {
    "text/plain"
  }
}

///|
async fn read_local(path : String, limit : Int) -> Bytes {
  guard !path.contains("://") && @fs.exists(path) && @fs.kind(path) is Regular else {
    fail("expected an existing local file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= limit.to_int64() else {
    fail("file is empty or exceeds the supported size: " + path)
  }
  file.read_exactly_at(size.to_int(), position=0)
}

///|
async fn unused(path : String) -> Unit {
  guard !path.is_empty() && !path.contains("://") && !@fs.exists(path) else {
    fail("output must be a new local file: " + path)
  }
}

///|
async fn save(draft : @captions.CaptionDraft, path : String) -> Unit {
  draft.validate()
  unused(path)
  @fs.write_file(
    path,
    @utf8.encode(draft.to_json().stringify(indent=2) + "\n"),
    create_mode=CreateNew,
  )
  println("Created " + path + " (" + draft.cues.length().to_string() + " cues)")
}

///|
async fn main {
  let args = @env.args()
  guard args.length() >= 2 else { usage() }
  if args[1] == "--help" || args[1] == "help" {
    println(help())
    return
  }
  guard args.length() >= 3 else { usage() }
  if args[1] == "import" {
    guard args.length() == 5 else { usage() }
    let draft = @captions.import_draft(
      read_local(args[2], 2097152),
      mime(args[2]),
      args[2],
      @string.parse_int(args[3]),
    )
    save(draft, args[4])
    return
  }
  let draft = @captions.read_draft(@utf8.decode(read_local(args[2], 16777216)))
  match args[1] {
    "show" => {
      guard args.length() == 3 else { usage() }
      for i, cue in draft.cues {
        println(
          (i + 1).to_string() +
          "\t" +
          cue.start_ms.to_string() +
          "–" +
          cue.end_ms.to_string() +
          " ms\t" +
          cue.text.replace_all(old="\n", new=" / "),
        )
      }
    }
    "set" => {
      guard args.length() == 8 else { usage() }
      save(
        draft.set_cue(
          @string.parse_int(args[3]),
          @string.parse_int(args[4]),
          @string.parse_int(args[5]),
          args[6],
        ),
        args[7],
      )
    }
    "split" => {
      guard args.length() == 8 else { usage() }
      save(
        draft.split_cue(
          @string.parse_int(args[3]),
          @string.parse_int(args[4]),
          args[5],
          args[6],
        ),
        args[7],
      )
    }
    "merge" => {
      guard args.length() == 7 else { usage() }
      save(
        draft.merge_cues(
          @string.parse_int(args[3]),
          @string.parse_int(args[4]),
          args[5],
        ),
        args[6],
      )
    }
    "shift" => {
      guard args.length() == 5 else { usage() }
      save(draft.shift(@string.parse_int(args[3])), args[4])
    }
    "sync" => {
      guard args.length() == 8 else { usage() }
      save(
        draft.sync(
          @string.parse_int(args[3]),
          @string.parse_int(args[4]),
          @string.parse_int(args[5]),
          @string.parse_int(args[6]),
        ),
        args[7],
      )
    }
    "export" => {
      guard args.length() == 4 else { usage() }
      let prefix = args[3]
      guard !prefix.is_empty() else { fail("output prefix must not be empty") }
      // Prepare and validate both full outputs before creating either file.
      let srt = draft.srt()
      let vtt = draft.vtt()
      unused(prefix + ".srt")
      unused(prefix + ".vtt")
      @fs.write_file(prefix + ".srt", @utf8.encode(srt), create_mode=CreateNew)
      @fs.write_file(prefix + ".vtt", @utf8.encode(vtt), create_mode=CreateNew)
      println(
        "Created " +
        prefix +
        ".srt and " +
        prefix +
        ".vtt (" +
        draft.cues.length().to_string() +
        " cues)",
      )
    }
    _ => usage()
  }
}

///|
fn help() -> String {
  "Caption editing, all times in integer milliseconds; cue numbers start at 1.\n" +
  "caption_edit import TRANSCRIPT DURATION_MS NEW_DRAFT.json\n" +
  "caption_edit show DRAFT.json\n" +
  "caption_edit set DRAFT.json CUE START_MS END_MS TEXT NEW_DRAFT.json\n" +
  "caption_edit split DRAFT.json CUE AT_MS FIRST_TEXT SECOND_TEXT NEW_DRAFT.json\n" +
  "caption_edit merge DRAFT.json FIRST_CUE LAST_CUE TEXT NEW_DRAFT.json\n" +
  "caption_edit shift DRAFT.json DELTA_MS NEW_DRAFT.json\n" +
  "caption_edit sync DRAFT.json SOURCE_1 TARGET_1 SOURCE_2 TARGET_2 NEW_DRAFT.json\n" +
  "caption_edit export DRAFT.json NEW_OUTPUT_PREFIX\n" +
  "JSON drafts can also be edited directly. Existing output files are never overwritten."
}

///|
fn usage() -> Unit raise {
  fail(help())
}
