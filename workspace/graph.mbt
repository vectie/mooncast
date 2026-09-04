///|
fn definition_named(
  catalog : Array[NodeDefinition],
  definition_id : String,
) -> NodeDefinition? {
  for definition in catalog {
    if definition.definition_id == definition_id {
      return Some(definition)
    }
  }
  None
}

///|
fn node_named(graph : WorkspaceGraph, node_id : String) -> WorkflowNode? {
  for node in graph.nodes {
    if node.node_id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn input_port_named(
  definition : NodeDefinition,
  port_id : String,
) -> PortDefinition? {
  for port in definition.inputs {
    if port.port_id == port_id {
      return Some(port)
    }
  }
  None
}

///|
fn output_port_named(
  definition : NodeDefinition,
  port_id : String,
) -> PortDefinition? {
  for port in definition.outputs {
    if port.port_id == port_id {
      return Some(port)
    }
  }
  None
}

///|
pub fn ArtifactKind::accepts(
  self : ArtifactKind,
  source : ArtifactKind,
) -> Bool {
  self == AnyArtifact || source == AnyArtifact || self == source
}

///|
fn duplicate_values(values : Array[String]) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let duplicates : Array[String] = []
  for value in values {
    if seen.contains(value) && !duplicates.contains(value) {
      duplicates.push(value)
    }
    seen[value] = true
  }
  duplicates.sort()
  duplicates
}

///|
fn topological_order(graph : WorkspaceGraph) -> Array[String] {
  let indegree : Map[String, Int] = Map([])
  let outgoing : Map[String, Array[String]] = Map([])
  for node in graph.nodes {
    indegree[node.node_id] = 0
    outgoing[node.node_id] = []
  }
  for edge in graph.edges {
    guard indegree.get(edge.source_node_id) is Some(_) &&
      indegree.get(edge.target_node_id) is Some(value) else {
      continue
    }
    indegree[edge.target_node_id] = value + 1
    outgoing[edge.source_node_id].push(edge.target_node_id)
  }
  let ready = graph.nodes
    .filter(node => indegree.get(node.node_id).unwrap_or(-1) == 0)
    .map(node => node.node_id)
  ready.sort()
  let ordered : Array[String] = []
  for ; !ready.is_empty(); {
    let current = ready.remove(0)
    ordered.push(current)
    for target in outgoing.get(current).unwrap_or([]) {
      let remaining = indegree.get(target).unwrap_or(0) - 1
      indegree[target] = remaining
      if remaining == 0 {
        ready.push(target)
        ready.sort()
      }
    }
  }
  ordered
}

///|
pub fn validate_graph(
  graph : WorkspaceGraph,
  catalog : Array[NodeDefinition],
) -> GraphValidation {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  if graph.contract != "mooncast.workspace-graph.v1" {
    errors.push("unsupported workspace graph contract")
  }
  if graph.graph_id.is_blank() ||
    graph.project_id.is_blank() ||
    graph.revision < 1 {
    errors.push("graph identity, project, and positive revision are required")
  }
  for id in duplicate_values(graph.nodes.map(node => node.node_id)) {
    errors.push("duplicate node id: " + id)
  }
  for id in duplicate_values(graph.edges.map(edge => edge.edge_id)) {
    errors.push("duplicate edge id: " + id)
  }
  for node in graph.nodes {
    if node.node_id.is_blank() {
      errors.push("node id must not be blank")
    }
    if definition_named(catalog, node.definition_id) is None {
      errors.push(
        "node " +
        node.node_id +
        " references unknown definition " +
        node.definition_id,
      )
    }
    for key in duplicate_values(node.parameters.map(parameter => parameter.key)) {
      errors.push("node " + node.node_id + " has duplicate parameter " + key)
    }
  }
  for edge in graph.edges {
    let source = node_named(graph, edge.source_node_id)
    let target = node_named(graph, edge.target_node_id)
    if source is None {
      errors.push("edge " + edge.edge_id + " has unknown source node")
      continue
    }
    if target is None {
      errors.push("edge " + edge.edge_id + " has unknown target node")
      continue
    }
    let source_definition = definition_named(
      catalog,
      source.unwrap().definition_id,
    )
    let target_definition = definition_named(
      catalog,
      target.unwrap().definition_id,
    )
    guard source_definition is Some(source_value) &&
      target_definition is Some(target_value) else {
      continue
    }
    let output = output_port_named(source_value, edge.source_port_id)
    let input = input_port_named(target_value, edge.target_port_id)
    if output is None {
      errors.push("edge " + edge.edge_id + " has unknown source port")
      continue
    }
    if input is None {
      errors.push("edge " + edge.edge_id + " has unknown target port")
      continue
    }
    if !input.unwrap().artifact_kind.accepts(output.unwrap().artifact_kind) {
      errors.push(
        "edge " + edge.edge_id + " connects incompatible artifact kinds",
      )
    }
  }
  for node in graph.nodes {
    guard definition_named(catalog, node.definition_id) is Some(definition) else {
      continue
    }
    for input in definition.inputs {
      let incoming = graph.edges.filter(edge => {
        edge.target_node_id == node.node_id &&
        edge.target_port_id == input.port_id
      })
      if input.required && incoming.is_empty() {
        errors.push(
          "node " + node.node_id + " is missing required input " + input.port_id,
        )
      }
      if input.cardinality == One && incoming.length() > 1 {
        errors.push(
          "node " +
          node.node_id +
          " has multiple values for single input " +
          input.port_id,
        )
      }
    }
  }
  for output_id in graph.output_node_ids {
    if node_named(graph, output_id) is None {
      errors.push("unknown graph output node: " + output_id)
    }
  }
  if graph.output_node_ids.is_empty() {
    warnings.push("graph has no explicit output nodes")
  }
  let ordered = topological_order(graph)
  if ordered.length() != graph.nodes.length() {
    errors.push("graph contains a cycle")
  }
  {
    contract: "mooncast.workspace-graph-validation.v1",
    valid: errors.is_empty(),
    errors,
    warnings,
    topological_node_ids: if errors.any(error => {
        error == "graph contains a cycle"
      }) {
      []
    } else {
      ordered
    },
  }
}
