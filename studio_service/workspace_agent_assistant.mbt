///|
fn workspace_agent_set_flag(
  graph : @workspace.WorkspaceGraph,
  node_id : String,
  key : String,
) -> @workspace.WorkspaceGraph? {
  guard graph.nodes.any(node => node.node_id == node_id) else { return None }
  let nodes = graph.nodes.map(node => {
    if node.node_id != node_id {
      return node
    }
    let parameters = node.parameters.filter(parameter => parameter.key != key)
    parameters.push({ key, value: true.to_json() })
    { ..node, parameters, }
  })
  Some({ ..graph, revision: graph.revision + 1, nodes })
}

///|
fn workspace_agent_layout(
  graph : @workspace.WorkspaceGraph,
) -> @workspace.WorkspaceGraph {
  let nodes : Array[@workspace.WorkflowNode] = []
  for index, node in graph.nodes {
    nodes.push({ ..node, x: 48 + index % 4 * 280, y: 96 + index / 4 * 190 })
  }
  { ..graph, revision: graph.revision + 1, nodes }
}

///|
pub async fn StudioService::assist_workspace_graph(
  self : StudioService,
  project_id : String,
  request : WorkspaceAgentAssistRequest,
) -> WorkspaceAgentAssistProjection {
  guard valid_id(project_id) &&
    valid_id(request.graph_id) &&
    !request.actor.trim().is_blank() &&
    !request.instruction.trim().is_blank() else {
    raise Invalid(
      code="workspace_agent_request_invalid",
      message="project, graph, named actor, and instruction are required",
    )
  }
  let graph = self.get_workspace_graph(project_id, request.graph_id)
  let normalized = request.instruction.to_lower()
  let diagnosis : Array[String] = []
  let validation = self.validate_workspace_graph(graph)
  if validation.valid {
    diagnosis.push(
      "Graph revision " + graph.revision.to_string() + " is structurally valid.",
    )
  } else {
    diagnosis.append(validation.errors)
  }
  let recent = self.list_workspace_runs(project_id, "", 0, 1)
  if recent.runs.get(0) is Some(run) {
    for node in run.nodes {
      if node.state == @workspace.Failed &&
        node.attempts.last() is Some(attempt) {
        diagnosis.push(
          node.node_id +
          " failed: " +
          attempt.error_code +
          " · " +
          attempt.error_message,
        )
      }
    }
  } else {
    diagnosis.push("No prior run evidence is available for diagnosis.")
  }
  let proposed : @workspace.WorkspaceGraph? = if normalized.contains("layout") ||
    normalized.contains("organize") {
    Some(workspace_agent_layout(graph))
  } else if normalized.contains("bypass") || normalized.contains("repair") {
    workspace_agent_set_flag(
      graph,
      request.target_node_id,
      "workspace:bypassed",
    )
  } else if normalized.contains("mute") {
    workspace_agent_set_flag(graph, request.target_node_id, "workspace:muted")
  } else {
    None
  }
  let proposal = match proposed {
    None => None
    Some(proposed_graph) => {
      let proposal_id = @runtime.new_id(prefix="workspace-agent-proposal")
      let proposal : @workspace.AgentGraphProposal = {
        contract: "mooncast.agent-graph-proposal.v1",
        proposal_id,
        project_id,
        base_graph_id: graph.graph_id,
        base_graph_revision: graph.revision,
        proposed_graph: {
          ..proposed_graph,
          created_by: "mooncast-workspace-assistant",
          created_at: now_string(),
        },
        explanation: request.instruction,
        affected_node_ids: if request.target_node_id.is_blank() {
          proposed_graph.nodes.map(node => node.node_id)
        } else {
          [request.target_node_id]
        },
        provider_ids: [],
        expected_cost_cny: 0.0,
        required_approvals: [request.actor],
        created_by: "mooncast-workspace-assistant",
        created_at: now_string(),
        applied: false,
      }
      Some(self.save_workspace_proposal(proposal))
    }
  }
  if proposal is None {
    diagnosis.push(
      "No mutation was proposed. Supported reviewed changes are auto layout, mute, bypass, and repair of the selected node.",
    )
  }
  {
    contract: "mooncast.workspace-agent-assist.v1",
    project_id,
    graph_id: graph.graph_id,
    diagnosis,
    proposal,
    execute_authority: false,
    publication_authority: false,
  }
}
