///|
fn fixture_adapter(capability : String) -> @execution_app.ProviderAdapterConfig {
  {
    adapter_id: "fixture-" + capability,
    capability,
    provider: "fixture-provider",
    endpoint: "https://fixture.invalid/" + capability,
    model: "fixture-" + capability + "-model",
    api_style: "mooncast-deterministic-ffmpeg-v1",
    secret_refs: {},
    timeout_seconds: 10,
    max_response_bytes: 1048576,
    default_parameters: {},
    commercial_use: "validation-only",
    network_authority: false,
  }
}

///|
fn fixture_spec(
  asset_id : String,
  kind : String,
  capability : String,
) -> @factory.ReusableAssetSpec {
  {
    asset_id,
    asset_version: 1,
    kind,
    capability,
    title: asset_id,
    intent: {
      source_id: "moonwiki-" + asset_id,
      source_version: "1",
      source_digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
      provenance_ref: "moonwiki://asset-intent/" + asset_id,
    },
    prompt_digest: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    source_asset_refs: [],
    rights_refs: ["rights://cleared/" + asset_id],
    continuity_key: "continuity:" + asset_id,
    provider_adapter_id: "fixture-" + capability,
    provider: "fixture-provider",
    model: "fixture-" + capability + "-model",
    permitted_data_class: "rights-cleared-validation",
    variant_limit: 1,
    retry_limit: 2,
    cost_ceiling_cny: 0.0,
    dependent_shot_ids: ["factory-shot-1"],
  }
}

///|
async test "multimodal asset factory binds immutable approved versions before shots" {
  let root = "/tmp/mooncast-asset-factory-" + @async.now().to_string()
  let execution = @execution_app.ProviderExecutionService::new(
    root + "/execution",
    root + "/artifacts",
    {
      contract: "mooncast.provider-catalog.v1",
      adapters: [
        fixture_adapter("text"),
        fixture_adapter("image"),
        fixture_adapter("video"),
        fixture_adapter("voice"),
        fixture_adapter("music"),
      ],
      authority_actors: ["creative-director"],
    },
  )
  let service = AssetFactoryService::new(root + "/factory", execution)
  let graph : @project.ProjectGraph = {
    project_id: "factory-project",
    revision: 7,
    title: "Multimodal fixture",
    target_duration_seconds: 180,
    maximum_budget_cny: 1000.0,
    episodes: [
      {
        episode_id: "factory-episode",
        order: 1,
        title: "Episode",
        scenes: [
          {
            scene_id: "factory-scene",
            order: 1,
            title: "Scene",
            shots: [
              {
                shot_id: "factory-shot-1",
                order: 1,
                duration_ms: 12000,
                character_ids: [],
                location_id: "factory-world",
                source_asset_ids: [],
              },
            ],
          },
        ],
      },
    ],
    assets: [],
  }
  let base : @factory.AssetFactoryPlan = {
    contract: "mooncast.asset-factory-plan.v1",
    plan: { id: "factory-plan", version: 1, digest: "" },
    project_id: graph.project_id,
    project_revision: 7,
    specs: [
      fixture_spec("hero", "character", "image"),
      fixture_spec("location", "location", "image"),
      fixture_spec("narrator", "voice", "voice"),
      fixture_spec("score", "music", "music"),
      fixture_spec("motion", "motion", "video"),
      fixture_spec("copy", "text", "text"),
    ],
    total_cost_ceiling_cny: 0.0,
    created_at: "2026-07-19T12:00:00+08:00",
    publication_authority: false,
    provider_execution_authority: false,
  }
  let plan = {
    ..base,
    plan: { ..base.plan, digest: @factory.plan_digest(base) },
  }
  ignore(service.record_plan(plan, graph, 7))
  ignore(
    service.decide_plan(graph.project_id, {
      expected_plan_version: 1,
      expected_plan_digest: plan.plan.digest,
      decision: "approve",
      actor: "creative-director",
      actor_role: "creative-director",
      note: "Reviewed exact MoonWiki intent, rights, bounds, and dependencies",
      decided_at: "2026-07-19T12:01:00+08:00",
      human_confirmed: true,
    }),
  )
  let variants = service.run_pending(graph.project_id, {
    expected_plan_version: 1,
    expected_plan_digest: plan.plan.digest,
    actor: "creative-director",
    human_confirmed: true,
    network_authority: true,
  })
  assert_eq(variants.length(), 6)
  assert_true(variants.all(value => value.state == "completed"))
  assert_true(variants.all(value => !value.network_effect_performed))
  for variant in variants {
    for dimension in @factory.required_qc_dimensions() {
      ignore(
        service.record_finding({
          variant_id: variant.variant_id,
          dimension,
          status: "pass",
          evidence_digest: variant.output_digest.unwrap() + ":" + dimension,
          reviewer: "continuity-lead",
          reviewer_role: "human-reviewer",
          reviewed_at: "2026-07-19T12:02:00+08:00",
          human_confirmed: true,
        }),
      )
    }
    ignore(
      service.approve_asset({
        asset_id: variant.asset_id,
        asset_version: variant.asset_version,
        variant_id: variant.variant_id,
        actor: "creative-director",
        actor_role: "creative-director",
        approved_at: "2026-07-19T12:03:00+08:00",
        human_confirmed: true,
      }),
    )
  }
  let bindings = service.bind_approved_assets(
    graph.project_id,
    7,
    ["factory-shot-1"],
    "2026-07-19T12:04:00+08:00",
  )
  assert_eq(bindings.length(), 1)
  assert_eq(bindings[0].assets.length(), 6)
  assert_true(bindings[0].assets.all(value => value.immutable))
  assert_false(bindings[0].publication_authority)
  let workspace = service.workspace(graph.project_id)
  assert_eq(workspace.approved_assets.length(), 6)
  assert_eq(workspace.shot_bindings.length(), 1)
  assert_false(workspace.provider_execution_authority)
}
