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
test "inventory associates exact media IDs with clips without reading media" {
  let rows = @relink.inventory(source_project())
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].media_ref_id, "media.a")
  assert_eq(rows[0].clip_ids, ["template.a"])
  assert_eq(rows[1].clip_ids, ["template.b"])
}

///|
test "relink preserves native snapshot contents and opens in editing consumers" {
  let source = source_project()
  let map = @relink.seed(source)
  let result = @relink.prepare(source, {
    ..map,
    replacements: [{ media_ref_id: "media.a", new_uri: "moved/camera-a.mp4", }],
  })
  let reopened = @domain.snapshot_from_json(
    @domain.snapshot_to_json(result.project),
  )
  assert_eq(reopened.project_id, source.project_id)
  assert_eq(reopened.revision, 8)
  assert_eq(reopened.timeline, source.timeline)
  assert_eq(reopened.artifacts, source.artifacts)
  assert_eq(reopened.identity_graph, source.identity_graph)
  assert_eq(reopened.intent_refs, source.intent_refs)
  assert_eq(reopened.media_refs[0].metadata, source.media_refs[0].metadata)
  assert_eq(reopened.media_refs[0].locator.uri, "moved/camera-a.mp4")
  assert_eq(reopened.media_refs[1], source.media_refs[1])
  assert_eq(source.media_refs[0].locator.uri, "synthetic-a.mp4")
  assert_eq(result.changes.length(), 1)
  let session = @domain.EditorSession::new(reopened)
  let edited = session.dispatch({
    contract: "mooncast.editor-edit-command.v1",
    command_id: "trim.1",
    expected_revision: 8,
    actor: { actor_id: "editor", provenance: "local-test", },
    operation: @domain.Trim(
      clip_id="template.a",
      source_in_tick=0,
      source_out_tick=9000,
      start_tick=None,
    ),
  })
  assert_eq(edited.snapshot.timeline.tracks[0].clips[0].duration_ticks, 9000)
  let plan = @render_plan.freeze(reopened, [], "preview")
  assert_eq(plan.tracks[0].clips[0].media_ref_id, "media.a")
  assert_eq(plan.tracks[0].clips[0].original_digest, "sha256:" + "a".repeat(64))
}

///|
test "no-op mapping keeps revision and semantic JSON binding" {
  let source = source_project()
  let map = @relink.seed(source)
  let parsed = @relink.read_map(map.to_json().stringify(indent=2))
  assert_eq(@relink.prepare(source, parsed).project, source)
  assert_eq(@relink.prepare(source, parsed).changes.length(), 0)
  let formatted = @domain.snapshot_from_json(
    source.to_json().stringify(indent=2),
  )
  assert_eq(@relink.binding(formatted), map.source_binding)
}

///|
test "stale source revision and silent timeline changes reject entire plan" {
  let source = source_project()
  let map = @relink.seed(source)
  assert_true((try? @relink.prepare({ ..source, revision: 8, }, map)) is Err(_))
  let changed = {
    ..source,
    timeline: { ..source.timeline, timeline_id: "other", },
  }
  assert_true((try? @relink.prepare(changed, map)) is Err(_))
}

///|
test "duplicate or unknown media mapping rejects" {
  let source = source_project()
  let map = @relink.seed(source)
  assert_true(
    (try? @relink.prepare(source, {
      ..map,
      replacements: [map.replacements[0], map.replacements[0]],
    }))
    is Err(_),
  )
  assert_true(
    (try? @relink.prepare(source, {
      ..map,
      replacements: [{ media_ref_id: "unknown", new_uri: "media.mp4", }],
    }))
    is Err(_),
  )
}

///|
test "empty mapping and foreign map contract reject" {
  let source = source_project()
  let map = @relink.seed(source)
  assert_true(
    (try? @relink.prepare(source, { ..map, replacements: [], })) is Err(_),
  )
  assert_true(
    (try? @relink.prepare(source, { ..map, contract: "wrong", })) is Err(_),
  )
}

///|
test "same destination for distinct media IDs preserves identities" {
  let source = source_project()
  let map = @relink.seed(source)
  let result = @relink.prepare(source, {
    ..map,
    replacements: map.replacements.map(row => { ..row, new_uri: "shared.mp4", }),
  })
  assert_eq(result.project.media_refs.length(), 2)
  assert_eq(result.project.media_refs[0].media_ref_id, "media.a")
  assert_eq(result.project.media_refs[1].media_ref_id, "media.b")
  assert_eq(result.changes.length(), 2)
}

///|
test "duplicate source IDs and missing clip media reject" {
  let source = source_project()
  assert_true(
    (try? @relink.inventory({
      ..source,
      media_refs: [source.media_refs[0], source.media_refs[0]],
    }))
    is Err(_),
  )
  assert_true(
    (try? @relink.seed({ ..source, media_refs: [source.media_refs[0]], }))
    is Err(_),
  )
}

///|
test "portable URI profile excludes traversal URLs and ambiguous paths" {
  for
    uri in [
      "../a", "/a", "a//b", "a/./b", "a/../b", "https://host/a", "file:a", "a\\b",
      "a\u{0000}b", "a/", "a b.mp4", "café.mp4",
    ] {
    assert_false(@relink.safe_uri(uri))
  }
  assert_true(@relink.safe_uri("assets/shot-01_A.mp4"))
  let source = source_project()
  let map = @relink.seed(source)
  assert_true(
    (try? @relink.prepare(source, {
      ..map,
      replacements: [{ media_ref_id: "media.a", new_uri: "../outside.mp4", }],
    }))
    is Err(_),
  )
}

///|
test "unverifiable metadata and unsupported locator kinds reject" {
  let source = source_project()
  let media = source.media_refs[0]
  assert_true(
    (try? @relink.seed({
      ..source,
      media_refs: [
        { ..media, metadata: { ..media.metadata, sha256: "unknown", }, },
        source.media_refs[1],
      ],
    }))
    is Err(_),
  )
  assert_true(
    (try? @relink.seed({
      ..source,
      media_refs: [
        { ..media, locator: { kind: "remote", uri: "asset.mp4", }, },
        source.media_refs[1],
      ],
    }))
    is Err(_),
  )
}

///|
test "map parse and input limits reject malformed documents" {
  assert_true((try? @relink.read_map("{}")) is Err(_))
  assert_true((try? @relink.read_map("{")) is Err(_))
  assert_true((try? @relink.read_map(" ".repeat(2097153))) is Err(_))
}

///|
test "revision boundary supports no-op and rejects overflow" {
  let source = { ..source_project(), revision: 2147483647, }
  let map = @relink.seed(source)
  assert_eq(@relink.prepare(source, map).project.revision, 2147483647)
  assert_true(
    (try? @relink.prepare(source, {
      ..map,
      replacements: [{ media_ref_id: "media.a", new_uri: "moved.mp4", }],
    }))
    is Err(_),
  )
}
