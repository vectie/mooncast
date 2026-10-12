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
      sha256: "a".repeat(64),
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
test "collection deduplicates bytes while retaining all native identities" {
  let source = source_project()
  let plan = @collect.prepare(source)
  assert_eq(plan.files.length(), 1)
  assert_eq(plan.total_size_bytes, 1L)
  assert_eq(plan.members.length(), 2)
  assert_eq(plan.project.revision, 8)
  assert_eq(plan.project.timeline, source.timeline)
  assert_eq(plan.project.identity_graph, source.identity_graph)
  assert_eq(plan.project.artifacts, source.artifacts)
  assert_eq(plan.project.media_refs[1].media_ref_id, "media.b")
  assert_eq(plan.project.media_refs[0].metadata, source.media_refs[0].metadata)
  assert_eq(
    plan.project.media_refs[0].locator.uri,
    "media/" + "a".repeat(64) + ".mp4",
  )
  assert_eq(source.media_refs[0].locator.uri, "synthetic-a.mp4")
  let reopened = @domain.snapshot_from_json(
    @domain.snapshot_to_json(plan.project),
  )
  let frozen = @render_plan.freeze(reopened, [], "local-test")
  assert_eq(frozen.timeline_id, source.timeline.timeline_id)
}

///|
test "unused library assets and distinct suffixes remain available" {
  let source = source_project()
  let extra = {
    ..source.media_refs[0],
    media_ref_id: "unused",
    locator: { kind: "pack-relative", uri: "captions/original.srt", },
  }
  let plan = @collect.prepare({
    ..source,
    media_refs: [..source.media_refs, extra],
  })
  assert_eq(plan.files.length(), 2)
  assert_eq(plan.members.length(), 3)
  assert_eq(
    plan.project.media_refs[2].locator.uri,
    "media/" + "a".repeat(64) + ".srt",
  )
}

///|
test "different bytes with colliding filenames get distinct paths" {
  let source = source_project()
  let second = source.media_refs[1]
  let plan = @collect.prepare({
    ..source,
    media_refs: [
      source.media_refs[0],
      {
        ..second,
        locator: { kind: "pack-relative", uri: "other/synthetic-a.mp4", },
        metadata: { ..second.metadata, sha256: "b".repeat(64), },
      },
    ],
  })
  assert_eq(plan.files.length(), 2)
  assert_true(plan.files[0].uri != plan.files[1].uri)
}

///|
test "collected project and manifest can be verified without original locations" {
  let plan = @collect.prepare(source_project())
  let bytes = @utf8.encode(@domain.snapshot_to_json(plan.project) + "\n")
  let manifest = plan.manifest(bytes)
  let parsed = @collect.read_manifest(manifest.to_json().stringify())
  assert_eq(@collect.verify_manifest(parsed, bytes), plan.project)
  assert_eq(@collect.prepare(plan.project).project.revision, 8)
  assert_true(
    (try? @collect.verify_manifest({ ..parsed, files: [], }, bytes)) is Err(_),
  )
  assert_true(
    (try? @collect.verify_manifest({ ..parsed, members: [], }, bytes)) is Err(_),
  )
  assert_true(
    (try? @collect.verify_manifest(
      parsed,
      @utf8.encode(@domain.snapshot_to_json(plan.project)),
    ))
    is Err(_),
  )
}

///|
test "conflicting metadata and collection size limits reject" {
  let source = source_project()
  let first = source.media_refs[0]
  let second = source.media_refs[1]
  assert_true(
    (try? @collect.prepare({
      ..source,
      media_refs: [
        first,
        { ..second, metadata: { ..second.metadata, size_bytes: 2, }, },
      ],
    }))
    is Err(_),
  )
  assert_true(
    (try? @collect.prepare({
      ..source,
      media_refs: [
        { ..first, metadata: { ..first.metadata, size_bytes: 268435457, }, },
        second,
      ],
    }))
    is Err(_),
  )
  assert_true(
    (try? @collect.prepare({ ..source, revision: 2147483647, })) is Err(_),
  )
}

///|
test "missing library member or unsafe locator cannot be collected" {
  let source = source_project()
  assert_true(
    (try? @collect.prepare({ ..source, media_refs: [source.media_refs[0]], }))
    is Err(_),
  )
  let first = source.media_refs[0]
  assert_true(
    (try? @collect.prepare({
      ..source,
      media_refs: [
        { ..first, locator: { kind: "pack-relative", uri: "../outside.mp4", }, },
        source.media_refs[1],
      ],
    }))
    is Err(_),
  )
}

///|
test "collection retains transforms keyframes and audio settings" {
  let source = source_project()
  let track = source.timeline.tracks[0]
  let clip = track.clips[0]
  let edited = {
    ..clip,
    settings: { ..clip.settings, scale: 1.5, volume_db: -3.0, },
    keyframes: {
      ..clip.keyframes,
      opacity: [
        { tick: 0, value: 0.0, interpolation: "linear", },
        { tick: 100, value: 1.0, interpolation: "linear", },
      ],
    },
  }
  let source = {
    ..source,
    timeline: {
      ..source.timeline,
      tracks: [{ ..track, clips: [edited, track.clips[1]], }],
    },
  }
  let result = @collect.prepare(source)
  assert_eq(result.project.timeline, source.timeline)
  assert_eq(
    @domain.snapshot_from_json(@domain.snapshot_to_json(result.project)),
    result.project,
  )
}

///|
test "aggregate byte budget is enforced before copying" {
  let source = source_project()
  let template = source.media_refs[0]
  let refs = source.media_refs.copy()
  for i in 0..<17 {
    let hash = "0123456789abcdef" +
      i.to_string() +
      "0".repeat(if i < 10 { 47 } else { 46 })
    refs.push({
      ..template,
      media_ref_id: "extra" + i.to_string(),
      metadata: { ..template.metadata, sha256: hash, size_bytes: 268435456, },
    })
  }
  assert_true(
    (try? @collect.prepare({ ..source, media_refs: refs, })) is Err(_),
  )
}
