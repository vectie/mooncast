///|
test "creative workspace is the primary lens" {
  let model = initial_model()
  assert_eq(model.workspace_lens, GraphLens)
  assert_eq(model.selected_workspace_recipe, CombineVideosRecipe)
  assert_eq(model.selected_workspace_node, "concat")
  assert_eq(workspace_nodes(CombineVideosRecipe).length(), 6)
  assert_eq(workspace_node_state(model, "intake"), "ready")
  assert_eq(workspace_node_state(model, "concat"), "blocked")
}

///|
test "concat activity projects onto inspectable node states" {
  let running = {
    ..initial_model(),
    utility_concat: { ..initial_model().utility_concat, phase: "running" },
  }
  assert_eq(workspace_node_state(running, "intake"), "ready")
  assert_eq(workspace_node_state(running, "probe"), "succeeded")
  assert_eq(workspace_node_state(running, "normalize"), "running")
  assert_eq(workspace_node_state(running, "concat"), "running")
  assert_eq(workspace_node_state(running, "verify"), "blocked")

  let succeeded = {
    ..running,
    utility_concat: { ..running.utility_concat, phase: "succeeded" },
  }
  assert_true(
    workspace_nodes(CombineVideosRecipe).all(node => {
      workspace_node_state(succeeded, node.node_id) ==
      (if node.node_id == "intake" { "ready" } else { "succeeded" })
    }),
  )
}

///|
test "recipe selection changes the visible graph and inspector focus" {
  let (_, model) = update(
    _ => @rabbita.none,
    SelectWorkspaceRecipe(BriefToDeliveryRecipe),
    initial_model(),
  )
  assert_eq(model.selected_workspace_recipe, BriefToDeliveryRecipe)
  assert_eq(model.selected_workspace_node, "generate")
  assert_eq(selected_workspace_node(model).owner, "MoonFlow")
  assert_eq(workspace_nodes(BriefToDeliveryRecipe).length(), 6)
}

///|
test "workspace lens and inspector selection update without mutation" {
  let model = initial_model()
  let (_, editor) = update(
    _ => @rabbita.none,
    SwitchWorkspaceLens(EditorLens),
    model,
  )
  assert_eq(editor.workspace_lens, EditorLens)
  let (_, selected) = update(
    _ => @rabbita.none,
    SelectWorkspaceNode("verify"),
    editor,
  )
  assert_eq(selected.selected_workspace_node, "verify")
  assert_eq(selected.workspace_lens, EditorLens)
}

///|
fn test_workspace_definition(
  id : String,
  input : Bool,
) -> WorkspaceDefinitionSummary {
  {
    definition_id: id,
    display_name: id,
    category: "test",
    node_kind: OperationNode,
    tool_id: "tool:test",
    inputs: if input {
      [
        {
          port_id: "input",
          label: "Input",
          schema_id: "mooncast.artifact.any.v1",
          artifact_kind: AnyArtifact,
          cardinality: One,
          required: true,
        },
      ]
    } else {
      []
    },
    outputs: [
      {
        port_id: "output",
        label: "Output",
        schema_id: "mooncast.artifact.any.v1",
        artifact_kind: AnyArtifact,
        cardinality: One,
        required: true,
      },
    ],
    authority: SandboxExecution,
    execution_owner: "mooncast",
    idempotent: true,
    review_required: false,
    evidence_outputs: ["workspace/artifacts"],
  }
}

///|
test "graph edits use persisted graph state with reversible history" {
  let definition = test_workspace_definition("test.operation", false)
  let graph : WorkspaceGraphSummary = {
    contract: "mooncast.workspace-graph.v1",
    graph_id: "test-graph",
    project_id: "test-project",
    revision: 3,
    title: "Test graph",
    nodes: [],
    edges: [],
    output_node_ids: [],
    created_by: "operator",
    created_at: "created",
  }
  let model = {
    ..initial_model(),
    workspace_catalog: [definition],
    workspace_graph: Some(graph),
  }
  let added = workspace_graph_add_node(model, definition)
  assert_true(added.workspace_graph_dirty)
  assert_eq(added.workspace_graph_undo, [graph])
  assert_eq(added.workspace_graph.unwrap().nodes.length(), 1)
  let (_, undone) = update(_ => @rabbita.none, WorkspaceGraphUndo, added)
  assert_eq(undone.workspace_graph, Some(graph))
  let (_, redone) = update(_ => @rabbita.none, WorkspaceGraphRedo, undone)
  assert_eq(redone.workspace_graph.unwrap().nodes.length(), 1)
}

///|
test "typed graph connections and run body target the saved revision" {
  let source_definition = test_workspace_definition("test.source", false)
  let target_definition = test_workspace_definition("test.target", true)
  let graph : WorkspaceGraphSummary = {
    contract: "mooncast.workspace-graph.v1",
    graph_id: "test-graph",
    project_id: "test-project",
    revision: 7,
    title: "Test graph",
    nodes: [
      {
        node_id: "source",
        definition_id: source_definition.definition_id,
        title: "Source",
        x: 1,
        y: 2,
        parameters: [],
        collapsed: false,
      },
      {
        node_id: "target",
        definition_id: target_definition.definition_id,
        title: "Target",
        x: 3,
        y: 4,
        parameters: [],
        collapsed: false,
      },
    ],
    edges: [],
    output_node_ids: ["target"],
    created_by: "operator",
    created_at: "created",
  }
  let model = {
    ..initial_model(),
    workspace_catalog: [source_definition, target_definition],
    workspace_graph: Some(graph),
  }
  let connected = workspace_graph_connect(
    model, "source", "output", "target", "input",
  )
  assert_eq(connected.workspace_graph.unwrap().edges.length(), 1)
  let body = workspace_graph_run_body(graph, "target").stringify()
  assert_true(body.contains("\"expected_revision\":7"))
  assert_true(body.contains("\"requested_output_node_ids\":[\"target\"]"))
}
