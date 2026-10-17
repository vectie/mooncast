///|
fn roll_fixture() -> Timeline raise {
  @json.from_json({
    "timeline_id": "cut",
    "revision": 7,
    "timebase": { "ticks_per_second": 1000 },
    "output": { "fps": { "numerator": 25, "denominator": 1 } },
    "transitions": [],
    "tracks": [
      {
        "track_id": "v1",
        "kind": "video",
        "clips": [
          {
            "clip_id": "a",
            "media_ref_id": "media.a",
            "start_tick": 0,
            "duration_ticks": 2000,
            "source_in_tick": 1000,
            "source_out_tick": 3000,
            "identity": {
              "project_id": "p",
              "episode_id": "e",
              "scene_id": "s",
              "shot_id": "a",
              "asset_id": "a",
            },
            "intent": { "intent_ref": "intent" },
          },
          {
            "clip_id": "b",
            "media_ref_id": "media.b",
            "start_tick": 2000,
            "duration_ticks": 2000,
            "source_in_tick": 1000,
            "source_out_tick": 3000,
            "identity": {
              "project_id": "p",
              "episode_id": "e",
              "scene_id": "s",
              "shot_id": "b",
              "asset_id": "b",
            },
            "intent": { "intent_ref": "intent" },
          },
          {
            "clip_id": "c",
            "media_ref_id": "media.c",
            "start_tick": 4000,
            "duration_ticks": 2000,
            "source_in_tick": 0,
            "source_out_tick": 2000,
            "identity": {
              "project_id": "p",
              "episode_id": "e",
              "scene_id": "s",
              "shot_id": "c",
              "asset_id": "c",
            },
            "intent": { "intent_ref": "intent" },
          },
        ],
      },
    ],
  })
}

///|
test "rolling cut emits paired trims independent of selection order" {
  let timeline = roll_fixture()
  let plan = plan_roll_cut(
    timeline,
    ["b", "a"],
    { "media.a": 5000, "media.b": 5000 },
    40,
  ).unwrap()
  assert_eq(plan.boundary_tick, 2040)
  @json.inspect(plan.payload, content={
    "trims": [
      {
        "clip_id": "a",
        "source_in_tick": 1000,
        "source_out_tick": 3040,
        "start_tick": 0,
      },
      {
        "clip_id": "b",
        "source_in_tick": 1040,
        "source_out_tick": 3000,
        "start_tick": 2040,
      },
    ],
  })
  assert_eq(timeline.tracks[0].clips[0].source_out_tick, 3000)
  assert_eq(timeline.tracks[0].clips[2].start_tick, 4000)
  assert_eq(
    plan_roll_cut(
      timeline,
      ["a", "b"],
      { "media.a": 5000, "media.b": 5000 },
      -40,
    ).unwrap().boundary_tick,
    1960,
  )
}

///|
test "rolling cut rejects missing handles invalid selections gaps and destructive bounds" {
  let timeline = roll_fixture()
  let durations : Map[String, Int] = { "media.a": 5000, "media.b": 5000 }
  for
    ids in [
      [],
      ["a"],
      ["a", "a"],
      ["a", "missing"],
      ["a", "c"],
      ["a", "b", "c"],
    ] {
    assert_true(plan_roll_cut(timeline, ids, durations, 40) is Err(_))
  }
  for delta in [0, -1001, -2000, 2000, 2147483647, -2147483648] {
    assert_true(plan_roll_cut(timeline, ["a", "b"], durations, delta) is Err(_))
  }
  assert_true(plan_roll_cut(timeline, ["a", "b"], {}, 40) is Err(_))
  assert_true(
    plan_roll_cut(
      timeline,
      ["a", "b"],
      { "media.a": 3000, "media.b": 5000 },
      40,
    )
    is Err(_),
  )
}

///|
test "rolling cut blocks transitions animated clips retiming and cross-track selection" {
  let timeline = roll_fixture()
  let track = timeline.tracks[0]
  let durations : Map[String, Int] = { "media.a": 5000, "media.b": 5000 }
  for
    left in [
      { ..track.clips[0], duration_ticks: 1999, },
      { ..track.clips[0], keyframes: Some({ "opacity": [{ "tick": 0 }] }), },
      { ..track.clips[0], effects: Some([{ "kind": "speed" }]), },
      { ..track.clips[0], source_in_tick: -1, },
    ] {
    let changed = {
      ..timeline,
      tracks: [{ ..track, clips: [left, track.clips[1]], }],
    }
    assert_true(plan_roll_cut(changed, ["a", "b"], durations, 40) is Err(_))
  }
  let cross = {
    ..timeline,
    tracks: [
      { ..track, clips: [track.clips[0]], },
      { ..track, track_id: "v2", clips: [track.clips[1]], },
    ],
  }
  assert_true(plan_roll_cut(cross, ["a", "b"], durations, 40) is Err(_))
  let transition : TimelineTransition = @json.from_json({
    "transition_id": "t",
    "from_clip_id": "a",
    "to_clip_id": "b",
    "kind": "dissolve",
    "duration_ticks": 100,
  })
  assert_true(
    plan_roll_cut(
      { ..timeline, transitions: [transition], },
      ["a", "b"],
      durations,
      40,
    )
    is Err(_),
  )
}

///|
test "rolling frame step uses declared output rate and bounded tick quantization" {
  let timeline = roll_fixture()
  assert_eq(roll_frame_ticks(timeline).unwrap(), 40)
  assert_eq(roll_frame_ticks({ ..timeline, output: None, }).unwrap(), 42)
  assert_true(
    roll_frame_ticks({ ..timeline, timebase: { ticks_per_second: 0, }, })
    is Err(_),
  )
  let output = timeline.output.unwrap()
  assert_true(
    roll_frame_ticks({
      ..timeline,
      output: Some({ ..output, fps: Some({ numerator: 0, denominator: 1, }), }),
    })
    is Err(_),
  )
  assert_eq(
    roll_frame_ticks({
      ..timeline,
      output: Some({
        ..output,
        fps: Some({ numerator: 30000, denominator: 1001, }),
      }),
    }).unwrap(),
    33,
  )
}
