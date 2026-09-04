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
    "project-workspace",
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

///|
async test "workspace recipes dispatch collaboration sharing and publishing are durable" {
  let root = "/tmp/mooncast-workspace-features-" + @async.now().to_string()
  let service = StudioService::new(root)
  let run = service.start_workspace_recipe("brief-to-generated-delivery", {
    project_id: "workspace-features",
    run_id: "run-features",
    created_by: "operator",
    created_at: "created",
    provider: "moonflow",
    model: "policy-routed",
    policy_digest: "sha256:policy",
    maximum_retries: 2,
    public_inputs: [
      { port_id: "brief", value: "A 30-second launch film".to_json() },
    ],
    requested_output_node_ids: ["review"],
  })
  assert_eq(run.nodes[0].state, @workspace.Ready)
  assert_true(run.plan.nodes.any(value => value.node_id == "review"))
  assert_false(run.plan.nodes.any(value => value.node_id == "delivery"))
  assert_true(
    run.plan.frozen_graph.nodes[0].parameters.any(value => {
      value.key == "public-input:brief"
    }),
  )
  let dispatch = service.prepare_workspace_dispatch(run.run_id, "brief", {
    input_refs: ["inline://brief"],
    created_at: "started",
  })
  assert_eq(dispatch.state, @workspace.PreparedDispatch)
  let completed = service.apply_workspace_dispatch_receipt(
    dispatch.dispatch_id,
    {
      contract: "mooncast.workspace-dispatch-receipt.v1",
      dispatch_id: dispatch.dispatch_id,
      idempotency_key: dispatch.idempotency_key,
      state: @workspace.SucceededDispatch,
      output_digest: "sha256:brief",
      output_ref: "workspace://artifact/brief",
      provider_receipt: { "worker": "moonclaw" }.to_json(),
      error_code: "",
      error_message: "",
      recorded_at: "finished",
    },
  )
  assert_eq(completed.state, @workspace.SucceededDispatch)
  assert_eq(
    service.get_workspace_run(run.run_id).nodes[1].state,
    @workspace.Ready,
  )

  let comment = service.record_workspace_comment({
    comment_id: "comment-features",
    project_id: "workspace-features",
    target_kind: @workspace.NodeTarget,
    target_id: "brief",
    body: "Tighten the first line.",
    actor: "reviewer",
    start_tick: None,
    end_tick: None,
    created_at: "commented",
  })
  assert_eq(comment.target_id, "brief")
  let share = service.create_workspace_share({
    share_id: "share-features",
    project_id: "workspace-features",
    target_kind: @workspace.RunTarget,
    target_id: run.run_id,
    mode: "client-review",
    token: "0123456789abcdef",
    expires_at: "tomorrow",
    created_by: "operator",
    created_at: "shared",
  })
  assert_false(share.publication_authority)
  let publication = service.publish_builtin_workspace_capsule(
    "brief-to-generated-delivery",
    {
      publication_id: "publication-features",
      project_id: "workspace-features",
      visibility: "workspace",
      actor: "operator",
      published_at: "published",
    },
  )
  assert_true(publication.immutable_digest.has_prefix("sha256:"))
  let features = service.workspace_features("workspace-features")
  assert_eq(features.comments.length(), 1)
  assert_eq(features.shares.length(), 1)
  assert_eq(features.publications.length(), 1)
  assert_eq(features.dispatches.length(), 1)
  assert_true(features.activities.length() >= 3)
  let search = service.search_workspace("workspace-features", "capsule")
  assert_true(search.matches.any(value => value.title == "capsule-published"))
  let global_search = service.search_workspace("", "capsule")
  assert_true(
    global_search.matches.any(value => value.title == "capsule-published"),
  )

  let search_body : Json = { "project_id": "", "query": "capsule" }
  let search_response = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/workspace/search",
    query: None,
    headers: Map([]),
    body: @utf8.encode(search_body.stringify()),
  })
  assert_eq(search_response.status, 200)

  let stream = service.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/workspace/runs/" + run.run_id + "/events",
    query: None,
    headers: Map([]),
    body: b"",
  })
  assert_eq(stream.status, 200)
  assert_eq(stream.headers["Content-Type"], "text/event-stream; charset=utf-8")
  assert_true(@utf8.decode(stream.body).contains("workspace-run-snapshot"))
}
