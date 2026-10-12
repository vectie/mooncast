///|
fn captions() -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: "episode",
    duration_ms: 6000,
    cues: [
      { start_ms: 0, end_ms: 1500, text: "Lead & intro", },
      { start_ms: 1000, end_ms: 5000, text: "Long overlap\n第二行 🌱", },
      { start_ms: 2000, end_ms: 3000, text: "At boundary", },
      { start_ms: 5000, end_ms: 6000, text: "Last", },
    ],
  }
}

///|
fn chapters() -> @chapters.Draft {
  {
    contract: "mooncast.chapter-draft.v1",
    project_id: "project",
    project_revision: 2,
    timeline_id: "cut",
    timeline_revision: 3,
    ticks_per_second: 24,
    duration_ticks: 144,
    markers: [
      { marker_id: "a", start_tick: 24, title: "First", },
      { marker_id: "b", start_tick: 48, title: "Second", },
      { marker_id: "c", start_tick: 96, title: "Silent start", },
      { marker_id: "d", start_tick: 120, title: "Last", },
    ],
  }
}

///|
test "lead-in, boundary ownership, overlaps and continuation without duplicate cues" {
  let cap = captions()
  let chap = chapters()
  let result = @readable_transcript.compose(cap, chap, "Episode")
  assert_true(
    result.sections.map(s => s.cue_numbers) == [[1], [2], [3], [], [4]],
  )
  assert_true(
    result.sections.map(s => s.continuing_cue_numbers) ==
    [[], [1], [2], [2], []],
  )
  assert_true(result.sections[0].marker_id == None)
  assert_true(result.sections[1].marker_id == Some("a"))
  assert_true(cap == captions() && chap == chapters())
  assert_eq(result.sections[4].end_ms, 6000)
}

///|
test "chapter zero avoids artificial lead-in and touching endpoint is not continuation" {
  let chap = chapters()
  let result = @readable_transcript.compose(
    captions(),
    { ..chap, markers: [{ marker_id: "zero", start_tick: 0, title: "All", }], },
    "Episode",
  )
  assert_eq(result.sections.length(), 1)
  assert_true(result.sections[0].cue_numbers == [1, 2, 3, 4])
  assert_true(result.sections[0].continuing_cue_numbers.is_empty())
}

///|
test "plain text retains multiline unicode and HTML escapes content and metadata" {
  let chap = chapters()
  let result = @readable_transcript.compose(
    captions(),
    {
      ..chap,
      markers: [{ marker_id: "<id>", start_tick: 0, title: "<script>&\"'", }],
    },
    "<Title>&\"'",
  )
  let html = result.html()
  assert_true(html.contains("&lt;script&gt;&amp;&quot;&#39;"))
  assert_true(html.contains("&lt;Title&gt;&amp;&quot;&#39;"))
  assert_true(!html.contains("<script>"))
  assert_true(!html.contains("<id>"))
  assert_true(html.contains("Lead &amp; intro"))
  assert_true(html.contains("Long overlap\n第二行 🌱"))
  assert_true(result.plain_text().contains("Long overlap\n第二行 🌱"))
  assert_true(html.contains("id=\"cue-4\""))
}

///|
test "empty chapter gets explicit text and accessible continuation link" {
  let result = @readable_transcript.compose(captions(), chapters(), "Episode")
  assert_true(result.html().contains("href=\"#cue-2\">cue 2 above</a>"))
  assert_true(result.html().contains("No cues begin in this chapter."))
  assert_true(result.plain_text().contains("00:00:04.000–00:00:05.000"))
}

///|
test "reject unequal durations" {
  let cap = captions()
  assert_true(
    (try? @readable_transcript.compose(
      { ..cap, duration_ms: 6001, },
      chapters(),
      "x",
    ))
    is Err(_),
  )
}

///|
test "reject submillisecond boundaries instead of silently rounding" {
  let chap = chapters()
  assert_true(
    (try? @readable_transcript.compose(
      captions(),
      {
        ..chap,
        markers: [{ marker_id: "a", start_tick: 1, title: "fraction", }],
      },
      "x",
    ))
    is Err(_),
  )
}

///|
test "reject invalid input ordering and duplicate chapter IDs" {
  let chap = chapters()
  assert_true(
    (try? @readable_transcript.compose(
      captions(),
      { ..chap, markers: [chap.markers[1], chap.markers[0]], },
      "x",
    ))
    is Err(_),
  )
  assert_true(
    (try? @readable_transcript.compose(
      captions(),
      {
        ..chap,
        markers: [
          { marker_id: "a", start_tick: 0, title: "a", },
          chap.markers[0],
        ],
      },
      "x",
    ))
    is Err(_),
  )
  let cap = captions()
  assert_true(
    (try? @readable_transcript.compose(
      { ..cap, cues: [cap.cues[2], cap.cues[0]], },
      chap,
      "x",
    ))
    is Err(_),
  )
}

///|
test "reject empty or multiline title" {
  assert_true(
    (try? @readable_transcript.compose(captions(), chapters(), " ")) is Err(_),
  )
  assert_true(
    (try? @readable_transcript.compose(captions(), chapters(), "a\nb"))
    is Err(_),
  )
}

///|
test "large legal tick clock uses wide arithmetic" {
  let chap = chapters()
  let result = @readable_transcript.compose(
    captions(),
    {
      ..chap,
      ticks_per_second: 300000000,
      duration_ticks: 1800000000,
      markers: [{ marker_id: "a", start_tick: 300000000, title: "First", }],
    },
    "x",
  )
  assert_eq(result.sections[1].start_ms, 1000)
  assert_eq(result.sections[1].end_ms, 6000)
}

///|
test "bounded pathological cross chapter expansion" {
  let cap = captions()
  let chap = chapters()
  let cues = Array::make(30, @captions.Caption::{
    start_ms: 0,
    end_ms: 6000,
    text: "long",
  })
  let markers = Array::makei(1000, i => @chapters.Marker::{
    marker_id: i.to_string(),
    start_tick: i,
    title: "part",
  })
  assert_true(
    (try? @readable_transcript.compose(
      { ..cap, cues, },
      { ..chap, ticks_per_second: 1000, duration_ticks: 6000, markers, },
      "x",
    ))
    is Err(_),
  )
}
