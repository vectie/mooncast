///|
fn test_capsule() -> CreativeCapsule {
  combine_videos_capsule(
    "project-workspace", "operator", "2026-09-04T00:00:00Z",
  )
}

///|
fn test_context() -> ExecutionContext {
  {
    provider: "local",
    model: "ffmpeg-bundled",
    policy_digest: "sha256:policy",
    cached_outputs: [],
  }
}

///|
test "combine-videos capsule is a valid typed graph" {
  let capsule = test_capsule()
  let validation = validate_graph(capsule.graph, builtin_workspace_catalog())
  assert_true(validation.valid)
  inspect(
    validation.topological_node_ids.join(","),
    content="intake,probe,normalize,concat,verify,register",
  )
  assert_eq(capsule.public_inputs[0].artifact_kind, MediaCollection)
  assert_eq(capsule.public_outputs[0].artifact_kind, VideoArtifact)
}

///|
test "graph validation rejects incompatible ports and cycles" {
  let capsule = test_capsule()
  let incompatible : WorkflowEdge = {
    edge_id: "bad",
    source_node_id: "concat",
    source_port_id: "video",
    target_node_id: "probe",
    target_port_id: "media",
  }
  let graph = { ..capsule.graph, edges: capsule.graph.edges + [incompatible] }
  let validation = validate_graph(graph, builtin_workspace_catalog())
  assert_false(validation.valid)
  assert_true(
    validation.errors.any(value => value.contains("incompatible artifact kinds")),
  )
  assert_true(validation.errors.contains("graph contains a cycle"))
}

///|
test "planning is deterministic and limited to selected ancestors" {
  let capsule = test_capsule()
  let plan = freeze_plan(
    capsule.graph,
    builtin_workspace_catalog(),
    ["concat"],
    test_context(),
    "2026-09-04T00:01:00Z",
  )
  inspect(
    plan.nodes.map(node => node.node_id).join(","),
    content="intake,probe,normalize,concat",
  )
  assert_true(plan.graph_digest.has_prefix("sha256:"))
  assert_eq(
    plan.frozen_graph,
    materialize_graph_parameters(capsule.graph, builtin_workspace_catalog()),
  )
  assert_true(plan.nodes.all(node => node.tool_digest.has_prefix("sha256:")))
  assert_true(plan.plan_id.has_prefix("plan-"))
  assert_false(plan.publication_authority)
  let second = freeze_plan(
    capsule.graph,
    builtin_workspace_catalog(),
    ["concat"],
    test_context(),
    "later",
  )
  assert_eq(plan.plan_id, second.plan_id)
  assert_eq(
    plan.nodes.map(node => node.cache_key),
    second.nodes.map(node => node.cache_key),
  )
}

///|
test "matching content-addressed records produce cache hits" {
  let capsule = test_capsule()
  let first = freeze_plan(
    capsule.graph,
    builtin_workspace_catalog(),
    ["intake"],
    test_context(),
    "first",
  )
  let cached : CachedNodeOutput = {
    node_id: "intake",
    cache_key: first.nodes[0].cache_key,
    output_digest: "sha256:input",
    output_ref: "workspace://artifact/input",
  }
  let context = { ..test_context(), cached_outputs: [cached] }
  let second = freeze_plan(
    capsule.graph,
    builtin_workspace_catalog(),
    ["intake"],
    context,
    "second",
  )
  assert_true(second.nodes[0].cache_hit)
  assert_eq(second.nodes[0].cached_output_ref, "workspace://artifact/input")
}

///|
test "workspace runs expose node progress and unblock downstream work" {
  let capsule = test_capsule()
  let plan = freeze_plan(
    capsule.graph,
    builtin_workspace_catalog(),
    ["probe"],
    test_context(),
    "freeze",
  )
  let run = new_run(plan, "run-1", "operator", "created")
  assert_eq(run.nodes[0].state, Ready)
  assert_eq(run.nodes[1].state, Blocked)
  let running = run.start_node("intake", "started")
  assert_eq(running.state, RunningRun)
  let progressing = running.progress_node("intake", 1, 2, "progress")
  assert_eq(progressing.nodes[0].progress_numerator, 1)
  let completed = progressing.succeed_node(
    "intake", "sha256:intake", "workspace://artifact/intake", "done",
  )
  assert_eq(completed.nodes[0].state, Succeeded)
  assert_eq(completed.nodes[1].state, Ready)
}

///|
test "failed nodes retry and running nodes recover after restart" {
  let capsule = test_capsule()
  let plan = freeze_plan(
    capsule.graph,
    builtin_workspace_catalog(),
    ["intake"],
    test_context(),
    "freeze",
  )
  let running = new_run(plan, "run-2", "operator", "created").start_node(
    "intake", "started",
  )
  let recovered = recover_run_after_restart(running, "restart")
  assert_eq(recovered.nodes[0].state, Ready)
  assert_eq(recovered.nodes[0].retry_count, 1)
  assert_eq(recovered.nodes[0].attempts[0].error_code, "process-restarted")
  let failed = recovered
    .start_node("intake", "again")
    .fail_node("intake", "probe-failed", "bad media", "failed")
  assert_eq(failed.state, FailedRun)
  let retry = failed.retry_node("intake", "retry")
  assert_eq(retry.nodes[0].state, Ready)
  assert_eq(retry.nodes[0].retry_count, 2)
}

///|
test "agent proposals are revision checked and auditable" {
  let capsule = test_capsule()
  let proposed_graph = {
    ..capsule.graph,
    revision: 2,
    title: "Combine launch videos",
  }
  let proposal : AgentGraphProposal = {
    contract: "mooncast.agent-graph-proposal.v1",
    proposal_id: "proposal-1",
    project_id: capsule.graph.project_id,
    base_graph_id: capsule.graph.graph_id,
    base_graph_revision: 1,
    proposed_graph,
    explanation: "Rename the recipe for the launch task.",
    affected_node_ids: [],
    provider_ids: [],
    expected_cost_cny: 0.0,
    required_approvals: [],
    created_by: "moonclaw",
    created_at: "now",
    applied: false,
  }
  let diff = graph_diff(capsule.graph, proposed_graph)
  assert_true(diff.added_node_ids.is_empty())
  assert_eq(diff.changed_graph_fields, ["title"])
  let (applied, receipt) = apply_agent_proposal(capsule.graph, proposal)
  assert_eq(applied.revision, 2)
  assert_true(receipt.applied)
}

///|
test "artifacts preserve immutable lineage and time-ranged annotations" {
  let artifact = new_workspace_artifact(
    "asset-1",
    1,
    "project-workspace",
    VideoArtifact,
    "sha256:output",
    "workspace://artifact/asset-1/1",
    "/api/workspace/artifacts/asset-1/1/preview",
    ["sha256:source-a", "sha256:source-b"],
    "combine-videos",
    "run-1",
    "register",
    "",
    "local",
    "ffmpeg-bundled",
    { "receipt_id": "local-concat-1" }.to_json(),
    "cleared",
    "passed",
    ["streams-readable", "duration-positive"],
    0.0,
    12.5,
    "now",
  )
  let annotated = artifact.annotate({
    annotation_id: "comment-1",
    actor: "reviewer",
    body: "Check this cut.",
    start_tick: Some(10),
    end_tick: Some(20),
    created_at: "later",
  })
  assert_true(annotated.immutable)
  assert_eq(annotated.parent_digests.length(), 2)
  assert_eq(annotated.annotations.length(), 1)
  assert_eq(annotated.qc_results.length(), 2)
}

///|
test "manifest-backed generation capsule exposes external and human gates" {
  let tools = [
    @pack.tool_declaration(
      "brief.validate",
      "mooncast",
      "creative-brief",
      "creative-brief",
      @pack.SandboxExecution,
      idempotent=true,
      evidence_outputs=[],
      review_required=false,
    ),
    @pack.tool_declaration(
      "project.create",
      "mooncast",
      "creative-brief",
      "production-project",
      @pack.SandboxExecution,
      idempotent=true,
      evidence_outputs=[],
      review_required=false,
    ),
    @pack.tool_declaration(
      "shots.generate",
      "mooncast",
      "production-project",
      "asset-provenance",
      @pack.ExternalEffect,
      idempotent=true,
      evidence_outputs=[],
      review_required=true,
    ),
    @pack.tool_declaration(
      "asset.review",
      "mooncast",
      "asset-provenance",
      "review-decision",
      @pack.WorkspaceMutation,
      idempotent=true,
      evidence_outputs=[],
      review_required=true,
    ),
    @pack.tool_declaration(
      "delivery.package",
      "mooncast",
      "review-decision",
      "delivery-package",
      @pack.SandboxExecution,
      idempotent=true,
      evidence_outputs=[],
      review_required=false,
    ),
  ]
  let capsule = brief_to_delivery_capsule(
    "project-generated", "operator", "now",
  )
  let validation = validate_graph(capsule.graph, complete_node_catalog(tools))
  assert_true(validation.valid)
  let plan = freeze_plan(
    capsule.graph,
    complete_node_catalog(tools),
    ["delivery"],
    test_context(),
    "freeze",
  )
  assert_true(
    plan.nodes.any(node => {
      node.node_id == "generate" &&
      node.execution_owner == "moonflow" &&
      node.review_required
    }),
  )
  assert_true(
    plan.nodes.any(node => node.node_id == "review" && node.review_required),
  )
  let catalog = complete_node_catalog(tools)
  assert_true(
    catalog.any(node => {
      node.tool_id == "shots.generate" && node.node_kind == OperationNode
    }),
  )
  assert_true(
    catalog.any(node => {
      node.tool_id == "asset.review" && node.node_kind == HumanGateNode
    }),
  )
}

///|
test "capsule installation starts an independent graph lineage" {
  let capsule = test_capsule()
  let graph = instantiate_capsule(
    capsule, "launch-cut", "project-launch", "Launch cut", "creator", "now",
  )
  assert_eq(graph.graph_id, "launch-cut")
  assert_eq(graph.project_id, "project-launch")
  assert_eq(graph.revision, 1)
  assert_eq(graph.nodes.length(), capsule.graph.nodes.length())
}

///|
test "graph editing is revisioned typed and cycle safe" {
  let capsule = test_capsule()
  let moved = move_graph_node(capsule.graph, "concat", 900, 240)
  assert_eq(moved.revision, 2)
  assert_true(
    moved.nodes.any(node => node.node_id == "concat" && node.x == 900),
  )
  let parameterized = set_graph_node_parameter(moved, "concat", {
    key: "mode",
    value: "copy-or-normalize".to_json(),
  })
  assert_eq(parameterized.revision, 3)
  let disconnected = disconnect_graph_edge(parameterized, "e-concat-verify")
  assert_eq(disconnected.revision, 4)
  let reconnected = connect_graph_nodes(
    disconnected,
    {
      edge_id: "e-concat-verify-v2",
      source_node_id: "concat",
      source_port_id: "video",
      target_node_id: "verify",
      target_port_id: "video",
    },
    builtin_workspace_catalog(),
  )
  assert_eq(reconnected.revision, 5)
  let forked = fork_graph(
    reconnected, "combine-videos-vertical", "Combine vertical videos", "operator",
    "later",
  )
  assert_eq(forked.revision, 1)
  assert_eq(forked.graph_id, "combine-videos-vertical")
  let removed = remove_graph_node(forked, "normalize")
  assert_false(
    removed.edges.any(edge => {
      edge.source_node_id == "normalize" || edge.target_node_id == "normalize"
    }),
  )
}

///|
test "asset comparison promotion and specialized lenses are governed" {
  let first = new_workspace_artifact(
    "variant-a",
    1,
    "project-workspace",
    VideoArtifact,
    "sha256:variant-a",
    "workspace://artifact/variant-a/1",
    "/preview/a",
    ["sha256:source"],
    "graph-a",
    "run-a",
    "generate",
    "sha256:prompt",
    "provider-a",
    "model-a",
    { "receipt": "a" }.to_json(),
    "cleared",
    "passed",
    ["probe-passed"],
    1.0,
    5.0,
    "now",
  )
  let second = {
    ..first,
    artifact_id: "variant-b",
    digest: "sha256:variant-b",
    provider: "provider-b",
    duration_seconds: 6.0,
  }
  let comparison = compare_artifacts(
    "project-workspace",
    [first, second],
    "variant-a",
  )
  assert_true(comparison.comparable)
  assert_true(comparison.differences.contains("provider"))
  assert_true(comparison.differences.contains("duration"))
  let promotion = promote_artifact(
    "project-workspace", first, "master-candidate", "reviewer", "Approved", "later",
  )
  assert_eq(promotion.artifact_id, "variant-a")
  assert_false(promotion.publication_authority)
  let branch = branch_workspace_artifact(
    first, "variant-a-branch", "sha256:variant-a-branch", "workspace://artifact/variant-a-branch/1",
    "/preview/a-branch", "run-branch", "edit", "later",
  )
  assert_eq(branch.version, 1)
  assert_true(branch.parent_digests.contains(first.digest))
  assert_eq(specialized_lens_for(TextArtifact), ScriptLens)
  assert_eq(specialized_lens_for(AudioArtifact), AudioTranscriptLens)
  assert_eq(specialized_lens_for(ReviewDecisionArtifact), ReviewLens)
}

///|
test "collaboration shares and capsule publishing are least-authority" {
  let comment = new_workspace_comment(
    "comment-1",
    "project-workspace",
    NodeTarget,
    "generate",
    "  Try the alternate framing.  ",
    "reviewer",
    "now",
    Some(100),
    Some(200),
  )
  assert_eq(comment.body, "Try the alternate framing.")
  let presence = renew_workspace_presence(
    "project-workspace",
    "actor-1",
    "Director",
    NodeTarget,
    "generate",
    "later",
    "now",
  )
  assert_eq(presence.target_id, "generate")
  let share = create_workspace_share(
    "share-1",
    "project-workspace",
    RunTarget,
    "run-1",
    "client-review",
    "0123456789abcdef",
    "tomorrow",
    "operator",
    "now",
  )
  assert_true(share.token_digest.has_prefix("sha256:"))
  assert_false(share.token_digest.has_prefix("sha256:sha256:"))
  assert_false(share.publication_authority)
  let publication = publish_capsule(
    "publication-1",
    test_capsule(),
    "workspace",
    "operator",
    "now",
  )
  assert_true(publication.immutable_digest.has_prefix("sha256:"))
  assert_false(publication.immutable_digest.has_prefix("sha256:sha256:"))
  assert_false(publication.publication_authority)
  let promoted = capsule_from_graph(
    test_capsule().graph,
    builtin_workspace_catalog(),
    "combine-promoted",
    "Combine promoted",
    "Promoted from a successful run",
    "operator",
    "later",
  )
  assert_false(promoted.public_inputs.is_empty())
  assert_false(promoted.public_outputs.is_empty())
}

///|
test "provider dispatch is deterministic and receipt driven" {
  let capsule = test_capsule()
  let plan = freeze_plan(
    capsule.graph,
    builtin_workspace_catalog(),
    ["probe"],
    test_context(),
    "freeze",
  )
  let run = new_run(plan, "dispatch-run", "operator", "created")
  let dispatch = prepare_workspace_dispatch(
    run,
    "intake",
    ["workspace://input/folder"],
    "started",
  )
  let repeated = prepare_workspace_dispatch(
    run,
    "intake",
    ["workspace://input/folder"],
    "later",
  )
  assert_eq(dispatch.dispatch_id, repeated.dispatch_id)
  assert_eq(dispatch.state, PreparedDispatch)
  let completed = apply_dispatch_receipt(dispatch, {
    contract: "mooncast.workspace-dispatch-receipt.v1",
    dispatch_id: dispatch.dispatch_id,
    idempotency_key: dispatch.idempotency_key,
    state: SucceededDispatch,
    output_digest: "sha256:folder",
    output_ref: "workspace://artifact/folder",
    provider_receipt: { "worker": "moonclaw" }.to_json(),
    error_code: "",
    error_message: "",
    recorded_at: "finished",
  })
  assert_eq(completed.state, SucceededDispatch)
  let event = workspace_run_event(run, "snapshot")
  assert_true(workspace_sse(event).has_prefix("retry: 1000\n"))
  assert_true(workspace_sse(event).contains("event: workspace-run-snapshot"))
  assert_true(workspace_sse(event).contains("data: {"))
}
