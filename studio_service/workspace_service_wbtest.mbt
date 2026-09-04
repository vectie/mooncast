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
  let graph_list = service.list_workspace_graphs("workspace-test")
  assert_eq(graph_list.graphs.map(graph => graph.graph_id), ["combine-videos"])
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
  assert_false(publication.immutable_digest.has_prefix("sha256:sha256:"))
  assert_true(
    service.workspace_capsules("workspace-features").capsules.any(capsule => {
      capsule.capsule_id == publication.capsule.capsule_id
    }),
  )
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

///|
async test "saved graph revisions drive runs cache claims and replay" {
  let root = "/tmp/mooncast-workspace-runtime-" + @async.now().to_string()
  let service = StudioService::new(root)
  let installed = service.install_workspace_capsule(
    "runtime-project",
    "combine-videos",
    { graph_id: "runtime-graph", title: "Runtime graph", actor: "operator" },
  )
  assert_eq(installed.revision, 1)
  let revised = service.revise_workspace_graph(
    "runtime-project",
    "runtime-graph",
    {
      expected_revision: 1,
      title: "Runtime graph revised",
      nodes: installed.nodes,
      edges: installed.edges,
      output_node_ids: installed.output_node_ids,
      actor: "operator",
    },
  )
  assert_eq(revised.revision, 2)
  let first = service.start_workspace_graph_run(
    "runtime-project",
    "runtime-graph",
    {
      expected_revision: 2,
      run_id: "runtime-run-1",
      created_by: "operator",
      provider: "local",
      model: "ffmpeg-bundled",
      policy_digest: "sha256:policy",
      maximum_retries: 2,
      requested_output_node_ids: ["intake"],
    },
  )
  let claimed = service.claim_workspace_run_node(first.run_id, {
    worker_id: "worker-1",
    execution_owner: "",
    input_refs: ["inline://inputs"],
  })
  assert_eq(claimed.node_id, "intake")
  ignore(
    service.apply_workspace_dispatch_receipt(claimed.dispatch_id, {
      contract: "mooncast.workspace-dispatch-receipt.v1",
      dispatch_id: claimed.dispatch_id,
      idempotency_key: claimed.idempotency_key,
      state: @workspace.SucceededDispatch,
      output_digest: "sha256:cached-intake",
      output_ref: "workspace://artifact/cached-intake",
      provider_receipt: { "worker": "worker-1" }.to_json(),
      error_code: "",
      error_message: "",
      recorded_at: "finished",
    }),
  )
  let replay = service.workspace_run_events(first.run_id, "")
  assert_true(replay.events.length() >= 3)
  let after_first = service.workspace_run_events(
    first.run_id,
    replay.events[0].event_id,
  )
  assert_eq(after_first.events.length(), replay.events.length() - 1)
  let second = service.start_workspace_graph_run(
    "runtime-project",
    "runtime-graph",
    {
      expected_revision: 2,
      run_id: "runtime-run-2",
      created_by: "operator",
      provider: "local",
      model: "ffmpeg-bundled",
      policy_digest: "sha256:policy",
      maximum_retries: 2,
      requested_output_node_ids: ["intake"],
    },
  )
  assert_eq(second.nodes[0].state, @workspace.Cached)
  let listed = service.list_workspace_runs("runtime-project", "", 0, 10)
  assert_eq(listed.total, 2)
}

///|
async test "asset library metadata is mutable while artifacts remain immutable" {
  let root = "/tmp/mooncast-workspace-assets-" + @async.now().to_string()
  let service = StudioService::new(root)
  let artifact = @workspace.new_workspace_artifact(
    "library-video",
    1,
    "asset-project",
    @workspace.VideoArtifact,
    "sha256:library-video",
    "workspace://artifact/library-video/1",
    "/api/workspace/artifacts/library-video/1/preview",
    [],
    "asset-graph",
    "asset-run",
    "asset-node",
    "",
    "local",
    "ffmpeg-bundled",
    Json::empty_object(),
    "cleared",
    "passed",
    [],
    0.0,
    2.0,
    "created",
  )
  ignore(service.save_workspace_artifact(artifact))
  let initial = service.list_workspace_asset_library(
    "asset-project", "library", "VideoArtifact", "", 0, 10, false,
  )
  assert_eq(initial.total, 1)
  let tagged = service.tag_workspace_asset("library-video", 1, {
    tags: ["Review", "review", "hero"],
    actor: "operator",
  })
  assert_eq(tagged.tags, ["review", "hero"])
  let filtered = service.list_workspace_asset_library(
    "asset-project", "", "", "hero", 0, 1, false,
  )
  assert_eq(filtered.entries.length(), 1)
  let hidden = service.delete_workspace_asset("library-video", 1, {
    actor: "operator",
  })
  assert_true(hidden.deleted)
  assert_eq(
    service.list_workspace_asset_library(
      "asset-project", "", "", "", 0, 10, false,
    ).total,
    0,
  )
  assert_eq(
    service.list_workspace_artifacts(project_id="asset-project").artifacts,
    [artifact],
  )
}

///|
async test "asset library lazily indexes artifacts created before the library" {
  let root = "/tmp/mooncast-workspace-legacy-asset-" + @async.now().to_string()
  let service = StudioService::new(root)
  let artifact = @workspace.new_workspace_artifact(
    "legacy-library-video",
    1,
    "legacy-asset-project",
    @workspace.VideoArtifact,
    "sha256:legacy-library-video",
    "workspace://artifact/legacy-library-video/1",
    "/api/workspace/artifacts/legacy-library-video/1/preview",
    [],
    "legacy-graph",
    "legacy-run",
    "legacy-node",
    "",
    "local",
    "ffmpeg-bundled",
    Json::empty_object(),
    "cleared",
    "passed",
    [],
    0.0,
    1.0,
    "created",
  )
  save_value(
    service.store,
    workspace_artifact_key(artifact.artifact_id, artifact.version),
    artifact,
  )
  let migrated = service.list_workspace_asset_library(
    "legacy-asset-project", "legacy-library", "VideoArtifact", "", 0, 10, false,
  )
  assert_eq(migrated.entries.length(), 1)
  assert_eq(migrated.entries[0].artifact, artifact)
  assert_eq(
    service.workspace_asset_entry(artifact.artifact_id, artifact.version).artifact,
    artifact,
  )
}

///|
async test "secure shares revoke and stored proposals apply once" {
  let root = "/tmp/mooncast-workspace-governed-" + @async.now().to_string()
  let service = StudioService::new(root)
  let installed = service.install_workspace_capsule(
    "governed-project",
    "brief-to-generated-delivery",
    { graph_id: "governed-graph", title: "Governed graph", actor: "operator" },
  )
  let created = service.create_secure_workspace_share({
    project_id: "governed-project",
    target_kind: @workspace.GraphTarget,
    target_id: installed.graph_id,
    mode: "client-review",
    created_by: "operator",
    lifetime_seconds: 600,
  })
  let access = service.access_workspace_share(
    created.share.share_id,
    created.token,
  )
  assert_eq(access.target_id, installed.graph_id)
  assert_true(created.access_path.has_prefix("/workspace/review/"))
  let review_page = service.dispatch_http({
    request_method: @host_http.Get,
    path: "/workspace/review/" + created.share.share_id,
    query: Some("token=" + created.token),
    headers: Map([]),
    body: b"",
  })
  assert_eq(review_page.status, 200)
  assert_eq(review_page.headers["Content-Type"], "text/html; charset=utf-8")
  assert_true(
    @utf8.decode(review_page.body).contains("Read-only client review"),
  )
  let revoked = service.revoke_workspace_share(created.share.share_id, {
    actor: "operator",
  })
  assert_true(revoked.revoked)

  let proposed = { ..installed, revision: 2, title: "Reviewed proposal" }
  let proposal : @workspace.AgentGraphProposal = {
    contract: "mooncast.agent-graph-proposal.v1",
    proposal_id: "proposal-governed",
    project_id: "governed-project",
    base_graph_id: installed.graph_id,
    base_graph_revision: installed.revision,
    proposed_graph: proposed,
    explanation: "Rename the reviewed graph",
    affected_node_ids: [],
    provider_ids: [],
    expected_cost_cny: 0.0,
    required_approvals: ["operator"],
    created_by: "moonclaw",
    created_at: "created",
    applied: false,
  }
  ignore(service.save_workspace_proposal(proposal))
  let review = service.review_saved_workspace_proposal(
    "governed-project",
    proposal.proposal_id,
  )
  assert_false(review.stale)
  assert_eq(review.current_graph_revision, 1)
  assert_eq(review.diff.changed_graph_fields, ["title"])
  let applied = service.apply_saved_workspace_proposal(
    "governed-project",
    proposal.proposal_id,
    { actor: "operator" },
  )
  assert_eq(applied.title, "Reviewed proposal")
  assert_true(
    service.list_workspace_proposals("governed-project").proposals[0].applied,
  )
}

///|
async test "capsule nodes expand into revisioned executable graph structure" {
  let root = "/tmp/mooncast-workspace-capsule-expand-" +
    @async.now().to_string()
  let service = StudioService::new(root)
  let graph : @workspace.WorkspaceGraph = {
    contract: "mooncast.workspace-graph.v1",
    graph_id: "outer-graph",
    project_id: "capsule-project",
    revision: 1,
    title: "Outer graph",
    nodes: [
      {
        node_id: "source",
        definition_id: "workspace.asset-input",
        title: "Source",
        x: 0,
        y: 0,
        parameters: [
          { key: "artifact-id", value: "source-1".to_json() },
          { key: "artifact-version", value: "1".to_json() },
          { key: "artifact-digest", value: "sha256:source".to_json() },
          { key: "artifact-uri", value: "/source/1".to_json() },
        ],
        collapsed: false,
      },
      {
        node_id: "sub",
        definition_id: "workspace.control.subgraph",
        title: "Reusable combine",
        x: 300,
        y: 100,
        parameters: [],
        collapsed: false,
      },
    ],
    edges: [
      {
        edge_id: "source-sub",
        source_node_id: "source",
        source_port_id: "asset",
        target_node_id: "sub",
        target_port_id: "input",
      },
    ],
    output_node_ids: ["sub"],
    created_by: "operator",
    created_at: "created",
  }
  ignore(service.save_workspace_graph(graph))
  let expanded = service.expand_workspace_capsule_node(
    graph.project_id,
    graph.graph_id,
    "sub",
    {
      expected_revision: 1,
      capsule_id: "combine-videos",
      capsule_version: 1,
      actor: "operator",
    },
  )
  assert_eq(expanded.revision, 2)
  assert_false(expanded.nodes.any(node => node.node_id == "sub"))
  assert_eq(expanded.nodes.length(), 6)
  assert_true(expanded.nodes.any(node => node.node_id == "sub--concat"))
  assert_true(
    expanded.edges.any(edge => {
      edge.edge_id == "source-sub" && edge.target_node_id == "sub--probe"
    }),
  )
  assert_eq(expanded.output_node_ids, ["sub--register"])
  assert_eq(
    service.workspace_graph_history(graph.project_id, graph.graph_id).revisions.length(),
    2,
  )
}
