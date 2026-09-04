///|
async test "workspace coordinator walks native nodes and pauses at human gates" {
  let root = "/tmp/mooncast-workspace-execution-" + @async.now().to_string()
  let service = StudioService::new(root)
  let graph : @workspace.WorkspaceGraph = {
    contract: "mooncast.workspace-graph.v1",
    graph_id: "native-walk",
    project_id: "native-project",
    revision: 1,
    title: "Native walk",
    nodes: [
      {
        node_id: "brief",
        definition_id: "workspace.brief-input",
        title: "Brief",
        x: 0,
        y: 0,
        parameters: [{ key: "text", value: "Make a launch film".to_json() }],
        collapsed: false,
      },
      {
        node_id: "approval",
        definition_id: "workspace.control.human-approval",
        title: "Approval",
        x: 240,
        y: 0,
        parameters: [],
        collapsed: false,
      },
      {
        node_id: "register",
        definition_id: "workspace.artifact-register",
        title: "Register",
        x: 480,
        y: 0,
        parameters: [],
        collapsed: false,
      },
    ],
    edges: [
      {
        edge_id: "brief-approval",
        source_node_id: "brief",
        source_port_id: "brief",
        target_node_id: "approval",
        target_port_id: "input",
      },
      {
        edge_id: "approval-register",
        source_node_id: "approval",
        source_port_id: "output",
        target_node_id: "register",
        target_port_id: "artifact",
      },
    ],
    output_node_ids: ["register"],
    created_by: "operator",
    created_at: "created",
  }
  ignore(service.save_workspace_graph(graph))
  let run = service.start_workspace_graph_run(
    graph.project_id,
    graph.graph_id,
    {
      expected_revision: 1,
      run_id: "native-run",
      created_by: "operator",
      provider: "local",
      model: "mooncast-native",
      policy_digest: "sha256:policy",
      maximum_retries: 1,
      requested_output_node_ids: ["register"],
    },
  )
  assert_eq(run.state, @workspace.Queued)
  let first = service.advance_workspace_run(run.run_id, { actor: "operator" })
  assert_eq(first.executed_node_ids, ["brief"])
  assert_eq(first.blockers.length(), 1)
  assert_eq(first.blockers[0].execution_owner, "human")
  let decided = service.decide_workspace_human_gate(run.run_id, "approval", {
    actor: "reviewer",
    decision: "approve",
    note: "Approved",
  })
  assert_eq(decided.nodes[1].state, @workspace.Succeeded)
  let decision = service.get_workspace_human_decision(run.run_id, "approval")
  assert_eq(decision.actor, "reviewer")
  assert_eq(decision.decision, "approve")
  assert_eq(decision.note, "Approved")
  assert_true(decision.digest.has_prefix("sha256:"))
  let completed = service.advance_workspace_run(run.run_id, {
    actor: "operator",
  })
  assert_eq(completed.executed_node_ids, ["register"])
  assert_eq(completed.run.state, @workspace.SucceededRun)
  assert_eq(completed.blockers, [])
  let output = service.get_workspace_native_output(run.run_id, "register")
  assert_eq(output.semantics, "immutable-artifact-registration")
  assert_true(output.digest.has_prefix("sha256:"))

  let assisted = service.assist_workspace_graph("native-project", {
    graph_id: graph.graph_id,
    target_node_id: "register",
    instruction: "Auto layout this graph and let me inspect the proposal",
    actor: "operator",
  })
  assert_true(assisted.proposal is Some(_))
  assert_false(assisted.execute_authority)
  assert_eq(
    service.list_workspace_proposals("native-project").proposals.length(),
    1,
  )
}
