///|
fn draft(
  name : String,
  cues : Array[@captions.Caption],
) -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: name,
    duration_ms: 6000,
    cues,
  }
}

///|
test "independent boundaries preserve gaps and language coverage" {
  let primary = draft("English original.srt", [
    { start_ms: 500, end_ms: 2500, text: "Hello.", },
    { start_ms: 3500, end_ms: 5000, text: "Goodbye.", },
  ])
  let secondary = draft("中文.vtt", [
    { start_ms: 1000, end_ms: 2000, text: "你好。", },
    { start_ms: 2000, end_ms: 3000, text: "欢迎。", },
    { start_ms: 4000, end_ms: 5500, text: "再见。", },
  ])
  let result = @bilingual.compose(primary, secondary)
  assert_eq(result.primary_source_file, "English original.srt")
  assert_eq(result.secondary_source_file, "中文.vtt")
  assert_eq(result.draft.cues.length(), 7)
  assert_eq(result.coverage.shared_ms, 2500)
  assert_eq(result.coverage.primary_only_ms, 1000)
  assert_eq(result.coverage.secondary_only_ms, 1000)
  assert_eq(result.coverage.uncaptioned_ms, 1500)
  assert_eq(result.draft.cues[0].start_ms, 500)
  assert_eq(result.draft.cues[0].end_ms, 1000)
  assert_eq(result.draft.cues[1].text, "Hello.\n你好。")
  assert_eq(result.draft.cues[2].text, "Hello.\n欢迎。")
  assert_eq(result.draft.cues[3].text, "欢迎。")
  assert_eq(result.segments[2].primary_cue, Some(1))
  assert_eq(result.segments[2].secondary_cue, Some(2))
  assert_eq(result.segments[6].primary_cue, None)
  assert_eq(result.segments[6].secondary_cue, Some(3))
  assert_eq(primary.cues.length(), 2)
  assert_eq(secondary.cues.length(), 3)
  let edited = result.draft.set_cue(1, 500, 1000, "Hello, garden!")
  assert_eq(result.draft.cues[0].text, "Hello.")
  assert_eq(edited.cues[0].text, "Hello, garden!")
}

///|
test "adjacent cues retain provenance and exact multiline text" {
  let primary = draft("first", [
    { start_ms: 0, end_ms: 1000, text: "Moon 🌙\nA & B", },
    { start_ms: 1000, end_ms: 2000, text: "Moon 🌙\nA & B", },
  ])
  let secondary = draft("second", [
    { start_ms: 0, end_ms: 2000, text: "月亮 🌙", },
  ])
  let result = @bilingual.compose(primary, secondary)
  assert_eq(result.draft.cues.length(), 2)
  assert_eq(result.segments[1].primary_cue, Some(2))
  assert_eq(result.draft.cues[0].text, "Moon 🌙\nA & B\n月亮 🌙")
  assert_true(result.draft.vtt().contains("A &amp; B"))
  assert_eq(result.coverage.shared_ms, 2000)
  assert_eq(result.coverage.uncaptioned_ms, 4000)
  let swapped = @bilingual.compose(secondary, primary)
  assert_eq(swapped.draft.cues[0].text, "月亮 🌙\nMoon 🌙\nA & B")
}

///|
test "within-track overlap must be resolved by the editor" {
  let overlap = draft("overlap", [
    { start_ms: 0, end_ms: 2000, text: "First", },
    { start_ms: 1000, end_ms: 3000, text: "Second", },
  ])
  let plain = draft("plain", [{ start_ms: 0, end_ms: 3000, text: "Other", }])
  guard (try? @bilingual.compose(overlap, plain)) is Err(Failure(message)) else {
    fail("expected primary overlap refusal")
  }
  assert_true(message.contains("primary cue 2 overlaps"))
  guard (try? @bilingual.compose(plain, overlap)) is Err(Failure(message)) else {
    fail("expected secondary overlap refusal")
  }
  assert_true(message.contains("secondary cue 2 overlaps"))
}

///|
test "unequal durations and oversized combined text do not produce drafts" {
  let plain = draft("plain", [{ start_ms: 0, end_ms: 1000, text: "Other", }])
  assert_true(
    (try? @bilingual.compose(plain, { ..plain, duration_ms: 6001, })) is Err(_),
  )
  let text = Array::make(1100, "a").join("")
  let long = draft("long", [{ start_ms: 0, end_ms: 1000, text, }])
  long.validate()
  assert_true((try? @bilingual.compose(long, long)) is Err(_))
}

///|
test "derived interval limit is independent of input cue limits" {
  let primary = draft(
    "primary",
    Array::makei(2501, i => { start_ms: i * 2, end_ms: i * 2 + 1, text: "A", }),
  )
  let secondary = draft(
    "secondary",
    Array::makei(2501, i => {
      start_ms: i * 2 + 1,
      end_ms: i * 2 + 2,
      text: "B",
    }),
  )
  guard (try? @bilingual.compose(primary, secondary)) is Err(Failure(message)) else {
    fail("expected derived interval limit")
  }
  assert_true(message.contains("exceeds 5000"))
}
