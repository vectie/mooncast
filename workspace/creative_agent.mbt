///|
fn graph_node_with_parameter(
  graph : WorkspaceGraph,
  catalog : Array[NodeDefinition],
  preferred_node_id : String,
  parameter_id : String,
) -> WorkflowNode? {
  let declares = fn(node : WorkflowNode) -> Bool {
    match definition_named(catalog, node.definition_id) {
      Some(definition) =>
        definition.parameters.any(parameter => {
          parameter.parameter_id == parameter_id
        })
      None => false
    }
  }
  match node_named(graph, preferred_node_id) {
    Some(node) if declares(node) => Some(node)
    _ => {
      for node in graph.nodes {
        if declares(node) {
          return Some(node)
        }
      }
      None
    }
  }
}

///|
fn graph_with_parameter_value(
  graph : WorkspaceGraph,
  node : WorkflowNode,
  parameter_id : String,
  value : Json,
) -> WorkspaceGraph? {
  if node.parameters.any(parameter => {
      parameter.key == parameter_id && parameter.value == value
    }) {
    return None
  }
  let parameters = node.parameters.filter(parameter => {
    parameter.key != parameter_id
  })
  parameters.push({ key: parameter_id, value })
  parameters.sort_by((left, right) => left.key.compare(right.key))
  Some({
    ..graph,
    revision: graph.revision + 1,
    nodes: graph.nodes.map(current => {
      if current.node_id == node.node_id {
        { ..current, parameters, }
      } else {
        current
      }
    }),
  })
}

///|
fn current_variant_count(node : WorkflowNode) -> Int {
  for parameter in node.parameters {
    if parameter.key == "variant_count" {
      match parameter.value {
        Json::Number(value, ..) => return value.to_int()
        _ => return 4
      }
    }
  }
  4
}

///|
/// Interprets a deliberately small creative vocabulary into data-only graph
/// edits. This is a deterministic local affordance; provider-backed agents may
/// produce broader proposals through the same `AgentGraphProposal` boundary.
pub fn suggest_creative_graph_edit(
  graph : WorkspaceGraph,
  catalog : Array[NodeDefinition],
  preferred_node_id : String,
  instruction : String,
) -> CreativeGraphSuggestion? {
  let normalized = instruction.trim().to_lower()
  let aspect_ratio = if normalized.contains("vertical") ||
    normalized.contains("9:16") {
    Some("9:16")
  } else if normalized.contains("square") || normalized.contains("1:1") {
    Some("1:1")
  } else if normalized.contains("portrait") || normalized.contains("4:5") {
    Some("4:5")
  } else if normalized.contains("landscape") || normalized.contains("16:9") {
    Some("16:9")
  } else {
    None
  }
  match aspect_ratio {
    Some(value) => {
      guard graph_node_with_parameter(
          graph, catalog, preferred_node_id, "aspect_ratio",
        )
        is Some(node) &&
        graph_with_parameter_value(graph, node, "aspect_ratio", value.to_json())
        is Some(proposed) else {
        return None
      }
      Some({
        graph: proposed,
        summary: "Set " + node.title + " aspect ratio to " + value + ".",
        affected_node_ids: [node.node_id],
      })
    }
    None if normalized.contains("more variant") ||
      normalized.contains("additional variant") => {
      guard graph_node_with_parameter(
          graph, catalog, preferred_node_id, "variant_count",
        )
        is Some(node) else {
        return None
      }
      let count = Int::min(8, current_variant_count(node) + 1)
      guard graph_with_parameter_value(
          graph,
          node,
          "variant_count",
          count.to_json(),
        )
        is Some(proposed) else {
        return None
      }
      Some({
        graph: proposed,
        summary: "Increase " + node.title + " to \{count} variants.",
        affected_node_ids: [node.node_id],
      })
    }
    None if normalized.contains("fewer variant") ||
      normalized.contains("less variant") => {
      guard graph_node_with_parameter(
          graph, catalog, preferred_node_id, "variant_count",
        )
        is Some(node) else {
        return None
      }
      let count = Int::max(1, current_variant_count(node) - 1)
      guard graph_with_parameter_value(
          graph,
          node,
          "variant_count",
          count.to_json(),
        )
        is Some(proposed) else {
        return None
      }
      Some({
        graph: proposed,
        summary: "Reduce " + node.title + " to \{count} variants.",
        affected_node_ids: [node.node_id],
      })
    }
    _ => None
  }
}
