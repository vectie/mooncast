///|
fn attribution_fixture_input(
  command : String,
  revision : Int,
  value : Double,
) -> EpisodeAttributionInput {
  {
    command_id: command,
    expected_project_revision: 0,
    expected_ledger_revision: revision,
    expected_actuals_digest: None,
    category: "labor_cny",
    value,
    evidence_ref: "fixture://" + command,
    author: "Named synthetic author <not verified>",
    note: "Synthetic evidence only",
    supersedes_id: None,
    supersedes_digest: None,
    human_confirmed: true,
  }
}

///|
fn attribution_test_parent() -> String {
  @env.get_env_var("MOONCAST_ATTRIBUTION_TEST_ROOT").unwrap_or(
    "/tmp/mooncast-attribution-tests",
  )
}

///|
async fn attribution_fixture(
  root : String,
) -> (StudioService, @project.ProjectGraph) {
  let parent = attribution_test_parent()
  if !@fs.exists(parent) {
    @fs.mkdir(parent, recursive=true) catch {
      error => {
        guard @fs.exists(parent) && @fs.kind(parent) is Directory else {
          raise error
        }
      }
    }
  }
  let service = StudioService::new(root)
  let first = @production_app.episode_production_graph(
    "cost-project", "Cost fixture", 180, 5000.0,
  )
  let graph = {
    ..first,
    episodes: [
      { ..first.episodes[0], scenes: [first.episodes[0].scenes[0]], },
      {
        ..first.episodes[0],
        episode_id: "episode-two",
        title: "Second",
        order: 2,
        scenes: first.episodes[0].scenes[1:].to_owned(),
      },
    ],
  }
  ignore(service.create_project(graph, "2026-10-08T00:00:00Z"))
  (service, graph)
}

///|
async fn attribution_expect_conflict(
  service : StudioService,
  episode : String,
  input : EpisodeAttributionInput,
  code : String,
) -> Unit {
  try service.record_episode_attribution("cost-project", episode, input) catch {
    Conflict(code=actual, ..) => assert_eq(actual, code)
    _ => fail("Unexpected error")
  } noraise {
    _ => fail("Expected conflict")
  }
}

///|
async test "episode attribution unknown zero two episodes corrections retries restart and preserved project evidence" {
  let root = attribution_test_parent() + "/history-" + @async.now().to_string()
  let (service, graph) = attribution_fixture(root)
  let episode = graph.episodes[0].episode_id
  let baseline = service.get_project(graph.project_id)
  let revision = baseline.snapshot.revision
  let first_input = {
    ..attribution_fixture_input("cost-one", 0, 12.0),
    expected_project_revision: revision,
  }
  let first = service.record_episode_attribution(
    graph.project_id,
    episode,
    first_input,
  )
  let second = service.record_episode_attribution(
    graph.project_id,
    "episode-two",
    {
      ..attribution_fixture_input("cost-two", 1, 0.0),
      expected_project_revision: revision,
    },
  )
  let view = service.episode_attribution_view(graph.project_id, episode)
  let labor = ledger_list(view, "reconciliation")[1]
  assert_eq(json_member(labor, "episode_recorded_value"), Some(12.0.to_json()))
  assert_eq(json_member(labor, "project_total"), Some(Json::null()))
  assert_eq(json_member(labor, "unallocated_remainder"), Some(Json::null()))
  assert_eq(
    json_member(
      ledger_list(view, "reconciliation")[0],
      "episode_recorded_value",
    ),
    Some(Json::null()),
  )
  let zero = service.episode_attribution_view(graph.project_id, "episode-two")
  assert_eq(
    json_member(
      ledger_list(zero, "reconciliation")[1],
      "episode_recorded_value",
    ),
    Some(0.0.to_json()),
  )
  let correction_input = {
    ..attribution_fixture_input("correct-one", 2, 9.0),
    expected_project_revision: revision,
    evidence_ref: first_input.evidence_ref,
    supersedes_id: Some(first.record_id),
    supersedes_digest: Some(first.digest),
  }
  let correction = service.record_episode_attribution(
    graph.project_id,
    episode,
    correction_input,
  )
  let reopened = StudioService::new(root)
  assert_eq(
    reopened.record_episode_attribution(graph.project_id, episode, first_input),
    first,
  )
  assert_eq(
    reopened.record_episode_attribution(
      graph.project_id,
      episode,
      correction_input,
    ),
    correction,
  )
  assert_eq(reopened.episode_attribution_records(graph.project_id), [
    first, second, correction,
  ])
  assert_eq(
    effective_attributions(
      reopened.episode_attribution_records(graph.project_id),
    ),
    [second, correction],
  )
  attribution_expect_conflict(
    reopened,
    episode,
    { ..first_input, value: 13.0, },
    "episode_attribution_command_conflict",
  )
  attribution_expect_conflict(
    reopened,
    episode,
    {
      ..correction_input,
      command_id: "stale-correction",
      expected_ledger_revision: 3,
    },
    "episode_attribution_correction_conflict",
  )
  attribution_expect_conflict(
    reopened,
    "episode-two",
    {
      ..attribution_fixture_input("duplicate-source", 3, 1.0),
      expected_project_revision: revision,
      evidence_ref: first_input.evidence_ref,
    },
    "episode_attribution_evidence_conflict",
  )
  assert_eq(reopened.get_project(graph.project_id), baseline)
  assert_eq(reopened.control_tower_actuals(graph.project_id), None)
  let page = @utf8.decode(
    reopened.episode_ledger_page(graph.project_id, episode).body,
  )
  assert_true(page.contains("Correct this exact record"))
  assert_true(page.contains("Superseded history"))
  assert_true(page.contains("&lt;not verified&gt;"))
  assert_false(page.contains("<not verified>"))
  assert_true(page.contains("Held: project total unknown"))
}

///|
async test "episode attribution comparable totals conservation overrun stale basis and exact correction binding" {
  let root = attribution_test_parent() + "/total-" + @async.now().to_string()
  let (service, graph) = attribution_fixture(root)
  let episode = graph.episodes[0].episode_id
  let revision = service.get_project(graph.project_id).snapshot.revision
  let actuals = service.record_control_tower_actuals(graph.project_id, {
    command_id: "project-cost",
    expected_project_revision: revision,
    expected_actuals_version: None,
    expected_actuals_digest: None,
    provider_cost_confirmed_cny: None,
    labor_cost_cny: Some(20.0),
    other_cost_cny: Some(0.0),
    recognized_revenue_cny: None,
    founder_hours: Some(4.0),
    completed_labor_hours: None,
    forecast_completion_date: None,
    provider_cost_reconciled: false,
    evidence_refs: ["fixture://project-cost"],
    actor: "Synthetic owner",
    actor_role: "producer",
    observed_at: "2026-10-08T00:00:00Z",
    human_confirmed: true,
  })
  let input = {
    ..attribution_fixture_input("part-one", 0, 12.0),
    expected_project_revision: revision,
    expected_actuals_digest: Some(actuals.digest),
  }
  let first = service.record_episode_attribution(
    graph.project_id,
    episode,
    input,
  )
  attribution_expect_conflict(
    service,
    "episode-two",
    {
      ..input,
      command_id: "over",
      expected_ledger_revision: 1,
      value: 9.0,
      evidence_ref: "fixture://over",
    },
    "episode_attribution_exceeds_total",
  )
  ignore(
    service.record_episode_attribution(graph.project_id, "episode-two", {
      ..input,
      command_id: "part-two",
      expected_ledger_revision: 1,
      value: 8.0,
      evidence_ref: "fixture://part-two",
    }),
  )
  let labor = ledger_list(
      service.episode_attribution_view(graph.project_id, episode),
      "reconciliation",
    )[1]
  assert_eq(json_member(labor, "unallocated_remainder"), Some(0.0.to_json()))
  assert_eq(ledger_text(labor, "status"), "comparable")
  attribution_expect_conflict(
    service,
    "episode-two",
    {
      ..input,
      command_id: "cross-correction",
      expected_ledger_revision: 2,
      supersedes_id: Some(first.record_id),
      supersedes_digest: Some(first.digest),
    },
    "episode_attribution_correction_conflict",
  )
  attribution_expect_conflict(
    service,
    episode,
    {
      ..input,
      command_id: "wrong-digest",
      expected_ledger_revision: 2,
      supersedes_id: Some(first.record_id),
      supersedes_digest: Some("wrong"),
    },
    "episode_attribution_correction_conflict",
  )
  attribution_expect_conflict(
    service,
    episode,
    {
      ..input,
      command_id: "stale-project",
      expected_project_revision: revision + 1,
      expected_ledger_revision: 2,
    },
    "episode_attribution_revision_conflict",
  )
  // A separately changed project record cannot silently reclassify old attribution.
  ignore(
    service.record_control_tower_actuals(graph.project_id, {
      command_id: "project-cost-revised",
      expected_project_revision: revision,
      expected_actuals_version: Some(actuals.version),
      expected_actuals_digest: Some(actuals.digest),
      provider_cost_confirmed_cny: None,
      labor_cost_cny: Some(10.0),
      other_cost_cny: Some(0.0),
      recognized_revenue_cny: None,
      founder_hours: Some(4.0),
      completed_labor_hours: None,
      forecast_completion_date: None,
      provider_cost_reconciled: false,
      evidence_refs: ["fixture://project-cost-revised"],
      actor: "Synthetic owner",
      actor_role: "producer",
      observed_at: "2026-10-08T00:01:00Z",
      human_confirmed: true,
    }),
  )
  let held = ledger_list(
      service.episode_attribution_view(graph.project_id, episode),
      "reconciliation",
    )[1]
  assert_eq(ledger_text(held, "status"), "held-stale-or-mixed-evidence-basis")
  assert_eq(json_member(held, "unallocated_remainder"), Some(Json::null()))
  assert_eq(
    service.record_episode_attribution(graph.project_id, episode, input),
    first,
  )
}

///|
async test "episode attribution production form controller validation isolated routes and interrupted persistence" {
  let root = attribution_test_parent() + "/form-" + @async.now().to_string()
  let (service, graph) = attribution_fixture(root)
  let episode = graph.episodes[0].episode_id
  let revision = service.get_project(graph.project_id).snapshot.revision
  let base = "/api/v2/projects/cost-project/episodes/" + episode + "/ledger"
  let fields = "command_id=form-one&expected_project_revision=" +
    revision.to_string() +
    "&expected_ledger_revision=0&expected_actuals_digest=&category=founder_hours&value=2.5&evidence_ref=fixture%3A%2F%2Ftime&author=Named+Author&note=Actual+time&supersedes_id=&supersedes_digest=&human_confirmed=true"
  let response = service.dispatch_http({
    request_method: Post,
    path: base + "/attributions/form",
    query: None,
    headers: {},
    body: @utf8.encode(fields),
  })
  assert_eq(response.status, 303)
  assert_eq(
    service.dispatch_http({
      request_method: Post,
      path: base + "/attributions/form",
      query: None,
      headers: {},
      body: @utf8.encode(fields),
    }).status,
    303,
  )
  assert_eq(service.episode_attribution_records(graph.project_id).length(), 1)
  assert_eq(
    service.dispatch_http({
      request_method: Post,
      path: base + "/attributions/form",
      query: None,
      headers: {},
      body: @utf8.encode(fields + "&value=3"),
    }).status,
    422,
  )
  let input = {
    ..attribution_fixture_input("invalid", 1, -1.0),
    expected_project_revision: revision,
  }
  assert_eq(
    service.dispatch_http({
      request_method: Post,
      path: base + "/attributions",
      query: None,
      headers: {},
      body: @utf8.encode(input.to_json().stringify()),
    }).status,
    422,
  )
  assert_eq(
    service.dispatch_http({
      request_method: Post,
      path: "/api/v2/projects/cost-project/episodes/foreign/ledger/attributions",
      query: None,
      headers: {},
      body: @utf8.encode(input.to_json().stringify()),
    }).status,
    404,
  )
  assert_eq(
    service.dispatch_http({
      request_method: Post,
      path: "/api/v2/projects/foreign/episodes/" +
      episode +
      "/ledger/attributions",
      query: None,
      headers: {},
      body: @utf8.encode(input.to_json().stringify()),
    }).status,
    404,
  )
  // Interrupted uncommitted temporary bytes do not become visible history.
  ignore(
    service.store.put_blob(
      episode_attribution_key(graph.project_id) + ".tmp-interrupted",
      b"incomplete",
    ),
  )
  let reopened = StudioService::new(root)
  assert_eq(reopened.episode_attribution_records(graph.project_id).length(), 1)
  let before = reopened.episode_attribution_records(graph.project_id)
  // Unreadable committed storage fails closed, never becoming an empty ledger.
  let blocked = StudioService::new(root + "/blocked")
  ignore(blocked.create_project(graph, "2026-10-08T00:00:00Z"))
  @fs.mkdir(root + "/blocked/" + episode_attribution_key(graph.project_id))
  try
    blocked.record_episode_attribution(graph.project_id, episode, {
      ..input,
      command_id: "interrupted",
      expected_ledger_revision: 0,
      value: 1.0,
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("write must fail")
  }
  assert_eq(reopened.episode_attribution_records(graph.project_id), before)
}
