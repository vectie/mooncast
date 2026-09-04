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
fn decode_workspace_catalog(
  response : Json,
) -> (Array[WorkspaceDefinitionSummary], Int) {
  let envelope : WorkspaceCatalogRawPayload = @json.from_json(response) catch {
    _ => return ([], -1)
  }
  let definitions : Array[WorkspaceDefinitionSummary] = []
  let mut rejected = 0
  for value in envelope.definitions {
    let decoded : WorkspaceDefinitionSummary? = Some(@json.from_json(value)) catch {
      _ => None
    }
    match decoded {
      Some(definition) => definitions.push(definition)
      None => rejected = rejected + 1
    }
  }
  (definitions, rejected)
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
    parameters: definition.parameters.filter_map(parameter => {
      parameter.default_value.map(value => {
        key: parameter.parameter_id,
        value,
      })
    }),
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
fn workspace_graph_add_asset_node(
  model : Model,
  entry : WorkspaceAssetEntrySummary,
) -> Model {
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
  let artifact = entry.artifact
  let parameters : Array[WorkspaceNodeParameterSummary] = [
    { key: "artifact-id", value: artifact.artifact_id.to_json() },
    { key: "artifact-version", value: artifact.version.to_string().to_json() },
    { key: "artifact-digest", value: artifact.digest.to_json() },
    { key: "artifact-uri", value: artifact.uri.to_json() },
    { key: "artifact-kind", value: artifact.kind.to_json() },
  ]
  {
    ..replace_workspace_graph(
      added,
      workspace_graph_with_node(graph, {
        ..node,
        title: artifact.artifact_id + " v" + artifact.version.to_string(),
        parameters,
      }),
    ),
    status: "Bound immutable asset version " +
    artifact.artifact_id +
    " v" +
    artifact.version.to_string() +
    ".",
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
fn workspace_asset_library_url(model : Model) -> String {
  let query = model.workspace_asset_query
    .trim()
    .to_owned()
    .replace_all(old=" ", new="%20")
  "/api/workspace/projects/" +
  model.project_id +
  "/assets?limit=" +
  model.workspace_asset_limit.to_string() +
  "&offset=" +
  model.workspace_asset_offset.to_string() +
  (if query.is_blank() { "" } else { "&q=" + query }) +
  (if model.workspace_asset_kind.is_blank() {
    ""
  } else {
    "&kind=" + model.workspace_asset_kind
  }) +
  (if model.workspace_asset_tag.trim().is_blank() {
    ""
  } else {
    "&tag=" +
    model.workspace_asset_tag.trim().to_owned().replace_all(old=" ", new="%20")
  })
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
fn workspace_graph_delete_selected_edge(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) &&
    graph.edges.any(edge => edge.edge_id == model.selected_workspace_edge) else {
    return model
  }
  let prepared = begin_workspace_graph_edit(model)
  {
    ..replace_workspace_graph(prepared, {
      ..graph,
      edges: graph.edges.filter(edge => {
        edge.edge_id != model.selected_workspace_edge
      }),
    }),
    selected_workspace_edge: "",
    status: "Deleted selected connection.",
    error: "",
  }
}

///|
fn workspace_graph_copy_selection(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) else { return model }
  let ids = if model.selected_workspace_node_ids.is_empty() {
    [model.selected_workspace_node]
  } else {
    model.selected_workspace_node_ids
  }
  let nodes = graph.nodes.filter(node => ids.contains(node.node_id))
  let edges = graph.edges.filter(edge => {
    ids.contains(edge.source_node_id) && ids.contains(edge.target_node_id)
  })
  {
    ..model,
    workspace_clipboard_nodes: nodes,
    workspace_clipboard_edges: edges,
    status: "Copied {nodes.length()} node(s) and {edges.length()} internal edge(s).",
    error: "",
  }
}

///|
fn workspace_graph_paste_selection(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) &&
    !model.workspace_clipboard_nodes.is_empty() else {
    return model
  }
  let nodes = graph.nodes.copy()
  let edges = graph.edges.copy()
  let pasted_ids : Array[String] = []
  for index, source in model.workspace_clipboard_nodes {
    let node_id = workspace_graph_unique_id(
      { ..graph, nodes: nodes.copy(), edges: edges.copy() },
      "node",
    )
    nodes.push({
      ..source,
      node_id,
      title: source.title + " copy",
      x: source.x + 48,
      y: source.y + 48,
    })
    pasted_ids.push(node_id)
    ignore(index)
  }
  for source_edge in model.workspace_clipboard_edges {
    let mut source_index = -1
    let mut target_index = -1
    for index, source_node in model.workspace_clipboard_nodes {
      if source_node.node_id == source_edge.source_node_id {
        source_index = index
      }
      if source_node.node_id == source_edge.target_node_id {
        target_index = index
      }
    }
    if source_index >= 0 && target_index >= 0 {
      edges.push({
        ..source_edge,
        edge_id: workspace_graph_unique_id(
          { ..graph, nodes: nodes.copy(), edges: edges.copy() },
          "edge",
        ),
        source_node_id: pasted_ids[source_index],
        target_node_id: pasted_ids[target_index],
      })
    }
  }
  let prepared = begin_workspace_graph_edit(model)
  {
    ..replace_workspace_graph(prepared, { ..graph, nodes, edges }),
    selected_workspace_node: pasted_ids[0],
    selected_workspace_node_ids: pasted_ids,
    status: "Pasted {pasted_ids.length()} node(s) with internal connections.",
    error: "",
  }
}

///|
fn workspace_graph_group_selection(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) &&
    model.selected_workspace_node_ids.length() >= 2 else {
    return { ..model, error: "Select at least two nodes to create a group." }
  }
  let group_id = workspace_graph_unique_id(graph, "group")
  let nodes = graph.nodes.map(node => {
    if !model.selected_workspace_node_ids.contains(node.node_id) {
      return node
    }
    let parameters = node.parameters.filter(parameter => {
      parameter.key != "workspace:group"
    })
    parameters.push({ key: "workspace:group", value: group_id.to_json() })
    { ..node, parameters, }
  })
  let prepared = begin_workspace_graph_edit(model)
  {
    ..replace_workspace_graph(prepared, { ..graph, nodes, }),
    status: "Grouped selected nodes as " + group_id + ".",
    error: "",
  }
}

///|
fn workspace_graph_toggle_mode(model : Model, key : String) -> Model {
  guard model.workspace_graph is Some(graph) &&
    workspace_graph_node(model, model.selected_workspace_node) is Some(node) else {
    return model
  }
  let parameters = node.parameters.filter(parameter => parameter.key != key)
  let enabled = !node.parameters.any(parameter => {
    parameter.key == key && parameter.value == true.to_json()
  })
  parameters.push({ key, value: enabled.to_json() })
  let prepared = begin_workspace_graph_edit(model)
  {
    ..replace_workspace_graph(
      prepared,
      workspace_graph_with_node(graph, { ..node, parameters, }),
    ),
    status: key + (if enabled { " enabled." } else { " disabled." }),
    error: "",
  }
}

///|
fn workspace_graph_auto_layout(model : Model) -> Model {
  guard model.workspace_graph is Some(graph) else { return model }
  let nodes : Array[WorkspaceGraphNodeSummary] = []
  for index, node in graph.nodes {
    nodes.push({ ..node, x: 48 + index % 4 * 280, y: 96 + index / 4 * 190 })
  }
  let prepared = begin_workspace_graph_edit(model)
  {
    ..replace_workspace_graph(prepared, { ..graph, nodes, }),
    status: "Applied deterministic grid layout.",
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
  let value : Json = match model.workspace_parameter_type {
    "boolean" =>
      (model.workspace_parameter_value.trim().to_lower() == "true").to_json()
    "number" => parse_number(model.workspace_parameter_value, 0.0).to_json()
    "json" =>
      @json.parse(model.workspace_parameter_value) catch {
        _ => return { ..model, error: "Parameter JSON is invalid." }
      }
    _ => model.workspace_parameter_value.to_json()
  }
  {
    ..workspace_graph_write_parameter(model, graph, node, key, value),
    workspace_parameter_key: "",
    workspace_parameter_value: "",
  }
}

///|
fn workspace_graph_write_parameter(
  model : Model,
  graph : WorkspaceGraphSummary,
  node : WorkspaceGraphNodeSummary,
  key : String,
  value : Json,
) -> Model {
  let parameters = node.parameters.filter(parameter => parameter.key != key)
  parameters.push({ key, value })
  parameters.sort_by((left, right) => left.key.compare(right.key))
  let prepared = begin_workspace_graph_edit(model)
  {
    ..replace_workspace_graph(
      prepared,
      workspace_graph_with_node(graph, { ..node, parameters, }),
    ),
    status: "Updated node parameter. Save a revision before running.",
    error: "",
  }
}

///|
fn workspace_declared_parameter(
  model : Model,
  node : WorkspaceGraphNodeSummary,
  key : String,
) -> WorkspaceParameterDefinition? {
  workspace_definition(model, node.definition_id).bind(definition => {
    definition.parameters
    .iter()
    .find_first(parameter => parameter.parameter_id == key)
  })
}

///|
fn workspace_parameter_value(
  node : WorkspaceGraphNodeSummary,
  definition : WorkspaceParameterDefinition,
) -> Json? {
  match
    node.parameters
    .iter()
    .find_first(parameter => parameter.key == definition.parameter_id)
    .map(parameter => parameter.value) {
    Some(value) => Some(value)
    None => definition.default_value
  }
}

///|
fn workspace_parameter_text(
  node : WorkspaceGraphNodeSummary,
  definition : WorkspaceParameterDefinition,
) -> String {
  match workspace_parameter_value(node, definition) {
    Some(Json::String(value)) => value
    Some(value) => value.stringify()
    None => ""
  }
}

///|
fn workspace_parameter_boolean(
  node : WorkspaceGraphNodeSummary,
  definition : WorkspaceParameterDefinition,
) -> Bool {
  match workspace_parameter_value(node, definition) {
    Some(Json::True) => true
    _ => false
  }
}

///|
fn workspace_parameter_number(value : Json) -> Double? {
  match value {
    Json::Number(number, ..) => Some(number)
    _ => None
  }
}

///|
fn workspace_declared_parameter_value(
  definition : WorkspaceParameterDefinition,
  raw : String,
) -> Result[Json, String] {
  let parsed : Json = match definition.value_kind {
    TextValue | AssetReferenceValue | ProviderValue | ModelValue =>
      raw.to_json()
    BooleanValue => (raw.trim().to_lower() == "true").to_json()
    IntegerValue | NumberValue | JsonValue =>
      @json.parse(raw) catch {
        _ => return Err("Enter valid " + definition.label.to_lower() + ".")
      }
  }
  let type_valid = match (definition.value_kind, parsed) {
    (
      TextValue
      | AssetReferenceValue
      | ProviderValue
      | ModelValue,
      Json::String(_),
    ) => true
    (IntegerValue | NumberValue, Json::Number(_, ..)) => true
    (BooleanValue, Json::True | Json::False) => true
    (JsonValue, _) => true
    _ => false
  }
  if !type_valid {
    return Err(definition.label + " has the wrong value type.")
  }
  if !definition.options.is_empty() {
    guard parsed is Json::String(value) &&
      definition.options.any(option => option.value == value) else {
      return Err(definition.label + " is not an allowed option.")
    }
  }
  match workspace_parameter_number(parsed) {
    Some(number) =>
      if definition.minimum.map(value => number < value).unwrap_or(false) ||
        definition.maximum.map(value => number > value).unwrap_or(false) {
        return Err(definition.label + " is outside its allowed range.")
      }
    None => ()
  }
  Ok(parsed)
}

///|
fn workspace_graph_set_declared_parameter(
  model : Model,
  node_id : String,
  key : String,
  raw : String,
) -> Model {
  guard model.workspace_graph is Some(graph) &&
    workspace_graph_node(model, node_id) is Some(node) &&
    workspace_declared_parameter(model, node, key) is Some(definition) else {
    return { ..model, error: "The declared parameter is unavailable." }
  }
  match workspace_declared_parameter_value(definition, raw) {
    Err(message) => { ..model, error: message }
    Ok(value) => workspace_graph_write_parameter(model, graph, node, key, value)
  }
}

///|
fn workspace_graph_toggle_declared_boolean(
  model : Model,
  node_id : String,
  key : String,
) -> Model {
  guard model.workspace_graph is Some(graph) &&
    workspace_graph_node(model, node_id) is Some(node) &&
    workspace_declared_parameter(model, node, key) is Some(definition) &&
    definition.value_kind == BooleanValue else {
    return { ..model, error: "The boolean parameter is unavailable." }
  }
  workspace_graph_write_parameter(
    model,
    graph,
    node,
    key,
    (!workspace_parameter_boolean(node, definition)).to_json(),
  )
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
  let edges = if model.selected_workspace_edge.is_blank() {
    graph.edges.copy()
  } else {
    graph.edges.filter(edge => edge.edge_id != model.selected_workspace_edge)
  }
  if source_node_id == target_node_id ||
    edges.any(edge => {
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
  {
    ..replace_workspace_graph(prepared, { ..graph, edges: edges + [edge] }),
    selected_workspace_edge: edge_id,
  }
}

///|
fn workspace_graph_revision_body(
  graph : WorkspaceGraphSummary,
  actor : String,
) -> Json {
  {
    "expected_revision": graph.revision,
    "title": graph.title,
    "nodes": graph.nodes,
    "edges": graph.edges,
    "output_node_ids": graph.output_node_ids,
    "actor": actor,
  }
}

///|
fn workspace_graph_run_body(
  graph : WorkspaceGraphSummary,
  selected_node_id : String,
  actor : String,
) -> Json {
  {
    "expected_revision": graph.revision,
    "run_id": "",
    "created_by": actor,
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
          model.workspace_actor_name,
        ),
      )
      .expect_json(result => dispatch(WorkspaceRecipeStarted(result)))
  }
}
