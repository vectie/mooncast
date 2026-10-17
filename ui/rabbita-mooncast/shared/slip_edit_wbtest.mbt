///|
test "slip preserves timeline interval and uses signed frame offsets" {
  let timeline = roll_fixture()
  let limits : Map[String, Int] = { "media.a": 5000 }
  @json.inspect(plan_slip_clip(timeline, ["a"], limits, 2).unwrap(), content={
    "clip_id": "a", "source_in_tick": 1080, "source_out_tick": 3080, "start_tick": 0,
  })
  @json.inspect(plan_slip_clip(timeline, ["a"], limits, -25).unwrap(), content={
    "clip_id": "a", "source_in_tick": 0, "source_out_tick": 2000, "start_tick": 0,
  })
  @json.inspect(plan_slip_clip(timeline, ["a"], limits, 50).unwrap(), content={
    "clip_id": "a", "source_in_tick": 3000, "source_out_tick": 5000, "start_tick": 0,
  })
  assert_eq(timeline.tracks[0].clips[0].source_in_tick, 1000)
  assert_eq(timeline.tracks[0].clips[1].start_tick, 2000)
  for frames in [0, -26, 51, 2147483647, -2147483648] {
    assert_true(plan_slip_clip(timeline, ["a"], limits, frames) is Err(_))
  }
}

///|
test "slip rejects unknown metadata and unsupported selections and content" {
  let timeline = roll_fixture()
  let track = timeline.tracks[0]
  let limits : Map[String, Int] = { "media.a": 5000 }
  for ids in [[], ["missing"], ["a", "b"], ["a", "a"]] {
    assert_true(plan_slip_clip(timeline, ids, limits, 1) is Err(_))
  }
  for durations in [{}, { "media.a": 0 }, { "media.a": 2999 }] {
    assert_true(plan_slip_clip(timeline, ["a"], durations, 1) is Err(_))
  }
  for clip in [
    { ..track.clips[0], effect_stack_digest: Some("unreconciled"), },
    { ..track.clips[0], duration_ticks: 1999, },
    { ..track.clips[0], start_tick: 2147483647, },
    { ..track.clips[0], source_in_tick: -1, },
    { ..track.clips[0], keyframes: Some({ "opacity": [{ "tick": 0 }] }), },
    { ..track.clips[0], keyframes: Some("invalid"), },
    { ..track.clips[0], effects: Some([{ "kind": "speed" }]), },
  ] {
    assert_true(plan_slip_clip({ ..timeline, tracks: [{ ..track, clips: [clip], }], }, ["a"], limits, 1) is Err(_))
  }
  let legacy_settings : Array[Json] = [
    { "transition": { "name": "fade", "duration_ticks": 40 } },
    { "effect": { "opacity": 1.0, "scale": 1.0, "x": 0.0, "y": 0.0 } },
    { "overlay": { "text": "title", "font_size": 20, "color": "white", "background": "black", "position": "bottom" } },
    { "color": { "brightness": 0.0, "contrast": 1.0, "saturation": 1.0, "gamma": 1.0 } },
  ]
  for settings_json in legacy_settings {
    let settings : ClipSettings = @json.from_json(settings_json)
    let changed = { ..track.clips[0], settings: Some(settings), }
    assert_true(plan_slip_clip({ ..timeline, tracks: [{ ..track, clips: [changed], }], }, ["a"], limits, 1) is Err(_))
  }
  let canonical_settings : ClipSettings = @json.from_json({ "fit": "contain", "opacity": 1.0, "scale": 1.0 })
  assert_true(plan_slip_clip({ ..timeline, tracks: [{ ..track, clips: [{ ..track.clips[0], settings: Some(canonical_settings), }], }], }, ["a"], limits, 1) is Ok(_))
  assert_true(plan_slip_clip({ ..timeline, tracks: [{ ..track, kind: "caption", }], }, ["a"], limits, 1) is Err(_))
  assert_true(plan_slip_clip({ ..timeline, tracks: [track, track], }, ["a"], limits, 1) is Err(_))
  let transition : TimelineTransition = @json.from_json({
    "transition_id": "t", "from_clip_id": "a", "to_clip_id": "b", "kind": "dissolve", "duration_ticks": 100,
  })
  assert_true(plan_slip_clip({ ..timeline, transitions: [transition], }, ["a"], limits, 1) is Err(_))
  assert_true(plan_slip_clip({ ..timeline, timebase: { ticks_per_second: 0, }, }, ["a"], limits, 1) is Err(_))
  let output = timeline.output.unwrap()
  @json.inspect(plan_slip_clip({ ..timeline, output: Some({ ..output, fps: Some({ numerator: 30000, denominator: 1001, }), }), }, ["a"], limits, 1).unwrap(), content={
    "clip_id": "a", "source_in_tick": 1033, "source_out_tick": 3033, "start_tick": 0,
  })
}
