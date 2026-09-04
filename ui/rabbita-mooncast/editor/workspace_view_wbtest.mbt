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
test "persisted run state drives generic nodes without masking active concat progress" {
  let base = initial_model()
  let run_node : WorkspaceNodeRunSummary = {
    node_id: "generate",
    state: Running,
    progress_numerator: 1,
    progress_denominator: 3,
    retry_count: 0,
    maximum_retries: 2,
    attempts: [],
  }
  let generic = {
    ..base,
    selected_workspace_recipe: BriefToDeliveryRecipe,
    workspace_run_nodes: [run_node],
  }
  assert_eq(workspace_node_state(generic, "generate"), "running")
  let concat = {
    ..base,
    utility_concat: { ..base.utility_concat, phase: "succeeded" },
    workspace_run_nodes: [
      {
        node_id: "concat",
        state: Ready,
        progress_numerator: 0,
        progress_denominator: 1,
        retry_count: 0,
        maximum_retries: 2,
        attempts: [],
      },
    ],
  }
  assert_eq(workspace_node_state(concat, "concat"), "succeeded")
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
  assert_false(undone.workspace_graph_dirty)
  let (_, redone) = update(_ => @rabbita.none, WorkspaceGraphRedo, undone)
  assert_eq(redone.workspace_graph.unwrap().nodes.length(), 1)
  assert_true(redone.workspace_graph_dirty)
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
  let body = workspace_graph_run_body(graph, "target", "operator").stringify()
  assert_true(body.contains("\"expected_revision\":7"))
  assert_true(body.contains("\"requested_output_node_ids\":[\"target\"]"))
}

///|
test "asset nodes bind the exact immutable artifact version" {
  let definition = test_workspace_definition("workspace.asset-input", false)
  let graph : WorkspaceGraphSummary = {
    contract: "mooncast.workspace-graph.v1",
    graph_id: "asset-graph",
    project_id: "asset-project",
    revision: 1,
    title: "Asset graph",
    nodes: [],
    edges: [],
    output_node_ids: [],
    created_by: "operator",
    created_at: "created",
  }
  let entry : WorkspaceAssetEntrySummary = {
    artifact: {
      artifact_id: "clip-47",
      version: 3,
      kind: VideoArtifact,
      digest: "sha256:exact",
      uri: "/api/assets/clip-47/3",
      preview_uri: "/api/assets/clip-47/3/preview",
      provider: "mooncast-native",
      node_id: "concat",
      qc_state: "passed",
      rights_state: "cleared",
      created_at: "created",
    },
    tags: ["source"],
    deleted: false,
    updated_at: "updated",
  }
  let bound = workspace_graph_add_asset_node(
    {
      ..initial_model(),
      workspace_catalog: [definition],
      workspace_graph: Some(graph),
    },
    entry,
  )
  let node = bound.workspace_graph.unwrap().nodes[0]
  assert_eq(node.title, "clip-47 v3")
  assert_true(
    node.parameters.any(parameter => {
      parameter.key == "artifact-id" && parameter.value == "clip-47".to_json()
    }),
  )
  assert_true(
    node.parameters.any(parameter => {
      parameter.key == "artifact-version" && parameter.value == "3".to_json()
    }),
  )
  assert_true(
    node.parameters.any(parameter => {
      parameter.key == "artifact-digest" &&
      parameter.value == "sha256:exact".to_json()
    }),
  )
  assert_true(
    node.parameters.any(parameter => {
      parameter.key == "artifact-uri" &&
      parameter.value == "/api/assets/clip-47/3".to_json()
    }),
  )
}

///|
test "canvas editing can reconnect copy group and lay out graph nodes" {
  let source_definition = test_workspace_definition("test.source", false)
  let target_definition = test_workspace_definition("test.target", true)
  let graph : WorkspaceGraphSummary = {
    contract: "mooncast.workspace-graph.v1",
    graph_id: "canvas-graph",
    project_id: "canvas-project",
    revision: 2,
    title: "Canvas graph",
    nodes: [
      {
        node_id: "source",
        definition_id: source_definition.definition_id,
        title: "Source",
        x: 900,
        y: 800,
        parameters: [],
        collapsed: false,
      },
      {
        node_id: "target-a",
        definition_id: target_definition.definition_id,
        title: "Target A",
        x: 1000,
        y: 900,
        parameters: [],
        collapsed: false,
      },
      {
        node_id: "target-b",
        definition_id: target_definition.definition_id,
        title: "Target B",
        x: 1100,
        y: 1000,
        parameters: [],
        collapsed: false,
      },
    ],
    edges: [
      {
        edge_id: "old-edge",
        source_node_id: "source",
        source_port_id: "output",
        target_node_id: "target-a",
        target_port_id: "input",
      },
    ],
    output_node_ids: ["target-a"],
    created_by: "operator",
    created_at: "created",
  }
  let model = {
    ..initial_model(),
    workspace_catalog: [source_definition, target_definition],
    workspace_graph: Some(graph),
    selected_workspace_node: "source",
    selected_workspace_node_ids: ["source", "target-a"],
    selected_workspace_edge: "old-edge",
  }
  let reconnected = workspace_graph_connect(
    model, "source", "output", "target-b", "input",
  )
  assert_eq(reconnected.workspace_graph.unwrap().edges.length(), 1)
  assert_eq(
    reconnected.workspace_graph.unwrap().edges[0].target_node_id,
    "target-b",
  )
  let copied = workspace_graph_copy_selection({
    ..reconnected,
    selected_workspace_node_ids: ["source", "target-b"],
  })
  let pasted = workspace_graph_paste_selection(copied)
  assert_eq(pasted.workspace_graph.unwrap().nodes.length(), 5)
  assert_eq(pasted.workspace_graph.unwrap().edges.length(), 2)
  let grouped = workspace_graph_group_selection(pasted)
  assert_true(
    grouped.workspace_graph.unwrap().nodes
    .filter(node => {
      grouped.selected_workspace_node_ids.contains(node.node_id) &&
      node.parameters.any(parameter => parameter.key == "workspace:group")
    })
    .length() ==
    2,
  )
  let laid_out = workspace_graph_auto_layout(grouped)
  assert_eq(laid_out.workspace_graph.unwrap().nodes[0].x, 48)
  assert_eq(laid_out.workspace_graph.unwrap().nodes[0].y, 96)
}

///|
test "asset library URL includes query kind tag and pagination" {
  let url = workspace_asset_library_url({
    ..initial_model(),
    project_id: "project-1",
    workspace_asset_query: "launch clip",
    workspace_asset_kind: "VideoArtifact",
    workspace_asset_tag: "hero take",
    workspace_asset_offset: 20,
    workspace_asset_limit: 10,
  })
  assert_true(url.contains("q=launch%20clip"))
  assert_true(url.contains("kind=VideoArtifact"))
  assert_true(url.contains("tag=hero%20take"))
  assert_true(url.contains("offset=20"))
  assert_true(url.contains("limit=10"))
}

///|
test "installable capsule versions load for subgraph expansion" {
  let response : Json = {
    "capsules": [
      {
        "capsule_id": "combine-videos",
        "version": 1,
        "title": "Combine videos",
        "summary": "Deterministic local assembly",
      },
      {
        "capsule_id": "promoted-cut",
        "version": 4,
        "title": "Promoted cut",
        "summary": "Reviewed project template",
      },
    ],
  }
  let (_, loaded) = update(
    _ => @rabbita.none,
    WorkspaceCapsulesLoaded(Ok(response)),
    initial_model(),
  )
  assert_eq(loaded.workspace_capsules.length(), 2)
  assert_eq(loaded.workspace_capsules[1].capsule_id, "promoted-cut")
  assert_eq(loaded.workspace_capsules[1].version, 4)
}
