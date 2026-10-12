///|
fn sample() -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: "synthetic.whisper.json",
    duration_ms: 10000,
    cues: [
      { start_ms: 500, end_ms: 1500, text: "Hello 🌙", },
      { start_ms: 2000, end_ms: 3000, text: "A second line", },
      { start_ms: 4000, end_ms: 5000, text: "Goodbye", },
    ],
  }
}

///|
test "correct text and timing then export the actual corrected captions" {
  let draft = sample()
  let updated = draft.set_cue(2, 2100, 3250, "Corrected 世界\nSecond line")
  assert_eq(draft.cues[1].text, "A second line")
  assert_eq(updated.cues[1].start_ms, 2100)
  assert_eq(updated.cues[1].end_ms, 3250)
  assert_true(
    updated
    .srt()
    .contains("00:00:02,100 --> 00:00:03,250\nCorrected 世界\nSecond line"),
  )
  assert_true(
    updated
    .vtt()
    .contains("00:00:02.100 --> 00:00:03.250\nCorrected 世界\nSecond line"),
  )
  assert_eq(@captions.read_draft(updated.to_json().stringify()), updated)
}

///|
test "split a long caption and merge a later range without mutating the input" {
  let draft = sample()
  let split = draft.split_cue(2, 2500, "Part one", "Part two")
  assert_eq(split.cues.length(), 4)
  assert_eq(split.cues[1], { start_ms: 2000, end_ms: 2500, text: "Part one", })
  assert_eq(split.cues[2], { start_ms: 2500, end_ms: 3000, text: "Part two", })
  let merged = split.merge_cues(2, 4, "Combined with ending")
  assert_eq(merged.cues.length(), 2)
  assert_eq(merged.cues[1], {
    start_ms: 2000,
    end_ms: 5000,
    text: "Combined with ending",
  })
  assert_eq(draft, sample())
}

///|
test "merge uses the longest end even when consecutive cues overlap" {
  let draft : @captions.CaptionDraft = {
    ..sample(),
    cues: [
      { start_ms: 500, end_ms: 4500, text: "Speaker one", },
      { start_ms: 1000, end_ms: 2000, text: "Speaker two", },
    ],
  }
  let merged = draft.merge_cues(1, 2, "Both speakers")
  assert_eq(merged.cues[0].end_ms, 4500)
  assert_eq(draft.shift(100).cues[1].start_ms, 1100)
}

///|
test "positive and negative offsets preserve gaps and exact boundaries" {
  let draft = sample()
  let shifted = draft.shift(125)
  assert_eq(shifted.cues[0].start_ms, 625)
  assert_eq(shifted.cues[2].end_ms, 5125)
  assert_eq(shifted.shift(-125), draft)
  assert_eq(draft.shift(-500).cues[0].start_ms, 0)
  expect_error(() => ignore(draft.shift(-501)))
  expect_error(() => ignore(draft.shift(5001)))
  expect_error(() => ignore(draft.shift(2147483647)))
  assert_eq(draft, sample())
}

///|
test "two point synchronization corrects offset and clock drift" {
  let synced = sample().sync(500, 750, 5000, 6150)
  assert_eq(synced.cues[0].start_ms, 750)
  assert_eq(synced.cues[0].end_ms, 1950)
  assert_eq(synced.cues[1].start_ms, 2550)
  assert_eq(synced.cues[1].end_ms, 3750)
  assert_eq(synced.cues[2].start_ms, 4950)
  assert_eq(synced.cues[2].end_ms, 6150)
  assert_eq(sample().sync(0, 0, 10000, 10000), sample())
}

///|
test "sync uses deterministic nearest milliseconds and no clipped output" {
  let draft : @captions.CaptionDraft = {
    ..sample(),
    cues: [{ start_ms: 1, end_ms: 3, text: "Half millisecond boundaries", }],
  }
  let result = draft.sync(0, 0, 4, 2)
  assert_eq(result.cues[0].start_ms, 1)
  assert_eq(result.cues[0].end_ms, 2)
  expect_error(() => ignore(draft.sync(0, 0, 10000, 1)))
  expect_error(() => ignore(sample().sync(2000, 0, 5000, 3000)))
  expect_error(() => ignore(sample().sync(0, 0, 1000, 10000)))
  expect_error(() => ignore(sample().sync(5000, 0, 5000, 1000)))
  expect_error(() => ignore(sample().sync(0, 2000, 5000, 1000)))
}

///|
test "import supported transcription files into the same editable model" {
  let json = @captions.import_draft(
    b"{\"segments\":[{\"start\":0.5,\"end\":1.5,\"text\":\"Caption\"}]}", "application/json",
    "source.json", 5000,
  )
  let tsv = @captions.import_draft(
    b"start\tend\ttext\n500\t1500\tCaption\n", "text/tab-separated-values", "source.tsv",
    5000,
  )
  let labels = @captions.import_draft(
    b"0.5\t1.5\tCaption\n", "text/plain", "source.txt", 5000,
  )
  let srt = @captions.import_draft(
    b"1\n00:00:00,500 --> 00:00:01,500\nCaption\n", "application/x-subrip", "source.srt",
    5000,
  )
  let vtt = @captions.import_draft(
    b"WEBVTT\n\n00:00.500 --> 00:01.500\nCaption\n", "text/vtt", "source.vtt", 5000,
  )
  assert_eq(json.cues, tsv.cues)
  assert_eq(json.cues, labels.cues)
  assert_eq(json.cues, srt.cues)
  assert_eq(json.cues, vtt.cues)
  assert_eq(json.duration_ms, 5000)
  assert_eq(json.source_file, "source.json")
}

///|
test "exported SRT and WebVTT reopen with their exact caption timing and text" {
  let draft = sample().set_cue(1, 500, 1500, "AT&T and literal &amp; 🌙")
  assert_true(draft.vtt().contains("AT&amp;T and literal &amp;amp; 🌙"))
  assert_eq(
    @captions.import_draft(
      @utf8.encode(draft.srt()),
      "application/x-subrip",
      "reopen.srt",
      10000,
    ).cues,
    draft.cues,
  )
  assert_eq(
    @captions.import_draft(
      @utf8.encode(draft.vtt()),
      "text/vtt",
      "reopen.vtt",
      10000,
    ).cues,
    draft.cues,
  )
}

///|
test "invalid user edits leave the original draft unchanged" {
  let draft = sample()
  expect_error(() => ignore(draft.set_cue(0, 0, 1000, "Wrong cue")))
  expect_error(() => ignore(draft.set_cue(4, 0, 1000, "Wrong cue")))
  expect_error(() => ignore(draft.set_cue(2, 499, 1000, "Out of order")))
  expect_error(() => ignore(draft.set_cue(1, 0, 0, "Empty interval")))
  expect_error(() => ignore(draft.split_cue(1, 500, "At start", "End")))
  expect_error(() => ignore(draft.split_cue(1, 1500, "Start", "At end")))
  expect_error(() => ignore(draft.merge_cues(2, 1, "Reversed")))
  expect_error(() => ignore(draft.merge_cues(1, 1, "Only one cue")))
  for
    text in [
      "", " \n ", "A\n\nB", "A\rB", "A\u{0000}B", "<b>Markup</b>", "A\tB",
    ] {
    expect_error(() => ignore(draft.set_cue(1, 500, 1500, text)))
  }
  assert_eq(draft, sample())
}

///|
test "draft and timestamp bounds are explicit" {
  let draft = sample()
  expect_error(() => ignore({ ..draft, contract: "unknown", }.validate()))
  expect_error(() => ignore({ ..draft, duration_ms: 0, }.validate()))
  expect_error(() => ignore({ ..draft, duration_ms: 7200001, }.validate()))
  expect_error(() => ignore({ ..draft, cues: [], }.validate()))
  expect_error(() => {
    ignore({ ..draft, cues: Array::make(5001, draft.cues[0]), }.validate())
  })
  expect_error(() => {
    ignore(@captions.read_draft("{\"contract\":\"mooncast.caption-draft.v1\"}"))
  })
  let late : @captions.CaptionDraft = {
    ..draft,
    duration_ms: 7200000,
    cues: [{ start_ms: 7199999, end_ms: 7200000, text: "Last millisecond", }],
  }
  assert_true(late.srt().contains("01:59:59,999 --> 02:00:00,000"))
  assert_eq(late.sync(0, 0, 7200000, 7200000), late)
}

///|
fn expect_error(work : () -> Unit raise) -> Unit raise {
  try work() catch {
    _ => ()
  } noraise {
    _ => fail("expected this edit to fail")
  }
}

///|
test "hand edited fractional clocks and oversized exports fail explicitly" {
  let draft = sample()
  let fractional = draft
    .to_json()
    .stringify()
    .replace_all(old="500", new="500.5")
  expect_error(() => ignore(@captions.read_draft(fractional)))
  let long = Array::make(2001, "x").join("")
  expect_error(() => ignore(draft.set_cue(1, 500, 1500, long)))
  let many : @captions.CaptionDraft = {
    ..draft,
    cues: Array::make(1200, {
      start_ms: 0,
      end_ms: 1000,
      text: Array::make(2000, "x").join(""),
    }),
  }
  expect_error(() => ignore(many.srt()))
  let escaped : @captions.CaptionDraft = {
    ..draft,
    cues: Array::make(250, {
      start_ms: 0,
      end_ms: 1000,
      text: Array::make(2000, "&").join(""),
    }),
  }
  ignore(escaped.srt())
  expect_error(() => ignore(escaped.vtt()))
}

///|
test "split overlapping speaker cue keeps intervening speaker in time order" {
  let draft : @captions.CaptionDraft = {
    ..sample(),
    cues: [
      { start_ms: 500, end_ms: 4500, text: "Speaker one opening and ending", },
      { start_ms: 1000, end_ms: 2000, text: "Speaker two interjection", },
    ],
  }
  let split = draft.split_cue(
    1, 2500, "Speaker one opening", "Speaker one ending",
  )
  assert_eq(split.cues, [
    { start_ms: 500, end_ms: 2500, text: "Speaker one opening", },
    { start_ms: 1000, end_ms: 2000, text: "Speaker two interjection", },
    { start_ms: 2500, end_ms: 4500, text: "Speaker one ending", },
  ])
  assert_eq(draft.cues.length(), 2)
  assert_eq(draft.cues[0].end_ms, 4500)
  let reopened = @captions.import_draft(
    @utf8.encode(split.srt()),
    "application/x-subrip",
    "split.srt",
    10000,
  )
  assert_eq(reopened.cues, split.cues)
}

///|
test "split preserves dense overlaps and inserts before equal-start cues" {
  let draft : @captions.CaptionDraft = {
    ..sample(),
    cues: [
      { start_ms: 0, end_ms: 6000, text: "Background speaker", },
      { start_ms: 500, end_ms: 4500, text: "Selected speaker", },
      { start_ms: 500, end_ms: 1000, text: "Same original start", },
      { start_ms: 1000, end_ms: 3000, text: "Intervening speaker", },
      { start_ms: 2500, end_ms: 3500, text: "Same split start", },
      { start_ms: 4000, end_ms: 5000, text: "Later speaker", },
    ],
  }
  let split = draft.split_cue(2, 2500, "First half", "Second half")
  assert_eq(split.cues.length(), 7)
  assert_eq(split.cues.map(cue => cue.start_ms), [
    0, 500, 500, 1000, 2500, 2500, 4000,
  ])
  assert_eq(split.cues.map(cue => cue.text), [
    "Background speaker", "First half", "Same original start", "Intervening speaker",
    "Second half", "Same split start", "Later speaker",
  ])
  for (original_index, split_index) in [(0, 0), (2, 2), (3, 3), (4, 5), (5, 6)] {
    assert_eq(split.cues[split_index], draft.cues[original_index])
  }
}
