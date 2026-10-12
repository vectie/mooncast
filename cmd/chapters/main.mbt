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
async fn write_new(path : String, text : String) -> Unit {
  guard !path.is_empty() && !path.contains("://") && !@fs.exists(path) else {
    fail("output must be a new local path: " + path)
  }
  @fs.write_file(path, @utf8.encode(text), create_mode=CreateNew)
}

///|
async fn main {
  let help = "usage:\n  chapters seed PROJECT.json TRACK_ID NEW_DRAFT.json\n  chapters preview DRAFT.json\n  chapters set DRAFT.json ID START_TICK TITLE NEW_DRAFT.json\n  chapters remove DRAFT.json ID NEW_DRAFT.json\n  chapters export DRAFT.json NEW_PREFIX\n\nCreates .chapters.vtt, .ffmetadata and .chapters.json. Local sidecars only.\nSee docs/timeline-chapters.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    println(
      "  chapters import DRAFT.json CHAPTERS.ffmetadata NEW_DRAFT.json\nReplace markers from exact FFmetadata intervals; see docs/chapter-import.md.",
    )
    return
  }
  guard args.length() >= 3 else { fail(help) }
  let draft = match args[1] {
    "seed" => {
      guard args.length() == 5 else { fail(help) }
      let project = @domain.snapshot_from_json(read_local(args[2], 16777216))
      let result = @chapter_data.seed(project, args[3])
      write_new(args[4], result.to_json().stringify(indent=2) + "\n")
      result
    }
    "preview" | "set" | "remove" | "export" | "import" =>
      @chapter_data.read_draft(read_local(args[2], 2097152))
    _ => fail(help)
  }
  let result = match args[1] {
    "import" => {
      guard args.length() == 5 else {
        fail(
          "usage: chapters import DRAFT.json CHAPTERS.ffmetadata NEW_DRAFT.json",
        )
      }
      let result = draft.import_ffmetadata(read_local(args[3], 2097152))
      write_new(args[4], result.to_json().stringify(indent=2) + "\n")
      result
    }
    "set" => {
      guard args.length() == 7 else { fail(help) }
      let result = draft.put({
        marker_id: args[3],
        start_tick: @string.parse_int(args[4]),
        title: args[5],
      })
      write_new(args[6], result.to_json().stringify(indent=2) + "\n")
      result
    }
    "remove" => {
      guard args.length() == 5 else { fail(help) }
      let result = draft.remove(args[3])
      write_new(args[4], result.to_json().stringify(indent=2) + "\n")
      result
    }
    "export" => {
      guard args.length() == 4 else { fail(help) }
      let prefix = args[3]
      guard !prefix.is_empty() && !prefix.contains("://") else {
        fail("output prefix must be local and nonempty")
      }
      let outputs = [
        (prefix + ".chapters.vtt", draft.webvtt()),
        (prefix + ".ffmetadata", draft.ffmetadata()),
        (prefix + ".chapters.json", draft.to_json().stringify(indent=2) + "\n"),
      ]
      for (path, _) in outputs {
        guard !@fs.exists(path) else { fail("output already exists: " + path) }
      }
      for (path, text) in outputs {
        write_new(path, text)
      }
      println(
        "Created " + prefix + ".chapters.vtt, .ffmetadata and .chapters.json",
      )
      draft
    }
    "preview" => {
      guard args.length() == 3 else { fail(help) }
      draft
    }
    _ => draft
  }
  println(
    "Timeline " +
    result.timeline_id +
    " revision " +
    result.timeline_revision.to_string() +
    ": " +
    result.duration_ticks.to_string() +
    " ticks at " +
    result.ticks_per_second.to_string() +
    " ticks/second",
  )
  for marker in result.markers {
    println(
      marker.marker_id +
      "\t" +
      marker.start_tick.to_string() +
      "\t" +
      marker.title,
    )
  }
}
