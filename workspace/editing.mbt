///|
fn next_graph_revision(graph : WorkspaceGraph) -> Int {
  graph.revision + 1
}

///|
pub fn add_graph_node(
  graph : WorkspaceGraph,
  node : WorkflowNode,
) -> WorkspaceGraph raise WorkspaceError {
  guard !node.node_id.is_blank() &&
    !graph.nodes.any(value => value.node_id == node.node_id) else {
    raise InvalidTransition("workspace node id must be non-blank and unique")
  }
  let nodes = graph.nodes.copy()
  nodes.push(node)
  { ..graph, revision: next_graph_revision(graph), nodes }
}

///|
pub fn move_graph_node(
  graph : WorkspaceGraph,
  node_id : String,
  x : Int,
  y : Int,
) -> WorkspaceGraph raise WorkspaceError {
  let nodes = graph.nodes.copy()
  for index, node in nodes {
    if node.node_id == node_id {
      nodes[index] = { ..node, x, y }
      return { ..graph, revision: next_graph_revision(graph), nodes }
    }
  }
  raise UnknownNode(node_id)
}

///|
pub fn set_graph_node_parameter(
  graph : WorkspaceGraph,
  node_id : String,
  parameter : NodeParameter,
) -> WorkspaceGraph raise WorkspaceError {
  guard !parameter.key.is_blank() else {
    raise InvalidTransition("workspace node parameter key must not be blank")
  }
  let nodes = graph.nodes.copy()
  for index, node in nodes {
    if node.node_id == node_id {
      let parameters = node.parameters.filter(value => {
        value.key != parameter.key
      })
      parameters.push(parameter)
      nodes[index] = { ..node, parameters, }
      return { ..graph, revision: next_graph_revision(graph), nodes }
    }
  }
  raise UnknownNode(node_id)
}

///|
pub fn connect_graph_nodes(
  graph : WorkspaceGraph,
  edge : WorkflowEdge,
  catalog : Array[NodeDefinition],
) -> WorkspaceGraph raise WorkspaceError {
  guard !edge.edge_id.is_blank() &&
    !graph.edges.any(value => value.edge_id == edge.edge_id) else {
    raise InvalidTransition("workspace edge id must be non-blank and unique")
  }
  guard node_named(graph, edge.source_node_id) is Some(source) &&
    node_named(graph, edge.target_node_id) is Some(target) else {
    raise InvalidTransition("workspace edge must bind existing nodes")
  }
  guard source.node_id != target.node_id else {
    raise InvalidTransition("workspace node cannot connect to itself")
  }
  guard definition_named(catalog, source.definition_id)
    is Some(source_definition) &&
    definition_named(catalog, target.definition_id) is Some(target_definition) &&
    output_port_named(source_definition, edge.source_port_id) is Some(output) &&
    input_port_named(target_definition, edge.target_port_id) is Some(input) else {
    raise InvalidTransition("workspace edge must bind declared ports")
  }
  guard input.artifact_kind.accepts(output.artifact_kind) else {
    raise InvalidTransition("workspace edge artifact kinds are incompatible")
  }
  guard input.cardinality == Many ||
    !graph.edges.any(value => {
      value.target_node_id == edge.target_node_id &&
      value.target_port_id == edge.target_port_id
    }) else {
    raise InvalidTransition("workspace single input already has a value")
  }
  let edges = graph.edges.copy()
  edges.push(edge)
  let candidate = { ..graph, revision: next_graph_revision(graph), edges }
  let order = topological_order(candidate)
  guard order.length() == candidate.nodes.length() else {
    raise InvalidTransition("workspace edge would create a cycle")
  }
  candidate
}

///|
pub fn disconnect_graph_edge(
  graph : WorkspaceGraph,
  edge_id : String,
) -> WorkspaceGraph raise WorkspaceError {
  guard graph.edges.any(edge => edge.edge_id == edge_id) else {
    raise InvalidTransition("workspace edge does not exist")
  }
  {
    ..graph,
    revision: next_graph_revision(graph),
    edges: graph.edges.filter(edge => edge.edge_id != edge_id),
  }
}

///|
pub fn remove_graph_node(
  graph : WorkspaceGraph,
  node_id : String,
) -> WorkspaceGraph raise WorkspaceError {
  guard graph.nodes.any(node => node.node_id == node_id) else {
    raise UnknownNode(node_id)
  }
  {
    ..graph,
    revision: next_graph_revision(graph),
    nodes: graph.nodes.filter(node => node.node_id != node_id),
    edges: graph.edges.filter(edge => {
      edge.source_node_id != node_id && edge.target_node_id != node_id
    }),
    output_node_ids: graph.output_node_ids.filter(value => value != node_id),
  }
}

///|
pub fn fork_graph(
  graph : WorkspaceGraph,
  graph_id : String,
  title : String,
  created_by : String,
  created_at : String,
) -> WorkspaceGraph raise WorkspaceError {
  guard !graph_id.is_blank() &&
    graph_id != graph.graph_id &&
    !title.is_blank() &&
    !created_by.is_blank() else {
    raise InvalidTransition("fork requires a new graph id, title, and actor")
  }
  { ..graph, graph_id, revision: 1, title, created_by, created_at }
}
