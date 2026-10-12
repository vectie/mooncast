///|
fn cut_player_fixture() -> Model {
  let model = step(cut_fixture_model("1.250", "3.750"), SelectCutPlayer(1))
  let player = model.cut_player.unwrap()
  let master = model.project.unwrap().master.unwrap()
  step(
    model,
    LoadedCutPlayer(
      player.generation,
      Ok({
        contract: "mooncast.promoted-master-playback.v1",
        project_id: player.project_id,
        master_id: master.master_id,
        master_sha256: master.sha256,
        duration_seconds: 240,
        job_id: "exact-promoted-export",
        media_url: "/api/editor/projects/" +
        player.project_id +
        "/exports/exact-promoted-export/media?master_sha256=sha256:master-file",
      }),
    ),
  )
}

///|
fn cut_player_ready() -> Model {
  let model = cut_player_fixture()
  step(
    model,
    CutPlayerEvent(model.cut_player_generation, "metadata", 0.0, 240.0),
  )
}

///|
test "playback query digest preserves native prefix and adds it for bare canonical digests" {
  let original = cut_player_fixture()
  let projection = original.cut_player.unwrap().projection.unwrap()
  let project = original.project.unwrap()
  let bare = {
    ..original,
    project: Some({
      ..project,
      master: Some({ ..project.master.unwrap(), sha256: "master-file", }),
    }),
  }
  let bare = edit_delivery_cuts(bare, RebindDeliveryCuts)
  let pending = step(bare, SelectCutPlayer(1))
  let accepted = step(
    pending,
    LoadedCutPlayer(
      pending.cut_player_generation,
      Ok({ ..projection, master_sha256: "master-file", }),
    ),
  )
  assert_true(accepted.cut_player.unwrap().projection is Some(_))
  let rejected = step(
    pending,
    LoadedCutPlayer(
      pending.cut_player_generation,
      Ok({
        ..projection,
        master_sha256: "master-file",
        media_url: "/api/editor/projects/caption-cut-project/exports/exact-promoted-export/media?master_sha256=master-file",
      }),
    ),
  )
  assert_true(rejected.cut_player.unwrap().projection is None)
}

///|
test "explicit preview retry clears recoverable play error but not hard media failure" {
  let ready = cut_player_ready()
  let failed = step(
    ready,
    CutPlayerEvent(ready.cut_player_generation, "play-error", 1.25, 240.0),
  )
  assert_true(failed.cut_player.unwrap().ready)
  assert_true(failed.cut_player.unwrap().error is Some(_))
  assert_true(
    step(failed, PreviewCutPlayer(failed.cut_player_generation)).cut_player.unwrap().error
    is None,
  )
  let hard = step(
    ready,
    CutPlayerEvent(ready.cut_player_generation, "error", 1.25, 240.0),
  )
  assert_false(hard.cut_player.unwrap().ready)
  assert_true(
    step(hard, PreviewCutPlayer(hard.cut_player_generation)).cut_player.unwrap().error
    is Some(_),
  )
}

///|
test "mark timestamps round nearest milliseconds while manual decimal boundaries stay exact" {
  for
    (seconds, text) in [
      (0.0, "0.000"),
      (1.2344, "1.234"),
      (1.2345, "1.235"),
      (179.9999, "180.000"),
      (240.0, "240.000"),
    ] {
    assert_eq(cut_player_mark_text(seconds), text)
  }
  assert_eq(cut_player_mark_text(-0.1), "")
  install_cut_storage("ok")
  defer restore_cut_storage()
  let model = cut_player_ready()
  let marked = step(
    model,
    CutPlayerEvent(model.cut_player_generation, "mark-start", 1.2345, 240.0),
  )
  assert_eq(delivery_cut_drafts(marked).cuts[0].start, "1.235")
  assert_eq(delivery_cut_drafts(marked).cuts[0].end, "3.750")
  assert_eq(marked.command_sequence, model.command_sequence)
  assert_false(marked.busy)
  let saved = decode_delivery_cut_draft(
    model.selected_project_id,
    match
      @json.parse(
        delivery_cut_storage_read(
          delivery_cut_storage_key(model.selected_project_id),
        ),
      ) {
      { "value": String(value), .. } => value
      _ => fail("No autosave")
    },
  ).unwrap()
  assert_eq(saved, delivery_cut_drafts(marked))
}

///|
test "metadata unavailable media error retry and stale callbacks cannot mark" {
  let model = cut_player_fixture()
  assert_false(model.cut_player.unwrap().ready)
  assert_eq(
    delivery_cut_drafts(
      step(
        model,
        CutPlayerEvent(model.cut_player_generation, "mark-start", 2.0, 240.0),
      ),
    ),
    delivery_cut_drafts(model),
  )
  let missing = step(
    model,
    CutPlayerEvent(model.cut_player_generation, "unavailable", 0.0, 0.0),
  )
  assert_true(missing.cut_player.unwrap().error is Some(_))
  assert_false(
    step(
      missing,
      CutPlayerEvent(model.cut_player_generation, "metadata", 0.0, 240.0),
    ).cut_player.unwrap().ready,
  )
  let ready = cut_player_ready()
  let failed = step(
    ready,
    CutPlayerEvent(ready.cut_player_generation, "error", 1.0, 240.0),
  )
  assert_false(failed.cut_player.unwrap().ready)
  let retried = step(failed, RetryCutPlayer)
  assert_true(retried.cut_player_generation > failed.cut_player_generation)
  assert_true(retried.cut_player.unwrap().loading)
  let stale = step(
    retried,
    CutPlayerEvent(ready.cut_player_generation, "mark-end", 2.0, 240.0),
  )
  assert_eq(delivery_cut_drafts(stale), delivery_cut_drafts(ready))
  assert_true(stale.cut_player.unwrap().loading)
}

///|
test "selected range reuses native-facing validation for reversed equal fractional and limit boundaries" {
  let ready = cut_player_ready()
  for
    (start, finish, valid) in [
      ("0", "180", true),
      ("0.001", "180.001", true),
      ("60", "240", true),
      ("0", "180.001", false),
      ("1.001", "1.000", false),
      ("2", "2", false),
      ("0", "240.001", false),
      ("0.0001", "1", false),
    ] {
    let model = edit_delivery_cuts(
      edit_delivery_cuts(ready, EditDeliveryCut(1, "start", start)),
      EditDeliveryCut(1, "end", finish),
    )
    assert_eq(
      cut_player_range(model, model.cut_player.unwrap()) is Ok(_),
      valid,
    )
    assert_eq(
      step(model, PreviewCutPlayer(model.cut_player_generation)).command_sequence,
      ready.command_sequence,
    )
  }
  let short = step(
    ready,
    CutPlayerEvent(ready.cut_player_generation, "metadata", 0.0, 2.0),
  )
  assert_true(cut_player_range(short, short.cut_player.unwrap()) is Err(_))
}

///|
test "player binds project master row and generation across A B A removal close and tab changes" {
  let ready = cut_player_ready()
  let event = CutPlayerEvent(
    ready.cut_player_generation,
    "mark-end",
    2.0,
    240.0,
  )
  let b = step(ready, SelectProject("other"))
  let returned = step(b, SelectProject(ready.selected_project_id))
  assert_true(returned.cut_player is None)
  assert_eq(
    delivery_cut_drafts(step(returned, event)),
    delivery_cut_drafts(ready),
  )
  let removed = step(ready, RemoveDeliveryCut(1))
  let reused = step(removed, AddDeliveryCut)
  assert_eq(delivery_cut_drafts(reused).cuts[0].key, 1)
  assert_eq(delivery_cut_drafts(step(reused, event)).cuts[0].end, "")
  assert_true(step(ready, CloseCutPlayer).cut_player is None)
  assert_true(step(ready, SelectTab(Overview)).cut_player is None)
  assert_true(step(ready, RefreshProject).cut_player is None)
  let project = ready.project.unwrap()
  let changed = {
    ..ready,
    project: Some({
      ..project,
      master: Some({ ..project.master.unwrap(), sha256: "sha256:changed", }),
    }),
  }
  assert_true(current_cut_player(changed) is None)
  assert_eq(
    delivery_cut_drafts(step(changed, event)),
    delivery_cut_drafts(ready),
  )
}

///|
test "projection fails closed for foreign master identity and external or changed media URLs" {
  let ready = cut_player_fixture()
  let projection = ready.cut_player.unwrap().projection.unwrap()
  for
    wrong in [
      { ..projection, master_sha256: "sha256:other", },
      { ..projection, project_id: "foreign", },
      { ..projection, master_id: "other-master", },
      { ..projection, duration_seconds: 180, },
      { ..projection, media_url: "https://example.invalid/master.mp4", },
    ] {
    let pending = step(ready, RetryCutPlayer)
    let rejected = step(
      pending,
      LoadedCutPlayer(pending.cut_player_generation, Ok(wrong)),
    )
    assert_true(rejected.cut_player.unwrap().error is Some(_))
    assert_true(rejected.cut_player.unwrap().projection is None)
  }
}

///|
test "autosave failure retains marked cut with explicit retry notice and no command submission" {
  install_cut_storage("write-error")
  defer restore_cut_storage()
  let ready = cut_player_ready()
  let failed = step(
    ready,
    CutPlayerEvent(ready.cut_player_generation, "mark-end", 2.501, 240.0),
  )
  assert_eq(delivery_cut_drafts(failed).cuts[0].end, "2.501")
  assert_true(
    delivery_cut_storage_notice(failed) is Some(message) &&
    message.contains("autosave failed"),
  )
  assert_eq(failed.command_sequence, ready.command_sequence)
  cut_storage_mode("ok")
  assert_true(
    delivery_cut_storage_notice(step(failed, SaveDeliveryCutDrafts)) is None,
  )
}

///|
test "prebuild player labels original master timing and leaves historical inspector available" {
  let ready = cut_player_ready()
  let html = rendered(render_cut_player(_ => @rabbita.none, ready))
  assert_true(html.contains("Mark in"))
  assert_true(html.contains("Mark out"))
  assert_true(html.contains("Preview selected range"))
  assert_true(html.contains("original master"))
  assert_true(html.contains("No delivery is built"))
  assert_true(html.contains("master_sha256=sha256:master-file"))
  assert_true(
    rendered(
      render_delivery_media(
        _ => @rabbita.none,
        media_fixture_model(),
        media_fixture_model().delivery_builds[0],
      ),
    ).contains("Inspect individual videos"),
  )
}
