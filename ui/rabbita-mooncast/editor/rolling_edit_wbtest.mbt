///|
fn roll_ui_timeline() -> @api.Timeline raise {
  @json.from_json({
    "timeline_id": "cut",
    "revision": 7,
    "timebase": { "ticks_per_second": 1000 },
    "output": { "fps": { "numerator": 25, "denominator": 1 } },
    "transitions": [],
    "tracks": [
      {
        "track_id": "v1",
        "kind": "video",
        "clips": [
          {
            "clip_id": "a",
            "media_ref_id": "media.a",
            "start_tick": 0,
            "duration_ticks": 2000,
            "source_in_tick": 1000,
            "source_out_tick": 3000,
            "identity": {
              "project_id": "p",
              "episode_id": "e",
              "scene_id": "s",
              "shot_id": "a",
              "asset_id": "a",
            },
            "intent": { "intent_ref": "intent" },
          },
          {
            "clip_id": "b",
            "media_ref_id": "media.b",
            "start_tick": 2000,
            "duration_ticks": 2000,
            "source_in_tick": 1000,
            "source_out_tick": 3000,
            "identity": {
              "project_id": "p",
              "episode_id": "e",
              "scene_id": "s",
              "shot_id": "b",
              "asset_id": "b",
            },
            "intent": { "intent_ref": "intent" },
          },
          {
            "clip_id": "c",
            "media_ref_id": "media.c",
            "start_tick": 4000,
            "duration_ticks": 2000,
            "source_in_tick": 0,
            "source_out_tick": 2000,
            "identity": {
              "project_id": "p",
              "episode_id": "e",
              "scene_id": "s",
              "shot_id": "c",
              "asset_id": "c",
            },
            "intent": { "intent_ref": "intent" },
          },
        ],
      },
    ],
  })
}

///|
fn roll_ui_model() -> Model raise {
  let value = roll_ui_timeline()
  let variants : Array[@api.TakeVariant] = value.tracks[0].clips.map(clip => {
    @json.from_json({
      "take_id": clip.clip_id,
      "role": "video",
      "variant": clip.clip_id,
      "project_id": "p",
      "episode_id": "e",
      "scene_id": "s",
      "shot_id": clip.clip_id,
      "asset_id": clip.clip_id,
      "duration_ticks": 5000,
      "qc": { "status": "approved" },
      "rights": { "status": "cleared" },
      "media_ref_id": clip.media_ref_id,
      "registry_digest": "fixture",
      "track_id": "v1",
      "track_kind": "video",
      "already_placed": true,
      "approved": true,
      "intent_ref": "intent",
      "source": { "state": "ready" },
    })
  })
  let workspace : @api.WorkspaceSnapshot = @json.from_json({
    "project_id": "p",
    "revision": 7,
  })
  {
    ..initial_model(),
    project_id: "p",
    selected_clip_ids: ["b", "a"],
    workspace: Some({
      ..workspace,
      timeline: Some(value),
      take_variants: Some(variants),
    }),
  }
}

///|
test "rolling editor control dispatch uses one revision-bound mutation and does not mutate the displayed snapshot" {
  let original = roll_ui_model()
  let plan = selected_roll_plan(original, 1).unwrap()
  let body = make_command_body(original, "group_trim", plan.payload)
  guard body is Object(fields) else { fail("command body") }
  assert_eq(fields["expected_revision"], Json::number(7))
  assert_eq(fields["idempotency_key"], Json::string("rabbita-group_trim-1"))
  let next = update(_ => @rabbita.none, RollSelection(1), original).1
  assert_true(next.busy)
  assert_eq(next.request_sequence, 1)
  assert_eq(clips(next)[0].source_out_tick, 3000)
  assert_eq(clips(next)[2].start_tick, 4000)
  assert_eq(next.undo_stack.length(), 0)
  let again = update(_ => @rabbita.none, RollSelection(1), next).1
  assert_eq(again.request_sequence, 1)
  assert_true(again.error.contains("Wait"))
}

///|
test "rolling editor guards stale project loading busy and absent source metadata" {
  let original = roll_ui_model()
  for
    model in [
      { ..original, project_id: "other", },
      { ..original, loading: true, },
      { ..original, busy: true, },
      {
        ..original,
        workspace: Some({ ..original.workspace.unwrap(), take_variants: None, }),
      },
    ] {
    assert_true(selected_roll_plan(model, 1) is Err(_))
    let next = update(_ => @rabbita.none, RollSelection(1), model).1
    assert_eq(next.request_sequence, 0)
    assert_true(next.error != "")
  }
  assert_true(selected_roll_plan(original, 0) is Err(_))
}

///|
test "rolling timeline renders connected controls and conservative blocker" {
  let model = roll_ui_model()
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(rolling_edit_controls(_ => @rabbita.none, model)),
  )
  assert_true(html.contains("Roll −1f"))
  assert_true(html.contains("Roll +1f"))
  assert_false(html.contains("disabled"))
  let empty = @rabbita.render_to_string(
    @rabbita.static_cell(
      rolling_edit_controls(_ => @rabbita.none, {
        ..model,
        selected_clip_ids: [],
      }),
    ),
  )
  assert_true(empty.contains("disabled"))
  assert_true(empty.contains("Select exactly two adjacent clips"))
}

///|
test "rolling reply from a previous project cannot change active project" {
  let model = roll_ui_model()
  let next = update(
      _ => @rabbita.none,
      ProjectReply(
        "other",
        model.open_generation,
        CommandFinished("group_trim", {}, Ok({})),
      ),
      model,
    ).1
  assert_eq(next.project_id, "p")
  assert_eq(next.request_sequence, model.request_sequence)
  assert_eq(next.error, "")
}
