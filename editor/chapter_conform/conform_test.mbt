///|
fn project() -> @domain.EditorProject {
  let identity : @domain.ProductionIdentity = {
    project_id: "project.demo",
    episode_id: "episode.1",
    scene_id: "scene.1",
    shot_id: "shot.1",
    asset_id: "asset.a",
  }
  let intent : @domain.IntentRef = { intent_ref: "intent.demo", }
  let clip : @domain.Clip = {
    clip_id: "a",
    media_ref_id: "media.a",
    identity,
    intent,
    artifact_id: None,
    start_tick: 0,
    duration_ticks: 2000,
    source_in_tick: 500,
    source_out_tick: 2500,
    settings: @domain.default_clip_settings(),
    keyframes: @domain.empty_keyframes(),
    effects: [],
    effect_stack_digest: "",
    audio_bus_id: None,
  }
  let media : @domain.MediaRef = {
    contract: "mooncast.editor-media-ref.v1",
    media_ref_id: "media.a",
    locator: { kind: "pack-relative", uri: "synthetic-a.mp4", },
    metadata: {
      sha256: "synthetic",
      mime_type: "video/mp4",
      size_bytes: 1,
      duration_ticks: 10000,
    },
  }
  {
    contract: "mooncast.editor-project.v1",
    project_id: "project.demo",
    revision: 7,
    identity_graph: [identity],
    media_refs: [media, { ..media, media_ref_id: "media.b", }],
    artifacts: [],
    intent_refs: [intent],
    timeline: {
      contract: "mooncast.editor-timeline.v1",
      timeline_id: "timeline.cut",
      revision: 8,
      timebase: { ticks_per_second: 1000, },
      output: {
        preset: "horizontal-1080p",
        orientation: "horizontal",
        width: 1920,
        height: 1080,
        fps: { numerator: 24, denominator: 1, },
        background: "#000000",
      },
      tracks: [
        {
          track_id: "video",
          kind: "video",
          order: 0,
          mix: None,
          clips: [
            clip,
            {
              ..clip,
              clip_id: "b",
              media_ref_id: "media.b",
              start_tick: 2000,
              source_in_tick: 2000,
              source_out_tick: 4000,
            },
            { ..clip, clip_id: "a-repeat", start_tick: 4000, },
          ],
        },
      ],
      transitions: [],
      audio_buses: [],
      delivery_audio: {
        target_lufs: -14.0,
        true_peak_limit_dbtp: -1.0,
        limiter_enabled: false,
        delivery_audio_digest: "",
      },
    },
  }
}

///|
fn sources() -> Array[@chapter_conform.SourceChapters] {
  let a : @chapters.Draft = {
    contract: "mooncast.chapter-draft.v1",
    project_id: "source.a",
    project_revision: 2,
    timeline_id: "original.a",
    timeline_revision: 3,
    ticks_per_second: 1000,
    duration_ticks: 10000,
    markers: [
      { marker_id: "opening", start_tick: 0, title: "Opening 🌙", },
      { marker_id: "details", start_tick: 1000, title: "Details & <care>", },
      { marker_id: "ending", start_tick: 3000, title: "Ending", },
    ],
  }
  [
    { media_ref_id: "media.a", draft: a, },
    {
      media_ref_id: "media.b",
      draft: {
        ..a,
        project_id: "source.b",
        ticks_per_second: 24,
        duration_ticks: 240,
        markers: [
          { marker_id: "setup", start_tick: 0, title: "Set up", },
          { marker_id: "demo", start_tick: 60, title: "Demonstration", },
          { marker_id: "result", start_tick: 84, title: "Result", },
        ],
      },
    },
  ]
}

///|
fn with_clips(
  p : @domain.EditorProject,
  clips : Array[@domain.Clip],
) -> @domain.EditorProject {
  {
    ..p,
    timeline: { ..p.timeline, tracks: [{ ..p.timeline.tracks[0], clips, }], },
  }
}

///|
fn expect_error(work : () -> Unit raise) -> Unit raise {
  try work() catch {
    _ => ()
  } noraise {
    _ => fail("expected failure")
  }
}

///|
test "carry active titles at cuts through different clocks reordering and repetition" {
  let p = project()
  let before = p.to_json().stringify()
  let input = sources()
  let drafts_before = input.map(s => s.draft.to_json().stringify())
  let result = @chapter_conform.conform(p, input)
  assert_eq(result.draft.markers.map(m => m.start_tick), [
    0, 500, 2000, 2500, 3500, 4000, 4500,
  ])
  assert_eq(result.draft.markers.map(m => m.title), [
    "Opening 🌙", "Details & <care>", "Set up", "Demonstration", "Result", "Opening 🌙",
    "Details & <care>",
  ])
  assert_eq(result.origins.map(o => o.output_end_tick), [
    500, 2000, 2500, 3500, 4000, 4500, 6000,
  ])
  assert_eq(result.origins.map(o => o.clipped_at_start), [
    true, false, true, false, false, true, false,
  ])
  assert_eq(result.origins.map(o => o.clipped_at_end), [
    false, true, false, false, true, false, true,
  ])
  assert_eq(result.source_uses.map(u => u.output_marker_ids.length()), [
    2, 2, 0, 1, 1, 1,
  ])
  assert_eq(result.origins.map(o => o.clip_id), [
    "a", "a", "b", "b", "b", "a-repeat", "a-repeat",
  ])
  assert_eq(result.origins[2].source_ticks_per_second, 24)
  assert_eq(result.draft.duration_ticks, 6000)
  assert_eq(result.draft.project_revision, 7)
  assert_eq(result.draft.timeline_revision, 8)
  assert_eq(result.draft.project_id, "project.demo")
  assert_eq(result.draft.timeline_id, "timeline.cut")
  assert_true(
    @chapters.read_draft(result.draft.to_json().stringify()) == result.draft,
  )
  assert_true(result.draft.webvtt().contains("Details &amp; &lt;care&gt;"))
  assert_true(result.draft.ffmetadata().contains("START=4500\nEND=6000"))
  assert_eq(p.to_json().stringify(), before)
  assert_eq(input.map(s => s.draft.to_json().stringify()), drafts_before)
}

///|
test "array order does not affect timeline output and exact end excludes next chapter" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  let selected = with_clips(p, [
    { ..c, source_in_tick: 1000, source_out_tick: 3000, },
  ])
  let result = @chapter_conform.conform(selected, [sources()[0]])
  assert_eq(result.draft.markers.length(), 1)
  assert_eq(result.draft.markers[0].title, "Details & <care>")
  assert_eq(result.origins[0].clipped_at_start, false)
  assert_eq(result.origins[0].clipped_at_end, false)
  let clips = p.timeline.tracks[0].clips
  let reordered = with_clips(p, [clips[2], clips[0], clips[1]])
  assert_true(
    @chapter_conform.conform(reordered, sources()).draft ==
    @chapter_conform.conform(p, [sources()[1], sources()[0]]).draft,
  )
}

///|
test "adjacent repeated chapter remains two editable markers with distinct origins" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  let one = {
    ..c,
    source_in_tick: 1000,
    source_out_tick: 1500,
    duration_ticks: 500,
  }
  let result = @chapter_conform.conform(
    with_clips(p, [one, { ..one, clip_id: "repeat", start_tick: 500, }]),
    [sources()[0]],
  )
  assert_eq(result.draft.markers.map(m => m.marker_id), [
    "conformed.1", "conformed.2",
  ])
  assert_eq(result.source_uses[1].output_marker_ids, [
    "conformed.1", "conformed.2",
  ])
}

///|
test "inexact surviving boundary fails while inexact removed boundary is irrelevant" {
  let p = project()
  let a = sources()[0]
  let draft = {
    ..a.draft,
    ticks_per_second: 24,
    duration_ticks: 240,
    markers: [
      { marker_id: "a", start_tick: 0, title: "A", },
      { marker_id: "b", start_tick: 25, title: "B", },
    ],
  }
  let c = p.timeline.tracks[0].clips[0]
  expect_error(() => {
    @chapter_conform.conform(with_clips(p, [c]), [{ ..a, draft, }]) |> ignore
  })
  let later = { ..c, source_in_tick: 2000, source_out_tick: 4000, }
  let result = @chapter_conform.conform(with_clips(p, [later]), [
    { ..a, draft, },
  ])
  assert_eq(result.draft.markers[0].title, "B")
}

///|
test "nonzero first source chapter is allowed only after chapter coverage begins" {
  let p = project()
  let a = sources()[0]
  let draft = {
    ..a.draft,
    markers: [{ marker_id: "first", start_tick: 1000, title: "First", }],
  }
  let c = p.timeline.tracks[0].clips[0]
  expect_error(() => {
    @chapter_conform.conform(with_clips(p, [c]), [{ ..a, draft, }]) |> ignore
  })
  let later = { ..c, source_in_tick: 1500, source_out_tick: 3500, }
  assert_eq(
    @chapter_conform.conform(with_clips(p, [later]), [{ ..a, draft, }]).draft.markers[0].start_tick,
    0,
  )
}

///|
test "missing duplicate unused and ambiguous media bindings fail" {
  let p = project()
  let ss = sources()
  expect_error(() => @chapter_conform.conform(p, [ss[0]]) |> ignore)
  expect_error(() => {
    @chapter_conform.conform(p, [ss[0], ss[1], ss[0]]) |> ignore
  })
  expect_error(() => {
    @chapter_conform.conform(p, [
      ss[0],
      ss[1],
      { ..ss[0], media_ref_id: "unused", },
    ])
    |> ignore
  })
  expect_error(() => {
    @chapter_conform.conform(
      { ..p, media_refs: [p.media_refs[0], p.media_refs[0], p.media_refs[1]], },
      ss,
    )
    |> ignore
  })
  expect_error(() => {
    @chapter_conform.conform({ ..p, media_refs: [p.media_refs[0]], }, ss)
    |> ignore
  })
  expect_error(() => @chapter_conform.conform(p, []) |> ignore)
}

///|
test "duration binding and source range must match video metadata" {
  let p = project()
  let ss = sources()
  expect_error(() => {
    @chapter_conform.conform(p, [
      { ..ss[0], draft: { ..ss[0].draft, duration_ticks: 10001, }, },
      ss[1],
    ])
    |> ignore
  })
  let media = p.media_refs[0]
  expect_error(() => {
    @chapter_conform.conform(
      {
        ..p,
        media_refs: [
          { ..media, metadata: { ..media.metadata, mime_type: "audio/wav", }, },
          p.media_refs[1],
        ],
      },
      ss,
    )
    |> ignore
  })
  let c = p.timeline.tracks[0].clips[0]
  expect_error(() => {
    @chapter_conform.conform(
      with_clips(p, [{ ..c, source_in_tick: 9000, source_out_tick: 11000, }]),
      [ss[0]],
    )
    |> ignore
  })
}

///|
test "gaps overlaps leading gaps zero lengths duplicate IDs and retiming fail" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  for
    bad in [
      { ..c, start_tick: 1, },
      { ..c, duration_ticks: 0, },
      { ..c, source_in_tick: -1, source_out_tick: 1999, },
      { ..c, source_out_tick: 5000, },
    ] {
    expect_error(() => {
      @chapter_conform.conform(with_clips(p, [bad]), [sources()[0]]) |> ignore
    })
  }
  for start in [1999, 2001] {
    expect_error(() => {
      @chapter_conform.conform(
        with_clips(p, [c, { ..c, clip_id: "second", start_tick: start, }]),
        [sources()[0]],
      )
      |> ignore
    })
  }
  expect_error(() => {
    @chapter_conform.conform(with_clips(p, [c, { ..c, start_tick: 2000, }]), [
      sources()[0],
    ])
    |> ignore
  })
  let speed : @domain.Effect = {
    effect_id: "speed",
    kind: "speed-ramp",
    enabled: true,
    effect_digest: "",
    parameters: {
      crop: None,
      transform: None,
      opacity: None,
      blend_mode: None,
      mask: None,
      speed_points: [],
    },
  }
  expect_error(() => {
    @chapter_conform.conform(with_clips(p, [{ ..c, effects: [speed], }]), [
      sources()[0],
    ])
    |> ignore
  })
  assert_eq(
    @chapter_conform.conform(
      with_clips(p, [{ ..c, effects: [{ ..speed, enabled: false, }], }]),
      [sources()[0]],
    ).draft.markers.length(),
    2,
  )
}

///|
test "unsupported tracks contracts and clocks fail" {
  let p = project()
  let track = p.timeline.tracks[0]
  for tracks in [[], [track, track], [{ ..track, kind: "audio", }]] {
    expect_error(() => {
      @chapter_conform.conform(
        { ..p, timeline: { ..p.timeline, tracks, }, },
        sources(),
      )
      |> ignore
    })
  }
  expect_error(() => {
    @chapter_conform.conform({ ..p, contract: "other", }, sources()) |> ignore
  })
  expect_error(() => {
    @chapter_conform.conform(
      { ..p, timeline: { ..p.timeline, timebase: { ticks_per_second: 0, }, }, },
      sources(),
    )
    |> ignore
  })
}

///|
test "full 1000 marker output works and expanded output over limit fails" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  let a = sources()[0]
  let draft = {
    ..a.draft,
    markers: Array::makei(1000, i => {
      marker_id: "chapter." + i.to_string(),
      start_tick: i * 10,
      title: "Chapter",
    }),
  }
  let full = {
    ..c,
    source_in_tick: 0,
    source_out_tick: 10000,
    duration_ticks: 10000,
  }
  let result = @chapter_conform.conform(with_clips(p, [full]), [{ ..a, draft, }])
  assert_eq(result.draft.markers.length(), 1000)
  expect_error(() => {
    @chapter_conform.conform(
      with_clips(p, [full, { ..c, clip_id: "repeat", start_tick: 10000, }]),
      [{ ..a, draft, }],
    )
    |> ignore
  })
}

///|
test "two hour and signed tick bounds are checked before narrowing arithmetic" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  let media = p.media_refs[0]
  let a = sources()[0]
  for duration in [7200001, 2147483647] {
    let selected = {
      ..with_clips(p, [
        {
          ..c,
          source_in_tick: 0,
          source_out_tick: duration,
          duration_ticks: duration,
        },
      ]),
      media_refs: [
        { ..media, metadata: { ..media.metadata, duration_ticks: duration, }, },
      ],
    }
    let draft = { ..a.draft, duration_ticks: duration, }
    expect_error(() => {
      @chapter_conform.conform(selected, [{ ..a, draft, }]) |> ignore
    })
  }
  // Products near Int32 squared fit Int64 and preserve exact equal clocks.
  let selected = {
    ..with_clips(p, [
      {
        ..c,
        source_in_tick: 0,
        source_out_tick: 2147483647,
        duration_ticks: 2147483647,
      },
    ]),
    timeline: {
      ..p.timeline,
      timebase: { ticks_per_second: 2147483647, },
      tracks: [
        {
          ..p.timeline.tracks[0],
          clips: [
            {
              ..c,
              source_in_tick: 0,
              source_out_tick: 2147483647,
              duration_ticks: 2147483647,
            },
          ],
        },
      ],
    },
    media_refs: [
      { ..media, metadata: { ..media.metadata, duration_ticks: 2147483647, }, },
    ],
  }
  let draft = {
    ..a.draft,
    ticks_per_second: 2147483647,
    duration_ticks: 2147483647,
    markers: [{ marker_id: "only", start_tick: 0, title: "One second", }],
  }
  assert_eq(
    @chapter_conform.conform(selected, [{ ..a, draft, }]).draft.duration_ticks,
    2147483647,
  )
}

///|
test "transitions and clip count reject unsupported edits" {
  let p = project()
  let transition : @domain.Transition = {
    transition_id: "dissolve",
    track_id: "video",
    from_clip_id: "a",
    to_clip_id: "b",
    kind: "dissolve",
    duration_ticks: 100,
    outgoing_handle_ticks: 50,
    incoming_handle_ticks: 50,
    color: "#000000",
    direction: "left",
    transition_digest: "",
  }
  expect_error(() => {
    @chapter_conform.conform(
      { ..p, timeline: { ..p.timeline, transitions: [transition], }, },
      sources(),
    )
    |> ignore
  })
  let c = p.timeline.tracks[0].clips[0]
  let clips = Array::makei(1000, i => {
    ..c,
    clip_id: i.to_string(),
    start_tick: i * 2000,
  })
  expect_error(() => {
    @chapter_conform.conform(with_clips(p, clips), [sources()[0]]) |> ignore
  })
}

///|
test "total output duration bound holds even with legal individual sources" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  let clips = Array::makei(721, i => {
    ..c,
    clip_id: i.to_string(),
    start_tick: i * 10000,
    source_in_tick: 0,
    source_out_tick: 10000,
    duration_ticks: 10000,
  })
  let a = sources()[0]
  let source = {
    ..a,
    draft: {
      ..a.draft,
      markers: [{ marker_id: "one", start_tick: 0, title: "One", }],
    },
  }
  expect_error(() => {
    @chapter_conform.conform(with_clips(p, clips), [source]) |> ignore
  })
  assert_eq(
    @chapter_conform.conform(with_clips(p, clips[:720].to_array()), [source]).draft.duration_ticks,
    7200000,
  )
}
