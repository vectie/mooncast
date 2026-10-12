///|
fn draft() -> @chapters.Draft {
  {
    contract: "mooncast.chapter-draft.v1",
    project_id: "p",
    project_revision: 9,
    timeline_id: "t",
    timeline_revision: 4,
    ticks_per_second: 1000,
    duration_ticks: 6000,
    markers: [
      { marker_id: "one", start_tick: 0, title: "Opening & <标题>", },
      { marker_id: "two", start_tick: 2250, title: "A=B; #\\ cats", },
    ],
  }
}

///|
fn probe(chapters : Array[Json]) -> Json {
  {
    "format": {
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "duration": "6.0",
      "start_time": "0.0",
    },
    "streams": [
      {
        "index": 0,
        "codec_type": "video",
        "codec_name": "h264",
        "disposition": { "attached_pic": 0 },
      },
      {
        "index": 1,
        "codec_type": "audio",
        "codec_name": "aac",
        "tags": { "language": "eng" },
      },
      {
        "index": 2,
        "codec_type": "audio",
        "codec_name": "aac",
        "tags": { "language": "fra" },
      },
      {
        "index": 3,
        "codec_type": "subtitle",
        "codec_name": "mov_text",
        "tags": { "language": "zho" },
      },
    ],
    "chapters": chapters,
  }
}

///|
fn chapters() -> Array[Json] {
  [
    {
      "time_base": "1/1000000000",
      "start": 0,
      "end": 2250000000.0,
      "tags": { "title": "Opening & <标题>" },
    },
    {
      "time_base": "1/1000000000",
      "start": 2250000000.0,
      "end": 6000000000.0,
      "tags": { "title": "A=B; #\\ cats" },
    },
  ]
}

///|
test "embed plan copies every audio subtitle and video track in order" {
  let plan = @chapter_media.prepare(draft(), probe([]))
  assert_eq(plan.stream_indices, [0, 1, 2, 3])
  assert_eq(plan.stream_signatures, [
    "video:h264:und", "audio:aac:eng", "audio:aac:fra", "subtitle:mov_text:zho",
  ])
  assert_eq(plan.replaced_chapters, 0)
  let args = @chapter_media.remux_arguments(
    plan, "/tmp/source with spaces.mp4", "/tmp/chapters.ffmetadata", "/tmp/output.mp4",
  )
  assert_true(args.contains("copy"))
  assert_true(args.contains("-n"))
  assert_true(args.contains("0:3"))
  assert_true(args.contains("/tmp/source with spaces.mp4"))
}

///|
test "extract exact nanosecond chapters into an editable native draft" {
  let original = draft()
  let result = @chapter_media.extract(original, probe(chapters()))
  assert_eq(result.project_revision, 9)
  assert_eq(result.timeline_revision, 4)
  assert_eq(result.markers[1].start_tick, 2250)
  assert_eq(result.markers[1].title, original.markers[1].title)
  assert_eq(result.markers[0].marker_id, "imported.1")
  let edited = result.put({
    marker_id: "imported.2",
    start_tick: 3000,
    title: "Revised",
  })
  assert_eq(edited.markers[1].start_tick, 3000)
  assert_eq(original.markers[1].start_tick, 2250)
  @chapter_media.verify_output(
    @chapter_media.prepare(original, probe([])),
    original,
    probe(chapters()),
  )
}

///|
test "reject chapter rounding and excessive draft duration" {
  let frame = {
    ..draft(),
    ticks_per_second: 24,
    duration_ticks: 144,
    markers: [{ marker_id: "a", start_tick: 1, title: "Unrepresentable", }],
  }
  assert_true((try? @chapter_media.validate_draft(frame)) is Err(_))
  assert_true(
    (try? @chapter_media.validate_draft({ ..draft(), duration_ticks: 7200001, }))
    is Err(_),
  )
}

///|
test "media mismatch and unsupported source streams fail before embedding" {
  let input = probe([])
  guard input is Object(fields) else { fail("object") }
  fields["format"] = {
    "format_name": "matroska,webm",
    "duration": "7",
    "start_time": "0",
  }
  assert_true((try? @chapter_media.prepare(draft(), input)) is Err(_))
  fields["format"] = {
    "format_name": "matroska,webm",
    "duration": "6",
    "start_time": "0.2",
  }
  assert_true((try? @chapter_media.prepare(draft(), input)) is Err(_))
  fields["format"] = {
    "format_name": "hls",
    "duration": "6",
    "start_time": "0",
  }
  assert_true((try? @chapter_media.prepare(draft(), input)) is Err(_))
  fields["format"] = {
    "format_name": "matroska,webm",
    "duration": "6",
    "start_time": "0",
  }
  guard fields["streams"] is Array(streams) else { fail("array") }
  streams.push({ "index": 4, "codec_type": "attachment", "codec_name": "ttf" })
  assert_true((try? @chapter_media.prepare(draft(), input)) is Err(_))
}

///|
test "known MP4 chapter data is replaced while arbitrary data is refused" {
  let input = probe(chapters())
  guard input is Object(fields) && fields["streams"] is Array(streams) else {
    fail("object")
  }
  streams.push({
    "index": 4,
    "codec_type": "data",
    "codec_name": "bin_data",
    "codec_tag_string": "text",
  })
  let plan = @chapter_media.prepare(draft(), input)
  assert_eq(plan.replaced_chapter_data_streams, 1)
  assert_eq(plan.stream_indices.length(), 4)
  streams.push({
    "index": 5,
    "codec_type": "data",
    "codec_name": "bin_data",
    "codec_tag_string": "gps ",
  })
  assert_true((try? @chapter_media.prepare(draft(), input)) is Err(_))
}

///|
test "extraction rejects empty chapters gaps missing titles and partial coverage" {
  assert_true((try? @chapter_media.extract(draft(), probe([]))) is Err(_))
  let cases : Array[Array[Json]] = [
    [{ "time_base": "1/1000", "start": 0, "end": 6000, "tags": {} }],
    [
      {
        "time_base": "1/1000",
        "start": 0,
        "end": 5999,
        "tags": { "title": "A" },
      },
    ],
    [
      {
        "time_base": "1/1000",
        "start": 0,
        "end": 1000,
        "tags": { "title": "A" },
      },
      {
        "time_base": "1/1000",
        "start": 1001,
        "end": 6000,
        "tags": { "title": "B" },
      },
    ],
  ]
  for entries in cases {
    assert_true(
      (try? @chapter_media.extract(draft(), probe(entries))) is Err(_),
    )
  }
}

///|
test "post remux verification catches dropped streams and chapter title changes" {
  let source = @chapter_media.prepare(draft(), probe([]))
  let output = probe(chapters())
  guard output is Object(fields) && fields["streams"] is Array(streams) else {
    fail("object")
  }
  ignore(streams.pop())
  assert_true(
    (try? @chapter_media.verify_output(source, draft(), output)) is Err(_),
  )
  let wrong = chapters()
  wrong[1] = {
    "time_base": "1/1000",
    "start": 2250,
    "end": 6000,
    "tags": { "title": "wrong" },
  }
  assert_true(
    (try? @chapter_media.verify_output(source, draft(), probe(wrong))) is Err(_),
  )
}
