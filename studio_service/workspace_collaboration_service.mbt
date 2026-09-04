///|
async fn StudioService::find_workspace_share(
  self : StudioService,
  share_id : String,
) -> @workspace.WorkspaceShare? {
  for key in self.store.list_keys(prefix="workspace-share-", suffix=".json") {
    let value : @workspace.WorkspaceShare? = load_value(self.store, key)
    if value is Some(share) && share.share_id == share_id {
      return Some(share)
    }
  }
  None
}

///|
pub async fn StudioService::create_secure_workspace_share(
  self : StudioService,
  request : WorkspaceSecureShareRequest,
) -> WorkspaceShareCreatedProjection {
  guard request.lifetime_seconds >= 60 && request.lifetime_seconds <= 2592000 else {
    raise Invalid(
      code="workspace_share_lifetime_invalid",
      message="share lifetime must be between 60 seconds and 30 days",
    )
  }
  let share_id = @runtime.new_id(prefix="workspace-share")
  let token = @runtime.new_id(prefix="workspace-token") + @runtime.new_id(prefix="secret")
  let created_at = (@runtime.wall_clock_ms() / 1000L).to_string()
  let expires_at = (
    @runtime.wall_clock_ms() / 1000L + Int64::from_int(request.lifetime_seconds)
  ).to_string()
  let share = self.create_workspace_share({
    share_id,
    project_id: request.project_id,
    target_kind: request.target_kind,
    target_id: request.target_id,
    mode: request.mode,
    token,
    expires_at,
    created_by: request.created_by,
    created_at,
  })
  {
    contract: "mooncast.workspace-share-created.v1",
    share,
    access_path: "/api/workspace/shares/" + share_id + "/access?token=" + token,
    token,
    publication_authority: false,
  }
}

///|
pub async fn StudioService::access_workspace_share(
  self : StudioService,
  share_id : String,
  token : String,
) -> WorkspaceShareAccessProjection {
  guard self.find_workspace_share(share_id) is Some(share) else {
    raise NotFound(entity="workspace_share", id=share_id)
  }
  guard !share.revoked else {
    raise Conflict(
      code="workspace_share_revoked",
      message="workspace share has been revoked",
    )
  }
  let now = (@runtime.wall_clock_ms() / 1000L).to_string()
  guard share.expires_at.length() == now.length() && share.expires_at > now else {
    raise Conflict(
      code="workspace_share_expired",
      message="workspace share has expired",
    )
  }
  guard share.token_digest == "sha256:" + sha256_text(token) else {
    raise Invalid(
      code="workspace_share_token_invalid",
      message="workspace share token is invalid",
    )
  }
  {
    contract: "mooncast.workspace-share-access.v1",
    share_id: share.share_id,
    project_id: share.project_id,
    target_kind: share.target_kind,
    target_id: share.target_id,
    mode: share.mode,
    expires_at: share.expires_at,
    publication_authority: false,
  }
}

///|
pub async fn StudioService::revoke_workspace_share(
  self : StudioService,
  share_id : String,
  request : WorkspaceShareRevokeRequest,
) -> @workspace.WorkspaceShare {
  self.with_mutation_lock(() => {
    guard self.find_workspace_share(share_id) is Some(share) else {
      raise NotFound(entity="workspace_share", id=share_id)
    }
    let revoked = { ..share, revoked: true }
    save_value(
      self.store,
      workspace_feature_key("share", share.project_id, share.share_id),
      revoked,
    )
    self.save_workspace_activity(
      workspace_activity(
        share.project_id,
        request.actor,
        "share-revoked",
        share.target_kind,
        share.target_id,
        share.share_id,
        now_string(),
      ),
    )
    revoked
  })
}

///|
pub async fn StudioService::apply_saved_workspace_proposal(
  self : StudioService,
  project_id : String,
  proposal_id : String,
  request : WorkspaceProposalApplyByIdRequest,
) -> @workspace.WorkspaceGraph {
  let proposal_key = workspace_proposal_key(project_id, proposal_id)
  guard load_value(self.store, proposal_key) is Some(proposal) else {
    raise NotFound(entity="workspace_proposal", id=proposal_id)
  }
  let proposal : @workspace.AgentGraphProposal = proposal
  guard proposal.project_id == project_id else {
    raise NotFound(entity="workspace_proposal", id=proposal_id)
  }
  let base = self.get_workspace_graph(project_id, proposal.base_graph_id)
  let (graph, applied) = @workspace.apply_agent_proposal(base, proposal) catch {
    @workspace.RevisionConflict(expected~, actual~) =>
      raise Conflict(
        code="workspace_proposal_revision_conflict",
        message="proposal expected graph revision " +
          expected.to_string() +
          " but found " +
          actual.to_string(),
      )
    @workspace.ProposalAlreadyApplied(id) =>
      raise Conflict(
        code="workspace_proposal_already_applied",
        message="proposal " + id + " is already applied",
      )
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_proposal_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_proposal_invalid",
        message="workspace proposal is invalid",
      )
  }
  let saved = self.save_workspace_graph(graph)
  save_value(self.store, proposal_key, applied)
  self.save_workspace_activity(
    workspace_activity(
      project_id,
      request.actor,
      "agent-proposal-applied",
      @workspace.GraphTarget,
      graph.graph_id,
      proposal_id,
      now_string(),
    ),
  )
  saved
}
