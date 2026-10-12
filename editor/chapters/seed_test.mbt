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
test "seed selected track preserves exact editorial boundaries and source identity" {
  let source = project()
  let draft = @chapters.seed(source, "video")
  assert_eq(draft.duration_ticks, 8000)
  assert_eq(draft.project_revision, 7)
  assert_eq(draft.timeline_revision, 8)
  assert_eq(draft.markers.length(), 3)
  assert_eq(draft.markers[0].start_tick, 1000)
  assert_eq(draft.markers[2].marker_id, "a-repeat")
  assert_true((try? @chapters.seed(source, "missing")) is Err(_))
}

///|
test "other tracks extend duration without adding chapters" {
  let source = project()
  let extra = {
    ..source.timeline.tracks[0],
    track_id: "audio",
    clips: [
      {
        ..source.timeline.tracks[0].clips[0],
        clip_id: "bed",
        start_tick: 0,
        duration_ticks: 12000,
      },
    ],
  }
  let layered = {
    ..source,
    timeline: { ..source.timeline, tracks: [source.timeline.tracks[0], extra], },
  }
  let draft = @chapters.seed(layered, "video")
  assert_eq(draft.duration_ticks, 12000)
  assert_eq(draft.markers.length(), 3)
  assert_true(draft.ffmetadata().contains("START=6000\nEND=12000"))
}

///|
test "seed rejects ambiguous coincident markers empty tracks and overflowing duration" {
  let source = project()
  let track = source.timeline.tracks[0]
  let coincident = {
    ..track,
    clips: [track.clips[0], { ..track.clips[1], start_tick: 1000, }],
  }
  let empty = { ..track, clips: [], }
  let overflow = {
    ..track,
    clips: [{ ..track.clips[0], start_tick: 2147483640, }],
  }
  for selected in [coincident, empty, overflow] {
    let invalid = {
      ..source,
      timeline: { ..source.timeline, tracks: [selected], },
    }
    assert_true((try? @chapters.seed(invalid, "video")) is Err(_))
  }
}
