///|
fn workspace_cached_output_key(cache_key : String) -> String {
  "workspace-cache-" + sha256_text(cache_key) + ".json"
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
