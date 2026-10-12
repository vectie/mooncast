///|
fn media() -> @media.Media {
  {
    suffix: ".mp4",
    duration_ms: 6000,
    tracks: [
      {
        index: 0,
        kind: "video",
        codec: "h264",
        language: "und",
        title: "",
        is_default: true,
        forced: false,
      },
      {
        index: 1,
        kind: "audio",
        codec: "aac",
        language: "und",
        title: "",
        is_default: true,
        forced: false,
      },
    ],
    chapters: [],
  }
}

///|
fn captions() -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: "café.srt",
    duration_ms: 6000,
    cues: [
      { start_ms: 500, end_ms: 2500, text: "Café &amp; 🌱\nLine two", },
      { start_ms: 1500, end_ms: 3000, text: "Other speaker", },
      { start_ms: 4000, end_ms: 6000, text: "Final words", },
    ],
  }
}

///|
fn chapters() -> @chapters.Draft {
  {
    contract: "mooncast.chapter-draft.v1",
    project_id: "p",
    project_revision: 1,
    timeline_id: "t",
    timeline_revision: 2,
    ticks_per_second: 30000,
    duration_ticks: 180000,
    markers: [
      { marker_id: "one", start_tick: 30000, title: "Opening", },
      { marker_id: "two", start_tick: 90030, title: "Next <scene>", },
    ],
  }
}

///|
test "screening joins exact media duration overlapping captions and chapter clock" {
  let plan = @screening.plan(
    media(),
    "Review",
    captions=captions(),
    chapters=chapters(),
  )
  assert_eq(plan.duration_ms, 6000)
  assert_eq(plan.cues.length(), 3)
  assert_eq(plan.cues[0].text, "Café &amp; 🌱\nLine two")
  assert_eq(plan.chapters.map(c => c.start_ms), [1000, 3001])
  assert_eq(plan.chapters[0].title, "Opening")
}

///|
test "chapter conversion floors only browser positions and preserves opening gap" {
  let draft = {
    ..chapters(),
    markers: [{ marker_id: "fraction", start_tick: 1001, title: "Fractional", }],
  }
  let plan = @screening.plan(media(), "Review", chapters=draft)
  assert_eq(plan.chapters[0].start_ms, 33)
  assert_eq(plan.chapters.length(), 1)
}

///|
test "empty optional drafts produce an honest media-only player" {
  let plan = @screening.plan(media(), "Silent captions absent")
  assert_true(plan.cues.is_empty())
  assert_true(plan.chapters.is_empty())
  let html = plan.html("video.mp4", "hash")
  assert_true(html.contains("No caption draft supplied"))
  assert_true(html.contains("No chapter draft supplied"))
  assert_true(!html.contains("href=\"captions.vtt\""))
  assert_true(!html.contains("href=\"chapters.vtt\""))
}

///|
test "refuse unmatched durations and out of range caption end despite duration tolerance" {
  assert_true(
    (try? @screening.plan(media(), "Review", captions={
      ..captions(),
      duration_ms: 6100,
    }))
    is Err(_),
  )
  assert_true(
    (try? @screening.plan(media(), "Review", chapters={
      ..chapters(),
      duration_ticks: 200000,
    }))
    is Err(_),
  )
  let draft = {
    ..captions(),
    duration_ms: 6010,
    cues: [{ start_ms: 6000, end_ms: 6010, text: "Late", }],
  }
  assert_true(
    (try? @screening.plan(media(), "Review", captions=draft)) is Err(_),
  )
  let chapter = {
    ..chapters(),
    duration_ticks: 180030,
    markers: [{ marker_id: "end", start_tick: 180000, title: "Too late", }],
  }
  assert_true(
    (try? @screening.plan(media(), "Review", chapters=chapter)) is Err(_),
  )
}

///|
test "browser profile refuses unsupported codecs containers multiple audio and embedded tracks" {
  assert_true(
    (try? @screening.plan({ ..media(), suffix: ".mkv", }, "Review")) is Err(_),
  )
  let tracks = media().tracks.copy()
  tracks[0] = { ..tracks[0], codec: "hevc", }
  assert_true(
    (try? @screening.plan({ ..media(), tracks, }, "Review")) is Err(_),
  )
  let two_audio = media().tracks.copy()
  two_audio.push({ ..two_audio[1], index: 2, })
  assert_true(
    (try? @screening.plan({ ..media(), tracks: two_audio, }, "Review"))
    is Err(_),
  )
  let embedded = media().tracks.copy()
  embedded.push({
    ..embedded[1],
    index: 2,
    kind: "subtitle",
    codec: "mov_text",
  })
  assert_true(
    (try? @screening.plan({ ..media(), tracks: embedded, }, "Review")) is Err(_),
  )
  assert_true(
    (try? @screening.plan(
      { ..media(), tracks: [media().tracks[0]], },
      "Silent video",
    ))
    is Ok(_),
  )
}

///|
test "HTML escapes data and contains portable native keyboard controls" {
  let plan = @screening.plan(
    media(),
    "</script><script>alert('x')</script>",
    captions=captions(),
    chapters=chapters(),
  )
  let html = plan.html("<source & café>.mp4", "hash")
  assert_true(html.contains("&lt;source &amp; café&gt;.mp4"))
  assert_true(html.contains("Next &lt;scene&gt;"))
  assert_true(html.contains("\\u003c/script\\u003e"))
  assert_true(!html.contains("<script>alert('x')</script>"))
  assert_true(html.contains("data-seek-ms=\"3001\""))
  assert_true(html.contains("aria-label=\"Screening video\""))
  assert_true(html.contains("<label for=\"search\">"))
  assert_true(html.contains("<noscript>"))
  assert_true(!html.contains("fetch("))
  assert_true(!html.contains("autoplay"))
}

///|
test "plan rejects malformed title and preserves source drafts" {
  assert_true((try? @screening.plan(media(), "  ")) is Err(_))
  assert_true((try? @screening.plan(media(), "new\nline")) is Err(_))
  assert_true((try? @screening.plan(media(), "x".repeat(201))) is Err(_))
  let draft = captions()
  let plan = @screening.plan(media(), "Review", captions=draft)
  plan.cues.clear()
  assert_eq(draft.cues.length(), 3)
}
