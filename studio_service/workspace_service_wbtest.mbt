///|
async test "workspace HTTP surface exposes catalog capsules graphs and plans" {
  let root = "/tmp/mooncast-workspace-api-" + @async.now().to_string()
  let service = StudioService::new(root)
  let catalog_response = service.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/workspace/catalog",
    query: None,
    headers: Map([]),
    body: b"",
  })
  assert_eq(catalog_response.status, 200)
  let catalog_body = @utf8.decode(catalog_response.body)
  assert_true(catalog_body.contains("workspace.media-concat"))
  assert_true(catalog_body.contains("tool:asset.generate"))
  assert_true(catalog_body.contains("\"publication_authority\":false"))

  let capsules_response = service.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/workspace/projects/workspace-test/capsules",
    query: None,
    headers: Map([]),
    body: b"",
  })
  assert_eq(capsules_response.status, 200)
  assert_true(@utf8.decode(capsules_response.body).contains("combine-videos"))

  let capsule = @workspace.combine_videos_capsule(
    "workspace-test", "operator", "created",
  )
  let saved = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/workspace/projects/workspace-test/graphs",
    query: None,
    headers: { "content-type": "application/json" },
    body: @utf8.encode(capsule.graph.to_json().stringify()),
  })
  assert_eq(saved.status, 201)
  let reopened = service.get_workspace_graph("workspace-test", "combine-videos")
  assert_eq(reopened, capsule.graph)
  let revision_two = {
    ..capsule.graph,
    revision: 2,
    title: "Combined launch cut",
  }
  ignore(service.save_workspace_graph(revision_two))
  assert_eq(
    service.get_workspace_graph("workspace-test", "combine-videos"),
    revision_two,
  )
  let history_response = service.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/workspace/projects/workspace-test/graphs/combine-videos/history",
    query: None,
    headers: Map([]),
    body: b"",
  })
  assert_eq(history_response.status, 200)
  let history = service.workspace_graph_history(
    "workspace-test", "combine-videos",
  )
  assert_eq(history.revisions.map(graph => graph.revision), [1, 2])
  assert_false(history.publication_authority)

  let plan_request : WorkspacePlanRequest = {
    graph: capsule.graph,
    requested_output_node_ids: ["register"],
    context: {
      provider: "local",
      model: "ffmpeg-bundled",
      policy_digest: "sha256:policy",
      cached_outputs: [],
    },
    frozen_at: "freeze",
  }
  let plan_response = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/workspace/plans",
    query: None,
    headers: { "content-type": "application/json" },
    body: @utf8.encode(plan_request.to_json().stringify()),
  })
  assert_eq(plan_response.status, 201)
  assert_true(
    @utf8.decode(plan_response.body).contains("workspace-execution-plan"),
  )
}

///|
async test "workspace runs persist transitions and artifacts are immutable" {
  let root = "/tmp/mooncast-workspace-run-" + @async.now().to_string()
  let service = StudioService::new(root)
  let capsule = @workspace.combine_videos_capsule(
    "workspace-run-test", "operator", "created",
  )
  let plan = service.freeze_workspace_plan({
    graph: capsule.graph,
    requested_output_node_ids: ["intake"],
    context: {
      provider: "local",
      model: "ffmpeg-bundled",
      policy_digest: "sha256:policy",
      cached_outputs: [],
    },
    frozen_at: "freeze",
  })
  let created = service.create_workspace_run({
    plan,
    run_id: "run-workspace-test",
    created_by: "operator",
    created_at: "created",
    maximum_retries: 2,
  })
  assert_eq(created.nodes[0].state, @workspace.Ready)
  let command : WorkspaceRunCommand = {
    command: "start",
    node_id: "intake",
    numerator: 0,
    denominator: 1,
    output_digest: "",
    output_ref: "",
    error_code: "",
    error_message: "",
    recorded_at: "started",
  }
  let running = service.apply_workspace_run_command(created.run_id, command)
  assert_eq(running.state, @workspace.RunningRun)
  let succeeded = service.apply_workspace_run_command(created.run_id, {
    ..command,
    command: "succeed",
    output_digest: "sha256:input",
    output_ref: "workspace://artifact/input",
    recorded_at: "finished",
  })
  assert_eq(succeeded.state, @workspace.SucceededRun)
  assert_eq(service.get_workspace_run(created.run_id), succeeded)

  let artifact = @workspace.new_workspace_artifact(
    "combined-video",
    1,
    @workspace.VideoArtifact,
    "sha256:output",
    "workspace://artifact/combined-video/1",
    "/api/workspace/artifacts/combined-video/1/preview",
    ["sha256:input"],
    capsule.graph.graph_id,
    created.run_id,
    "intake",
    "",
    "local",
    "ffmpeg-bundled",
    { "receipt_id": "local-concat-1" }.to_json(),
    "cleared",
    "passed",
    ["media-probe-passed"],
    0.0,
    1.0,
    "finished",
  )
  ignore(service.save_workspace_artifact(artifact))
  let listed = service.list_workspace_artifacts()
  assert_eq(listed.artifacts, [artifact])
  assert_false(listed.publication_authority)
}
