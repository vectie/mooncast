///|
fn mapping(fps? : Int = 24) -> @edl.ReelMap {
  {
    contract: "mooncast.edl-reel-map.v1",
    fps,
    record_start_timecode: "01:00:00:00",
    draft_timeline_id: "timeline.edl-draft",
    bindings: [
      {
        reel: "CAM_A",
        media_ref_id: "media.a",
        template_clip_id: "template.a",
        source_start_timecode: "10:00:00:00",
      },
      {
        reel: "CAM_B",
        media_ref_id: "media.b",
        template_clip_id: "template.b",
        source_start_timecode: "02:00:00:00",
      },
    ],
  }
}

///|
fn source_project() -> @domain.EditorProject {
  let identity : @domain.ProductionIdentity = {
    project_id: "project.demo",
    episode_id: "episode.1",
    scene_id: "scene.1",
    shot_id: "shot.1",
    asset_id: "asset.a",
  }
  let intent : @domain.IntentRef = { intent_ref: "intent.demo", }
  let clip : @domain.Clip = {
    clip_id: "template.a",
    media_ref_id: "media.a",
    identity,
    intent,
    artifact_id: None,
    start_tick: 0,
    duration_ticks: 10000,
    source_in_tick: 0,
    source_out_tick: 10000,
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
    identity_graph: [
      identity,
      { ..identity, asset_id: "asset.b", shot_id: "shot.2", },
    ],
    media_refs: [
      media,
      {
        ..media,
        media_ref_id: "media.b",
        locator: { kind: "pack-relative", uri: "synthetic-b.mp4", },
      },
    ],
    artifacts: [],
    intent_refs: [intent],
    timeline: {
      contract: "mooncast.editor-timeline.v1",
      timeline_id: "timeline.original",
      revision: 7,
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
              clip_id: "template.b",
              media_ref_id: "media.b",
              identity: { ..identity, asset_id: "asset.b", shot_id: "shot.2", },
              start_tick: 10000,
            },
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
fn sample_edl() -> String {
  (
    #|TITLE: Synthetic interview cut
    #|FCM: NON-DROP FRAME
    #|
    #|001  CAM_A  V  C  10:00:00:01 10:00:02:02 01:00:00:03 01:00:02:04
    #|* FROM CLIP NAME: synthetic-a.mp4
    #|002  CAM_B  V  C  02:00:01:00 02:00:03:00 01:00:03:00 01:00:05:00
    #|
  )
}

///|
test "import native draft preserves exact frames source offsets gaps and production lineage" {
  let source = source_project()
  let result = @edl.import_edl(source, sample_edl(), mapping())
  assert_eq(result.preview.cuts.length(), 2)
  assert_eq(result.preview.duration_frames, 120)
  assert_eq(result.preview.gap_frames, 23)
  assert_eq(result.preview.cuts[0].gap_before_frames, 3)
  assert_eq(result.preview.cuts[1].gap_before_frames, 20)
  assert_eq(result.preview.source_revision, 7)
  let project = result.project
  assert_eq(project.timeline.timebase.ticks_per_second, 3000)
  assert_eq(project.media_refs[0].metadata.duration_ticks, 30000)
  let clips = project.timeline.tracks[0].clips
  assert_eq(clips[0].start_tick, 375)
  assert_eq(clips[0].source_in_tick, 125)
  assert_eq(clips[0].source_out_tick, 6250)
  assert_eq(clips[0].duration_ticks, 6125)
  assert_eq(clips[1].start_tick, 9000)
  assert_eq(clips[1].identity.asset_id, "asset.b")
  assert_eq(source, source_project())
  assert_eq(
    @domain.snapshot_from_json(@domain.snapshot_to_json(project)),
    project,
  )
}

///|
test "canonical EDL roundtrip retains native cuts and gaps at all supported common rates" {
  for fps in [24, 25, 30, 50, 60] {
    let source = source_project()
    let map = mapping(fps~)
    let imported = @edl.import_edl(source, sample_edl(), map)
    let exported = @edl.export_edl(
      imported.project,
      map,
      imported.preview.title,
    )
    let reimported = @edl.import_edl(source, exported, map)
    assert_eq(reimported.project, imported.project)
    assert_eq(reimported.preview, imported.preview)
  }
}

///|
test "native draft supports reducer trim undo and re-export of the edited cut" {
  let imported = @edl.import_edl(source_project(), sample_edl(), mapping())
  let session = @domain.EditorSession::new(imported.project)
  let trimmed = session.dispatch({
    contract: "mooncast.editor-edit-command.v1",
    command_id: "trim.1",
    expected_revision: 0,
    actor: { actor_id: "editor", provenance: "local-test", },
    operation: @domain.Trim(
      clip_id="edl.001",
      source_in_tick=250,
      source_out_tick=6250,
      start_tick=None,
    ),
  })
  assert_eq(trimmed.snapshot.revision, 1)
  let exported = @edl.export_edl(trimmed.snapshot, mapping(), "Trimmed cut")
  assert_true(
    exported.contains("10:00:00:02 10:00:02:02 01:00:00:03 01:00:02:03"),
  )
  let undone = trimmed.dispatch({
    contract: "mooncast.editor-edit-command.v1",
    command_id: "undo.1",
    expected_revision: 1,
    actor: { actor_id: "editor", provenance: "local-test", },
    operation: @domain.Undo(target_command_id=Some("trim.1")),
  })
  assert_eq(undone.snapshot.timeline.tracks, imported.project.timeline.tracks)
}

///|
test "timecode boundary rollover and decimal handling are exact" {
  assert_eq(@edl.timecode_frames("00:01:00:00", 24), 1440)
  assert_eq(@edl.timecode_frames("01:00:00:00", 30), 108000)
  assert_eq(@edl.frames_timecode(2073599, 24), "23:59:59:23")
  assert_eq(@edl.timecode_frames("00:00:08:09", 24), 201)
  for
    bad in [
      "00:00:00;00", "00:00:00:24", "24:00:00:00", "00:60:00:00", "00:00:60:00",
      "0:00:00:00", "00:00:00:-1",
    ] {
    assert_true((try? @edl.timecode_frames(bad, 24)) is Err(_))
  }
  assert_true((try? @edl.frames_timecode(2073600, 24)) is Err(_))
  for fps in [0, 61, -1] {
    assert_true((try? @edl.timecode_frames("00:00:00:00", fps)) is Err(_))
  }
}

///|
test "reject transition drop-frame audio retime overlap unordered and unknown directives" {
  let cases = [
    sample_edl().replace_all(old="NON-DROP FRAME", new="DROP FRAME"),
    sample_edl().replace_all(old="V  C", new="V  D  024"),
    sample_edl().replace_all(old="V  C", new="AA  C"),
    sample_edl().replace_all(old="01:00:02:04", new="01:00:02:05"),
    sample_edl().replace_all(
      old="01:00:03:00 01:00:05:00",
      new="01:00:02:00 01:00:04:00",
    ),
    sample_edl().replace_all(old="002  CAM_B", new="001  CAM_B"),
    sample_edl() + "M2 CAM_A 024.0 10:00:00:00\n",
    sample_edl() + "* SPEED: 50%\n",
    sample_edl().replace_all(old="CAM_A", new="BL"),
    sample_edl().replace_all(old="10:00:00:01", new="10:00:02:03"),
  ]
  for input in cases {
    assert_true((try? @edl.parse_edl(input, 24)) is Err(_))
  }
  assert_true(
    (try? @edl.parse_edl("TITLE: empty\nFCM: NON-DROP FRAME\n", 24)) is Err(_),
  )
}

///|
test "reel mapping rejects missing ambiguous mismatched and out of source ranges" {
  let source = source_project()
  let map = mapping()
  for
    bad in [
      { ..map, bindings: [map.bindings[0]], },
      { ..map, bindings: [map.bindings[0], map.bindings[0]], },
      {
        ..map,
        bindings: [
          { ..map.bindings[0], media_ref_id: "missing", },
          map.bindings[1],
        ],
      },
      {
        ..map,
        bindings: [
          { ..map.bindings[0], template_clip_id: "template.b", },
          map.bindings[1],
        ],
      },
      {
        ..map,
        bindings: [
          { ..map.bindings[0], source_start_timecode: "10:00:00:02", },
          map.bindings[1],
        ],
      },
      { ..map, record_start_timecode: "01:00:00:04", },
    ] {
    assert_true((try? @edl.import_edl(source, sample_edl(), bad)) is Err(_))
  }
  let beyond = sample_edl().replace_all(
    old="10:00:00:01 10:00:02:02",
    new="10:00:09:01 10:00:11:02",
  )
  assert_true((try? @edl.import_edl(source, beyond, map)) is Err(_))
  let audio = {
    ..source,
    media_refs: [
      {
        ..source.media_refs[0],
        metadata: { ..source.media_refs[0].metadata, mime_type: "audio/wav", },
      },
      source.media_refs[1],
    ],
  }
  assert_true((try? @edl.import_edl(audio, sample_edl(), map)) is Err(_))
}

///|
test "export rejects fractional frame boundaries visual edits overlap and extra tracks" {
  let project = @edl.import_edl(source_project(), sample_edl(), mapping()).project
  let timeline = project.timeline
  let track = timeline.tracks[0]
  let clip = track.clips[0]
  for
    bad_clip in [
      { ..clip, start_tick: 376, },
      { ..clip, duration_ticks: clip.duration_ticks - 1, },
      { ..clip, settings: { ..clip.settings, opacity: 0.5, }, },
      {
        ..clip,
        keyframes: {
          ..clip.keyframes,
          opacity: [{ tick: 0, value: 0.5, interpolation: "linear", }],
        },
      },
      { ..clip, audio_bus_id: Some("master"), },
    ] {
    let bad = {
      ..project,
      timeline: {
        ..timeline,
        tracks: [{ ..track, clips: [bad_clip, track.clips[1]], }],
      },
    }
    assert_true((try? @edl.export_edl(bad, mapping(), "Test")) is Err(_))
  }
  let overlap = {
    ..project,
    timeline: {
      ..timeline,
      tracks: [
        { ..track, clips: [clip, { ..track.clips[1], start_tick: 500, }], },
      ],
    },
  }
  assert_true((try? @edl.export_edl(overlap, mapping(), "Test")) is Err(_))
  let layers = { ..project, timeline: { ..timeline, tracks: [track, track], }, }
  assert_true((try? @edl.export_edl(layers, mapping(), "Test")) is Err(_))
  assert_true(
    (try? @edl.export_edl(project, mapping(fps=30), "Test")) is Err(_),
  )
}

///|
test "timebase scaling rejects native tick overflow without wrapping" {
  let source = source_project()
  let huge = {
    ..source,
    timeline: {
      ..source.timeline,
      timebase: { ticks_per_second: 2147483647, },
    },
  }
  assert_true((try? @edl.import_edl(huge, sample_edl(), mapping())) is Err(_))
  let media = source.media_refs[0]
  let long = {
    ..source,
    media_refs: [
      { ..media, metadata: { ..media.metadata, duration_ticks: 2147483647, }, },
      source.media_refs[1],
    ],
  }
  assert_true((try? @edl.import_edl(long, sample_edl(), mapping())) is Err(_))
}

///|
test "CRLF whitespace comments and map serialization remain interoperable" {
  let input = sample_edl()
    .replace_all(old="  ", new="\t")
    .replace_all(old="\n", new="\r\n")
  assert_eq(@edl.parse_edl(input, 24), @edl.parse_edl(sample_edl(), 24))
  assert_eq(@edl.read_reel_map(mapping().to_json().stringify()), mapping())
}

///|
test "timecode encode decode is exact through minute and hour boundaries for every supported fps" {
  for fps = 1; fps <= 60; fps = fps + 1 {
    for
      frame in [
        0,
        fps - 1,
        fps,
        60 * fps - 1,
        60 * fps,
        3600 * fps - 1,
        3600 * fps,
        86400 * fps - 1,
      ] {
      assert_eq(
        @edl.timecode_frames(@edl.frames_timecode(frame, fps), fps),
        frame,
      )
    }
  }
}

///|
test "EDL export canonicalizes event numbers but retains record and source positions" {
  let input = sample_edl()
    .replace_all(old="001  CAM_A", new="019  CAM_A")
    .replace_all(old="002  CAM_B", new="042  CAM_B")
  let imported = @edl.import_edl(source_project(), input, mapping())
  assert_eq(imported.project.timeline.tracks[0].clips[0].clip_id, "edl.019")
  let output = @edl.export_edl(imported.project, mapping(), "Canonical")
  let cuts = @edl.parse_edl(output, 24).cuts
  let original = @edl.parse_edl(input, 24).cuts
  assert_eq(cuts[0], { ..original[0], event_number: 1, })
  assert_eq(cuts[1], { ..original[1], event_number: 2, })
}

///|
test "exclusive source out exactly at duration is valid and one extra frame is rejected" {
  let map = mapping()
  let source = source_project()
  let input = "FCM: NON-DROP FRAME\n001 CAM_A V C 10:00:09:00 10:00:10:00 01:00:00:00 01:00:01:00\n"
  let imported = @edl.import_edl(source, input, map)
  assert_eq(imported.project.timeline.tracks[0].clips[0].source_out_tick, 30000)
  let beyond = "FCM: NON-DROP FRAME\n001 CAM_A V C 10:00:09:00 10:00:10:01 01:00:00:00 01:00:01:01\n"
  assert_true((try? @edl.import_edl(source, beyond, map)) is Err(_))
}
