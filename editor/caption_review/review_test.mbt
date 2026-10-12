///|
fn example() -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: "synthetic,review.srt",
    duration_ms: 10000,
    cues: [
      {
        start_ms: 100,
        end_ms: 2000,
        text: "Hello, \"garden\"\nCafé 🌱 & herbs",
      },
      { start_ms: 3000, end_ms: 5000, text: "=literal formula-looking words", },
      { start_ms: 6000, end_ms: 9000, text: "Last cue", },
    ],
  }
}

///|
fn rejected(draft : @captions.CaptionDraft, sheet : String) -> Bool {
  try {
    ignore(@review.apply_sheet(draft, sheet))
    false
  } catch {
    _ => true
  }
}

///|
test "unchanged sheet preserves quoted commas Unicode newlines and formula text" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
  assert_true(sheet.contains("\"text:=literal"))
  assert_true(sheet.contains("\"\"garden\"\"\nCafé"))
  let result = @review.apply_sheet(draft, sheet)
  assert_eq(result.draft, draft)
  assert_eq(result.changes.length(), 0)
}

///|
test "whole batch text and timing updates preserve source and line breaks" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
    .replace_all(old="\"3000\",\"5000\"", new="\"6500\",\"7500\"")
    .replace_all(old="\"6000\",\"9000\"", new="\"8000\",\"10000\"")
    .replace_all(old="Last cue", new="Last, corrected\nSecond line")
  let result = @review.apply_sheet(draft, sheet)
  assert_eq(result.changes.length(), 2)
  assert_eq(result.changes[0].cue_key, "cue-2")
  assert_eq(result.changes[1].before, draft.cues[2])
  assert_eq(result.draft.cues[1].start_ms, 6500)
  assert_eq(result.draft.cues[2].text, "Last, corrected\nSecond line")
  assert_eq(draft, example())
  assert_true(result.draft.srt().contains("00:00:08,000 --> 00:00:10,000"))
  assert_true(result.draft.vtt().contains("Café 🌱 &amp; herbs"))
}

///|
test "spreadsheet CRLF BOM and missing trailing newline" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
  let crlf = "\u{feff}" + sheet.replace_all(old="\n", new="\r\n")
  assert_eq(@review.apply_sheet(draft, crlf).draft, draft)
  assert_eq(
    @review.apply_sheet(draft, sheet[:sheet.length() - 1].to_owned()).draft,
    draft,
  )
}

///|
test "row sorting does not reorder output cues" {
  let draft = {
    ..example(),
    cues: example().cues.map(c => { ..c, text: "one line", }),
  }
  let lines = @review.export_sheet(draft)
    .split("\n")
    .map(s => s.to_owned())
    .to_array()
  let sorted = [lines[0], lines[3], lines[1], lines[2]].join("\n")
  assert_eq(@review.apply_sheet(draft, sorted).draft, draft)
}

///|
test "semantic binding tolerates JSON formatting but catches any source change" {
  let draft = example()
  let formatted = @captions.read_draft(draft.to_json().stringify(indent=4))
  assert_eq(@review.binding(draft), @review.binding(formatted))
  let sheet = @review.export_sheet(draft)
  assert_true(rejected({ ..draft, source_file: "different.srt", }, sheet))
  assert_true(rejected({ ..draft, duration_ms: 11000, }, sheet))
  assert_true(rejected(draft.set_cue(3, 6000, 9000, "changed"), sheet))
}

///|
test "duplicate unknown and missing cue keys fail" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
  assert_true(rejected(draft, sheet.replace_all(old="cue-3", new="cue-2")))
  assert_true(rejected(draft, sheet.replace_all(old="cue-3", new="cue-4")))
  assert_true(rejected(draft, sheet.replace_all(old="cue-3", new="cue-03")))
  assert_true(rejected(draft, sheet + "extra,row,1,2,text:oops\n"))
  assert_true(rejected(draft, "source_binding,cue_key,start_ms,end_ms,text\n"))
}

///|
test "invalid times reject whole operation" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
  for value in ["-1", "+1", "1.0", "1e3", " 100", "", "2147483648", "9001"] {
    assert_true(
      rejected(
        draft,
        sheet.replace_all(old="\"6000\"", new="\"" + value + "\""),
      ),
    )
  }
  assert_true(
    rejected(draft, sheet.replace_all(old="\"9000\"", new="\"10001\"")),
  )
}

///|
test "timing reorder fails but ties and overlaps remain allowed" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
  assert_true(
    rejected(draft, sheet.replace_all(old="\"6000\"", new="\"2000\"")),
  )
  let tied = @review.apply_sheet(
    draft,
    sheet.replace_all(old="\"6000\"", new="\"3000\""),
  )
  assert_eq(tied.draft.cues[2].start_ms, 3000)
}

///|
test "invalid caption text retains existing validator boundaries" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
  for value in ["", " ", "bad\n\nline", "<tag>", "tab\there", "nul\u{0}here"] {
    assert_true(rejected(draft, sheet.replace_all(old="Last cue", new=value)))
  }
  let long = StringBuilder()
  for _ in 0..<2001 {
    long.write_string("a")
  }
  assert_true(
    rejected(draft, sheet.replace_all(old="Last cue", new=long.to_string())),
  )
}

///|
test "text prefix required and exact literal prefix preserved" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
  assert_true(
    rejected(draft, sheet.replace_all(old="text:Last cue", new="Last cue")),
  )
  let result = @review.apply_sheet(
    draft,
    sheet.replace_all(old="text:Last cue", new="text:text:literal"),
  )
  assert_eq(result.draft.cues[2].text, "text:literal")
}

///|
test "strict malformed CSV and header rejection" {
  let draft = example()
  let sheet = @review.export_sheet(draft)
  assert_true(
    rejected(draft, sheet.replace_all(old="source_binding", new="revision")),
  )
  assert_true(
    rejected(
      draft,
      sheet.replace_all(old="\"text:Last cue\"", new="\"text:Last cue"),
    ),
  )
  assert_true(
    rejected(
      draft,
      sheet.replace_all(old="\"text:Last cue\"", new="\"text:Last cue\"x"),
    ),
  )
  assert_true(
    rejected(
      draft,
      sheet.replace_all(old="\"text:Last cue\"", new="text:Last\"cue"),
    ),
  )
  assert_true(
    rejected(draft, sheet.replace_all(old="Last cue", new="Last\rcue")),
  )
  assert_true(rejected(draft, sheet + "\n"))
  assert_true(
    rejected(draft, sheet.replace_all(old="cue-3\",", new="cue-3\",extra,")),
  )
}

///|
test "SRT and WebVTT exports reopen with exact edited values" {
  let draft = example()
  let result = @review.apply_sheet(
    draft,
    @review.export_sheet(draft).replace_all(
      old="Last cue",
      new="Changed, café\n🌱 & more",
    ),
  )
  let srt = @captions.import_draft(
    @utf8.encode(result.draft.srt()),
    "application/x-subrip",
    draft.source_file,
    draft.duration_ms,
  )
  let vtt = @captions.import_draft(
    @utf8.encode(result.draft.vtt()),
    "text/vtt",
    draft.source_file,
    draft.duration_ms,
  )
  assert_eq(srt, result.draft)
  assert_eq(vtt, result.draft)
}

///|
test "unquoted numeric cells and text cells supported" {
  let draft = {
    ..example(),
    cues: [{ start_ms: 0, end_ms: 10000, text: "simple", }],
  }
  let sheet = "source_binding,cue_key,start_ms,end_ms,text\n" +
    @review.binding(draft) +
    ",cue-1,0,10000,text:simple"
  assert_eq(@review.apply_sheet(draft, sheet).draft, draft)
}

///|
test "maximum cue count preserves identity and rejects inserted row" {
  let draft = {
    ..example(),
    cues: Array::makei(5000, i => { start_ms: i, end_ms: i + 1, text: "a", }),
  }
  let sheet = @review.export_sheet(draft)
  let result = @review.apply_sheet(draft, sheet)
  assert_eq(result.draft, draft)
  assert_true(rejected(draft, sheet + "one,two,3,4,text:a\n"))
}

///|
test "oversized sheet is refused before CSV processing" {
  let text = StringBuilder()
  for _ in 0..<16778 {
    text.write_string("x".repeat(1000))
  }
  assert_true(rejected(example(), text.to_string()))
}
