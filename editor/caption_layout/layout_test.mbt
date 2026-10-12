///|
fn draft(cues : Array[@captions.Caption]) -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: "synthetic.srt",
    duration_ms: 7200000,
    cues,
  }
}

///|
fn profile() -> @caption_layout.Profile {
  {
    ..@caption_layout.default_profile(),
    max_line_chars: 12,
    max_lines: 2,
    min_duration_ms: 100,
  }
}

///|
test "reflow wraps words and preserves input timing identity and wording" {
  let original = draft([
    {
      start_ms: 100,
      end_ms: 4100,
      text: "  Grow   fresh\nherbs in pots today. ",
    },
  ])
  let result = @caption_layout.reflow(original, profile())
  assert_eq(result.draft.cues[0].text, "Grow fresh\nherbs in\npots today.")
  assert_eq(result.draft.cues[0].start_ms, 100)
  assert_eq(result.draft.cues[0].end_ms, 4100)
  assert_eq(result.draft.source_file, original.source_file)
  assert_eq(result.draft.duration_ms, original.duration_ms)
  assert_eq(original.cues[0].text, "  Grow   fresh\nherbs in pots today. ")
  assert_eq(result.origins[0].source_cue, 1)
  assert_false(result.origins[0].estimated_timing)
  assert_eq(@caption_layout.reflow(result.draft, profile()), result)
  assert_eq(
    @captions.read_draft(result.draft.to_json().stringify()),
    result.draft,
  )
}

///|
test "pagination partitions exact endpoints proportionally without losing words" {
  let source = draft([
    { start_ms: 101, end_ms: 6102, text: "Grow fresh herbs in pots today.", },
  ])
  let result = @caption_layout.paginate(source, profile())
  assert_eq(result.draft.cues.length(), 2)
  assert_eq(result.draft.cues[0].text, "Grow fresh\nherbs in")
  assert_eq(result.draft.cues[1].text, "pots today.")
  // 19 and 11 characters, including each page's internal spaces.
  assert_eq(result.draft.cues[0].start_ms, 101)
  assert_eq(result.draft.cues[0].end_ms, 3901)
  assert_eq(result.draft.cues[1].start_ms, 3901)
  assert_eq(result.draft.cues[1].end_ms, 6102)
  assert_true(result.origins.all(origin => origin.estimated_timing))
  assert_eq(result.origins[1].page, 2)
  assert_eq(result.origins[1].page_count, 2)
  assert_eq(
    result.draft.cues
    .map(cue => cue.text.replace_all(old="\n", new=" "))
    .join(" "),
    source.cues[0].text,
  )
  assert_eq(source.cues.length(), 1)
}

///|
test "pagination restores chronological order across overlapping speakers and ties" {
  let input = draft([
    { start_ms: 0, end_ms: 6000, text: "abcdefgh ijklmnop qrstuvwx", },
    { start_ms: 1000, end_ms: 4000, text: "Second voice", },
    { start_ms: 2000, end_ms: 3000, text: "Third", },
  ])
  let narrow = { ..profile(), max_line_chars: 8, max_lines: 1, }
  let output = @caption_layout.paginate(input, narrow)
  output.draft.validate()
  assert_eq(output.draft.cues.map(cue => cue.start_ms), [
    0, 1000, 2000, 2000, 2636, 4000,
  ])
  assert_eq(output.origins.map(origin => origin.source_cue), [1, 2, 1, 3, 2, 1])
  assert_eq(input.cues.length(), 3)
}

///|
test "Unicode scalar width does not split emoji or punctuation" {
  let input = draft([
    {
      start_ms: 0,
      end_ms: 5000,
      text: "🌱🌱🌱🌱 🌻🌻🌻🌻 Café & tea",
    },
  ])
  let result = @caption_layout.reflow(input, { ..profile(), max_line_chars: 8, })
  assert_eq(
    result.draft.cues[0].text,
    "🌱🌱🌱🌱\n🌻🌻🌻🌻\nCafé &\ntea",
  )
  assert_eq(
    @caption_layout.review(result.draft, profile()).cues[0].characters,
    20,
  )
  assert_true(result.draft.vtt().contains("Café &amp;"))
}

///|
test "reflow refuses long unbreakable words including nonbreaking spaces" {
  let too_long = draft([{ start_ms: 0, end_ms: 3000, text: "unbreakableword", }])
  assert_true((try? @caption_layout.reflow(too_long, profile())) is Err(_))
  let nbsp = draft([{ start_ms: 0, end_ms: 3000, text: "abcdef\u{a0}ghijkl", }])
  assert_true((try? @caption_layout.reflow(nbsp, profile())) is Err(_))
}

///|
test "pagination fails atomically on too short pages and enforces single page minimum" {
  let source = draft([
    { start_ms: 0, end_ms: 1000, text: "Grow fresh herbs in pots today.", },
  ])
  let strict = { ..profile(), min_duration_ms: 500, }
  assert_true((try? @caption_layout.paginate(source, strict)) is Err(_))
  assert_eq(source.cues.length(), 1)
  let short = draft([{ start_ms: 0, end_ms: 99, text: "Short", }])
  assert_true((try? @caption_layout.paginate(short, profile())) is Err(_))
  assert_eq(@caption_layout.reflow(short, profile()).draft.cues[0].end_ms, 99)
}

///|
test "review covers thresholds and both sides of nested overlaps without treating adjacency as overlap" {
  let input = draft([
    { start_ms: 0, end_ms: 5000, text: "Long lived", },
    { start_ms: 1000, end_ms: 1100, text: "Too fast", },
    { start_ms: 2000, end_ms: 3000, text: "Nested", },
    { start_ms: 5000, end_ms: 6000, text: "abcdefghijkl", },
  ])
  let feedback = @caption_layout.review(input, {
    ..profile(),
    max_chars_per_second: 12,
  })
  assert_true(feedback.cues[0].issues.contains("overlap"))
  assert_true(feedback.cues[1].issues.contains("fast_reading"))
  assert_true(feedback.cues[2].issues.contains("overlap"))
  assert_true(feedback.cues[3].issues.is_empty())
  assert_eq(feedback.cues[3].chars_per_second_milli, 12000)
  assert_eq(feedback.flagged_cues, 3)
  let crowded = draft([
    { start_ms: 0, end_ms: 99, text: "a long long line\nsecond\nthird", },
  ])
  assert_eq(@caption_layout.review(crowded, profile()).cues[0].issues, [
    "long_line", "too_many_lines", "short_duration", "fast_reading",
  ])
}

///|
test "profile parsing bounds and invalid draft errors are explicit" {
  assert_eq(
    @caption_layout.read_profile(profile().to_json().stringify()),
    profile(),
  )
  for
    invalid in [
      { ..profile(), contract: "unknown", },
      { ..profile(), max_line_chars: 7, },
      { ..profile(), max_line_chars: 121, },
      { ..profile(), max_lines: 0, },
      { ..profile(), max_lines: 5, },
      { ..profile(), min_duration_ms: 0, },
      { ..profile(), min_duration_ms: 10001, },
      { ..profile(), max_chars_per_second: 0, },
      { ..profile(), max_chars_per_second: 101, },
    ] {
    assert_true((try? invalid.validate()) is Err(_))
  }
  assert_true((try? @caption_layout.read_profile("{}")) is Err(_))
  assert_true((try? @caption_layout.reflow(draft([]), profile())) is Err(_))
}

///|
test "maximum duration integer arithmetic and cue count bound remain safe" {
  let input = draft([
    { start_ms: 0, end_ms: 7200000, text: "abcdefgh ijklmnop qrstuvwx", },
  ])
  let narrow = { ..profile(), max_line_chars: 8, max_lines: 1, }
  let result = @caption_layout.paginate(input, narrow)
  assert_eq(result.draft.cues.map(cue => cue.end_ms), [
    2400000, 4800000, 7200000,
  ])
  let huge = draft(
    Array::makei(2501, i => {
      start_ms: i * 1000,
      end_ms: i * 1000 + 900,
      text: "abcdefgh ijklmnop",
    }),
  )
  assert_true((try? @caption_layout.paginate(huge, narrow)) is Err(_))
}

///|
test "SRT and WebVTT reopen with exact pagination and TSV is one physical row per cue" {
  let result = @caption_layout.paginate(
    draft([
      {
        start_ms: 0,
        end_ms: 6000,
        text: "=SUM(A1) Café & tea for the garden",
      },
    ]),
    profile(),
  )
  let srt = @captions.import_draft(
    @utf8.encode(result.draft.srt()),
    "application/x-subrip",
    "output.srt",
    7200000,
  )
  let vtt = @captions.import_draft(
    @utf8.encode(result.draft.vtt()),
    "text/vtt",
    "output.vtt",
    7200000,
  )
  assert_eq(srt.cues, result.draft.cues)
  assert_eq(vtt.cues, result.draft.cues)
  let table = @caption_layout.tsv(result.draft, profile())
  assert_true(table.contains("\tjson:\"=SUM(A1)"))
  assert_eq(table.split("\n").count(), result.draft.cues.length() + 2)
}

///|
test "blank lines control characters and voice markup remain outside the plain text profile" {
  for
    text in [
      "", "   ", "one\n\ntwo", "one\n \ntwo", "<v Alice>Hello", "<i>Hello</i>", "one\ttwo",
      "one\rtwo",
    ] {
    let invalid = draft([{ start_ms: 0, end_ms: 3000, text, }])
    assert_true((try? @caption_layout.reflow(invalid, profile())) is Err(_))
    assert_true((try? @caption_layout.paginate(invalid, profile())) is Err(_))
  }
}

///|
test "every pagination origin is uniquely addressable and short final remainders fail" {
  let input = draft([
    { start_ms: 0, end_ms: 7001, text: "abcdefgh ijklmnop qrstuvwx", },
    { start_ms: 0, end_ms: 7001, text: "abcdefgh ijklmnop qrstuvwx", },
  ])
  let narrow = { ..profile(), max_line_chars: 8, max_lines: 1, }
  let result = @caption_layout.paginate(input, narrow)
  assert_eq(result.draft.cues.map(cue => cue.end_ms), [
    2333, 2333, 4667, 4667, 7001, 7001,
  ])
  assert_eq(result.origins.map(origin => origin.output_cue), [1, 2, 3, 4, 5, 6])
  assert_eq(result.origins.map(origin => origin.source_cue), [1, 2, 1, 2, 1, 2])
  assert_eq(result.origins.map(origin => origin.page), [1, 1, 2, 2, 3, 3])
  let remainder = draft([{ start_ms: 0, end_ms: 200, text: "abcdefgh x", }])
  assert_true((try? @caption_layout.paginate(remainder, narrow)) is Err(_))
}
