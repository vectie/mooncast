///|
fn hash() -> String {
  "ab".repeat(32)
}

///|
fn probe() -> Json {
  {
    "streams": [
      {
        "index": 0,
        "codec_type": "video",
        "codec_name": "h264",
        "width": 640,
        "height": 360,
        "start_time": "0.000000",
        "disposition": { "attached_pic": 0 },
      },
    ],
    "chapters": [],
    "format": {
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "duration": "8.000000",
      "start_time": "0",
    },
  }
}

///|
test "actual metadata clock uses integer PTS including equal rounded millisecond frames" {
  let rows = @scene_index.parse_detections(
    "frame:0    pts:2001 pts_time:2.001\nlavfi.scd.score=85.547\nframe:1    pts:2001 pts_time:2.001\nlavfi.scd.score=12.000\nframe:2    pts:6000 pts_time:6\nlavfi.scd.score=44.5\n",
    8000,
  )
  assert_eq(rows.map(r => r.start_ms), [2001, 2001, 6000])
  assert_eq(rows[0].score, 85.547)
  let result = @scene_index.index(hash(), 8000, 10, 500, rows)
  assert_eq(result.scenes.map(s => s.start_ms), [0, 2001, 6000])
  assert_true(!result.candidates[1].included)
}

///|
test "select earliest boundaries retain every short interval explanation and final range" {
  let result = @scene_index.index(hash(), 8000, 10, 1000, [
    { start_ms: 300, score: 90.0, },
    { start_ms: 1000, score: 20.0, },
    { start_ms: 1200, score: 99.0, },
    { start_ms: 2500, score: 10.0, },
    { start_ms: 7500, score: 70.0, },
  ])
  assert_eq(result.scenes.map(s => s.start_ms), [0, 1000, 2500])
  assert_eq(result.scenes.map(s => s.end_ms), [1000, 2500, 8000])
  assert_eq(result.candidates.map(c => c.included), [
    false, true, false, true, false,
  ])
  assert_eq(result.candidates[4].reason, "minimum final scene length")
  assert_eq(result.candidates[2].score, 99.0)
}

///|
test "static and shorter than minimum input yields one honest opening scene" {
  let rows = @scene_index.parse_detections("", 250)
  let result = @scene_index.index(hash(), 250, 100, 1000, rows)
  assert_eq(result.scenes.length(), 1)
  assert_eq(result.scenes[0].start_ms, 0)
  assert_eq(result.scenes[0].end_ms, 250)
  assert_true(result.candidates.is_empty())
  assert_true(
    result.chapters.webvtt().contains("00:00:00.000 --> 00:00:00.250"),
  )
}

///|
test "editable chapter draft round trips into screening and exported sidecars" {
  let result = @scene_index.index(hash(), 8000, 10, 1000, [
    { start_ms: 2000, score: 50.0, },
  ])
  let reopened = @chapters.read_draft(result.chapters.to_json().stringify())
  let edited = reopened.put({
    marker_id: "scene-2",
    start_tick: 2200,
    title: "Café & seedlings",
  })
  assert_eq(result.chapters.markers[1].start_tick, 2000)
  assert_true(edited.ffmetadata().contains("START=2200"))
  assert_true(edited.webvtt().contains("Café &amp; seedlings"))
  let media : @media.Media = {
    suffix: ".mp4",
    duration_ms: 8000,
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
    ],
    chapters: [],
  }
  let plan = @screening.plan(media, "Scene review", chapters=edited)
  assert_eq(plan.chapters[1].start_ms, 2200)
  assert_eq(plan.chapters[1].title, "Café & seedlings")
}

///|
test "reject malformed incomplete unordered out of range and invalid score metadata" {
  for
    text in [
      "lavfi.scd.score=12\n", "frame:0 pts:1000 pts_time:1\n", "frame:0 pts:1000 pts_time:1\nframe:1 pts:2000 pts_time:2\n",
      "frame:0 pts:-1 pts_time:-0.001\nlavfi.scd.score=12\n", "frame:0 pts:8000 pts_time:8\nlavfi.scd.score=12\n",
      "frame:0 pts:1.5 pts_time:1.5\nlavfi.scd.score=12\n", "frame:0 pts:2 pts_time:0.002\nlavfi.scd.score=12\nframe:1 pts:1 pts_time:0.001\nlavfi.scd.score=15\n",
      "frame:0 pts:1000 pts_time:1\nlavfi.scd.score=101\n", "frame:0 pts:1000 pts_time:1\nlavfi.scd.score=NaN\n",
      "anything else\n",
    ] {
    assert_true((try? @scene_index.parse_detections(text, 8000)) is Err(_))
  }
}

///|
test "validate thresholds ranges binding and source profile" {
  assert_true((try? @scene_index.index("bad", 8000, 10, 500, [])) is Err(_))
  assert_true((try? @scene_index.index(hash(), 0, 10, 500, [])) is Err(_))
  assert_true((try? @scene_index.index(hash(), 1800001, 10, 500, [])) is Err(_))
  assert_true((try? @scene_index.index(hash(), 8000, 0, 500, [])) is Err(_))
  assert_true((try? @scene_index.index(hash(), 8000, 101, 500, [])) is Err(_))
  assert_true((try? @scene_index.index(hash(), 8000, 10, 99, [])) is Err(_))
  assert_true((try? @scene_index.index(hash(), 8000, 10, 60001, [])) is Err(_))
  assert_true(
    (try? @scene_index.index(hash(), 8000, 10, 500, [
      { start_ms: -1, score: 20.0, },
    ]))
    is Err(_),
  )
  assert_true(
    (try? @scene_index.index(hash(), 8000, 10, 500, [
      { start_ms: 2000, score: 9.0, },
    ]))
    is Err(_),
  )
  assert_eq(@scene_index.inspect_probe(probe()).duration_ms, 8000)
  assert_true((try? @scene_index.inspect_probe({})) is Err(_))
  let too_many = Array::makei(1000, i => @scene_index.Detection::{
    start_ms: (i + 1) * 100,
    score: 20.0,
  })
  assert_true(
    (try? @scene_index.index(hash(), 101000, 10, 100, too_many)) is Err(_),
  )
}

///|
test "analysis command is bounded exact stream argv no shell or audio changes" {
  let command = @scene_index.command("/tmp/café ; video.mp4", 2, 10)
  assert_eq(command.executable, "ffmpeg")
  assert_true(command.arguments.contains("/tmp/café ; video.mp4"))
  assert_true(command.arguments.contains("0:2"))
  assert_true(command.arguments.contains("file,pipe"))
  assert_true(command.arguments.contains("-an"))
  assert_true(command.arguments.contains("-fps_mode"))
  assert_true(command.arguments.any(a => a.contains("settb=expr=1/1000")))
  assert_eq(command.timeout_ms, 300000)
  assert_true(
    (try? @scene_index.command("https://example.org/video.mp4", 0, 10))
    is Err(_),
  )
}

///|
test "source probe rejects shifted oversized HDR and long media" {
  let text = probe().stringify()
  for
    (before, after) in [
      ("640", "5000"),
      ("8.000000", "1800.001"),
      ("0.000000", "1.000000"),
      ("\"width\":640", "\"color_transfer\":\"smpte2084\",\"width\":640"),
    ] {
    let changed = text.replace_all(old=before, new=after)
    assert_true(changed != text)
    assert_true(
      (try? @scene_index.inspect_probe(@json.parse(changed))) is Err(_),
    )
  }
}
