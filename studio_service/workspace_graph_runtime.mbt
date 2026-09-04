///|
fn workspace_cached_output_key(cache_key : String) -> String {
  "workspace-cache-" + sha256_text(cache_key) + ".json"
}

///|
fn workspace_capsule_input_port(
  capsule : @workspace.CreativeCapsule,
  port_id : String,
) -> @workspace.CapsulePort? {
  match
    capsule.public_inputs.iter().find_first(port => port.port_id == port_id) {
    Some(port) => Some(port)
    None if capsule.public_inputs.length() == 1 => capsule.public_inputs.get(0)
    None => None
  }
}

///|
fn workspace_capsule_output_port(
  capsule : @workspace.CreativeCapsule,
  port_id : String,
) -> @workspace.CapsulePort? {
  match
    capsule.public_outputs.iter().find_first(port => port.port_id == port_id) {
    Some(port) => Some(port)
    None if capsule.public_outputs.length() == 1 =>
      capsule.public_outputs.get(0)
    None => None
  }
}

///|
pub async fn StudioService::install_workspace_capsule(
  self : StudioService,
  project_id : String,
  capsule_id : String,
  request : WorkspaceCapsuleInstallRequest,
) -> @workspace.WorkspaceGraph {
  guard valid_id(project_id) && valid_id(capsule_id) else {
    raise Invalid(
      code="workspace_capsule_install_invalid",
      message="workspace project and capsule ids must be portable",
    )
  }
  let graph_id = if request.graph_id.is_blank() {
    capsule_id
  } else {
    request.graph_id
  }
  guard valid_id(graph_id) && !request.actor.is_blank() else {
    raise Invalid(
      code="workspace_capsule_install_invalid",
      message="graph id and actor are required",
    )
  }
  let key = workspace_graph_key(project_id, graph_id)
  let existing : @workspace.WorkspaceGraph? = load_value(self.store, key)
  if existing is Some(graph) {
    return graph
  }
  let capsules = self.workspace_capsules(project_id).capsules
  guard capsules.iter().find_first(value => value.capsule_id == capsule_id)
    is Some(capsule) else {
    raise NotFound(entity="workspace_capsule", id=capsule_id)
  }
  let graph = @workspace.instantiate_capsule(
    capsule,
    graph_id,
    project_id,
    if request.title.is_blank() {
      capsule.title
    } else {
      request.title
    },
    request.actor,
    now_string(),
  ) catch {
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_capsule_install_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_capsule_install_invalid",
        message="capsule could not be installed",
      )
  }
  self.save_workspace_graph(graph) catch {
    Conflict(code=_, message=_) =>
      self.get_workspace_graph(project_id, graph_id)
    error => raise error
  }
}

///|
pub async fn StudioService::expand_workspace_capsule_node(
  self : StudioService,
  project_id : String,
  graph_id : String,
  node_id : String,
  request : WorkspaceCapsuleExpandRequest,
) -> @workspace.WorkspaceGraph {
  let graph = self.get_workspace_graph(project_id, graph_id)
  guard graph.revision == request.expected_revision &&
    !request.actor.trim().is_blank() else {
    raise Conflict(
      code="workspace_capsule_expand_conflict",
      message="capsule expansion requires the exact graph revision and a named actor",
    )
  }
  guard graph.nodes.iter().find_first(node => node.node_id == node_id)
    is Some(wrapper) &&
    wrapper.definition_id == "workspace.control.subgraph" else {
    raise NotFound(entity="workspace_capsule_node", id=node_id)
  }
  let capsules = self.workspace_capsules(project_id).capsules
  guard capsules
    .iter()
    .find_first(capsule => {
      capsule.capsule_id == request.capsule_id &&
      capsule.version == request.capsule_version
    })
    is Some(capsule) else {
    raise NotFound(
      entity="workspace_capsule",
      id=request.capsule_id + "@" + request.capsule_version.to_string(),
    )
  }
  let prefix = node_id + "--"
  let bound_input_node_ids : Array[String] = []
  for outer_edge in graph.edges {
    if outer_edge.target_node_id != node_id {
      continue
    }
    guard workspace_capsule_input_port(capsule, outer_edge.target_port_id)
      is Some(port) else {
      raise Invalid(
        code="workspace_capsule_input_unmapped",
        message="capsule has no public input " + outer_edge.target_port_id,
      )
    }
    if !bound_input_node_ids.contains(port.node_id) {
      bound_input_node_ids.push(port.node_id)
    }
  }
  let nodes = graph.nodes.filter(node => node.node_id != node_id)
  for child in capsule.graph.nodes {
    if bound_input_node_ids.contains(child.node_id) {
      continue
    }
    let expanded_id = prefix + child.node_id
    guard !nodes.any(node => node.node_id == expanded_id) else {
      raise Conflict(
        code="workspace_capsule_expand_collision",
        message="expanded capsule node id already exists: " + expanded_id,
      )
    }
    let parameters = child.parameters.copy()
    for exposed in capsule.exposed_parameters {
      if exposed.node_id != child.node_id {
        continue
      }
      let value = wrapper.parameters
        .iter()
        .find_first(parameter => {
          parameter.key == "capsule:" + exposed.parameter_id
        })
        .map(parameter => parameter.value)
        .unwrap_or(exposed.default_value)
      let retained = parameters.filter(parameter => {
        parameter.key != exposed.node_parameter_key
      })
      retained.push({ key: exposed.node_parameter_key, value })
      parameters.clear()
      parameters.append(retained)
    }
    nodes.push({
      ..child,
      node_id: expanded_id,
      x: wrapper.x + child.x,
      y: wrapper.y + child.y,
    })
  }
  let edges = graph.edges.filter(edge => {
    edge.source_node_id != node_id && edge.target_node_id != node_id
  })
  for child_edge in capsule.graph.edges {
    if capsule.public_inputs.any(port => {
        bound_input_node_ids.contains(port.node_id) &&
        child_edge.source_node_id == port.node_id &&
        child_edge.source_port_id == port.node_port_id
      }) {
      continue
    }
    edges.push({
      ..child_edge,
      edge_id: prefix + child_edge.edge_id,
      source_node_id: prefix + child_edge.source_node_id,
      target_node_id: prefix + child_edge.target_node_id,
    })
  }
  for outer_edge in graph.edges {
    if outer_edge.target_node_id == node_id {
      guard workspace_capsule_input_port(capsule, outer_edge.target_port_id)
        is Some(port) else {
        raise Invalid(
          code="workspace_capsule_input_unmapped",
          message="capsule has no public input " + outer_edge.target_port_id,
        )
      }
      let downstream = capsule.graph.edges.filter(edge => {
        edge.source_node_id == port.node_id &&
        edge.source_port_id == port.node_port_id
      })
      guard !downstream.is_empty() else {
        raise Invalid(
          code="workspace_capsule_input_unmapped",
          message="capsule public input has no internal consumer: " +
            port.port_id,
        )
      }
      for index, child_edge in downstream {
        edges.push({
          edge_id: if index == 0 {
            outer_edge.edge_id
          } else {
            outer_edge.edge_id + "--" + index.to_string()
          },
          source_node_id: outer_edge.source_node_id,
          source_port_id: outer_edge.source_port_id,
          target_node_id: prefix + child_edge.target_node_id,
          target_port_id: child_edge.target_port_id,
        })
      }
    } else if outer_edge.source_node_id == node_id {
      guard workspace_capsule_output_port(capsule, outer_edge.source_port_id)
        is Some(port) else {
        raise Invalid(
          code="workspace_capsule_output_unmapped",
          message="capsule has no public output " + outer_edge.source_port_id,
        )
      }
      edges.push({
        ..outer_edge,
        source_node_id: prefix + port.node_id,
        source_port_id: port.node_port_id,
      })
    }
  }
  let output_node_ids : Array[String] = []
  for output_id in graph.output_node_ids {
    if output_id != node_id {
      output_node_ids.push(output_id)
    } else {
      for port in capsule.public_outputs {
        let expanded_id = prefix + port.node_id
        if !output_node_ids.contains(expanded_id) {
          output_node_ids.push(expanded_id)
        }
      }
    }
  }
  self.revise_workspace_graph(project_id, graph_id, {
    expected_revision: request.expected_revision,
    title: graph.title,
    nodes,
    edges,
    output_node_ids,
    actor: request.actor,
  })
}

///|
pub async fn StudioService::revise_workspace_graph(
  self : StudioService,
  project_id : String,
  graph_id : String,
  request : WorkspaceGraphRevisionRequest,
) -> @workspace.WorkspaceGraph {
  let current = self.get_workspace_graph(project_id, graph_id)
  guard request.expected_revision == current.revision else {
    raise Conflict(
      code="workspace_graph_revision_conflict",
      message="workspace graph changed after this editor loaded it",
    )
  }
  guard !request.actor.is_blank() else {
    raise Invalid(
      code="workspace_graph_actor_invalid",
      message="a named graph editor is required",
    )
  }
  let revised : @workspace.WorkspaceGraph = {
    ..current,
    revision: current.revision + 1,
    title: if request.title.is_blank() {
      current.title
    } else {
      request.title
    },
    nodes: request.nodes.copy(),
    edges: request.edges.copy(),
    output_node_ids: request.output_node_ids.copy(),
    created_by: request.actor,
    created_at: now_string(),
  }
  self.save_workspace_graph(revised)
}

///|
async fn StudioService::cached_outputs_for_graph(
  self : StudioService,
  graph : @workspace.WorkspaceGraph,
  requested_output_node_ids : Array[String],
  provider : String,
  model : String,
  policy_digest : String,
) -> Array[@workspace.CachedNodeOutput] {
  let cached : Array[@workspace.CachedNodeOutput] = []
  let mut plan = self.freeze_workspace_plan({
    graph,
    requested_output_node_ids,
    context: { provider, model, policy_digest, cached_outputs: [] },
    frozen_at: now_string(),
  })
  let ordered_ids = plan.nodes.map(node => node.node_id)
  for node_id in ordered_ids {
    plan = self.freeze_workspace_plan({
      graph,
      requested_output_node_ids,
      context: { provider, model, policy_digest, cached_outputs: cached },
      frozen_at: now_string(),
    })
    guard plan.nodes.iter().find_first(value => value.node_id == node_id)
      is Some(node) else {
      continue
    }
    let value : @workspace.CachedNodeOutput? = load_value(
      self.store,
      workspace_cached_output_key(node.cache_key),
    )
    if value is Some(output) &&
      output.cache_key == node.cache_key &&
      output.node_id == node.node_id &&
      !output.output_digest.is_blank() &&
      !output.output_ref.is_blank() {
      cached.push(output)
    }
  }
  cached
}

///|
pub async fn StudioService::start_workspace_graph_run(
  self : StudioService,
  project_id : String,
  graph_id : String,
  request : WorkspaceGraphRunRequest,
) -> @workspace.RunRecord {
  let graph = self.get_workspace_graph(project_id, graph_id)
  guard request.expected_revision == graph.revision else {
    raise Conflict(
      code="workspace_graph_revision_conflict",
      message="run must target the exact saved graph revision",
    )
  }
  let cached_outputs = self.cached_outputs_for_graph(
    graph,
    request.requested_output_node_ids,
    request.provider,
    request.model,
    request.policy_digest,
  )
  let recorded_at = now_string()
  let plan = self.freeze_workspace_plan({
    graph,
    requested_output_node_ids: request.requested_output_node_ids,
    context: {
      provider: request.provider,
      model: request.model,
      policy_digest: request.policy_digest,
      cached_outputs,
    },
    frozen_at: recorded_at,
  })
  self.create_workspace_run({
    plan,
    run_id: if request.run_id.is_blank() {
      @runtime.new_id(prefix="workspace-run")
    } else {
      request.run_id
    },
    created_by: request.created_by,
    created_at: recorded_at,
    maximum_retries: request.maximum_retries,
  })
}

///|
async fn StudioService::remember_workspace_node_output(
  self : StudioService,
  run : @workspace.RunRecord,
  node_id : String,
  output_digest : String,
  output_ref : String,
) -> Unit {
  guard run.plan.nodes.iter().find_first(value => value.node_id == node_id)
    is Some(node) else {
    return
  }
  guard !output_digest.is_blank() && !output_ref.is_blank() else { return }
  let cached : @workspace.CachedNodeOutput = {
    node_id,
    cache_key: node.cache_key,
    output_digest,
    output_ref,
  }
  save_value(self.store, workspace_cached_output_key(node.cache_key), cached)
}
