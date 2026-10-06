///|
fn initialization_conversion(status : String?) -> ConversionProjection {
  {
    contract: "mooncast.quote-conversion.v1",
    quote_id: "accepted-quote",
    quote_version: 2,
    quote_digest: "sha256:accepted-quote-v2",
    capacity_digest: "sha256:accepted-capacity",
    project_id: "accepted-project",
    actor: "original-producer",
    actor_role: "producer",
    converted_at: "2026-10-04T00:00:00Z",
    digest: "sha256:original-conversion",
    payment_effect_performed: false,
    publication_authority: false,
    initialization_status: status,
  }
}

///|
fn initialization_dashboard(
  conversions : Array[ConversionProjection],
) -> CommercialDashboardProjection {
  {
    contract: "mooncast.commercial-intake-dashboard.v1",
    revision: 20,
    record_digest: "sha256:commercial-state",
    leads: [],
    quotes: [],
    resources: [],
    reservations: [],
    conversions,
    external_effects: false,
  }
}

///|
fn initialization_model() -> Model {
  let model = loaded_fixture("selected-project")
  {
    ..model,
    tab: Commercial,
    artifact_draft: "keep my local edit",
    selected_quote_id: "newer-selected-quote",
    commercial: Some(
      initialization_dashboard([initialization_conversion(Some("pending"))]),
    ),
    capacity_board: Some({
      contract: "fixture",
      quote_id: "newer-selected-quote",
      quote_version: 9,
      quote_digest: "sha256:newer-quote",
      reservations: [],
      utilization: [],
      conflicts: [{ "code": "capacity-changed" }],
      ready: false,
      calculated_at: "2026-10-05T00:00:00Z",
      digest: "sha256:newer-capacity",
    }),
    operator: {
      ..model.operator,
      human_confirmed: true,
      actor: "resuming-producer",
      role: "producer",
    },
  }
}

///|
test "adopted existing draft is preserved without claiming initialization or offering reseeding" {
  let model = {
    ..initialization_model(),
    commercial: Some(
      initialization_dashboard([
        initialization_conversion(Some("preserved-existing")),
      ]),
    ),
  }
  let panel = rendered(render_quote_initializations(_ => @rabbita.none, model))
  assert_true(panel.contains("existing draft preserved"))
  assert_true(panel.contains("missing legacy drafts were not inferred"))
  assert_false(panel.contains("original draft initialization is complete"))
  assert_false(panel.contains("Resume draft initialization"))
  assert_eq(
    quote_initialization_request(model, "sha256:original-conversion"),
    None,
  )
}

///|
test "draft initialization retry uses the stored quote and capacity with no latest quote available" {
  let model = initialization_model()
  let expected : Json = {
    "expected_version": 2,
    "expected_digest": "sha256:accepted-quote-v2",
    "expected_capacity_digest": "sha256:accepted-capacity",
    "human_confirmed": true,
    "actor": "resuming-producer",
    "actor_role": "producer",
  }
  assert_eq(
    quote_initialization_request(model, "sha256:original-conversion"),
    Some(("/api/commercial-intake/quotes/accepted-quote/conversion", expected)),
  )
  assert_eq(
    quote_initialization_request(
      { ..model, capacity_board: None, selected_quote_id: "", },
      "sha256:original-conversion",
    ),
    Some(("/api/commercial-intake/quotes/accepted-quote/conversion", expected)),
  )
}

///|
test "draft initialization reducer preserves focus and drafts and suppresses duplicate clicks" {
  let model = initialization_model()
  let started = step(
    model,
    ResumeQuoteInitialization("sha256:original-conversion"),
  )
  assert_true(started.busy)
  assert_eq(started.error, None)
  assert_eq(started.selected_project_id, model.selected_project_id)
  assert_eq(started.selected_quote_id, model.selected_quote_id)
  assert_eq(started.project.map(p => p.id), Some("selected-project"))
  assert_eq(started.artifact_draft, "keep my local edit")
  assert_eq(
    started.capacity_board.map(b => b.digest),
    Some("sha256:newer-capacity"),
  )
  assert_true(started.status.contains("Resuming"))
  let duplicate = step(
    started,
    ResumeQuoteInitialization("sha256:original-conversion"),
  )
  assert_eq(duplicate.status, started.status)
  assert_eq(duplicate.error, started.error)
  assert_eq(duplicate.command_sequence, started.command_sequence)
  assert_eq(
    quote_initialization_request(duplicate, "sha256:original-conversion"),
    None,
  )
  let other_click = step(started, ConvertQuote)
  assert_eq(other_click.status, started.status)
  assert_eq(other_click.error, None)
}

///|
test "draft initialization rejects unconfirmed missing ambiguous completed and untracked retries" {
  let model = initialization_model()
  let digest = "sha256:original-conversion"
  let unconfirmed = {
    ..model,
    operator: { ..model.operator, human_confirmed: false, },
  }
  assert_eq(quote_initialization_request(unconfirmed, digest), None)
  assert_false(step(unconfirmed, ResumeQuoteInitialization(digest)).busy)
  assert_eq(quote_initialization_request(model, "foreign-conversion"), None)
  assert_eq(
    quote_initialization_request({ ..model, commercial: None, }, digest),
    None,
  )
  for status in [Some("completed"), Some("legacy"), None, Some("unknown")] {
    let blocked = {
      ..model,
      commercial: Some(
        initialization_dashboard([initialization_conversion(status)]),
      ),
    }
    assert_eq(quote_initialization_request(blocked, digest), None)
    assert_false(step(blocked, ResumeQuoteInitialization(digest)).busy)
  }
  let conversion = initialization_conversion(Some("pending"))
  let ambiguous = {
    ..model,
    commercial: Some(initialization_dashboard([conversion, conversion])),
  }
  assert_eq(quote_initialization_request(ambiguous, digest), None)
}

///|
test "quote conversion failure describes partial persistence and supports a refreshed retry" {
  let model = { ..initialization_model(), busy: true, }
  let request = project_request(model)
  for label in ["Quote conversion", "Draft initialization"] {
    let failed = step(
      model,
      ActionCompleted(request, label, Err(ProjectLoadTestError("interrupted"))),
    )
    assert_false(failed.busy)
    assert_true(failed.status.contains("partially saved"))
    assert_false(failed.status.contains("not changed"))
    assert_eq(failed.selected_project_id, model.selected_project_id)
    assert_eq(failed.artifact_draft, "keep my local edit")
    let rejected = step(
      model,
      ActionCompleted(
        request,
        label,
        Ok({ "error": { "message": "disk unavailable" } }),
      ),
    )
    assert_false(rejected.busy)
    assert_true(rejected.status.contains("partially saved"))
    assert_true(rejected.error.unwrap().contains("disk unavailable"))
    let refreshed = step(
      failed,
      LoadedCommercial(
        Ok(
          initialization_dashboard([initialization_conversion(Some("pending"))]),
        ),
      ),
    )
    assert_true(
      quote_initialization_request(refreshed, "sha256:original-conversion")
      is Some(_),
    )
  }
}

///|
test "completed draft initialization refresh preserves selection and later completion removes retry" {
  let model = { ..initialization_model(), busy: true, }
  let completed = step(
    model,
    ActionCompleted(project_request(model), "Draft initialization", Ok({})),
  )
  assert_false(completed.busy)
  assert_eq(completed.selected_project_id, model.selected_project_id)
  assert_eq(completed.selected_quote_id, model.selected_quote_id)
  assert_eq(completed.artifact_draft, "keep my local edit")
  let refreshed = step(
    completed,
    LoadedCommercial(
      Ok(
        initialization_dashboard([initialization_conversion(Some("completed"))]),
      ),
    ),
  )
  assert_eq(
    quote_initialization_request(refreshed, "sha256:original-conversion"),
    None,
  )
  assert_false(
    rendered(render_quote_initializations(_ => @rabbita.none, refreshed)).contains(
      "Resume draft initialization",
    ),
  )
}

///|
test "late draft initialization response leaves the newly selected project untouched" {
  let original = initialization_model()
  let request = project_request(original)
  let switched = step(original, SelectProject("other-project"))
  let switched = {
    ..switched,
    busy: true,
    status: "Other project command in flight",
    artifact_draft: "other draft",
  }
  let results : Array[Result[Json, Error]] = [
    Ok({}),
    Err(ProjectLoadTestError("lost response")),
  ]
  for result in results {
    let late = step(
      switched,
      ActionCompleted(request, "Draft initialization", result),
    )
    assert_eq(late.selected_project_id, "other-project")
    assert_eq(late.artifact_draft, "other draft")
    assert_eq(late.status, "Other project command in flight")
    assert_true(late.busy)
    assert_eq(
      late.command_notices.length(),
      switched.command_notices.length() + 1,
    )
  }
}

///|
test "ordinary intake renders actionable frozen initialization even when current capacity conflicts" {
  let model = initialization_model()
  let panel = rendered(render_quote_initializations(_ => @rabbita.none, model))
  assert_true(panel.contains("Resume draft initialization"))
  assert_true(panel.contains("accepted-quote · v2"))
  assert_true(panel.contains("sha256:accepted-quote-v2"))
  assert_true(panel.contains("sha256:accepted-capacity"))
  assert_true(panel.contains("accepted-project"))
  assert_false(panel.contains("newer-capacity"))
  assert_false(panel.contains("disabled"))
  assert_true(
    rendered(render_app(_ => @rabbita.none, model)).contains(
      "Resume draft initialization",
    ),
  )
  assert_true(
    rendered(
      render_quote_initializations(_ => @rabbita.none, { ..model, busy: true, }),
    ).contains("disabled"),
  )
  assert_true(
    rendered(
      render_quote_initializations(_ => @rabbita.none, {
        ..model,
        operator: { ..model.operator, human_confirmed: false, },
      }),
    ).contains("disabled"),
  )
}

///|
test "legacy conversion projections remain readable and are never inferred to be pending" {
  let legacy : ConversionProjection = @json.from_json({
    "contract": "mooncast.quote-conversion.v1",
    "quote_id": "legacy-quote",
    "quote_version": 1,
    "quote_digest": "sha256:legacy-quote",
    "capacity_digest": "sha256:legacy-capacity",
    "project_id": "<script>legacy</script>",
    "actor": "producer",
    "actor_role": "producer",
    "converted_at": "2026-10-01T00:00:00Z",
    "digest": "sha256:legacy-conversion",
    "payment_effect_performed": false,
    "publication_authority": false,
  })
  assert_eq(legacy.initialization_status, None)
  let model = {
    ..initialization_model(),
    commercial: Some(initialization_dashboard([legacy])),
  }
  let html = rendered(render_quote_initializations(_ => @rabbita.none, model))
  assert_true(html.contains("initialization untracked"))
  assert_true(html.contains("no tracked recovery plan"))
  assert_false(html.contains("Resume draft initialization"))
  assert_true(html.contains("&lt;script&gt;legacy&lt;/script&gt;"))
  assert_false(html.contains("<script>legacy</script>"))
  let refreshed = step(model, RefreshQuoteInitializations)
  assert_eq(refreshed.busy, model.busy)
  assert_eq(refreshed.selected_quote_id, model.selected_quote_id)
  assert_eq(refreshed.selected_project_id, model.selected_project_id)
}
