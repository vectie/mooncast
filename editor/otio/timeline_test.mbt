///|
fn rt(value : Int, rate? : Int = 24) -> Json {
  { "OTIO_SCHEMA": "RationalTime.1", "value": value, "rate": rate }
}

///|
fn span(start : Int, duration : Int) -> Json {
  {
    "OTIO_SCHEMA": "TimeRange.1",
    "start_time": rt(start),
    "duration": rt(duration),
  }
}

///|
fn clip(start? : Int = 2401, duration? : Int = 48, v2? : Bool = false) -> Json {
  let fields : Map[String, Json] = {
    "OTIO_SCHEMA": (if v2 { "Clip.2" } else { "Clip.1" }).to_json(),
    "name": "Café 🐈".to_json(),
    "metadata": { "recorded_note": "Literal external metadata" },
    "source_range": span(start, duration),
    "effects": [],
    "markers": [],
    "enabled": true,
  }
  let reference : Json = {
    "OTIO_SCHEMA": "ExternalReference.1",
    "target_url": "https://unfetched.invalid/a.mov",
    "available_range": span(2400, 240),
  }
  if v2 {
    fields["active_media_reference_key"] = "DEFAULT_MEDIA"
    fields["media_references"] = { "DEFAULT_MEDIA": reference }
  } else {
    fields["media_reference"] = reference
  }
  Json::object(fields)
}

///|
fn gap(duration : Int) -> Json {
  { "OTIO_SCHEMA": "Gap.1", "source_range": span(0, duration) }
}

///|
fn timeline(children : Array[Json]) -> String {
  let value : Json = {
    "OTIO_SCHEMA": "Timeline.1",
    "name": "Synthetic assembly",
    "metadata": {},
    "global_start_time": rt(86400),
    "tracks": {
      "OTIO_SCHEMA": "Stack.1",
      "source_range": null,
      "children": [
        {
          "OTIO_SCHEMA": "Track.1",
          "kind": "Video",
          "source_range": null,
          "children": children,
        },
      ],
    },
  }
  value.stringify()
}

///|
fn modified(value : Json, key : String, replacement : Json) -> Json {
  guard value is Object(fields) else { abort("expected fixture object") }
  let copy = fields.copy()
  copy[key] = replacement
  Json::object(copy)
}

///|
fn mapping() -> @otio.MediaMap {
  {
    contract: "mooncast.otio-media-map.v1",
    fps: 24,
    draft_timeline_id: "timeline.imported",
    bindings: [
      {
        target_url: "https://unfetched.invalid/a.mov",
        media_ref_id: "media.a",
        template_clip_id: "template.a",
        source_start_frame: 2400,
      },
    ],
  }
}

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
  {
    contract: "mooncast.editor-project.v1",
    project_id: "project.demo",
    revision: 7,
    identity_graph: [identity],
    media_refs: [
      {
        contract: "mooncast.editor-media-ref.v1",
        media_ref_id: "media.a",
        locator: { kind: "pack-relative", uri: "synthetic.mp4", },
        metadata: {
          sha256: "synthetic",
          mime_type: "video/mp4",
          size_bytes: 1,
          duration_ticks: 10000,
        },
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
          clips: [clip],
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
test "OTIO catalogs Clip.1 and Clip.2 with exact ordered gaps and source coordinates" {
  let input = timeline([gap(3), clip(), gap(21), clip(start=2410, v2=true)])
  let result = @otio.catalog_timeline(input, 24)
  assert_eq(result.duration_frames, 120)
  assert_eq(result.global_start_frame, Some(86400))
  assert_eq(result.items.length(), 4)
  assert_eq(result.items[1].name, "Café 🐈")
  assert_eq(result.items[1].source_start_frame, 2401)
  assert_eq(result.items[3].start_frame, 72)
  assert_eq(result.items[3].target_url, "https://unfetched.invalid/a.mov")
  assert_true(result == @otio.catalog_timeline(input, 24))
}

///|
test "OTIO import edits through actual native reducer and exports exact cuts" {
  let input = timeline([gap(3), clip(), gap(21), clip(start=2410, v2=true)])
  let original = project()
  let before = original.to_json().stringify()
  let result = @otio.import_timeline(original, input, mapping())
  assert_eq(result.project.timeline.timebase.ticks_per_second, 3000)
  assert_eq(result.project.timeline.tracks[0].clips[0].start_tick, 375)
  assert_eq(result.project.timeline.tracks[0].clips[0].source_in_tick, 125)
  assert_eq(result.preview.gap_frames, 24)
  assert_eq(result.preview.duration_frames, 120)
  assert_eq(result.project.media_refs[0].metadata.duration_ticks, 30000)
  assert_true(
    @domain.snapshot_from_json(result.project.to_json().stringify()) ==
    result.project,
  )
  let session = @domain.EditorSession::new(result.project)
  let trimmed = session.dispatch({
    contract: "mooncast.editor-edit-command.v1",
    command_id: "trim.1",
    expected_revision: 0,
    actor: { actor_id: "editor", provenance: "synthetic-test", },
    operation: @domain.Trim(
      clip_id="edl.001",
      source_in_tick=250,
      source_out_tick=6125,
      start_tick=None,
    ),
  })
  assert_eq(trimmed.snapshot.timeline.tracks[0].clips[0].source_in_tick, 250)
  let edl = @edl.export_edl(
    trimmed.snapshot,
    result.edl_mapping,
    "Edited OTIO cut",
  )
  assert_true(edl.contains("00:00:00:02 00:00:02:01"))
  let replayed = @edl.import_edl(original, edl, result.edl_mapping)
  assert_eq(replayed.project.timeline.tracks, trimmed.snapshot.timeline.tracks)
  let undone = trimmed.dispatch({
    contract: "mooncast.editor-edit-command.v1",
    command_id: "undo.1",
    expected_revision: 1,
    actor: { actor_id: "editor", provenance: "synthetic-test", },
    operation: @domain.Undo(target_command_id=Some("trim.1")),
  })
  assert_eq(undone.snapshot.timeline.tracks, result.project.timeline.tracks)
  assert_eq(original.to_json().stringify(), before)
}

///|
test "OTIO refuses unsupported clip semantics instead of flattening them" {
  for
    child in [
      modified(clip(), "effects", [
        { "OTIO_SCHEMA": "LinearTimeWarp.1", "time_scalar": 2 },
      ]),
      modified(clip(), "markers", [{ "OTIO_SCHEMA": "Marker.2" }]),
      modified(clip(), "enabled", false),
      modified(clip(), "color", "RED"),
      modified(clip(), "unknown", true),
      modified(clip(), "OTIO_SCHEMA", "Clip.3"),
      modified(clip(), "OTIO_SCHEMA", "Transition.1"),
      modified(clip(), "source_range", null),
      modified(clip(), "source_range", span(2400, 0)),
      modified(clip(), "source_range", span(2630, 20)),
      modified(clip(), "source_range", {
        "OTIO_SCHEMA": "TimeRange.1",
        "start_time": rt(1, rate=25),
        "duration": rt(48),
      }),
      modified(clip(), "media_reference", {
        "OTIO_SCHEMA": "MissingReference.1",
      }),
      modified(clip(v2=true), "active_media_reference_key", "missing"),
      modified(clip(v2=true), "media_references", {}),
      modified(clip(), "media_references", {}),
    ] {
    try @otio.catalog_timeline(timeline([child]), 24) catch {
      _ => ()
    } noraise {
      _ => fail("unsupported child accepted")
    }
  }
}

///|
test "OTIO rejects empty trailing gaps layered audio and trimmed compositions" {
  for
    input in [
      timeline([]),
      timeline([gap(3)]),
      timeline([clip(), gap(3)]),
      "{}",
      "[]",
      "broken",
    ] {
    try @otio.catalog_timeline(input, 24) catch {
      _ => ()
    } noraise {
      _ => fail("invalid timeline accepted")
    }
  }
  let valid = timeline([clip()])
  for
    input in [
      valid.replace(old="Video", new="Audio"),
      valid.replace(old="Track.1", new="Stack.1"),
      valid.replace(
        old="\"source_range\":null",
        new="\"source_range\":{" + "\"OTIO_SCHEMA\":\"TimeRange.1\"}",
      ),
      valid.replace(old="\"rate\":24", new="\"rate\":23.976"),
      valid.replace(old="\"value\":2401", new="\"value\":2401.5"),
      valid.replace(old="\"value\":2401", new="\"value\":-1"),
    ] {
    try @otio.catalog_timeline(input, 24) catch {
      _ => ()
    } noraise {
      _ => fail("invalid timing/container accepted")
    }
  }
  for fps in [0, -1, 61] {
    try @otio.catalog_timeline(valid, fps) catch {
      _ => ()
    } noraise {
      _ => fail("invalid fps accepted")
    }
  }
}

///|
test "OTIO mappings require explicit unique source identities and fitting origins" {
  let map = mapping()
  assert_true(@otio.read_media_map(map.to_json().stringify()) == map)
  let binding = map.bindings[0]
  for
    bad in [
      { ..map, contract: "v2", },
      { ..map, fps: 0, },
      { ..map, bindings: [], },
      { ..map, bindings: [binding, binding], },
      { ..map, bindings: [{ ..binding, source_start_frame: -1, }], },
      { ..map, bindings: [{ ..binding, source_start_frame: 2402, }], },
      { ..map, bindings: [{ ..binding, target_url: "different", }], },
      { ..map, bindings: [{ ..binding, media_ref_id: "missing", }], },
      { ..map, bindings: [{ ..binding, template_clip_id: "missing", }], },
    ] {
    try @otio.import_timeline(project(), timeline([clip()]), bad) catch {
      _ => ()
    } noraise {
      _ => fail("invalid mapping accepted")
    }
  }
  let short = project()
  short.media_refs[0] = {
    ..short.media_refs[0],
    metadata: { ..short.media_refs[0].metadata, duration_ticks: 500, },
  }
  try @otio.import_timeline(short, timeline([clip()]), map) catch {
    _ => ()
  } noraise {
    _ => fail("out of media range accepted")
  }
}

///|
test "OTIO structural and numeric limits have explicit refusal outcomes" {
  let valid = @json.parse(timeline([clip()]))
  guard valid is Object(root) &&
    root["tracks"] is Object(stack) &&
    stack["children"] is Array(tracks) else {
    fail("fixture structure")
  }
  for children in [[], [tracks[0], tracks[0]]] {
    let bad = modified(
      valid,
      "tracks",
      modified(root["tracks"], "children", children.to_json()),
    )
    try @otio.catalog_timeline(bad.stringify(), 24) catch {
      _ => ()
    } noraise {
      _ => fail("unsupported track count")
    }
  }
  let bad_origin = modified(valid, "global_start_time", rt(1, rate=25))
  try @otio.catalog_timeline(bad_origin.stringify(), 24) catch {
    _ => ()
  } noraise {
    _ => fail("mixed origin rate")
  }
  for
    input in [
      timeline(Array::make(2000, clip())),
      timeline(Array::make(1000, clip())),
      timeline([gap(2073600), clip()]),
    ] {
    try @otio.catalog_timeline(input, 24) catch {
      _ => ()
    } noraise {
      _ => fail("timeline limit")
    }
  }
  let map = mapping().to_json().stringify()
  for
    input in [
      map.replace(old="\"fps\":24", new="\"fps\":24.5"),
      map.replace(
        old="\"source_start_frame\":2400",
        new="\"source_start_frame\":2400.5",
      ),
      map.replace(
        old="\"source_start_frame\":2400",
        new="\"source_start_frame\":2147483648",
      ),
    ] {
    try @otio.read_media_map(input) catch {
      _ => ()
    } noraise {
      _ => fail("fractional/overflowing map accepted")
    }
  }
}

///|
test "OTIO rejects fractional tokens even when binary64 rounds to whole frames" {
  let valid = timeline([clip()])
  for
    token in [
      "2401.00000000000000001", "2400.99999999999999999", "2.401000000000000001e3",
      "1e-9999", "-1e-9999", "2147483647.00000000001",
    ] {
    let input = valid.replace(old="\"value\":2401", new="\"value\":" + token)
    assert_true(input != valid)
    try @otio.catalog_timeline(input, 24) catch {
      _ => ()
    } noraise {
      _ => fail("fractional frame accepted: " + token)
    }
  }
  for
    token in [
      "24.00000000000000001", "23.99999999999999999", "2.400000000000000001e1",
    ] {
    let input = valid.replace(old="\"rate\":24", new="\"rate\":" + token)
    try @otio.catalog_timeline(input, 24) catch {
      _ => ()
    } noraise {
      _ => fail("fractional rate accepted: " + token)
    }
  }
  let map = mapping().to_json().stringify()
  for
    input in [
      map.replace(old="\"fps\":24", new="\"fps\":24.00000000000000001"),
      map.replace(
        old="\"source_start_frame\":2400",
        new="\"source_start_frame\":2399.99999999999999999",
      ),
      map.replace(
        old="\"source_start_frame\":2400",
        new="\"source_start_frame\":1e-9999",
      ),
    ] {
    assert_true(input != map)
    try @otio.read_media_map(input) catch {
      _ => ()
    } noraise {
      _ => fail("fractional map integer accepted")
    }
  }
}

///|
test "OTIO keeps exact integral decimals and exponent forms without rounding" {
  let valid = timeline([clip()])
  let expected = @otio.catalog_timeline(valid, 24).to_json().stringify()
  for
    token in [
      "2401.0", "24010e-1", "2.401e3", "0.2401e4", "2401000000000000000000000000e-24",
    ] {
    let input = valid.replace(old="\"value\":2401", new="\"value\":" + token)
    assert_eq(@otio.catalog_timeline(input, 24).to_json().stringify(), expected)
  }
  let map = mapping().to_json().stringify()
  let exponent_map = map
    .replace(old="\"fps\":24", new="\"fps\":2.400e1")
    .replace(
      old="\"source_start_frame\":2400",
      new="\"source_start_frame\":240000e-2",
    )
  assert_true(@otio.read_media_map(exponent_map) == mapping())
}

///|
test "OTIO decoded duplicate keys cannot hide contradictory timing" {
  let valid = timeline([clip()])
  for
    input in [
      valid.replace(old="\"value\":2401", new="\"value\":1.9,\"value\":2401"),
      valid.replace(
        old="\"value\":2401",
        new="\"value\":1.9,\"v\\u0061lue\":2401",
      ),
    ] {
    try @otio.catalog_timeline(input, 24) catch {
      _ => ()
    } noraise {
      _ => fail("duplicate timing accepted")
    }
  }
  let map = mapping()
    .to_json()
    .stringify()
    .replace(old="\"fps\":24", new="\"fps\":1.9,\"fps\":24")
  try @otio.read_media_map(map) catch {
    _ => ()
  } noraise {
    _ => fail("duplicate map field accepted")
  }
}
