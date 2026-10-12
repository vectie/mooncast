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
    start_tick: 1000,
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
              start_tick: 4000,
              source_in_tick: 2000,
              source_out_tick: 4000,
            },
            { ..clip, clip_id: "a-repeat", start_tick: 6000, },
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
fn sources() -> Array[@caption_conform.SourceCaptions] {
  let a : @captions.CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file: "a.srt",
    duration_ms: 10000,
    cues: [
      { start_ms: 0, end_ms: 500, text: "Outside left", },
      { start_ms: 250, end_ms: 1000, text: "Opening 🌙", },
      { start_ms: 1000, end_ms: 3000, text: "Ending", },
      { start_ms: 2500, end_ms: 4000, text: "Outside right", },
    ],
  }
  [
    { media_ref_id: "media.a", draft: Some(a), },
    {
      media_ref_id: "media.b",
      draft: Some({
        ..a,
        source_file: "b.vtt",
        cues: [{ start_ms: 2500, end_ms: 3500, text: "Other camera & voice", }],
      }),
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
test "crop and retime multiple sources with gaps and repeated selections" {
  let p = project()
  let result = @caption_conform.conform(p, sources())
  assert_eq(result.draft.cues, [
    { start_ms: 1000, end_ms: 1500, text: "Opening 🌙", },
    { start_ms: 1500, end_ms: 3000, text: "Ending", },
    { start_ms: 4500, end_ms: 5500, text: "Other camera & voice", },
    { start_ms: 6000, end_ms: 6500, text: "Opening 🌙", },
    { start_ms: 6500, end_ms: 8000, text: "Ending", },
  ])
  assert_eq(result.draft.duration_ms, 8000)
  assert_eq(result.origins.map(o => o.source_cue), [2, 3, 1, 2, 3])
  assert_eq(result.origins.map(o => o.clipped_at_cut), [
    true, true, false, true, true,
  ])
  assert_eq(result.origins.map(o => o.clip_id), [
    "a", "a", "b", "a-repeat", "a-repeat",
  ])
  assert_eq(result.timeline_revision, 8)
  assert_eq(result.project_revision, 7)
  assert_eq(p, project())
  assert_eq(
    @captions.read_draft(result.draft.to_json().stringify()),
    result.draft,
  )
}

///|
test "reordered native storage is sorted by playback position without mutating it" {
  let p = project()
  let clips = p.timeline.tracks[0].clips
  let unsorted = with_clips(p, [clips[2], clips[0], clips[1]])
  assert_eq(
    @caption_conform.conform(unsorted, sources()),
    @caption_conform.conform(p, sources()),
  )
  assert_eq(unsorted.timeline.tracks[0].clips[0].clip_id, "a-repeat")
}

///|
test "fractional millisecond boundaries round inward instead of crossing a cut" {
  let p = project()
  let clip = p.timeline.tracks[0].clips[0]
  let fractional = with_clips(
    { ..p, timeline: { ..p.timeline, timebase: { ticks_per_second: 3000, }, }, },
    [
      {
        ..clip,
        start_tick: 125,
        duration_ticks: 2875,
        source_in_tick: 0,
        source_out_tick: 2875,
      },
    ],
  )
  let source : @captions.CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file: "one.srt",
    duration_ms: 3000,
    cues: [{ start_ms: 0, end_ms: 2000, text: "24 fps boundaries", }],
  }
  let result = @caption_conform.conform(fractional, [
    { media_ref_id: "media.a", draft: Some(source), },
  ])
  assert_eq(result.draft.cues[0], {
    start_ms: 42,
    end_ms: 1000,
    text: "24 fps boundaries",
  })
  assert_true(result.origins[0].rounded_inward)
  assert_true(result.origins[0].clipped_at_cut)
}

///|
test "silent media are explicit and leave caption-free intervals" {
  let bindings = sources()
  let result = @caption_conform.conform(project(), [
    bindings[0],
    { media_ref_id: "media.b", draft: None, },
  ])
  assert_eq(result.draft.cues.length(), 4)
  assert_eq(result.silent_media_ref_ids, ["media.b"])
  assert_eq(result.draft.cues[2].start_ms, 6000)
  expect_error(() => ignore(@caption_conform.conform(project(), [bindings[0]])))
  expect_error(() => {
    ignore(
      @caption_conform.conform(project(), [
        bindings[0],
        bindings[0],
        bindings[1],
      ]),
    )
  })
}

///|
test "exported captions reopen for correction with exact output timing" {
  let result = @caption_conform.conform(project(), sources())
  assert_eq(
    @captions.import_draft(
      @utf8.encode(result.draft.srt()),
      "application/x-subrip",
      "cut.srt",
      8000,
    ).cues,
    result.draft.cues,
  )
  assert_eq(
    @captions.import_draft(
      @utf8.encode(result.draft.vtt()),
      "text/vtt",
      "cut.vtt",
      8000,
    ).cues,
    result.draft.cues,
  )
  assert_eq(
    result.draft.set_cue(1, 1000, 1500, "Reviewed fragment").cues[0].text,
    "Reviewed fragment",
  )
}

///|
test "overlapping speaker cues keep their order and are cropped independently" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  let source : @captions.CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file: "speakers.srt",
    duration_ms: 10000,
    cues: [
      { start_ms: 0, end_ms: 3000, text: "Speaker one", },
      { start_ms: 250, end_ms: 1000, text: "Speaker two", },
    ],
  }
  let result = @caption_conform.conform(with_clips(p, [c]), [
    { media_ref_id: "media.a", draft: Some(source), },
  ])
  assert_eq(result.draft.cues.map(cue => (cue.start_ms, cue.end_ms)), [
    (1000, 3000),
    (1000, 1500),
  ])
  assert_eq(result.origins.map(o => o.source_cue), [1, 2])
}

///|
test "overlaps retimes and invalid media bounds cannot masquerade as a cut" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  for
    bad in [
      { ..c, start_tick: -1, },
      { ..c, duration_ticks: 1000, },
      { ..c, source_in_tick: 9500, source_out_tick: 11500, },
      { ..c, source_in_tick: -500, source_out_tick: 1500, },
      { ..c, duration_ticks: 2147483647, },
    ] {
    expect_error(() => {
      ignore(@caption_conform.conform(with_clips(p, [bad]), [sources()[0]]))
    })
  }
  expect_error(() => {
    ignore(
      @caption_conform.conform(
        with_clips(p, [c, { ..c, clip_id: "overlap", start_tick: 2500, }]),
        [sources()[0]],
      ),
    )
  })
  expect_error(() => {
    ignore(
      @caption_conform.conform(with_clips(p, [c, { ..c, start_tick: 4000, }]), [
        sources()[0],
      ]),
    )
  })
  expect_error(() => {
    ignore(
      @caption_conform.conform(
        {
          ..p,
          timeline: {
            ..p.timeline,
            tracks: [p.timeline.tracks[0], p.timeline.tracks[0]],
          },
        },
        sources(),
      ),
    )
  })
}

///|
test "submillisecond intersections and all-silent cuts report no usable captions" {
  let p = project()
  let c = p.timeline.tracks[0].clips[0]
  let short = with_clips(
    { ..p, timeline: { ..p.timeline, timebase: { ticks_per_second: 3000, }, }, },
    [
      {
        ..c,
        start_tick: 0,
        duration_ticks: 1,
        source_in_tick: 900,
        source_out_tick: 901,
      },
    ],
  )
  let short_source : @captions.CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file: "short.srt",
    duration_ms: 3000,
    cues: [{ start_ms: 0, end_ms: 1000, text: "Tiny selected fragment", }],
  }
  match
    (try? @caption_conform.conform(short, [
      { media_ref_id: "media.a", draft: Some(short_source), },
    ])) {
    Err(error) =>
      assert_true(
        error.to_string().contains("shorter than a representable millisecond"),
      )
    Ok(_) => fail("submillisecond selection must fail")
  }
  expect_error(() => {
    ignore(
      @caption_conform.conform(p, [
        { media_ref_id: "media.a", draft: None, },
        { media_ref_id: "media.b", draft: None, },
      ]),
    )
  })
}

///|
test "enabled speed ramps are rejected even when overall duration is unchanged" {
  let p = project()
  let clip = p.timeline.tracks[0].clips[0]
  let effect : @domain.Effect = {
    effect_id: "speed",
    kind: "speed-ramp",
    enabled: true,
    effect_digest: "synthetic",
    parameters: {
      crop: None,
      transform: None,
      opacity: None,
      blend_mode: None,
      mask: None,
      speed_points: [
        { timeline_tick: 0, source_tick: 500, interpolation: "linear", },
        { timeline_tick: 1000, source_tick: 2000, interpolation: "linear", },
        { timeline_tick: 2000, source_tick: 2500, interpolation: "linear", },
      ],
    },
  }
  expect_error(() => {
    ignore(
      @caption_conform.conform(
        with_clips(p, [{ ..clip, effects: [effect], }]),
        [sources()[0]],
      ),
    )
  })
  let disabled = with_clips(p, [
    { ..clip, effects: [{ ..effect, enabled: false, }], },
  ])
  assert_eq(
    @caption_conform.conform(disabled, [sources()[0]]).draft.cues.length(),
    2,
  )
}

///|
test "source captions past media duration and unresolved media are rejected" {
  let p = project()
  let clip = p.timeline.tracks[0].clips[0]
  let source : @captions.CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file: "wrong.srt",
    duration_ms: 12000,
    cues: [{ start_ms: 0, end_ms: 11000, text: "Wrong source duration", }],
  }
  expect_error(() => {
    ignore(
      @caption_conform.conform(with_clips(p, [clip]), [
        { media_ref_id: "media.a", draft: Some(source), },
      ]),
    )
  })
  expect_error(() => ignore(@caption_conform.media_duration_ms(p, "absent")))
  expect_error(() => {
    ignore(
      @caption_conform.media_duration_ms(
        { ..p, media_refs: [p.media_refs[0], p.media_refs[0]], },
        "media.a",
      ),
    )
  })
}
