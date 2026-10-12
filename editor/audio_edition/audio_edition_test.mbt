///|
fn draft() -> @chapters.Draft {
  {
    contract: "mooncast.chapter-draft.v1",
    project_id: "episode",
    project_revision: 7,
    timeline_id: "cut",
    timeline_revision: 3,
    ticks_per_second: 1000,
    duration_ticks: 5000,
    markers: [
      { marker_id: "intro", start_tick: 0, title: "Opening 标题", },
      { marker_id: "detail", start_tick: 1750, title: "A=B; #\\ detail", },
    ],
  }
}

///|
fn audio(index : Int, language : String, channels : Int) -> Json {
  {
    "index": index,
    "codec_type": "audio",
    "codec_name": "aac",
    "channels": channels,
    "sample_rate": "48000",
    "start_time": "0",
    "duration": "5",
    "tags": { "language": language, "title": "Dialogue" },
  }
}

///|
fn probe(streams : Array[Json]) -> Json {
  {
    "format": {
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "duration": "5",
      "start_time": "0",
    },
    "streams": streams,
    "chapters": [
      {
        "time_base": "1/1000",
        "start": 0,
        "end": 1750,
        "tags": { "title": "Opening 标题" },
      },
      {
        "time_base": "1/1000",
        "start": 1750,
        "end": 5000,
        "tags": { "title": "A=B; #\\ detail" },
      },
    ],
  }
}

///|
test "explicit audio index selects language channels and omitted stream list" {
  let source = @audio_edition.inspect_source(
    probe([
      { "index": 0, "codec_type": "video" },
      audio(1, "eng", 1),
      audio(2, "fra", 2),
    ]),
  )
  let plan = @audio_edition.prepare(draft(), source, 2)
  assert_eq(plan.track.language, "fra")
  assert_eq(plan.track.channels, 2)
  assert_eq(plan.omitted_stream_indices, [0, 1])
  assert_eq(plan.duration_ms, 5000)
  assert_eq(plan.target_bitrate, 160000)
  assert_true((try? @audio_edition.prepare(draft(), source, 0)) is Err(_))
  assert_true((try? @audio_edition.prepare(draft(), source, -1)) is Err(_))
}

///|
test "reject timing mismatch shifted audio surround and invalid language" {
  let source = @audio_edition.inspect_source(probe([audio(0, "eng", 2)]))
  let track = source.audio_tracks[0]
  for
    changed in [
      { ..track, channels: 6, },
      { ..track, language: "en-US", },
      { ..track, start_ms: 20.0, },
      { ..track, duration_ms: Some(499.0), },
    ] {
    assert_true(
      (try? @audio_edition.prepare(
        draft(),
        { ..source, audio_tracks: [changed], },
        0,
      ))
      is Err(_),
    )
  }
  assert_true(
    (try? @audio_edition.prepare(draft(), { ..source, duration_ms: 5100.0, }, 0))
    is Err(_),
  )
  assert_true(
    (try? @audio_edition.prepare(
      {
        ..draft(),
        markers: [{ marker_id: "a", start_tick: 1, title: "Gap", }],
      },
      source,
      0,
    ))
    is Err(_),
  )
  assert_true(
    (try? @audio_edition.prepare(
      { ..draft(), ticks_per_second: 3000, },
      source,
      0,
    ))
    is Err(_),
  )
}

///|
test "audio-only WAV FLAC inputs allow absent implicit zero start" {
  for name in ["wav", "flac"] {
    let input : Json = {
      "format": { "format_name": name, "duration": "5" },
      "streams": [
        {
          "index": 0,
          "codec_type": "audio",
          "codec_name": "pcm_s16le",
          "sample_rate": "44100",
          "channels": 1,
        },
      ],
    }
    let source = @audio_edition.inspect_source(input)
    let plan = @audio_edition.prepare(draft(), source, 0)
    assert_eq(plan.track.start_ms, 0.0)
    assert_eq(plan.track.language, "und")
    assert_eq(plan.omitted_stream_indices.length(), 0)
  }
}

///|
test "inspect refuses unsupported containers duplicate streams and missing audio" {
  assert_true((try? @audio_edition.inspect_source(probe([]))) is Err(_))
  assert_true(
    (try? @audio_edition.inspect_source(
      probe([audio(0, "eng", 1), audio(0, "eng", 1)]),
    ))
    is Err(_),
  )
  let input = probe([audio(0, "eng", 1)])
  guard input is Object(fields) else { fail("object") }
  let formats : Array[Json] = [
    { "format_name": "hls", "duration": "5", "start_time": "0" },
    {
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "duration": "NaN",
      "start_time": "0",
    },
    { "format_name": "wav", "duration": "5", "start_time": "1" },
  ]
  for format in formats {
    fields["format"] = format
    assert_true((try? @audio_edition.inspect_source(input)) is Err(_))
  }
}

///|
test "output verification accepts chapter navigation and rejects video or short audio" {
  let plan = @audio_edition.prepare(
    draft(),
    @audio_edition.inspect_source(probe([audio(2, "fra", 2)])),
    2,
  )
  let data : Json = {
    "index": 1,
    "codec_type": "data",
    "codec_name": "bin_data",
    "codec_tag_string": "text",
  }
  @audio_edition.verify_output(plan, draft(), probe([audio(0, "fra", 2), data]))
  for
    streams in [
      [audio(0, "fra", 2), { "index": 1, "codec_type": "video" }],
      [audio(0, "eng", 2)],
      [audio(0, "fra", 1)],
      [audio(0, "fra", 2), audio(1, "fra", 2)],
    ] {
    assert_true(
      (try? @audio_edition.verify_output(plan, draft(), probe(streams)))
      is Err(_),
    )
  }
  let short = audio(0, "fra", 2)
  guard short is Object(fields) else { fail("object") }
  fields["duration"] = "1.0"
  assert_true(
    (try? @audio_edition.verify_output(plan, draft(), probe([short]))) is Err(_),
  )
}

///|
test "output verification checks exact chapter titles boundaries and coverage" {
  let plan = @audio_edition.prepare(
    draft(),
    @audio_edition.inspect_source(probe([audio(0, "eng", 1)])),
    0,
  )
  let input = probe([audio(0, "eng", 1)])
  guard input is Object(fields) && fields["chapters"] is Array(chapters) else {
    fail("object")
  }
  chapters[1] = {
    "time_base": "1/1000",
    "start": 1751,
    "end": 5000,
    "tags": { "title": "Wrong" },
  }
  assert_true(
    (try? @audio_edition.verify_output(plan, draft(), input)) is Err(_),
  )
}
