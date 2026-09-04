///|
fn workspace_graph_prefix(project_id : String, graph_id : String) -> String {
  "workspace-graph-" + sha256_text(project_id + "\u{0000}" + graph_id)
}

///|
fn workspace_graph_key(project_id : String, graph_id : String) -> String {
  workspace_graph_prefix(project_id, graph_id) + "-latest.json"
}

///|
fn workspace_graph_revision_key(
  project_id : String,
  graph_id : String,
  revision : Int,
) -> String {
  workspace_graph_prefix(project_id, graph_id) +
  "-revision-" +
  revision.to_string() +
  ".json"
}

///|
fn workspace_run_key(run_id : String) -> String {
  "workspace-run-" + sha256_text(run_id) + ".json"
}

///|
fn workspace_artifact_key(artifact_id : String, version : Int) -> String {
  "workspace-artifact-" +
  sha256_text(artifact_id + "\u{0000}" + version.to_string()) +
  ".json"
}

///|
pub fn StudioService::workspace_catalog(
  self : StudioService,
) -> WorkspaceCatalogProjection {
  ignore(self)
  {
    contract: "mooncast.workspace-catalog.v1",
    definitions: @mooncast_pack.workspace_node_catalog(),
    publication_authority: false,
  }
}

///|
pub fn StudioService::workspace_capsules(
  self : StudioService,
  project_id : String,
) -> WorkspaceCapsuleProjection raise {
  ignore(self)
  guard valid_id(project_id) else {
    raise Invalid(
      code="workspace_project_id_invalid",
      message="workspace project id must be a portable flat identifier",
    )
  }
  {
    contract: "mooncast.workspace-capsules.v1",
    capsules: [
      @workspace.combine_videos_capsule(project_id, "mooncast", ""),
      @workspace.brief_to_delivery_capsule(project_id, "mooncast", ""),
    ],
    publication_authority: false,
  }
}

///|
pub fn StudioService::validate_workspace_graph(
  self : StudioService,
  graph : @workspace.WorkspaceGraph,
) -> @workspace.GraphValidation {
  @workspace.validate_graph(graph, self.workspace_catalog().definitions)
}

///|
pub async fn StudioService::save_workspace_graph(
  self : StudioService,
  graph : @workspace.WorkspaceGraph,
) -> @workspace.WorkspaceGraph {
  self.with_mutation_lock(() => {
    guard valid_id(graph.project_id) && valid_id(graph.graph_id) else {
      raise Invalid(
        code="workspace_graph_id_invalid",
        message="workspace project and graph ids must be portable flat identifiers",
      )
    }
    let validation = self.validate_workspace_graph(graph)
    guard validation.valid else {
      raise Invalid(
        code="workspace_graph_invalid",
        message=validation.errors.join("; "),
      )
    }
    let key = workspace_graph_key(graph.project_id, graph.graph_id)
    let existing : @workspace.WorkspaceGraph? = load_value(self.store, key)
    match existing {
      None =>
        if graph.revision != 1 {
          raise Invalid(
            code="workspace_graph_revision_invalid",
            message="new workspace graph must start at revision 1",
          )
        }
      Some(value) =>
        if graph.revision != value.revision + 1 {
          raise Conflict(
            code="workspace_graph_revision_conflict",
            message="workspace graph revision must advance the stored graph by one",
          )
        }
    }
    save_value(
      self.store,
      workspace_graph_revision_key(
        graph.project_id,
        graph.graph_id,
        graph.revision,
      ),
      graph,
    )
    save_value(self.store, key, graph)
    graph
  })
}

///|
pub async fn StudioService::get_workspace_graph(
  self : StudioService,
  project_id : String,
  graph_id : String,
) -> @workspace.WorkspaceGraph {
  guard valid_id(project_id) && valid_id(graph_id) else {
    raise NotFound(entity="workspace_graph", id=graph_id)
  }
  let value : @workspace.WorkspaceGraph? = load_value(
    self.store,
    workspace_graph_key(project_id, graph_id),
  )
  match value {
    Some(graph) => graph
    None => raise NotFound(entity="workspace_graph", id=graph_id)
  }
}

///|
pub async fn StudioService::workspace_graph_history(
  self : StudioService,
  project_id : String,
  graph_id : String,
) -> WorkspaceGraphHistoryProjection {
  guard valid_id(project_id) && valid_id(graph_id) else {
    raise NotFound(entity="workspace_graph", id=graph_id)
  }
  let revisions : Array[@workspace.WorkspaceGraph] = []
  let prefix = workspace_graph_prefix(project_id, graph_id) + "-revision-"
  for key in self.store.list_keys(prefix~, suffix=".json") {
    let value : @workspace.WorkspaceGraph? = load_value(self.store, key)
    match value {
      Some(graph) => revisions.push(graph)
      None => ()
    }
  }
  revisions.sort_by((left, right) => left.revision.compare(right.revision))
  guard !revisions.is_empty() else {
    raise NotFound(entity="workspace_graph", id=graph_id)
  }
  {
    contract: "mooncast.workspace-graph-history.v1",
    graph_id,
    revisions,
    publication_authority: false,
  }
}

///|
pub fn StudioService::freeze_workspace_plan(
  self : StudioService,
  request : WorkspacePlanRequest,
) -> @workspace.ExecutionPlan raise {
  @workspace.freeze_plan(
    request.graph,
    self.workspace_catalog().definitions,
    request.requested_output_node_ids,
    request.context,
    request.frozen_at,
  ) catch {
    @workspace.InvalidGraph(errors) =>
      raise Invalid(code="workspace_graph_invalid", message=errors.join("; "))
    @workspace.UnknownNode(node_id) =>
      raise Invalid(
        code="workspace_output_unknown",
        message="unknown workspace output node " + node_id,
      )
    _ =>
      raise Invalid(
        code="workspace_plan_invalid",
        message="workspace plan could not be frozen",
      )
  }
}

///|
pub async fn StudioService::create_workspace_run(
  self : StudioService,
  request : WorkspaceRunCreateRequest,
) -> @workspace.RunRecord {
  self.with_mutation_lock(() => {
    guard valid_id(request.run_id) &&
      !request.created_by.is_blank() &&
      request.maximum_retries >= 0 &&
      request.maximum_retries <= 10 else {
      raise Invalid(
        code="workspace_run_invalid",
        message="workspace run identity, actor, or retry policy is invalid",
      )
    }
    let key = workspace_run_key(request.run_id)
    let existing : @workspace.RunRecord? = load_value(self.store, key)
    match existing {
      Some(value) => {
        guard value.plan.plan_id == request.plan.plan_id else {
          raise Conflict(
            code="workspace_run_id_conflict",
            message="workspace run id already binds another plan",
          )
        }
        value
      }
      None => {
        let value = @workspace.new_run(
          request.plan,
          request.run_id,
          request.created_by,
          request.created_at,
          maximum_retries=request.maximum_retries,
        )
        save_value(self.store, key, value)
        value
      }
    }
  })
}

///|
pub async fn StudioService::get_workspace_run(
  self : StudioService,
  run_id : String,
) -> @workspace.RunRecord {
  guard valid_id(run_id) else {
    raise NotFound(entity="workspace_run", id=run_id)
  }
  let value : @workspace.RunRecord? = load_value(
    self.store,
    workspace_run_key(run_id),
  )
  match value {
    Some(run) => run
    None => raise NotFound(entity="workspace_run", id=run_id)
  }
}

///|
pub async fn StudioService::apply_workspace_run_command(
  self : StudioService,
  run_id : String,
  command : WorkspaceRunCommand,
) -> @workspace.RunRecord {
  self.with_mutation_lock(() => {
    let current = self.get_workspace_run(run_id)
    guard !command.recorded_at.is_blank() else {
      raise Invalid(
        code="workspace_run_command_invalid",
        message="workspace run command requires a timestamp",
      )
    }
    let updated = try {
      match command.command {
        "start" => current.start_node(command.node_id, command.recorded_at)
        "progress" =>
          current.progress_node(
            command.node_id,
            command.numerator,
            command.denominator,
            command.recorded_at,
          )
        "succeed" =>
          current.succeed_node(
            command.node_id,
            command.output_digest,
            command.output_ref,
            command.recorded_at,
          )
        "fail" =>
          current.fail_node(
            command.node_id,
            command.error_code,
            command.error_message,
            command.recorded_at,
          )
        "retry" => current.retry_node(command.node_id, command.recorded_at)
        "cancel" => current.cancel(command.recorded_at)
        _ =>
          raise Invalid(
            code="workspace_run_command_unknown",
            message="unknown workspace run command",
          )
      }
    } catch {
      @workspace.UnknownNode(node_id) =>
        raise Invalid(
          code="workspace_node_unknown",
          message="unknown workspace node " + node_id,
        )
      @workspace.InvalidTransition(message) =>
        raise Conflict(code="workspace_run_transition_invalid", message~)
      _ =>
        raise Invalid(
          code="workspace_run_command_invalid",
          message="workspace run command is invalid",
        )
    }
    save_value(self.store, workspace_run_key(run_id), updated)
    updated
  })
}

///|
pub async fn StudioService::save_workspace_artifact(
  self : StudioService,
  artifact : @workspace.WorkspaceArtifact,
) -> @workspace.WorkspaceArtifact {
  self.with_mutation_lock(() => {
    guard valid_id(artifact.artifact_id) && artifact.immutable else {
      raise Invalid(
        code="workspace_artifact_invalid",
        message="workspace artifact must be immutable and have a portable id",
      )
    }
    let key = workspace_artifact_key(artifact.artifact_id, artifact.version)
    let existing : @workspace.WorkspaceArtifact? = load_value(self.store, key)
    match existing {
      Some(value) => {
        guard value == artifact else {
          raise Conflict(
            code="workspace_artifact_immutable",
            message="artifact version already exists with different content",
          )
        }
        value
      }
      None => {
        save_value(self.store, key, artifact)
        artifact
      }
    }
  })
}

///|
pub async fn StudioService::list_workspace_artifacts(
  self : StudioService,
) -> WorkspaceArtifactProjection {
  let artifacts : Array[@workspace.WorkspaceArtifact] = []
  for key in self.store.list_keys(prefix="workspace-artifact-", suffix=".json") {
    let value : @workspace.WorkspaceArtifact? = load_value(self.store, key)
    match value {
      Some(artifact) => artifacts.push(artifact)
      None => ()
    }
  }
  {
    contract: "mooncast.workspace-artifacts.v1",
    artifacts,
    publication_authority: false,
  }
}

///|
pub async fn StudioService::apply_workspace_proposal(
  self : StudioService,
  request : WorkspaceProposalApplyRequest,
) -> @workspace.WorkspaceGraph {
  let (graph, _) = @workspace.apply_agent_proposal(
    request.base,
    request.proposal,
  ) catch {
    @workspace.RevisionConflict(expected~, actual~) =>
      raise Conflict(
        code="workspace_proposal_revision_conflict",
        message="proposal expected graph revision " +
          expected.to_string() +
          " but found " +
          actual.to_string(),
      )
    @workspace.ProposalAlreadyApplied(proposal_id) =>
      raise Conflict(
        code="workspace_proposal_already_applied",
        message="proposal " + proposal_id + " is already applied",
      )
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_proposal_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_proposal_invalid",
        message="workspace proposal is invalid",
      )
  }
  self.save_workspace_graph(graph)
}
