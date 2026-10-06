///|
async fn ledger_quote_fixture(
  service : StudioService,
  project_id : String,
  title : String,
) -> QuoteProjection {
  let lead = service.create_commercial_lead({
    customer: "SYNTHETIC studio fixture; no real customer",
    customer_contact_ref: "fixture://no-contact",
    payable_problem: "Exercise one offline 180 second media commission",
    baseline_cost_cny: 100.0,
    baseline_time_hours: 1.0,
    channels: ["review-only"],
    measurable_acceptance: ["Inspect local master and exact lineage"],
    repeat_hypothesis: "Fixture assumption only",
  })
  ignore(
    service.qualify_commercial_lead(lead.lead_id, {
      expected_version: lead.version,
      expected_digest: lead.digest,
      decision: "qualify",
      note: "Synthetic test decision",
      human_confirmed: true,
      actor: "fixture-producer",
      actor_role: "producer",
      authority: None,
    }),
  )
  let quote = service.create_or_revise_quote(lead.lead_id, None, {
    expected_lead_version: Some(lead.version),
    expected_lead_digest: Some(lead.digest),
    expected_version: None,
    expected_digest: None,
    project_id,
    title,
    objective: "Synthetic 180 second local media fixture",
    audience: "local reviewer",
    rights_owner: "Synthetic fixture operator",
    target_duration_seconds: 180,
    production_budget_cny: 5000.0,
    start_date: "2026-10-04",
    delivery_date: "2026-10-10",
    revision_rounds: 2,
    deliverables: ["fixture-master", "fixture-manifest"],
    provider_overage_policy: "No paid provider work",
    rights_restrictions: ["Synthetic assets only"],
    model_restrictions: ["Local deterministic fixture"],
    data_restrictions: ["No customer data"],
    quoted_revenue_cny: 1000.0,
    provider_cost_cny: 10.0,
    labor_cost_cny: 100.0,
    other_cost_cny: 5.0,
    founder_hours: 2.0,
    contingency_percent: 10.0,
    milestones: [
      { kind: "deposit", amount_cny: 300.0, },
      { kind: "animatic", amount_cny: 300.0, },
      { kind: "accepted-master", amount_cny: 400.0, },
    ],
  })
  for authority in ["commercial", "production", "client"] {
    ignore(
      service.decide_commercial_quote(quote.quote_id, authority, {
        expected_version: quote.version,
        expected_digest: quote.digest,
        decision: if authority == "client" {
          "accept"
        } else {
          "approve"
        },
        note: "Synthetic quote approval; not a real commitment",
        human_confirmed: true,
        actor: "fixture-" + authority,
        actor_role: authority,
        authority: Some(authority),
      }),
    )
  }
  let resource = service.create_capacity_resource({
    name: "Synthetic editor",
    role: "editor",
    skills: ["editing"],
    weekly_hours: 8.0,
    available_from: "2026-10-04",
    available_to: "2026-10-10",
    human_confirmed: true,
    actor: "fixture-producer",
    actor_role: "producer",
  })
  ignore(
    service.create_capacity_reservation({
      quote_id: quote.quote_id,
      quote_version: quote.version,
      quote_digest: quote.digest,
      resource_id: resource.resource_id,
      skills: ["editing"],
      depends_on: [],
      start_date: "2026-10-04",
      end_date: "2026-10-10",
      hours: 4.0,
      human_confirmed: true,
      actor: "fixture-producer",
      actor_role: "producer",
    }),
  )
  quote
}

///|
async fn ledger_convert_fixture(
  service : StudioService,
  quote : QuoteProjection,
) -> Unit {
  let board = service.commerce_application
    .capacity_board(quote_id=quote.quote_id)
    .unwrap()
  assert_true(board.ready)
  let request : QuoteConversionInput = {
    expected_version: quote.version,
    expected_digest: quote.digest,
    expected_capacity_digest: board.digest,
    human_confirmed: true,
    actor: "fixture-producer",
    actor_role: "producer",
  }
  ignore(service.convert_commercial_quote(quote.quote_id, request))
  ignore(service.convert_commercial_quote(quote.quote_id, request))
  assert_eq(
    service.commerce_application.load().conversions
    .filter(item => item.project_id == quote.project.project_id)
    .length(),
    1,
  )
}

///|
async test "episode ledger missing evidence is unknown read only scoped and safely rendered" {
  let root = "/tmp/mooncast-ledger-empty-" + @async.now().to_string()
  let service = StudioService::new(root)
  let graph = @production_app.episode_production_graph(
    "ledger-empty", "<script>synthetic</script>", 180, 5000.0,
  )
  let record = service.create_project(graph, "2026-10-04T00:00:00Z")
  let episode_id = graph.episodes[0].episode_id
  let before = service.store.list_keys()
  let restarted = StudioService::new(root)
  let ledger = restarted.episode_ledger(graph.project_id, episode_id)
  assert_eq(json_member(ledger, "actual_provider_cost_cny"), Some(Json::null()))
  assert_eq(json_member(ledger, "actual_labor_cost_cny"), Some(Json::null()))
  assert_eq(
    json_member(ledger, "client_acceptance_recorded"),
    Some(false.to_json()),
  )
  assert_eq(
    json_member(ledger, "payment_evidence_recorded"),
    Some(false.to_json()),
  )
  assert_eq(json_member(ledger, "master_url"), Some(Json::null()))
  let page = restarted.episode_ledger_page(graph.project_id, episode_id)
  let text = @utf8.decode(page.body)
  assert_true(text.contains("Unknown"))
  assert_false(text.contains("<script>synthetic</script>"))
  assert_true(text.contains("&lt;script&gt;synthetic&lt;/script&gt;"))
  assert_eq(page.headers.get("Cache-Control"), Some("no-store"))
  assert_eq(service.store.list_keys(), before)
  assert_eq(restarted.get_project(graph.project_id), record)
  for
    path in [
      "/api/v2/projects/ledger-empty/episodes/foreign-episode/ledger",
      "/api/v2/projects/foreign-project/episodes/" + episode_id + "/ledger",
    ] {
    assert_eq(
      restarted.dispatch_http({
        request_method: Get,
        path,
        query: None,
        headers: {},
        body: b"",
      }).status,
      404,
    )
  }
}

///|
async test "episode ledger quote conversion survives reload without duplicate costs" {
  let root = "/tmp/mooncast-ledger-quote-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "ledger-quoted", "Synthetic quoted commission",
  )
  ledger_convert_fixture(service, quote)
  let restarted = StudioService::new(root)
  let project = restarted.get_project("ledger-quoted")
  let ledger = restarted.episode_ledger(
    project.project_id,
    project.snapshot.graph.episodes[0].episode_id,
  )
  let evidence = json_member(ledger, "quote_evidence").unwrap()
  assert_true(evidence.stringify().contains(quote.digest))
  assert_eq(ledger_list(evidence, "decisions").length(), 3)
  assert_eq(ledger_list(evidence, "capacity_at_conversion").length(), 1)
  assert_eq(json_member(ledger, "actual_provider_cost_cny"), Some(Json::null()))
  assert_eq(
    json_member(ledger, "payment_evidence_recorded"),
    Some(false.to_json()),
  )
  assert_eq(
    restarted.episode_ledger(
      project.project_id,
      project.snapshot.graph.episodes[0].episode_id,
    ),
    ledger,
  )
  let edited = {
    ..project,
    snapshot: {
      ..project.snapshot,
      graph: { ..project.snapshot.graph, title: "Edited after conversion", },
    },
  }
  save_value(restarted.store, project_key(project.project_id), edited)
  let metadata : ProjectExperienceMetadata = {
    objective: "Updated brief",
    audience: "Changed audience",
    channels: ["internal-review"],
    rights_owner: "Updated rights owner",
    rights_confirmed: false,
  }
  restarted.save_project_experience(project.project_id, metadata)
  let before_retry = restarted.commerce_application.load()
  let conversion = before_retry.conversions[0]
  ignore(
    restarted.convert_commercial_quote(quote.quote_id, {
      expected_version: quote.version,
      expected_digest: quote.digest,
      expected_capacity_digest: conversion.capacity_digest,
      human_confirmed: true,
      actor: "fixture-retry-operator",
      actor_role: "producer",
    }),
  )
  assert_eq(restarted.get_project(project.project_id), edited)
  let saved : ProjectExperienceMetadata = load_value(
    restarted.store,
    project_experience_key(project.project_id),
  ).unwrap()
  assert_eq(saved.to_json(), metadata.to_json())
  assert_eq(restarted.commerce_application.load(), before_retry)
  // A completed initialization is terminal: later removal never reopens the
  // seed plan or turns this existing project into an inferred new commission.
  // Interrupted pending plans have separate missing-only recovery coverage.
  let partial = {
    ..project,
    snapshot: @kernel.empty_snapshot(project.snapshot.graph),
    events: [],
    command_receipts: [],
  }
  save_value(restarted.store, project_key(project.project_id), partial)
  ignore(
    restarted.convert_commercial_quote(quote.quote_id, {
      expected_version: quote.version,
      expected_digest: quote.digest,
      expected_capacity_digest: conversion.capacity_digest,
      human_confirmed: true,
      actor: "fixture-retry-operator",
      actor_role: "producer",
    }),
  )
  assert_eq(restarted.get_project(project.project_id), partial)
  assert_eq(
    ledger_list(
      restarted.episode_ledger(
        project.project_id,
        project.snapshot.graph.episodes[0].episode_id,
      ),
      "creative_history",
    ).length(),
    0,
  )
}
