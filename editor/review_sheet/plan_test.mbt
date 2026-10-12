///|
fn chapters() -> @chapters.Draft {
  {
    contract: "mooncast.chapter-draft.v1",
    project_id: "p",
    project_revision: 3,
    timeline_id: "cut",
    timeline_revision: 2,
    ticks_per_second: 24000,
    duration_ticks: 240000,
    markers: [
      { marker_id: "a", start_tick: 48000, title: "Opening <wide>", },
      { marker_id: "b", start_tick: 144000, title: "Finale & café", },
    ],
  }
}

///|
fn captions() -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: "captions.srt",
    duration_ms: 10000,
    cues: [
      { start_ms: 0, end_ms: 2000, text: "Before.", },
      { start_ms: 2000, end_ms: 3000, text: "Start & continue.\n第二行", },
      { start_ms: 5000, end_ms: 7000, text: "Across boundary.", },
      { start_ms: 6000, end_ms: 9000, text: "Another speaker.", },
    ],
  }
}

///|
test "uniform midpoint samples partition the entire duration without end seeks" {
  let sheet = @review_sheet.uniform(10001, 3, "Cut review")
  assert_eq(sheet.cards.length(), 3)
  assert_eq(sheet.cards[0].start_ms, 0)
  assert_eq(sheet.cards[0].end_ms, 3333)
  assert_eq(sheet.cards[0].requested_ms, 1666)
  assert_eq(sheet.cards[1].start_ms, 3333)
  assert_eq(sheet.cards[1].end_ms, 6667)
  assert_eq(sheet.cards[1].requested_ms, 5000)
  assert_eq(sheet.cards[2].end_ms, 10001)
  assert_eq(sheet.cards[2].requested_ms, 8334)
  assert_eq(sheet.cards[2].image, "frames/frame-3.png")
  assert_eq(@review_sheet.time(3600123), "01:00:00.123")
}

///|
test "chapter midpoint sampling includes uncovered opening and exact nonmillisecond clock" {
  let sheet = @review_sheet.by_chapters(10000, chapters(), "Review")
  assert_eq(sheet.cards.length(), 3)
  assert_eq(sheet.cards[0].title, "Before first chapter")
  assert_eq(sheet.cards[0].requested_ms, 1000)
  assert_eq(sheet.cards[1].start_ms, 2000)
  assert_eq(sheet.cards[1].requested_ms, 4000)
  assert_eq(sheet.cards[2].requested_ms, 8000)
  let zero = {
    ..chapters(),
    markers: [{ marker_id: "a", start_tick: 0, title: "All", }],
  }
  assert_eq(@review_sheet.by_chapters(10000, zero, "Review").cards.length(), 1)
}

///|
test "caption overlap includes all speakers and explicit repeated cues at boundaries" {
  let sheet = @review_sheet.by_chapters(
    10000,
    chapters(),
    "Review",
    captions=captions(),
  )
  assert_eq(sheet.cards[0].excerpts.length(), 1)
  assert_eq(sheet.cards[0].excerpts[0].cue_number, 1)
  assert_eq(sheet.cards[1].excerpts.length(), 2)
  assert_eq(sheet.cards[1].excerpts[0].cue_number, 2)
  assert_eq(sheet.cards[1].excerpts[1].cue_number, 3)
  assert_eq(sheet.cards[2].excerpts.length(), 2)
  assert_eq(sheet.cards[2].excerpts[0].cue_number, 3)
  assert_eq(sheet.cards[2].excerpts[0].start_ms, 5000)
  assert_eq(sheet.cards[2].excerpts[0].end_ms, 7000)
  assert_eq(sheet.cards[2].excerpts[1].cue_number, 4)
}

///|
test "HTML escapes inputs and remains a scriptless relative portable printable sheet" {
  let sheet = @review_sheet.by_chapters(
    10000,
    chapters(),
    "<script> & \"Title\"",
    captions=captions(),
  )
  let html = sheet.html("a<img src=x>.mp4", "abc&def")
  assert_true(html.contains("&lt;script&gt; &amp; &quot;Title&quot;"))
  assert_true(html.contains("Opening &lt;wide&gt;"))
  assert_true(html.contains("Start &amp; continue.\n第二行"))
  assert_true(html.contains("a&lt;img src=x&gt;.mp4"))
  assert_true(html.contains("src=\"frames/frame-1.png\""))
  assert_true(html.contains("href=\"#card-3\""))
  assert_true(html.contains("@media print"))
  assert_true(!html.contains("<script"))
  assert_true(!html.contains("https://"))
  assert_true(!html.contains("file://"))
  assert_true(html.contains("abc&amp;def"))
}

///|
test "empty and excessive selections fail before any work" {
  assert_true((try? @review_sheet.uniform(0, 1, "Review")) is Err(_))
  assert_true((try? @review_sheet.uniform(7200001, 1, "Review")) is Err(_))
  assert_true((try? @review_sheet.uniform(1000, 0, "Review")) is Err(_))
  assert_true((try? @review_sheet.uniform(1000, 121, "Review")) is Err(_))
  assert_true((try? @review_sheet.uniform(1, 2, "Review")) is Err(_))
  assert_true((try? @review_sheet.uniform(1000, 1, "\n")) is Err(_))
  assert_eq(@review_sheet.uniform(1, 1, "Review").cards[0].requested_ms, 0)
  assert_eq(@review_sheet.uniform(7200000, 120, "Review").cards.length(), 120)
}

///|
test "mismatched durations and inexact chapter milliseconds reject rather than drift" {
  assert_true(
    (try? @review_sheet.uniform(9000, 3, "Review", captions=captions()))
    is Err(_),
  )
  assert_true(
    (try? @review_sheet.by_chapters(9000, chapters(), "Review")) is Err(_),
  )
  let fractional = {
    ..chapters(),
    markers: [{ marker_id: "a", start_tick: 1, title: "Fraction", }],
  }
  assert_true(
    (try? @review_sheet.by_chapters(10000, fractional, "Review")) is Err(_),
  )
  let outside = {
    ..chapters(),
    markers: [{ marker_id: "a", start_tick: 239976, title: "End", }],
  }
  assert_true(
    (try? @review_sheet.by_chapters(9990, outside, "Review")) is Err(_),
  )
  assert_eq(
    @review_sheet.uniform(10049, 1, "Review", captions=captions()).duration_ms,
    10049,
  )
}

///|
test "caption absence differs from a supplied caption gap" {
  let absent = @review_sheet.uniform(10000, 2, "Review").html("cut.mp4", "hash")
  assert_true(absent.contains("No caption draft supplied."))
  let gap = @review_sheet.uniform(10000, 10, "Review", captions=captions()).html(
    "cut.mp4", "hash",
  )
  assert_true(gap.contains("No supplied caption overlaps this interval."))
}

///|
test "bounded excerpts reject oversized repeated text and excessive chapters" {
  let many = {
    ..captions(),
    cues: Array::makei(501, _ => @captions.Caption::{
      start_ms: 0,
      end_ms: 10000,
      text: "a".repeat(2000),
    }),
  }
  assert_true(
    (try? @review_sheet.uniform(10000, 1, "Review", captions=many)) is Err(_),
  )
  let many_chapters = {
    ..chapters(),
    markers: Array::makei(120, i => @chapters.Marker::{
      marker_id: i.to_string(),
      start_tick: (i + 1) * 24,
      title: "Chapter",
    }),
  }
  assert_true(
    (try? @review_sheet.by_chapters(10000, many_chapters, "Review")) is Err(_),
  )
}
