///|
async test "episode attribution serializes simultaneous stale writers and refuses cross project correction" {
  let root = attribution_test_parent() +
    "/concurrency-" +
    @async.now().to_string()
  let (service, graph) = attribution_fixture(root)
  let revision = service.get_project(graph.project_id).snapshot.revision
  let episode = graph.episodes[0].episode_id
  let saved : Array[EpisodeAttributionRecord] = []
  let conflicts : Array[String] = []
  @async.with_task_group(group => {
    for command in ["parallel-one", "parallel-two"] {
      group.spawn_bg(() => {
        let input = {
          ..attribution_fixture_input(command, 0, 1.0),
          expected_project_revision: revision,
        }
        try
          service.record_episode_attribution(graph.project_id, episode, input)
        catch {
          Conflict(code~, ..) => conflicts.push(code)
          error => raise error
        } noraise {
          record => saved.push(record)
        }
      })
    }
  })
  assert_eq(saved.length(), 1)
  assert_eq(conflicts, ["episode_attribution_revision_conflict"])
  let other = @production_app.episode_production_graph(
    "other-project", "Other project", 180, 5000.0,
  )
  let other_project = service.create_project(other, "2026-10-08T00:00:00Z")
  try
    service.record_episode_attribution(
      other.project_id,
      other.episodes[0].episode_id,
      {
        ..attribution_fixture_input("cross-project", 0, 1.0),
        expected_project_revision: other_project.snapshot.revision,
        supersedes_id: Some(saved[0].record_id),
        supersedes_digest: Some(saved[0].digest),
      },
    )
  catch {
    Conflict(code~, ..) =>
      assert_eq(code, "episode_attribution_correction_conflict")
    error => raise error
  } noraise {
    _ => fail("Cross project correction must fail")
  }
  assert_eq(service.episode_attribution_records(graph.project_id), saved)
  assert_eq(service.episode_attribution_records(other.project_id), [])
}

///|
test "episode attribution form rejects duplicate and invalid encoding while preserving Unicode evidence" {
  assert_eq(
    attribution_form_decode("%E4%B8%AD%E6%96%87+evidence%3Dline"),
    "中文 evidence=line",
  )
  for malformed in ["%", "%2", "%+1", "%GG", "%FF"] {
    try attribution_form_decode(malformed) catch {
      _ => ()
    } noraise {
      _ => fail("Malformed form must fail")
    }
  }
}

///|
async test "episode attribution actuals write and locked reconciliation complete within bounded timeout" {
  @async.with_timeout(5000, () => {
    let root = attribution_test_parent() + "/locks-" + @async.now().to_string()
    let (service, graph) = attribution_fixture(root)
    let revision = service.get_project(graph.project_id).snapshot.revision
    ignore(
      service.record_control_tower_actuals(graph.project_id, {
        command_id: "lock-test-actuals",
        expected_project_revision: revision,
        expected_actuals_version: None,
        expected_actuals_digest: None,
        provider_cost_confirmed_cny: None,
        labor_cost_cny: Some(10.0),
        other_cost_cny: None,
        recognized_revenue_cny: None,
        founder_hours: None,
        completed_labor_hours: None,
        forecast_completion_date: None,
        provider_cost_reconciled: false,
        evidence_refs: ["fixture://lock-test"],
        actor: "Synthetic owner",
        actor_role: "producer",
        observed_at: "2026-10-08T00:00:00Z",
        human_confirmed: true,
      }),
    )
    let view = service.episode_attribution_view(
      graph.project_id,
      graph.episodes[0].episode_id,
    )
    assert_eq(
      ledger_text(ledger_list(view, "reconciliation")[1], "status"),
      "comparable",
    )
    assert_eq(
      service.episode_ledger_page(
        graph.project_id,
        graph.episodes[0].episode_id,
      ).status,
      200,
    )
  })
}
