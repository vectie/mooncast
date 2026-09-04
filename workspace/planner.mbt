///|
fn sha256_text(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn canonical_parameter(parameter : NodeParameter) -> String {
  parameter.key.to_json().stringify() + ":" + parameter.value.stringify()
}

///|
fn canonical_node(node : WorkflowNode) -> String {
  let parameters = node.parameters.map(canonical_parameter)
  parameters.sort()
  [
    node.node_id.to_json().stringify(),
    node.definition_id.to_json().stringify(),
    node.title.to_json().stringify(),
    node.x.to_string(),
    node.y.to_string(),
    parameters.join(","),
    node.collapsed.to_string(),
  ].join("|")
}

///|
fn canonical_edge(edge : WorkflowEdge) -> String {
  [
    edge.edge_id,
    edge.source_node_id,
    edge.source_port_id,
    edge.target_node_id,
    edge.target_port_id,
  ]
  .map(value => value.to_json().stringify())
  .join("|")
}

///|
pub fn graph_digest(graph : WorkspaceGraph) -> String {
  let nodes = graph.nodes.map(canonical_node)
  let edges = graph.edges.map(canonical_edge)
  let outputs = graph.output_node_ids.copy()
  nodes.sort()
  edges.sort()
  outputs.sort()
  sha256_text(
    [
      graph.contract,
      graph.graph_id,
      graph.project_id,
      graph.revision.to_string(),
      graph.title,
      nodes.join("\n"),
      edges.join("\n"),
      outputs.join("\n"),
    ].join("\u{0000}"),
  )
}

///|
fn selected_ancestors(
  graph : WorkspaceGraph,
  selected_outputs : Array[String],
) -> Map[String, Bool] {
  let selected : Map[String, Bool] = Map([])
  let pending = selected_outputs.copy()
  for ; !pending.is_empty(); {
    let current = pending.remove(0)
    if selected.contains(current) {
      continue
    }
    selected[current] = true
    for edge in graph.edges {
      if edge.target_node_id == current {
        pending.push(edge.source_node_id)
      }
    }
  }
  selected
}

///|
fn cached_output_for(
  context : ExecutionContext,
  node_id : String,
) -> CachedNodeOutput? {
  for value in context.cached_outputs {
    if value.node_id == node_id {
      return Some(value)
    }
  }
  None
}

///|
fn planned_node_for(
  nodes : Array[PlannedNode],
  node_id : String,
) -> PlannedNode? {
  for node in nodes {
    if node.node_id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn workflow_node_for(graph : WorkspaceGraph, node_id : String) -> WorkflowNode? {
  for node in graph.nodes {
    if node.node_id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn catalog_definition_for(
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
fn tool_digest(definition : NodeDefinition) -> String {
  sha256_text(definition.to_json().stringify())
}

///|
pub fn freeze_plan(
  graph : WorkspaceGraph,
  catalog : Array[NodeDefinition],
  requested_output_node_ids : Array[String],
  context : ExecutionContext,
  frozen_at : String,
) -> ExecutionPlan raise WorkspaceError {
  let validation = validate_graph(graph, catalog)
  guard validation.valid else { raise InvalidGraph(validation.errors) }
  let outputs = if requested_output_node_ids.is_empty() {
    graph.output_node_ids.copy()
  } else {
    requested_output_node_ids.copy()
  }
  for output_id in outputs {
    guard graph.nodes.any(node => node.node_id == output_id) else {
      raise UnknownNode(output_id)
    }
  }
  let selected = selected_ancestors(graph, outputs)
  let planned : Array[PlannedNode] = []
  for node_id in validation.topological_node_ids {
    if !selected.contains(node_id) {
      continue
    }
    guard workflow_node_for(graph, node_id) is Some(node) &&
      catalog_definition_for(catalog, node.definition_id) is Some(definition) else {
      raise UnknownNode(node_id)
    }
    let input_ids = graph.edges
      .filter(edge => edge.target_node_id == node_id)
      .map(edge => edge.source_node_id)
    input_ids.sort()
    let input_digests = input_ids.map(input_id => {
      guard planned_node_for(planned, input_id) is Some(input_node) else {
        return "missing:" + input_id
      }
      match cached_output_for(context, input_id) {
        Some(cache) if input_node.cache_hit => cache.output_digest
        _ => input_node.cache_key
      }
    })
    let parameters = node.parameters.map(canonical_parameter)
    parameters.sort()
    let definition_digest = tool_digest(definition)
    let cache_key = sha256_text(
      [
        definition.definition_id,
        definition.tool_id,
        definition_digest,
        parameters.join("\n"),
        input_digests.join("\n"),
        context.provider,
        context.model,
        context.policy_digest,
      ].join("\u{0000}"),
    )
    let cached = cached_output_for(context, node_id)
    let cache_hit = definition.idempotent &&
      cached is Some(value) &&
      value.cache_key == cache_key &&
      !value.output_digest.is_blank() &&
      !value.output_ref.is_blank()
    planned.push({
      node_id,
      definition_id: definition.definition_id,
      tool_digest: definition_digest,
      input_node_ids: input_ids,
      cache_key,
      cache_hit,
      cached_output_digest: cached
      .map(value => value.output_digest)
      .unwrap_or(""),
      cached_output_ref: cached.map(value => value.output_ref).unwrap_or(""),
      authority: definition.authority,
      execution_owner: definition.execution_owner,
      review_required: definition.review_required,
    })
  }
  let digest = graph_digest(graph)
  let output_copy = outputs.copy()
  output_copy.sort()
  let plan_core = [
    digest,
    output_copy.join("\n"),
    planned.map(node => node.cache_key).join("\n"),
    context.provider,
    context.model,
    context.policy_digest,
  ].join("\u{0000}")
  {
    contract: "mooncast.workspace-execution-plan.v1",
    plan_id: "plan-" + sha256_text(plan_core)[7:27].to_owned(),
    graph_id: graph.graph_id,
    graph_revision: graph.revision,
    graph_digest: digest,
    frozen_graph: graph,
    selected_output_node_ids: output_copy,
    nodes: planned,
    provider: context.provider,
    model: context.model,
    policy_digest: context.policy_digest,
    frozen_at,
    publication_authority: false,
  }
}
