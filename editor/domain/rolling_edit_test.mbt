///|
fn roll_source_project() -> @domain.EditorProject {
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
    duration_ticks: 2000,
    source_in_tick: 1000,
    source_out_tick: 3000,
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
              start_tick: 2000,
            },
            { ..clip, clip_id: "tail", start_tick: 4000, },
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
fn roll_command() -> @domain.EditCommand raise {
  @domain.command_from_json(
    (
      {
        "contract": "mooncast.editor-edit-command.v1",
        "command_id": "roll.1",
        "expected_revision": 7,
        "actor": { "actor_id": "editor", "provenance": "rolling-cut-test" },
        "type": "group_trim",
        "payload": {
          "trims": [
            {
              "clip_id": "template.a",
              "source_in_tick": 1000,
              "source_out_tick": 3040,
              "start_tick": 0,
            },
            {
              "clip_id": "template.b",
              "source_in_tick": 1040,
              "source_out_tick": 3000,
              "start_tick": 2040,
            },
          ],
        },
      } : Json).stringify(),
  )
}

///|
test "rolling group trim is atomic keeps downstream timing and lineage and undo redo replay" {
  let before = roll_source_project()
  let session = @domain.EditorSession::new(before)
  let command = roll_command()
  let rolled = session.dispatch(command)
  let track = rolled.snapshot.timeline.tracks[0]
  assert_eq(track.clips[0].duration_ticks, 2040)
  assert_eq(track.clips[1].duration_ticks, 1960)
  assert_eq(track.clips[1].start_tick, 2040)
  assert_eq(track.clips[2], before.timeline.tracks[0].clips[2])
  assert_eq(
    track.clips[0].identity,
    before.timeline.tracks[0].clips[0].identity,
  )
  assert_eq(
    track.clips[1].media_ref_id,
    before.timeline.tracks[0].clips[1].media_ref_id,
  )
  assert_eq(rolled.command_log.length(), 1)
  assert_eq(rolled.snapshot.revision, 8)
  assert_eq(rolled.dispatch(command), rolled)
  let undo = {
    ..command,
    command_id: "undo.1",
    expected_revision: 8,
    operation: @domain.Undo(target_command_id=Some("roll.1")),
  }
  let undone = rolled.dispatch(undo)
  assert_eq(undone.snapshot.timeline.tracks, before.timeline.tracks)
  let redo = {
    ..command,
    command_id: "redo.1",
    expected_revision: 9,
    operation: @domain.Redo(target_command_id=Some("roll.1")),
  }
  let redone = undone.dispatch(redo)
  assert_eq(redone.snapshot.timeline.tracks, rolled.snapshot.timeline.tracks)
  assert_eq(@domain.replay(before, [command, undo, redo]), redone)
  assert_eq(session.snapshot, before)
}

///|
test "rolling rejects stale revisions and a failed second trim leaves the session unchanged" {
  let session = @domain.EditorSession::new(roll_source_project())
  let command = roll_command()
  assert_true(
    (try? session.dispatch({ ..command, expected_revision: 6, })) is Err(_),
  )
  let broken = {
    ..command,
    operation: @domain.GroupTrim([
      {
        clip_id: "template.a",
        source_in_tick: 1000,
        source_out_tick: 3040,
        start_tick: Some(0),
      },
      {
        clip_id: "missing",
        source_in_tick: 1040,
        source_out_tick: 3000,
        start_tick: Some(2040),
      },
    ]),
  }
  assert_true((try? session.dispatch(broken)) is Err(_))
  assert_eq(session.snapshot.revision, 7)
  assert_eq(session.snapshot.timeline.tracks[0].clips[0].source_out_tick, 3000)
  assert_eq(session.command_log.length(), 0)
}
