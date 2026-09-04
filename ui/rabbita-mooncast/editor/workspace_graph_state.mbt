///|
fn workspace_recipe_id(recipe : WorkspaceRecipe) -> String {
  match recipe {
    CombineVideosRecipe => "combine-videos"
    BriefToDeliveryRecipe => "brief-to-generated-delivery"
  }
}

///|
fn workspace_recipe_title(recipe : WorkspaceRecipe) -> String {
  match recipe {
    CombineVideosRecipe => "Combine videos"
    BriefToDeliveryRecipe => "Brief to generated delivery"
  }
}

///|
fn workspace_artifact_kind_label(kind : WorkspaceArtifactKind) -> String {
  match kind {
    TextArtifact => "text"
    ImageArtifact => "image"
    AudioArtifact => "audio"
    VideoArtifact => "video"
    MediaCollection => "media collection"
    ShotCollection => "shot collection"
    TimelineArtifact => "timeline"
    ReviewDecisionArtifact => "review decision"
    DeliveryPackageArtifact => "delivery package"
    DataArtifact => "data"
    AnyArtifact => "any artifact"
  }
}

///|
fn workspace_authority_label(authority : WorkspaceAuthoritySummary) -> String {
  match authority {
    CognitiveMaintenance => "Cognitive maintenance"
    ExternalEffect => "External effect"
    Observe => "Observe"
    PhysicalEffect => "Physical effect"
    SandboxExecution => "Sandbox execution"
    WorkspaceMutation => "Workspace mutation"
  }
}

///|
fn workspace_definition(
  model : Model,
  definition_id : String,
) -> WorkspaceDefinitionSummary? {
  model.workspace_catalog
  .iter()
  .find_first(value => value.definition_id == definition_id)
}

///|
fn workspace_graph_node(
  model : Model,
  node_id : String,
) -> WorkspaceGraphNodeSummary? {
  model.workspace_graph.bind(graph => {
    graph.nodes.iter().find_first(value => value.node_id == node_id)
  })
}

///|
fn workspace_node_view_from_graph(
  model : Model,
  node : WorkspaceGraphNodeSummary,
) -> WorkspaceNodeView {
  match workspace_definition(model, node.definition_id) {
    Some(definition) =>
      {
        node_id: node.node_id,
        definition_id: node.definition_id,
        title: node.title,
        detail: definition.category + " · " + definition.tool_id,
        owner: definition.execution_owner,
        authority: workspace_authority_label(definition.authority),
        inputs: definition.inputs,
        outputs: definition.outputs,
        collapsed: node.collapsed,
      }
    None =>
      {
        node_id: node.node_id,
        definition_id: node.definition_id,
        title: node.title,
        detail: "Unavailable definition",
        owner: "unavailable",
        authority: "Unavailable",
        inputs: [],
        outputs: [],
        collapsed: node.collapsed,
      }
  }
}

///|
fn visible_workspace_nodes(model : Model) -> Array[WorkspaceNodeView] {
  match model.workspace_graph {
    Some(graph) =>
      graph.nodes.map(node => workspace_node_view_from_graph(model, node))
    None => workspace_nodes(model.selected_workspace_recipe)
  }
}

///|
fn workspace_graph_with_node(
  graph : WorkspaceGraphSummary,
  node : WorkspaceGraphNodeSummary,
) -> WorkspaceGraphSummary {
  let nodes = graph.nodes.map(value => {
    if value.node_id == node.node_id {
      node
    } else {
      value
    }
  })
  { ..graph, nodes, }
}

///|
fn begin_workspace_graph_edit(model : Model) -> Model {
  match model.workspace_graph {
    None => model
    Some(graph) =>
      {
        ..model,
        workspace_graph_undo: model.workspace_graph_undo + [graph],
        workspace_graph_redo: [],
        workspace_graph_dirty: true,
      }
  }
}

///|
fn replace_workspace_graph(
  model : Model,
  graph : WorkspaceGraphSummary,
) -> Model {
  { ..model, workspace_graph: Some(graph), workspace_graph_dirty: true }
}

///|
fn workspace_graph_unique_id(
  graph : WorkspaceGraphSummary,
  prefix : String,
) -> String {
  for index = graph.nodes.length() + graph.edges.length() + 1; ; index = index +
        1 {
    let candidate = prefix + "-" + index.to_string()
    if !graph.nodes.any(node => node.node_id == candidate) &&
      !graph.edges.any(edge => edge.edge_id == candidate) {
      return candidate
    }
  }
}

///|
fn workspace_graph_add_node(
  model : Model,
  definition : WorkspaceDefinitionSummary,
) -> Model {
  guard model.workspace_graph is Some(graph) else { return model }
  let prepared = begin_workspace_graph_edit(model)
  let node_id = workspace_graph_unique_id(graph, "node")
  let column = graph.nodes.length() % 4
  let row = graph.nodes.length() / 4
  let node : WorkspaceGraphNodeSummary = {
    node_id,
    definition_id: definition.definition_id,
    title: definition.display_name,
    x: 48 + column * 280,
    y: 96 + row * 190,
    parameters: [],
    collapsed: false,
  }
  let updated = { ..graph, nodes: graph.nodes + [node] }
  {
    ..replace_workspace_graph(prepared, updated),
    selected_workspace_node: node_id,
    workspace_node_palette_search: "",
    status: "Added " +
    definition.display_name +
    ". Connect required inputs before saving.",
    error: "",
  }
}

///|
fn workspace_graph_add_asset_node(model : Model, title : String) -> Model {
  guard workspace_definition(model, "workspace.asset-input") is Some(definition) else {
    return {
      ..model,
      error: "The governed asset-input definition is unavailable.",
    }
  }
  let added = workspace_graph_add_node(model, definition)
  guard added.workspace_graph is Some(graph) &&
    workspace_graph_node(added, added.selected_workspace_node) is Some(node) else {
    return added
  }
  let parameter : WorkspaceNodeParameterSummary = {
    key: "asset-label",
    value: title.to_json(),
  }
  {
    ..replace_workspace_graph(
      added,
      workspace_graph_with_node(graph, {
        ..node,
        title,
        parameters: [parameter],
      }),
    ),
    status: "Created a versioned asset input node. Bind the durable artifact before running.",
  }
}

///|
fn workspace_graph_bind_public_input(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) &&
    graph.nodes.iter().find_first(node => node.node_id == "brief") is Some(node) else {
    return model
  }
  let key = "public-input:brief"
  let value = model.workspace_public_input.to_json()
  if node.parameters.any(parameter => {
      parameter.key == key && parameter.value == value
    }) {
    return model
  }
  let parameters = node.parameters.filter(parameter => parameter.key != key)
  parameters.push({ key, value })
  let prepared = begin_workspace_graph_edit(model)
  replace_workspace_graph(
    prepared,
    workspace_graph_with_node(graph, { ..node, parameters, }),
  )
}

///|
fn workspace_graph_delete_selected(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) &&
    graph.nodes.any(node => node.node_id == model.selected_workspace_node) else {
    return model
  }
  let node_id = model.selected_workspace_node
  let prepared = begin_workspace_graph_edit(model)
  let updated = {
    ..graph,
    nodes: graph.nodes.filter(node => node.node_id != node_id),
    edges: graph.edges.filter(edge => {
      edge.source_node_id != node_id && edge.target_node_id != node_id
    }),
    output_node_ids: graph.output_node_ids.filter(value => value != node_id),
  }
  {
    ..replace_workspace_graph(prepared, updated),
    selected_workspace_node: updated.nodes
    .get(0)
    .map(node => node.node_id)
    .unwrap_or(""),
    status: "Deleted node and its connections.",
    error: "",
  }
}

///|
fn workspace_graph_duplicate_selected(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) &&
    graph.nodes
    .iter()
    .find_first(node => node.node_id == model.selected_workspace_node)
    is Some(source) else {
    return model
  }
  let prepared = begin_workspace_graph_edit(model)
  let node_id = workspace_graph_unique_id(graph, "node")
  let copy = {
    ..source,
    node_id,
    title: source.title + " copy",
    x: source.x + 40,
    y: source.y + 40,
  }
  {
    ..replace_workspace_graph(prepared, { ..graph, nodes: graph.nodes + [copy] }),
    selected_workspace_node: node_id,
    status: "Duplicated node without copying incoming authority or outputs.",
    error: "",
  }
}

///|
fn workspace_graph_toggle_collapsed(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) &&
    workspace_graph_node(model, model.selected_workspace_node) is Some(node) else {
    return model
  }
  let prepared = begin_workspace_graph_edit(model)
  replace_workspace_graph(
    prepared,
    workspace_graph_with_node(graph, { ..node, collapsed: !node.collapsed }),
  )
}

///|
fn workspace_graph_set_parameter(model : Model) -> Model {
  let key = model.workspace_parameter_key.trim().to_owned()
  guard !key.is_blank() &&
    model.workspace_graph is Some(graph) &&
    workspace_graph_node(model, model.selected_workspace_node) is Some(node) else {
    return { ..model, error: "Choose a node and enter a parameter key." }
  }
  let parameters = node.parameters.filter(parameter => parameter.key != key)
  parameters.push({ key, value: model.workspace_parameter_value.to_json() })
  let prepared = begin_workspace_graph_edit(model)
  {
    ..replace_workspace_graph(
      prepared,
      workspace_graph_with_node(graph, { ..node, parameters, }),
    ),
    workspace_parameter_key: "",
    workspace_parameter_value: "",
    status: "Updated node parameter. Save a revision before running.",
    error: "",
  }
}

///|
fn workspace_graph_delete_parameter(model : Model, key : String) -> Model {
  guard model.workspace_graph is Some(graph) &&
    workspace_graph_node(model, model.selected_workspace_node) is Some(node) else {
    return model
  }
  let prepared = begin_workspace_graph_edit(model)
  {
    ..replace_workspace_graph(
      prepared,
      workspace_graph_with_node(graph, {
        ..node,
        parameters: node.parameters.filter(parameter => parameter.key != key),
      }),
    ),
    status: "Removed node parameter. Save a revision before running.",
    error: "",
  }
}

///|
fn workspace_graph_move_node(
  model : Model,
  node_id : String,
  x : Int,
  y : Int,
) -> Model {
  guard model.workspace_graph is Some(graph) &&
    workspace_graph_node(model, node_id) is Some(node) else {
    return model
  }
  replace_workspace_graph(
    model,
    workspace_graph_with_node(graph, {
      ..node,
      x: Int::max(0, x),
      y: Int::max(0, y),
    }),
  )
}

///|
fn workspace_graph_connect(
  model : Model,
  source_node_id : String,
  source_port_id : String,
  target_node_id : String,
  target_port_id : String,
) -> Model {
  guard model.workspace_graph is Some(graph) else { return model }
  if source_node_id == target_node_id ||
    graph.edges.any(edge => {
      edge.source_node_id == source_node_id &&
      edge.source_port_id == source_port_id &&
      edge.target_node_id == target_node_id &&
      edge.target_port_id == target_port_id
    }) {
    return {
      ..model,
      error: "That connection already exists or targets the same node.",
    }
  }
  let edge_id = workspace_graph_unique_id(graph, "edge")
  let edge : WorkspaceGraphEdgeSummary = {
    edge_id,
    source_node_id,
    source_port_id,
    target_node_id,
    target_port_id,
  }
  let prepared = begin_workspace_graph_edit(model)
  replace_workspace_graph(prepared, { ..graph, edges: graph.edges + [edge] })
}

///|
fn workspace_graph_revision_body(graph : WorkspaceGraphSummary) -> Json {
  {
    "expected_revision": graph.revision,
    "title": graph.title,
    "nodes": graph.nodes,
    "edges": graph.edges,
    "output_node_ids": graph.output_node_ids,
    "actor": "Mooncast operator",
  }
}

///|
fn workspace_graph_run_body(
  graph : WorkspaceGraphSummary,
  selected_node_id : String,
) -> Json {
  {
    "expected_revision": graph.revision,
    "run_id": "",
    "created_by": "Mooncast operator",
    "provider": if graph.graph_id == "combine-videos" {
      "local"
    } else {
      "moonflow"
    },
    "model": if graph.graph_id == "combine-videos" {
      "ffmpeg"
    } else {
      "policy-routed"
    },
    "policy_digest": "sha256:workspace-default-policy",
    "maximum_retries": 2,
    "requested_output_node_ids": if !selected_node_id.is_blank() {
      [selected_node_id]
    } else {
      graph.output_node_ids
    },
  }
}

///|
fn workspace_port_accepts(
  input : WorkspaceArtifactKind,
  output : WorkspaceArtifactKind,
) -> Bool {
  input == AnyArtifact || output == AnyArtifact || input == output
}

///|
fn workspace_palette_definitions(
  model : Model,
) -> Array[WorkspaceDefinitionSummary] {
  let query = model.workspace_node_palette_search.trim().to_lower()
  let values : Array[WorkspaceDefinitionSummary] = []
  for definition in model.workspace_catalog {
    let searchable = (definition.display_name +
    " " +
    definition.category +
    " " +
    definition.tool_id).to_lower()
    if (query.is_blank() && definition.category == "control") ||
      (!query.is_blank() && searchable.contains(query)) {
      values.push(definition)
      if values.length() >= 12 {
        break
      }
    }
  }
  values
}

///|
fn start_workspace_graph_http(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  selected_only : Bool,
) -> @rabbita.Cmd {
  match model.workspace_graph {
    None => @rabbita.none
    Some(graph) =>
      @http.post(
        "/api/workspace/projects/" +
        graph.project_id +
        "/graphs/" +
        graph.graph_id +
        "/runs",
      )
      .with_json(
        workspace_graph_run_body(
          graph,
          if selected_only {
            model.selected_workspace_node
          } else {
            ""
          },
        ),
      )
      .expect_json(result => dispatch(WorkspaceRecipeStarted(result)))
  }
}
