///|
fn cover_fixture_model(timestamp : String) -> Model {
  let model = edit_delivery_cuts(
    cut_fixture_model("1", "3"),
    ToggleDeliveryCut(1),
  )
  edit_delivery_covers(
    edit_delivery_covers(model, AddDeliveryCover),
    EditDeliveryCover(1, "timestamp", timestamp),
  )
}

///|
test "covers accept exact ms at zero and before end but reject incomplete nonfinite and end frame" {
  for timestamp in ["0", "12.250", "239.999"] {
    let model = cover_fixture_model(timestamp)
    assert_true(
      delivery_cover_selection(model, model.project.unwrap()) is Ok(_),
    )
    assert_true(step(model, CreateDeliveryBuild).busy)
  }
  for
    timestamp in [
      "", "-1", "NaN", "Infinity", "1e2", "240", "240.001", "0.0001", "2147483.648",
    ] {
    let model = cover_fixture_model(timestamp)
    assert_true(
      delivery_cover_selection(model, model.project.unwrap()) is Err(_),
    )
    assert_false(step(model, CreateDeliveryBuild).busy)
  }
  let model = cover_fixture_model("12.250")
  assert_eq(
    delivery_cover_selection(model, model.project.unwrap()).unwrap()[0].timestamp_ms,
    12250,
  )
}

///|
test "cover rows are bounded stable selected only and cannot collide with cuts or variants" {
  let mut model = cover_fixture_model("12.250")
  for _ in 0..<9 {
    model = edit_delivery_covers(model, AddDeliveryCover)
  }
  assert_eq(delivery_cover_drafts(model).covers.length(), 8)
  assert_true(model.error is Some(_))
  for key in 2..<=8 {
    model = edit_delivery_covers(model, ToggleDeliveryCover(key))
  }
  assert_eq(
    delivery_cover_selection(model, model.project.unwrap()).unwrap().length(),
    1,
  )
  for
    (field, value) in [
      ("name", "../bad"),
      ("name", "MASTER"),
      ("name", "Vertical-1080p"),
      ("source", "cut-1"),
      ("format", "gif"),
    ] {
    let invalid = edit_delivery_covers(
      model,
      EditDeliveryCover(1, field, value),
    )
    assert_true(
      delivery_cover_selection(invalid, invalid.project.unwrap()) is Err(_),
    )
  }
  let cuts = edit_delivery_cuts(model, ToggleDeliveryCut(1))
  let collision = edit_delivery_covers(
    cuts,
    EditDeliveryCover(1, "name", "CUT-1"),
  )
  assert_true(
    delivery_cover_selection(collision, collision.project.unwrap()) is Err(_),
  )
  let collision = edit_delivery_covers(
    edit_delivery_covers(model, ToggleDeliveryCover(2)),
    EditDeliveryCover(2, "name", "COVER-1"),
  )
  assert_true(
    delivery_cover_selection(collision, collision.project.unwrap()) is Err(_),
  )
  let removed = edit_delivery_covers(model, RemoveDeliveryCover(1))
  let edited = edit_delivery_covers(
    removed,
    EditDeliveryCover(2, "name", "retained-row"),
  )
  assert_eq(delivery_cover_drafts(edited).covers[0].cover_id, "retained-row")
  assert_eq(delivery_cover_drafts(model).covers[0].cover_id, "cover-1")
  assert_eq(
    edit_delivery_covers({ ..model, busy: true, }, RemoveDeliveryCover(1)).delivery_cover_drafts,
    model.delivery_cover_drafts,
  )
}

///|
test "cover profile preserves named cuts captions variants rights and exact image settings" {
  let model = edit_delivery_cuts(
    cover_fixture_model("12.250"),
    ToggleDeliveryCut(1),
  )
  let model = edit_delivery_covers(
    model,
    EditDeliveryCover(1, "source", "vertical-1080p"),
  )
  let model = edit_delivery_covers(model, EditDeliveryCover(1, "format", "jpg"))
  let profile = delivery_profile(
    delivery_cut_selection(model, model.project.unwrap()).unwrap(),
    covers=delivery_cover_selection(model, model.project.unwrap()).unwrap(),
  )
  assert_true(
    profile
    is {
      "covers": [
        {
          "cover_id": "cover-1",
          "source_variant": "vertical-1080p",
          "timestamp_seconds": 12.25,
          "format": "jpg",
        },
      ],
      "cuts": Array([_]),
      "variants": Array([_, _]),
      "include_subtitles": True,
      "include_provenance_rights_ai_manifest": True,
      ..
    },
  )
  let html = rendered(render_delivery(_ => @rabbita.none, model, model.project))
  assert_true(html.contains("Timestamped covers"))
  assert_true(html.contains("cover-1 · vertical-1080p · 12250 ms · JPG"))
  assert_true(html.contains("Frame time (seconds)"))
}

///|
test "cover draft retains edits across refresh A B A and requires deliberate new master rebind" {
  let model = cover_fixture_model("239.999")
  assert_eq(
    delivery_cover_drafts(step(model, RefreshProject)),
    delivery_cover_drafts(model),
  )
  let other = step(model, SelectProject("other-project"))
  assert_true(delivery_cover_drafts(other).covers.is_empty())
  let returned = step(other, SelectProject(model.selected_project_id))
  assert_eq(delivery_cover_drafts(returned), delivery_cover_drafts(model))
  assert_true(delivery_cover_selection(other, model.project.unwrap()) is Err(_))
  let project = model.project.unwrap()
  let next = {
    ..project,
    master: Some({
      ..project.master.unwrap(),
      sha256: "sha256:new-master",
      media: { duration_seconds: 220, },
    }),
  }
  let stale = { ..model, project: Some(next), }
  assert_false(step(stale, CreateDeliveryBuild).busy)
  assert_true(
    rendered(render_delivery(_ => @rabbita.none, stale, stale.project)).contains(
      "Use current master for covers",
    ),
  )
  let rebound = edit_delivery_covers(stale, RebindDeliveryCovers)
  assert_true(delivery_cover_selection(rebound, next) is Err(_))
  let fixed = edit_delivery_covers(
    rebound,
    EditDeliveryCover(1, "timestamp", "219.999"),
  )
  assert_true(step(fixed, CreateDeliveryBuild).busy)
  let started = step(fixed, CreateDeliveryBuild)
  assert_eq(
    step(started, CreateDeliveryBuild).command_sequence,
    started.command_sequence,
  )
  assert_eq(
    step(started, RemoveDeliveryCover(1)).delivery_cover_drafts,
    started.delivery_cover_drafts,
  )
}

///|
test "cover storage preserves incomplete draft strings and cannot overwrite corrupt originals" {
  install_cut_storage("ok")
  let model = edit_delivery_covers(
    cover_fixture_model("12.250"),
    AddDeliveryCover,
  )
  let model = edit_delivery_covers(model, EditDeliveryCover(2, "timestamp", ""))
  let model = edit_delivery_covers(model, ToggleDeliveryCover(2))
  let saved = save_delivery_cover_drafts(model)
  let draft = delivery_cover_drafts(saved)
  let encoded = encode_delivery_cover_draft(model.selected_project_id, draft)
  assert_eq(
    decode_delivery_cover_draft(model.selected_project_id, encoded),
    Ok(draft),
  )
  assert_true(decode_delivery_cover_draft("foreign", encoded) is Err(_))
  let restored = load_delivery_cover_drafts(
    initial_model(),
    model.selected_project_id,
  )
  assert_eq(
    restored.delivery_cover_drafts.get(model.selected_project_id),
    Some(draft),
  )
  assert_true(
    decode_delivery_cover_draft(
      model.selected_project_id,
      encode_delivery_cover_draft(model.selected_project_id, {
        ..draft,
        covers: [draft.covers[0], draft.covers[0]],
      }),
    )
    is Err(_),
  )
  let key = delivery_cover_storage_key(model.selected_project_id)
  assert_eq(delivery_cover_storage_write(key, "original corrupt bytes"), "")
  let blocked = load_delivery_cover_drafts(
    initial_model(),
    model.selected_project_id,
  )
  let edited = save_delivery_cover_drafts(
    edit_delivery_covers(
      {
        ..blocked,
        project: model.project,
        selected_project_id: model.selected_project_id,
      },
      AddDeliveryCover,
    ),
  )
  assert_eq(delivery_cover_drafts(edited).covers.length(), 1)
  assert_true(
    delivery_cover_storage_read(key).contains("original corrupt bytes"),
  )
  assert_true(delivery_cover_storage_notice(edited) is Some(_))
  restore_cut_storage()
}

///|
test "cover storage quota failure retry is visible and isolated from cut autosave" {
  install_cut_storage("write-error")
  let model = save_delivery_cover_drafts(cover_fixture_model("1"))
  assert_true(delivery_cover_storage_notice(model) is Some(_))
  let edited = edit_delivery_covers(
    model,
    EditDeliveryCover(1, "name", "latest-cover"),
  )
  cut_storage_mode("ok")
  let saved = save_delivery_cover_drafts(edited)
  assert_eq(delivery_cover_storage_notice(saved), None)
  let restored = load_delivery_cover_drafts(
    initial_model(),
    model.selected_project_id,
  )
  assert_eq(
    restored.delivery_cover_drafts.get(model.selected_project_id).unwrap().covers[0].cover_id,
    "latest-cover",
  )
  assert_true(
    delivery_cut_storage_read(
      delivery_cut_storage_key(model.selected_project_id),
    ).contains("missing"),
  )
  cut_storage_mode("read-error")
  let unreadable = load_delivery_cover_drafts(
    initial_model(),
    model.selected_project_id,
  )
  assert_true(
    unreadable.delivery_cover_storage_blocked.contains(
      model.selected_project_id,
    ),
  )
  restore_cut_storage()
}

///|
test "completed cover gallery shows exact image download provenance and historic identity without acceptance" {
  let model = cover_fixture_model("1")
  let url = "/api/v2/projects/caption-cut-project/delivery-builds/build-one/covers/poster/digest"
  let build : DeliveryBuildProjection = {
    build_id: "build-one",
    build_digest: "build-digest",
    state: "completed",
    revision: 2,
    attempt_count: 1,
    recovery_count: 0,
    master_sha256: "sha256:master-file",
    delivery_digest: "delivery-digest",
    download_url: None,
    last_error: None,
    record_digest: "record-digest",
    publication_authority: false,
    videos: None,
    cover_frames: Some([
      {
        cover_id: "<poster>",
        source_variant: "master",
        timestamp_seconds: 1.25,
        format: "png",
        name: "build-one-poster.png",
        sha256: "sha256:image-digest",
        preview_url: url,
      },
    ]),
  }
  let html = rendered(render_delivery_build(_ => @rabbita.none, model, build))
  assert_true(html.contains("Cover preview"))
  assert_true(html.contains("src=\"" + url + "\""))
  assert_true(html.contains("href=\"" + url + "/download\""))
  assert_true(html.contains("&lt;poster&gt;"))
  assert_false(html.contains("<poster>"))
  assert_true(html.contains("1.25 seconds"))
  assert_true(html.contains("sha256:image-digest"))
  assert_false(model.operator.human_confirmed)
  assert_false(html.contains("Historical build:"))
  assert_false(
    rendered(
      render_delivery_cover_gallery(model, {
        ..build,
        master_sha256: "master-file",
      }),
    ).contains("Historical build:"),
  )
  let historical = rendered(
    render_delivery_cover_gallery(model, {
      ..build,
      master_sha256: "old-master",
    }),
  )
  assert_true(historical.contains("Historical build:"))
  assert_true(historical.contains(url))
  assert_false(
    rendered(
      render_delivery_cover_gallery(model, { ..build, state: "failed", }),
    ).contains("<img"),
  )
}
