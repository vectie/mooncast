///|
fn slide_fixture() -> Timeline raise {
  let timeline = roll_fixture()
  let track = timeline.tracks[0]
  {
    ..timeline,
    tracks: [
      {
        ..track,
        clips: [
          { ..track.clips[0], clip_id: "template.a", },
          { ..track.clips[1], clip_id: "template.b", },
          {
            ..track.clips[2],
            clip_id: "tail",
            media_ref_id: "media.a",
            source_in_tick: 1000,
            source_out_tick: 3000,
          },
        ],
      },
    ],
  }
}

///|
fn slide_handles() -> Map[String, Int] {
  { "media.a": 10000, "media.b": 10000 }
}

///|
test "slide plans signed offsets and three trims without changing source input" {
  let timeline = slide_fixture()
  let track = timeline.tracks[0]
  let original = track.clips.map(clip => clip.to_json()).to_json()
  for frames in [1, -1, 12, -12, -25, 49] {
    let plan = plan_slide_clip(
      timeline,
      ["template.b"],
      slide_handles(),
      frames,
    ).unwrap()
    let delta = frames * 40
    assert_eq(plan.delta_ticks, delta)
    assert_eq(plan.start_tick, 2000 + delta)
    assert_eq(plan.end_tick, 4000 + delta)
    @json.inspect(plan.payload, content={
      "trims": [
        {
          "clip_id": "template.a",
          "source_in_tick": 1000,
          "source_out_tick": 3000 + delta,
          "start_tick": 0,
        },
        {
          "clip_id": "template.b",
          "source_in_tick": 1000,
          "source_out_tick": 3000,
          "start_tick": 2000 + delta,
        },
        {
          "clip_id": "tail",
          "source_in_tick": 1000 + delta,
          "source_out_tick": 3000,
          "start_tick": 4000 + delta,
        },
      ],
    })
    assert_eq(track.clips.map(clip => clip.to_json()).to_json(), original)
  }
  let shuffled = {
    ..timeline,
    tracks: [
      { ..track, clips: [track.clips[2], track.clips[0], track.clips[1]], },
    ],
  }
  assert_eq(
    plan_slide_clip(shuffled, ["template.b"], slide_handles(), 1).unwrap().payload,
    plan_slide_clip(timeline, ["template.b"], slide_handles(), 1).unwrap().payload,
  )
  let audio = { ..timeline, tracks: [{ ..track, kind: "audio", }], }
  assert_eq(
    plan_slide_clip(audio, ["template.b"], slide_handles(), 1).unwrap().delta_ticks,
    40,
  )
  let output = timeline.output.unwrap()
  let ntsc = {
    ..timeline,
    output: Some({
      ..output,
      fps: Some({ numerator: 30000, denominator: 1001, }),
    }),
  }
  assert_eq(
    plan_slide_clip(ntsc, ["template.b"], slide_handles(), 3).unwrap().delta_ticks,
    99,
  )
}

///|
test "slide refuses missing selection handles destructive offsets and malformed timing" {
  let timeline = slide_fixture()
  let track = timeline.tracks[0]
  for
    ids in [
      [],
      ["missing"],
      ["template.a"],
      ["tail"],
      ["template.a", "template.b"],
      ["template.b", "template.b"],
    ] {
    assert_true(plan_slide_clip(timeline, ids, slide_handles(), 1) is Err(_))
  }
  for frames in [0, -26, -50, 50, 2147483647, -2147483648] {
    assert_true(
      plan_slide_clip(timeline, ["template.b"], slide_handles(), frames)
      is Err(_),
    )
  }
  for
    handles in [
      ({}, { "media.a": 10000 }),
      (
        { "media.a": 3000, "media.b": 10000 },
        { "media.a": 10000, "media.b": 0 },
      ),
    ] {
    assert_true(
      plan_slide_clip(timeline, ["template.b"], handles.0, 1) is Err(_),
    )
    assert_true(
      plan_slide_clip(timeline, ["template.b"], handles.1, 1) is Err(_),
    )
  }
  for
    right in [
      { ..track.clips[2], start_tick: 4001, },
      { ..track.clips[2], start_tick: 3999, },
      { ..track.clips[2], duration_ticks: 0, },
      { ..track.clips[2], source_in_tick: -1, },
      { ..track.clips[2], duration_ticks: 1999, },
      { ..track.clips[2], start_tick: 2147483647, },
    ] {
    assert_true(
      plan_slide_clip(
        {
          ..timeline,
          tracks: [{ ..track, clips: [track.clips[0], track.clips[1], right], }],
        },
        ["template.b"],
        slide_handles(),
        1,
      )
      is Err(_),
    )
  }
  assert_true(
    plan_slide_clip(
      { ..timeline, tracks: [{ ..track, kind: "subtitle", }], },
      ["template.b"],
      slide_handles(),
      1,
    )
    is Err(_),
  )
  assert_true(
    plan_slide_clip(
      { ..timeline, timebase: { ticks_per_second: 0, }, },
      ["template.b"],
      slide_handles(),
      1,
    )
    is Err(_),
  )
  assert_true(
    plan_slide_clip(
      {
        ..timeline,
        output: Some({
          ..timeline.output.unwrap(),
          fps: Some({ numerator: 0, denominator: 1, }),
        }),
      },
      ["template.b"],
      slide_handles(),
      1,
    )
    is Err(_),
  )
}

///|
test "slide detects ambiguous neighbors overlaps and IDs across tracks" {
  let timeline = slide_fixture()
  let track = timeline.tracks[0]
  let blank = { ..track.clips[1], clip_id: " ", }
  assert_true(
    plan_slide_clip(
      {
        ..timeline,
        tracks: [{ ..track, clips: [track.clips[0], blank, track.clips[2]], }],
      },
      [" "],
      slide_handles(),
      1,
    )
    is Err(_),
  )
  let blank_media = { ..track.clips[1], media_ref_id: " ", }
  assert_true(
    plan_slide_clip(
      {
        ..timeline,
        tracks: [
          { ..track, clips: [track.clips[0], blank_media, track.clips[2]], },
        ],
      },
      ["template.b"],
      { "media.a": 10000, " ": 10000 },
      1,
    )
    is Err(_),
  )
  for
    extra in [
      track.clips[1],
      { ..track.clips[0], clip_id: "ambiguous-left", },
      { ..track.clips[2], clip_id: "ambiguous-right", },
      {
        ..track.clips[0],
        clip_id: "overlap",
        start_tick: 500,
        duration_ticks: 100,
        source_out_tick: 1100,
      },
    ] {
    let changed = {
      ..timeline,
      tracks: [{ ..track, clips: track.clips + [extra], }],
    }
    assert_true(
      plan_slide_clip(changed, ["template.b"], slide_handles(), 1) is Err(_),
    )
  }
  for duplicate in track.clips {
    let changed = {
      ..timeline,
      tracks: [track, { ..track, track_id: "v2", clips: [duplicate], }],
    }
    assert_true(
      plan_slide_clip(changed, ["template.b"], slide_handles(), 1) is Err(_),
    )
  }
  let unrelated = { ..track.clips[0], clip_id: "unrelated", }
  let changed = {
    ..timeline,
    tracks: [track, { ..track, track_id: "v2", clips: [unrelated], }],
  }
  assert_true(
    plan_slide_clip(changed, ["template.b"], slide_handles(), 1) is Ok(_),
  )
}

///|
test "slide refuses destructive features on any of the three affected clips" {
  let timeline = slide_fixture()
  let track = timeline.tracks[0]
  let settings : ClipSettings = @json.from_json({
    "effect": { "opacity": 1, "scale": 1, "x": 0, "y": 0 },
  })
  for index in 0..<3 {
    let clip = track.clips[index]
    for
      bad in [
        { ..clip, effects: Some([{ "kind": "speed" }]), },
        { ..clip, keyframes: Some({ "opacity": [{ "tick": 0 }] }), },
        { ..clip, effect_stack_digest: Some("unreconciled"), },
        { ..clip, settings: Some(settings), },
      ] {
      let clips = track.clips.copy()
      clips[index] = bad
      assert_true(
        plan_slide_clip(
          { ..timeline, tracks: [{ ..track, clips, }], },
          ["template.b"],
          slide_handles(),
          1,
        )
        is Err(_),
      )
    }
    let transition : TimelineTransition = @json.from_json({
      "transition_id": "t",
      "from_clip_id": clip.clip_id,
      "to_clip_id": "outside",
      "kind": "dissolve",
      "duration_ticks": 100,
    })
    assert_true(
      plan_slide_clip(
        { ..timeline, transitions: [transition], },
        ["template.b"],
        slide_handles(),
        1,
      )
      is Err(_),
    )
  }
  let defaults : ClipSettings = @json.from_json({
    "fit": "contain",
    "opacity": 1,
    "volume_db": 0,
  })
  let ordinary = {
    ..timeline,
    tracks: [
      {
        ..track,
        clips: track.clips.map(clip => {
          ..clip,
          settings: Some(defaults),
          keyframes: Some({}),
          effects: Some([]),
          effect_stack_digest: Some(""),
        }),
      },
    ],
  }
  assert_true(
    plan_slide_clip(ordinary, ["template.b"], slide_handles(), 1) is Ok(_),
  )
}
