///|
fn replacement_probe() -> Json {
  {
    "format": {
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "start_time": "0",
      "duration": "6",
    },
    "chapters": [
      {
        "start_time": "0",
        "end_time": "6",
        "tags": { "title": "Opening 开场" },
      },
    ],
    "streams": [
      {
        "index": 0,
        "codec_type": "video",
        "codec_name": "h264",
        "disposition": { "attached_pic": 0, "default": 1 },
      },
      {
        "index": 2,
        "codec_type": "audio",
        "codec_name": "aac",
        "tags": { "language": "fra", "title": "French" },
        "disposition": { "default": 1 },
      },
      {
        "index": 5,
        "codec_type": "subtitle",
        "codec_name": "mov_text",
        "tags": { "language": "eng", "handler_name": "English CC" },
        "disposition": { "default": 1, "forced": 1, "hearing_impaired": 1 },
      },
      {
        "index": 6,
        "codec_type": "subtitle",
        "codec_name": "mov_text",
        "tags": { "language": "zho", "handler_name": "中文" },
        "disposition": { "default": 0 },
      },
    ],
  }
}

///|
fn replacement_draft() -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: "corrected.json",
    duration_ms: 6000,
    cues: [
      { start_ms: 501, end_ms: 2551, text: "Café 🌱\nCorrected line.", },
    ],
  }
}

///|
test "replacement targets absolute source index but maps original output position" {
  let plan = @caption_media.prepare_replacement(
    replacement_probe(),
    replacement_draft(),
    5,
  )
  assert_eq(plan.output_position, 2)
  assert_eq(plan.selected.language, "eng")
  assert_eq(plan.stream_dispositions[2], [
    "default", "forced", "hearing_impaired",
  ])
  let selected = @caption_media.verify_replacement(plan, replacement_probe())
  assert_eq(selected.index, 5)
}

///|
test "replacement does not require an extra stream slot" {
  let probe = replacement_probe()
  guard! probe is { "streams": Array(streams), .. }
  for i = 7; i < 20; i = i + 1 {
    streams.push({
      "index": i,
      "codec_type": "subtitle",
      "codec_name": "mov_text",
      "disposition": { "default": 0 },
    })
  }
  let plan = @caption_media.prepare_replacement(probe, replacement_draft(), 5)
  assert_eq(plan.media.tracks.length(), 17)
  assert_true(
    replacement_rejected(() => {
      ignore(
        @caption_media.validate_attachment(
          plan.media,
          replacement_draft(),
          "eng",
          "English",
        ),
      )
    }),
  )
}

///|
test "replacement rejects wrong indices image subtitles mismatched timing and overlap" {
  for index in [0, 2, 99] {
    assert_true(
      replacement_rejected(() => {
        ignore(
          @caption_media.prepare_replacement(
            replacement_probe(),
            replacement_draft(),
            index,
          ),
        )
      }),
    )
  }
  assert_true(
    replacement_rejected(() => {
      ignore(
        @caption_media.prepare_replacement(
          replacement_probe(),
          { ..replacement_draft(), duration_ms: 7000, },
          5,
        ),
      )
    }),
  )
  let overlap = {
    ..replacement_draft(),
    cues: [
      { start_ms: 0, end_ms: 2000, text: "One", },
      { start_ms: 1000, end_ms: 3000, text: "Two", },
    ],
  }
  assert_true(
    replacement_rejected(() => {
      ignore(
        @caption_media.prepare_replacement(replacement_probe(), overlap, 5),
      )
    }),
  )
  let probe = replacement_probe()
  guard! probe is { "streams": Array(streams), .. }
  guard! streams[2] is Object(fields)
  fields["codec_name"] = "hdmv_pgs_subtitle"
  assert_true(
    replacement_rejected(() => {
      ignore(@caption_media.prepare_replacement(probe, replacement_draft(), 5))
    }),
  )
}

///|
test "replacement verification rejects lost flags labels extra tracks and changed chapters" {
  let plan = @caption_media.prepare_replacement(
    replacement_probe(),
    replacement_draft(),
    5,
  )
  for property in ["disposition", "tags", "codec_name"] {
    let changed = replacement_probe()
    guard! changed is { "streams": Array(streams), .. }
    guard! streams[2] is Object(fields)
    fields[property] = match property {
      "disposition" => { "default": 1, "forced": 1 }
      "tags" => { "language": "fra", "handler_name": "French" }
      _ => "subrip"
    }
    assert_true(
      replacement_rejected(() => {
        ignore(@caption_media.verify_replacement(plan, changed))
      }),
    )
  }
  let extra = replacement_probe()
  guard! extra is { "streams": Array(streams), .. }
  streams.push({
    "index": 7,
    "codec_type": "subtitle",
    "codec_name": "mov_text",
    "disposition": {},
  })
  assert_true(
    replacement_rejected(() => {
      ignore(@caption_media.verify_replacement(plan, extra))
    }),
  )
  let chapter = replacement_probe()
  guard! chapter is { "chapters": Array(chapters), .. }
  chapters[0] = {
    "start_time": "0",
    "end_time": "5",
    "tags": { "title": "Changed" },
  }
  assert_true(
    replacement_rejected(() => {
      ignore(@caption_media.verify_replacement(plan, chapter))
    }),
  )
}

///|
test "replacement retains ordinal mapping after output stream renumbering" {
  let plan = @caption_media.prepare_replacement(
    replacement_probe(),
    replacement_draft(),
    6,
  )
  let output = replacement_probe()
  guard! output is { "streams": Array(streams), .. }
  for i, stream in streams {
    guard! stream is Object(fields)
    fields["index"] = i.to_json()
  }
  assert_eq(@caption_media.verify_replacement(plan, output).index, 3)
  assert_eq(plan.selected.index, 6)
}

///|
test "replacement validates complete disposition evidence" {
  for value in [Json::number(2), Json::string("yes")] {
    let probe = replacement_probe()
    guard! probe is { "streams": Array(streams), .. }
    guard! streams[2] is { "disposition": Object(flags), .. }
    flags["forced"] = value
    assert_true(
      replacement_rejected(() => {
        ignore(
          @caption_media.prepare_replacement(probe, replacement_draft(), 5),
        )
      }),
    )
  }
}

///|
fn replacement_rejected(action : () -> Unit raise) -> Bool {
  try {
    action()
    false
  } catch {
    _ => true
  }
}
