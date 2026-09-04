///|
fn node_changed(left : WorkflowNode, right : WorkflowNode) -> Bool {
  left != right
}

///|
fn edge_changed(left : WorkflowEdge, right : WorkflowEdge) -> Bool {
  left != right
}

///|
fn graph_node_for(graph : WorkspaceGraph, node_id : String) -> WorkflowNode? {
  for node in graph.nodes {
    if node.node_id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn graph_edge_for(graph : WorkspaceGraph, edge_id : String) -> WorkflowEdge? {
  for edge in graph.edges {
    if edge.edge_id == edge_id {
      return Some(edge)
    }
  }
  None
}

///|
pub fn graph_diff(
  base : WorkspaceGraph,
  proposed : WorkspaceGraph,
) -> GraphDiff {
  let added_nodes : Array[String] = []
  let removed_nodes : Array[String] = []
  let modified_nodes : Array[String] = []
  let added_edges : Array[String] = []
  let removed_edges : Array[String] = []
  let modified_edges : Array[String] = []
  for node in proposed.nodes {
    match graph_node_for(base, node.node_id) {
      None => added_nodes.push(node.node_id)
      Some(value) if node_changed(value, node) =>
        modified_nodes.push(node.node_id)
      _ => ()
    }
  }
  for node in base.nodes {
    if !proposed.nodes.any(value => value.node_id == node.node_id) {
      removed_nodes.push(node.node_id)
    }
  }
  for edge in proposed.edges {
    match graph_edge_for(base, edge.edge_id) {
      None => added_edges.push(edge.edge_id)
      Some(value) if edge_changed(value, edge) =>
        modified_edges.push(edge.edge_id)
      _ => ()
    }
  }
  for edge in base.edges {
    if !proposed.edges.any(value => value.edge_id == edge.edge_id) {
      removed_edges.push(edge.edge_id)
    }
  }
  added_nodes.sort()
  removed_nodes.sort()
  modified_nodes.sort()
  added_edges.sort()
  removed_edges.sort()
  modified_edges.sort()
  {
    contract: "mooncast.workspace-graph-diff.v1",
    added_node_ids: added_nodes,
    removed_node_ids: removed_nodes,
    modified_node_ids: modified_nodes,
    added_edge_ids: added_edges,
    removed_edge_ids: removed_edges,
    modified_edge_ids: modified_edges,
  }
}

///|
pub fn apply_agent_proposal(
  base : WorkspaceGraph,
  proposal : AgentGraphProposal,
) -> (WorkspaceGraph, AgentGraphProposal) raise WorkspaceError {
  guard !proposal.applied else {
    raise ProposalAlreadyApplied(proposal.proposal_id)
  }
  guard proposal.base_graph_id == base.graph_id &&
    proposal.base_graph_revision == base.revision else {
    raise RevisionConflict(
      expected=proposal.base_graph_revision,
      actual=base.revision,
    )
  }
  guard proposal.project_id == base.project_id &&
    proposal.proposed_graph.graph_id == base.graph_id &&
    proposal.proposed_graph.project_id == base.project_id &&
    proposal.proposed_graph.revision == base.revision + 1 else {
    raise InvalidTransition(
      "proposal must advance the same project graph by one revision",
    )
  }
  (proposal.proposed_graph, { ..proposal, applied: true })
}
