///|
fn postprocess_adapter(operation : String) -> @execution_app.ProviderAdapterConfig {
  {
    adapter_id: "fixture-" + operation, capability: operation,
    provider: "fixture-provider", endpoint: "https://fixture.invalid/" + operation,
    model: "fixture-" + operation + "-model",
    api_style: "mooncast-deterministic-ffmpeg-v1", secret_refs: {},
    timeout_seconds: 10, max_response_bytes: 1048576,
    default_parameters: {}, commercial_use: "validation-only",
    network_authority: false,
  }
}

///|
fn postprocess_asset(id : String, kind : String) -> @project.Asset {
  {
    asset_id: id, kind, version: 1,
    digest: "sha256:" + (id + kind).pad_end(64, '1')[:64].to_owned(),
    uri: "provider-artifact:" + id, rights_record_id: "rights:" + id,
    immutable: true,
  }
}

///|
async test "lip sync translation and upscale produce immutable importable outputs" {
  let root = "/tmp/mooncast-postprocess-" + @async.now().to_string()
  let execution = @execution_app.ProviderExecutionService::new(
    root + "/execution", root + "/artifacts",
    {
      contract: "mooncast.provider-catalog.v1",
      adapters: [postprocess_adapter("lip-sync"), postprocess_adapter("translation"), postprocess_adapter("upscale")],
      authority_actors: ["post-producer"],
    },
  )
  let service = PostprocessService::new(root + "/state", execution)
  let hero = postprocess_asset("hero", "character")
  let voice = postprocess_asset("voice", "voice")
  let video = postprocess_asset("video", "video")
  let text = postprocess_asset("script", "text")
  let graph : @project.ProjectGraph = {
    project_id: "post-project", revision: 8, title: "Postprocess fixture",
    target_duration_seconds: 3, maximum_budget_cny: 100.0,
    episodes: [{ episode_id: "episode", order: 1, title: "Episode", scenes: [{
      scene_id: "scene", order: 1, title: "Scene", shots: [{
        shot_id: "shot", order: 1, duration_ms: 3000,
        character_ids: ["hero"], location_id: "world", source_asset_ids: [],
      }],
    }] }], assets: [],
  }
  for index, operation in ["lip-sync", "translation", "upscale"] {
    let sources = match operation {
      "lip-sync" => [hero, voice, video]
      "translation" => [text]
      _ => [video]
    }
    let base : @postprocess_domain.PostprocessTask = {
      contract: "mooncast.postprocess-task.v1",
      reference: { id: "post-task", version: index + 1, digest: "" },
      project_id: graph.project_id, project_revision: 8, operation,
      source_assets: sources,
      prompt_digest: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
      rights_refs: ["rights://cleared/post"],
      shot_ids: if operation == "translation" { [] } else { ["shot"] },
      editor_project_id: Some("editor-project"),
      delivery_output_id: Some("delivery-output"),
      target_locale: if operation == "translation" { Some("zh-CN") } else { None },
      terminology_refs: if operation == "translation" { ["terms:v1"] } else { [] },
      claims_ledger_digest: if operation == "translation" { Some("sha256:claims") } else { None },
      target_width: if operation == "upscale" { Some(1920) } else { None },
      target_height: if operation == "upscale" { Some(1080) } else { None },
      provider_adapter_id: "fixture-" + operation,
      provider: "fixture-provider", model: "fixture-" + operation + "-model",
      permitted_data_class: "rights-cleared-validation",
      cost_ceiling_cny: 10.0, retry_limit: 2,
      created_at: "2026-07-19T12:00:00+08:00",
      provider_execution_authority: false, publication_authority: false,
    }
    let task = { ..base, reference: { ..base.reference, digest: @postprocess_domain.task_digest(base) } }
    ignore(service.record_task(task, graph))
    let output = service.run(graph.project_id, {
      expected_task_version: task.reference.version,
      expected_task_digest: task.reference.digest,
      actor: "post-producer", human_confirmed: true, network_authority: true,
    })
    assert_eq(output.operation, operation)
    assert_true(output.immutable)
    assert_false(output.publication_authority)
    assert_true(output.provenance_digest.has_prefix("sha256:"))
    let binding = service.bind(graph.project_id, {
      output_asset_id: output.reference.asset_id, output_asset_version: 1,
      destination_kind: "shot", destination_id: "shot", editor_media_digest: None,
      actor: "post-producer", bound_at: "2026-07-19T12:01:00+08:00",
      human_confirmed: true,
    })
    assert_true(binding.immutable)
  }
  let workspace = service.workspace(graph.project_id)
  assert_eq(workspace.tasks.length(), 3)
  assert_eq(workspace.outputs.length(), 3)
  assert_eq(workspace.bindings.length(), 3)
  assert_false(workspace.provider_execution_authority)
}
