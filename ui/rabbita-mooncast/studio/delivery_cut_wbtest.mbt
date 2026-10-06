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
  {
    ..initial_model(),
    tab: Delivery,
    loading: false,
    selected_project_id: project.id,
    project: Some(project),
    delivery_cut_start: start,
    delivery_cut_end: end,
  }
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
test "cut selection requires a positive at-most-180-second interval within exact master" {
  let project = cut_fixture_project()
  assert_eq(
    delivery_cut_selection(cut_fixture_model("", "  "), project),
    Ok(None),
  )
  assert_eq(
    delivery_cut_selection(cut_fixture_model("12.250", "42.750"), project),
    Ok(Some({ start_ms: 12250, end_ms: 42750, })),
  )
  assert_eq(
    delivery_cut_selection(cut_fixture_model("60", "240"), project),
    Ok(Some({ start_ms: 60000, end_ms: 240000, })),
  )
  assert_eq(
    delivery_cut_selection(cut_fixture_model("0", "0.001"), project),
    Ok(Some({ start_ms: 0, end_ms: 1, })),
  )
  for
    (start, end) in [
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
    assert_true(
      delivery_cut_selection(cut_fixture_model(start, end), project) is Err(_),
    )
  }
  assert_true(
    delivery_cut_selection(cut_fixture_model("0", "1"), {
      ..project,
      master: None,
    })
    is Err(_),
  )
  let master = project.master.unwrap()
  assert_true(
    delivery_cut_selection(cut_fixture_model("0", "1"), {
      ..project,
      master: Some({ ..master, media: { duration_seconds: 0, }, }),
    })
    is Err(_),
  )
}

///|
test "delivery profile keeps master variants and exact selected cut with captions enabled" {
  let profile = delivery_profile(Some({ start_ms: 12250, end_ms: 42750, }))
  match profile {
    {
      "cuts": Array([cut]),
      "include_source_master": True,
      "include_subtitles": True,
      "variants": Array(variants),
      ..
    } => {
      assert_eq(cut, {
        "cut_id": "selected-cut",
        "channel": "review-only",
        "source_variant": "master",
        "in_seconds": 12.25,
        "out_seconds": 42.75,
      })
      assert_eq(variants.length(), 2)
    }
    _ => fail("selected cut or existing delivery profile was lost")
  }
  assert_true(
    delivery_profile(None)
    is { "cuts": Array([]), "include_subtitles": True, .. },
  )
}

///|
test "delivery cut reducer validates before submission and ignores repeated create while busy" {
  let model = cut_fixture_model("", "")
  let edited = step(
    step(model, SetDeliveryCutStart("12.250")),
    SetDeliveryCutEnd("42.750"),
  )
  assert_eq(edited.delivery_cut_start, "12.250")
  assert_eq(edited.delivery_cut_end, "42.750")
  let started = step(edited, CreateDeliveryBuild)
  assert_true(started.busy)
  assert_eq(started.error, None)
  let repeated = step(started, CreateDeliveryBuild)
  assert_eq(repeated.command_sequence, started.command_sequence)
  assert_eq(repeated.status, started.status)
  assert_true(repeated.busy)
  for (start, end) in [("0", ""), ("0", "181"), ("239", "241"), ("NaN", "10")] {
    let rejected = step(cut_fixture_model(start, end), CreateDeliveryBuild)
    assert_false(rejected.busy)
    assert_true(rejected.error is Some(_))
  }
  assert_true(step(model, CreateDeliveryBuild).busy)
}

///|
test "selected cut preview shows exact source and boundary rule without changing master preview" {
  let model = cut_fixture_model("12.250", "42.750")
  let html = rendered(render_delivery(_ => @rabbita.none, model, model.project))
  assert_true(html.contains("Cut start (seconds)"))
  assert_true(html.contains("Cut end (seconds)"))
  assert_false(
    html.split("Create delivery build").to_array()[0].contains("disabled"),
  )
  assert_true(html.contains("value=\"12.250\""))
  assert_true(html.contains("value=\"42.750\""))
  assert_true(html.contains("Promoted master · approved-master · v3"))
  assert_true(html.contains("sha256:master-file"))
  assert_true(
    html.contains(
      "selected-cut · source master · 12250–42750 ms · 30500 ms long",
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
  let no_cut = cut_fixture_model("", "")
  let blank = rendered(
    render_delivery(_ => @rabbita.none, no_cut, no_cut.project),
  )
  assert_true(blank.contains("No cut selected"))
  assert_false(blank.contains("delivery-captions/cut/"))
  let invalid = cut_fixture_model("0", "181")
  let rejected = rendered(
    render_delivery(_ => @rabbita.none, invalid, invalid.project),
  )
  assert_true(rejected.contains("at most 180 seconds long"))
  assert_false(rejected.contains("delivery-captions/cut/"))
  assert_true(
    rejected.split("Create delivery build").to_array()[0].contains("disabled"),
  )
}

///|
test "cut selection revalidates against refreshed master and escapes its identity" {
  let model = cut_fixture_model("200", "230")
  let project = cut_fixture_project()
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
  let html = rendered(render_delivery(_ => @rabbita.none, model, Some(newer)))
  assert_true(html.contains("Cut end exceeds the promoted master duration"))
  assert_false(html.contains("delivery-captions/cut/"))
  assert_true(html.contains("&lt;script&gt;new-master&lt;/script&gt; · v4"))
  assert_true(html.contains("sha256:new-master-file"))
  assert_false(html.contains("sha256:master-file"))
  assert_false(html.contains("<script>new-master</script>"))
  let rejected = step({ ..model, project: Some(newer), }, CreateDeliveryBuild)
  assert_false(rejected.busy)
  assert_eq(
    rejected.error,
    Some("Cut end exceeds the promoted master duration."),
  )
}

///|
test "cut form resets on project change and empty selection but survives same-project refresh" {
  let model = cut_fixture_model("12.250", "42.750")
  let refreshed = step(model, RefreshProject)
  assert_eq(refreshed.delivery_cut_start, "12.250")
  assert_eq(refreshed.delivery_cut_end, "42.750")
  let changed = step(model, SelectProject("caption-project-B"))
  assert_eq(changed.delivery_cut_start, "")
  assert_eq(changed.delivery_cut_end, "")
  let returned = step(changed, SelectProject("caption-cut-project"))
  assert_eq(returned.delivery_cut_start, "")
  assert_eq(returned.delivery_cut_end, "")
  let cleared = step(model, SelectProject(""))
  assert_eq(cleared.delivery_cut_start, "")
  assert_eq(cleared.delivery_cut_end, "")
  let other = cut_fixture_project()
  let other = { ..other, id: "caption-project-B", }
  let html = rendered(
    render_delivery(
      _ => @rabbita.none,
      { ..changed, project: Some(other), },
      Some(other),
    ),
  )
  assert_false(html.contains("caption-cut-project/delivery-captions"))
  assert_false(html.contains("delivery-captions/cut/"))
  assert_true(html.contains("caption-project-B/delivery-captions/view"))
}
