///|
async test "episode ledger isolates episode shots and retains failed revised source history" {
  let root = "/tmp/mooncast-ledger-history-" + @async.now().to_string()
  let service = StudioService::new(root)
  let asset : @project.Asset = {
    asset_id: "source-a",
    kind: "image",
    version: 1,
    digest: "sha256:source-a-v1",
    uri: "fixture://source-a",
    rights_record_id: "fixture-rights",
    immutable: true,
  }
  let shot : @project.Shot = {
    shot_id: "shot-a",
    order: 1,
    duration_ms: 90000,
    character_ids: [],
    location_id: "fixture",
    source_asset_ids: [asset.asset_id],
  }
  let episode : @project.Episode = {
    episode_id: "episode-a",
    order: 1,
    title: "Synthetic A",
    scenes: [{ scene_id: "scene-a", order: 1, title: "A", shots: [shot], }],
  }
  let graph : @project.ProjectGraph = {
    project_id: "ledger-history",
    revision: 1,
    title: "Synthetic two episode project",
    target_duration_seconds: 180,
    maximum_budget_cny: 5000.0,
    assets: [asset],
    episodes: [
      episode,
      {
        ..episode,
        episode_id: "episode-b",
        order: 2,
        title: "Synthetic B",
        scenes: [
          {
            scene_id: "scene-b",
            order: 1,
            title: "B",
            shots: [{ ..shot, shot_id: "shot-b", }],
          },
        ],
      },
    ],
  }
  let record = service.create_project(graph, "2026-10-04T00:00:00Z")
  let attempt : @governance.GenerationAttempt = {
    attempt: { id: "attempt-a", version: 1, digest: "sha256:attempt-a", },
    shot_id: "shot-a",
    route_id: "fixture-route",
    route_plan: {
      id: "fixture-plan",
      version: 1,
      digest: "sha256:fixture-plan",
    },
    prompt_digest: "sha256:prompt",
    source_asset_digests: [asset.digest],
    seed: None,
    duration_ms: 90000,
    cost_cny: 1.0,
    output_digest: "sha256:output-a",
    status: "succeeded",
  }
  let findings = @governance.qc_dimensions().mapi((index, dimension) => @governance.QcFinding::{
    finding: {
      id: "finding-" + index.to_string(),
      version: 1,
      digest: "sha256:finding-" + index.to_string(),
    },
    shot_id: shot.shot_id,
    attempt_digest: attempt.output_digest,
    dimension,
    status: "pass",
    evidence_digest: "sha256:fixture-qc",
    note: "Synthetic QC fixture",
  })
  let decisions = findings.map(finding => @governance.QcDecision::{
    finding: finding.finding,
    decision: "approved",
    actor: "fixture-reviewer",
    role: "fixture",
    decided_at: "2026-10-04T00:00:00Z",
  })
  // Explicit persisted synthetic snapshots let us qualify damaged-record
  // projections without claiming these are authorized production receipts.
  let with_history = {
    ..record,
    snapshot: {
      ..record.snapshot,
      generation_attempts: [
        attempt,
        {
          ..attempt,
          attempt: { ..attempt.attempt, id: "attempt-b", },
          shot_id: "shot-b",
          output_digest: "sha256:output-b",
        },
      ],
      qc_findings: findings,
      qc_decisions: decisions,
    },
  }
  save_value(service.store, project_key(record.project_id), with_history)
  let first = service.episode_ledger(record.project_id, "episode-a")
  let first_shot = ledger_list(first, "shots")[0]
  assert_eq(ledger_list(first, "shots").length(), 1)
  assert_eq(
    json_member(first_shot, "latest_attempt_qc_passed"),
    Some(true.to_json()),
  )
  assert_eq(
    json_member(first_shot, "source_bindings_current"),
    Some(true.to_json()),
  )
  assert_false(
    ledger_list(first, "shots").to_json().stringify().contains("attempt-b"),
  )
  let revised = {
    ..with_history,
    snapshot: {
      ..with_history.snapshot,
      graph: {
        ..graph,
        assets: [{ ..asset, version: 2, digest: "sha256:source-a-v2", }],
      },
      generation_attempts: [
        ..with_history.snapshot.generation_attempts,
        {
          ..attempt,
          attempt: {
            id: "attempt-a-retry",
            version: 2,
            digest: "sha256:attempt-a-retry",
          },
          status: "failed",
          output_digest: "",
        },
      ],
    },
  }
  save_value(service.store, project_key(record.project_id), revised)
  let reloaded = StudioService::new(root).episode_ledger(
    record.project_id,
    "episode-a",
  )
  let revised_shot = ledger_list(reloaded, "shots")[0]
  assert_eq(ledger_list(revised_shot, "attempts").length(), 2)
  assert_eq(ledger_list(revised_shot, "qc_findings").length(), 5)
  assert_eq(
    json_member(revised_shot, "latest_attempt_qc_passed"),
    Some(false.to_json()),
  )
  assert_eq(
    json_member(revised_shot, "source_bindings_current"),
    Some(false.to_json()),
  )
  save_value(service.store, project_key(record.project_id), {
    ..revised,
    snapshot: {
      ..revised.snapshot,
      graph: { ..revised.snapshot.graph, assets: [], },
    },
  })
  let missing = service.episode_ledger(record.project_id, "episode-a")
  assert_eq(
    ledger_list(ledger_list(missing, "shots")[0], "missing_source_asset_ids"),
    ["source-a".to_json()],
  )
  assert_eq(json_member(missing, "master_available"), Some(false.to_json()))
}

///|
async test "episode ledger excludes foreign commercial evidence and exposes contradictory bindings" {
  let root = "/tmp/mooncast-ledger-foreign-" + @async.now().to_string()
  let service = StudioService::new(root)
  let quote = ledger_quote_fixture(
    service, "ledger-own", "Synthetic own project",
  )
  ledger_convert_fixture(service, quote)
  let own = service.get_project("ledger-own")
  let commercial = service.commerce_application.load()
  let foreign : @commerce.MilestoneBillingEntry = {
    contract: "mooncast.milestone-billing-entry.v1",
    billing_id: "foreign-billing",
    project_id: "foreign-project",
    kind: "deposit",
    currency: "CNY",
    amount: 98765.0,
    reference: "fixture://foreign-payment",
    state: "paid",
    quoted_at: "fixture",
    due_at: Some("fixture"),
    paid_at: Some("fixture"),
    waived_at: None,
    history: [],
    revision: 1,
    record_digest: "sha256:foreign",
    payment_effect_performed: false,
  }
  ignore(
    service.commerce_application.store.put_json(
      "commercial-snapshot.json",
      { ..commercial, billing: [foreign], }.to_json(),
    ),
  )
  let actuals : @control_tower.OperatingActuals = {
    contract: "mooncast.control-tower-operating-actuals.v1",
    command_id: "foreign-actuals",
    project_id: "foreign-project",
    version: 1,
    project_revision: 1,
    provider_cost_confirmed_cny: Some(98765.0),
    labor_cost_cny: None,
    other_cost_cny: None,
    recognized_revenue_cny: None,
    founder_hours: None,
    completed_labor_hours: None,
    forecast_completion_date: None,
    provider_cost_reconciled: false,
    evidence_refs: ["fixture://foreign"],
    actor: "fixture",
    actor_role: "fixture",
    observed_at: "fixture",
    digest: "sha256:foreign",
  }
  save_value(service.store, control_tower_actuals_key(own.project_id), actuals)
  let ledger = service.episode_ledger(
    own.project_id,
    own.snapshot.graph.episodes[0].episode_id,
  )
  assert_eq(
    json_member(ledger, "payment_evidence_recorded"),
    Some(false.to_json()),
  )
  assert_eq(json_member(ledger, "actual_provider_cost_cny"), Some(Json::null()))
  assert_false(ledger.stringify().contains("98765"))
  assert_true(
    ledger_list(ledger, "blockers")
    .to_json()
    .stringify()
    .contains("another project"),
  )
  let changed = {
    ..commercial,
    conversions: [
      ..commercial.conversions,
      {
        ..commercial.conversions[0],
        capacity_digest: "sha256:conflicting-capacity",
      },
    ],
  }
  ignore(
    service.commerce_application.store.put_json(
      "commercial-snapshot.json",
      changed.to_json(),
    ),
  )
  let ambiguous = service.episode_ledger(
    own.project_id,
    own.snapshot.graph.episodes[0].episode_id,
  )
  assert_eq(json_member(ambiguous, "quote_evidence"), Some(Json::null()))
  assert_true(
    ledger_list(ambiguous, "blockers")
    .to_json()
    .stringify()
    .contains("unambiguously"),
  )
}
