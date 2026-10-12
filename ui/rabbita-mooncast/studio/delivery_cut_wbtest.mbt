///|
fn cut_fixture_project() -> ProjectProjection {
  {
    ..fixture_project("caption-cut-project", 7),
    master: Some({
      master_id: "approved-master",
      version: 3,
      digest: "sha256:master-record",
      sha256: "sha256:master-file",
      media: { duration_seconds: 240, },
    }),
    delivery_package: Some({
      version: 2,
      digest: "sha256:delivery-record",
      content: {
        master_digest: "sha256:master-record",
        formats: [],
        destinations: [],
        provenance_included: true,
        manifest_digest: "sha256:manifest",
        rights_ledger_digest: "sha256:rights",
      },
    }),
  }
}

///|
fn cut_fixture_model(start : String, end : String) -> Model {
  let project = cut_fixture_project()
  let model = {
    ..initial_model(),
    tab: Delivery,
    loading: false,
    selected_project_id: project.id,
    project: Some(project),
  }
  let model = edit_delivery_cuts(model, AddDeliveryCut)
  let model = edit_delivery_cuts(model, EditDeliveryCut(1, "start", start))
  edit_delivery_cuts(model, EditDeliveryCut(1, "end", end))
}

///|
test "cut seconds preserve exact milliseconds and reject non-finite or ambiguous input" {
  for
    (text, milliseconds) in [
      ("0", 0),
      ("12.250", 12250),
      (" 42.75 ", 42750),
      ("0.001", 1),
      ("2147483.647", 2147483647),
    ] {
    assert_eq(delivery_cut_milliseconds(text), Some(milliseconds))
  }
  for
    text in [
      "", "NaN", "Infinity", "-Infinity", "1e2", "-1", "+1", "0.0001", "1.", ".1",
      "1.2.3", "1,200", "2147483.648", "2147484", "999999999999999999999999999999999999",
      "1x",
    ] {
    assert_eq(delivery_cut_milliseconds(text), None)
  }
}

///|
test "cuts require positive at-most-180-second intervals within the exact master" {
  assert_eq(delivery_cut_range("12.250", "42.750", 240), Ok((12250, 42750)))
  assert_eq(delivery_cut_range("60", "240", 240), Ok((60000, 240000)))
  assert_eq(delivery_cut_range("0", "0.001", 240), Ok((0, 1)))
  for
    (start, end) in [
      ("", ""),
      ("0", ""),
      ("", "1"),
      ("0", "0"),
      ("12", "11"),
      ("0", "180.001"),
      ("200", "240.001"),
      ("NaN", "1"),
      ("0", "Infinity"),
      ("-1", "1"),
      ("0", "0.0001"),
    ] {
    let model = cut_fixture_model(start, end)
    assert_true(delivery_cut_selection(model, model.project.unwrap()) is Err(_))
    assert_false(step(model, CreateDeliveryBuild).busy)
  }
  let model = cut_fixture_model("0", "1")
  assert_true(
    delivery_cut_selection(model, { ..cut_fixture_project(), master: None, })
    is Err(_),
  )
}

///|
test "bounded list edits preserve stable row identity and selected-only delivery" {
  let first = cut_fixture_model("12.250", "42.750")
  let mut model = first
  for _ in 0..<13 {
    model = edit_delivery_cuts(model, AddDeliveryCut)
  }
  assert_eq(delivery_cut_drafts(model).cuts.length(), 12)
  assert_true(model.error is Some(_))
  model = edit_delivery_cuts(
    model,
    EditDeliveryCut(2, "name", "portrait-teaser"),
  )
  model = edit_delivery_cuts(
    model,
    EditDeliveryCut(2, "source", "vertical-1080p"),
  )
  model = edit_delivery_cuts(model, EditDeliveryCut(2, "channel", "shorts"))
  model = edit_delivery_cuts(model, EditDeliveryCut(2, "start", "45.500"))
  model = edit_delivery_cuts(model, EditDeliveryCut(2, "end", "60.001"))
  for key in 3..<=12 {
    model = edit_delivery_cuts(model, ToggleDeliveryCut(key))
  }
  let selection = delivery_cut_selection(model, model.project.unwrap()).unwrap()
  assert_eq(selection.length(), 2)
  assert_eq(selection[1], {
    cut_id: "portrait-teaser",
    channel: "shorts",
    source_variant: "vertical-1080p",
    start_ms: 45500,
    end_ms: 60001,
  })
  model = edit_delivery_cuts(model, RemoveDeliveryCut(1))
  model = edit_delivery_cuts(
    model,
    EditDeliveryCut(2, "name", "retained-second"),
  )
  assert_eq(delivery_cut_drafts(model).cuts[0].cut_id, "retained-second")
  assert_eq(delivery_cut_drafts(first).cuts[0].cut_id, "cut-1")
  assert_eq(
    edit_delivery_cuts({ ..model, busy: true, }, RemoveDeliveryCut(2)).delivery_cut_drafts,
    model.delivery_cut_drafts,
  )
}

///|
test "named selections reject collisions unsafe names sources and channels but allow shared ranges" {
  let mut model = edit_delivery_cuts(
    cut_fixture_model("1", "3"),
    AddDeliveryCut,
  )
  model = edit_delivery_cuts(model, EditDeliveryCut(2, "start", "1"))
  model = edit_delivery_cuts(model, EditDeliveryCut(2, "end", "3"))
  assert_eq(
    delivery_cut_selection(model, model.project.unwrap()).unwrap().length(),
    2,
  )
  for
    invalid in [
      "", "../cut", "-cut", "a/b", "<script>", "master", "MASTER", "Horizontal-1080p",
      "horizontal-1080p", "vertical-1080p", "CUT-1",
    ] {
    let edited = edit_delivery_cuts(model, EditDeliveryCut(2, "name", invalid))
    assert_true(
      delivery_cut_selection(edited, edited.project.unwrap()) is Err(_),
    )
  }
  for
    (field, value) in [
      ("channel", "  "),
      ("source", "cut-1"),
      ("source", "unknown"),
    ] {
    let edited = edit_delivery_cuts(model, EditDeliveryCut(2, field, value))
    assert_true(
      delivery_cut_selection(edited, edited.project.unwrap()) is Err(_),
    )
  }
  let excluded = edit_delivery_cuts(
    edit_delivery_cuts(model, EditDeliveryCut(2, "name", "CUT-1")),
    ToggleDeliveryCut(2),
  )
  assert_eq(
    delivery_cut_selection(excluded, excluded.project.unwrap())
    .unwrap()
    .length(),
    1,
  )
}

///|
test "delivery profile includes every exact selected cut and retains master variants captions rights" {
  let mut model = cut_fixture_model("12.250", "42.750")
  model = edit_delivery_cuts(model, AddDeliveryCut)
  model = edit_delivery_cuts(model, EditDeliveryCut(2, "start", "70"))
  model = edit_delivery_cuts(model, EditDeliveryCut(2, "end", "90"))
  model = edit_delivery_cuts(
    model,
    EditDeliveryCut(2, "source", "vertical-1080p"),
  )
  let profile = delivery_profile(
    delivery_cut_selection(model, model.project.unwrap()).unwrap(),
  )
  guard profile
    is {
      "cuts": Array(cuts),
      "variants": Array(variants),
      "include_source_master": True,
      "include_subtitles": True,
      "include_provenance_rights_ai_manifest": True,
      ..
    } else {
    fail("missing required profile fields")
  }
  assert_eq(variants.length(), 2)
  assert_eq(cuts.length(), 2)
  assert_eq(cuts[0], {
    "cut_id": "cut-1",
    "channel": "review-only",
    "source_variant": "master",
    "in_seconds": 12.25,
    "out_seconds": 42.75,
  })
  assert_eq(cuts[1], {
    "cut_id": "cut-2",
    "channel": "review-only",
    "source_variant": "vertical-1080p",
    "in_seconds": 70,
    "out_seconds": 90,
  })
  assert_true(
    delivery_profile([]) is { "cuts": Array([]), "include_subtitles": True, .. },
  )
}

///|
test "delivery submission ignores repeated clicks and retains edits while busy" {
  let model = cut_fixture_model("12.250", "42.750")
  let started = step(model, CreateDeliveryBuild)
  assert_true(started.busy)
  let repeated = step(started, CreateDeliveryBuild)
  assert_eq(repeated.command_sequence, started.command_sequence)
  assert_eq(repeated.status, started.status)
  assert_eq(
    step(started, RemoveDeliveryCut(1)).delivery_cut_drafts,
    started.delivery_cut_drafts,
  )
  let none = edit_delivery_cuts(model, ToggleDeliveryCut(1))
  assert_eq(delivery_cut_selection(none, none.project.unwrap()), Ok([]))
  assert_true(step(none, CreateDeliveryBuild).busy)
}

///|
test "cut preview shows exact source and boundaries and escapes labels" {
  let model = cut_fixture_model("12.250", "42.750")
  let html = rendered(render_delivery(_ => @rabbita.none, model, model.project))
  assert_true(html.contains("Named channel cuts"))
  assert_true(html.contains("Cut start (seconds)"))
  assert_true(html.contains("value=\"12.250\""))
  assert_true(html.contains("Promoted master · approved-master · v3"))
  assert_true(
    html.contains(
      "cut-1 · channel review-only · source master · 12250–42750 ms · 30500 ms long",
    ),
  )
  assert_true(
    html.contains(
      "/api/v2/projects/caption-cut-project/delivery-captions/cut/12250/42750/view",
    ),
  )
  assert_true(
    html.contains("/api/v2/projects/caption-cut-project/delivery-captions/view"),
  )
  assert_true(html.contains("clipped to its boundaries and rebased"))
  assert_true(
    html.contains(
      "Reordering, speed changes and cut chains require a corrected Cut Editor export",
    ),
  )
  let none = edit_delivery_cuts(model, ToggleDeliveryCut(1))
  let blank = rendered(render_delivery(_ => @rabbita.none, none, none.project))
  assert_true(blank.contains("No cuts selected"))
  assert_false(blank.contains("delivery-captions/cut/"))
  let escaped = edit_delivery_cuts(
    model,
    EditDeliveryCut(1, "channel", "<script>unsafe</script>"),
  )
  let safe_html = rendered(
    render_delivery(_ => @rabbita.none, escaped, escaped.project),
  )
  assert_false(safe_html.contains("<script>unsafe</script>"))
  assert_true(safe_html.contains("&lt;script&gt;unsafe&lt;/script&gt;"))
}

///|
test "changed promoted master blocks cut reuse until explicit rebind and range validation" {
  let model = cut_fixture_model("200", "230")
  let project = model.project.unwrap()
  let master = project.master.unwrap()
  let newer = {
    ..project,
    master: Some({
      ..master,
      master_id: "<script>new-master</script>",
      version: 4,
      sha256: "sha256:new-master-file",
      media: { duration_seconds: 220, },
    }),
  }
  let model = { ..model, project: Some(newer), }
  assert_false(step(model, CreateDeliveryBuild).busy)
  let html = rendered(render_delivery(_ => @rabbita.none, model, model.project))
  assert_true(html.contains("Use current master"))
  assert_false(html.contains("delivery-captions/cut/"))
  assert_true(html.contains("&lt;script&gt;new-master&lt;/script&gt; · v4"))
  let rebound = edit_delivery_cuts(model, RebindDeliveryCuts)
  assert_true(
    delivery_cut_selection(rebound, newer) is Err(message) &&
    message.contains("exceeds the promoted master"),
  )
  let valid = edit_delivery_cuts(rebound, EditDeliveryCut(1, "end", "220"))
  assert_true(delivery_cut_selection(valid, newer) is Ok(_))
}

///|
test "cut edits survive project refresh and A B A switches without cross-project selection" {
  let model = cut_fixture_model("12.250", "42.750")
  assert_eq(
    delivery_cut_drafts(step(model, RefreshProject)),
    delivery_cut_drafts(model),
  )
  let changed = step(model, SelectProject("caption-project-B"))
  assert_true(delivery_cut_drafts(changed).cuts.is_empty())
  let returned = step(changed, SelectProject("caption-cut-project"))
  assert_eq(delivery_cut_drafts(returned), delivery_cut_drafts(model))
  assert_true(
    delivery_cut_drafts(step(model, SelectProject(""))).cuts.is_empty(),
  )
  let other = { ..cut_fixture_project(), id: "caption-project-B", }
  let html = rendered(
    render_delivery(
      _ => @rabbita.none,
      { ..changed, project: Some(other), },
      Some(other),
    ),
  )
  assert_false(html.contains("caption-cut-project/delivery-captions"))
  assert_false(html.contains("delivery-captions/cut/"))
  assert_true(delivery_cut_selection(changed, model.project.unwrap()) is Err(_))
}
