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
fn workspace_feature_key(
  kind : String,
  project_id : String,
  id : String,
) -> String {
  "workspace-" +
  kind +
  "-" +
  sha256_text(project_id + "\u{0000}" + id) +
  ".json"
}

///|
fn workspace_dispatch_key(dispatch_id : String) -> String {
  "workspace-dispatch-" + sha256_text(dispatch_id) + ".json"
}

///|
fn workspace_proposal_key(project_id : String, proposal_id : String) -> String {
  workspace_feature_key("proposal", project_id, proposal_id)
}

///|
fn workspace_activity(
  project_id : String,
  actor : String,
  action : String,
  target_kind : @workspace.WorkspaceTargetKind,
  target_id : String,
  detail : String,
  recorded_at : String,
) -> @workspace.WorkspaceActivity {
  {
    contract: "mooncast.workspace-activity.v1",
    activity_id: "activity-" +
    sha256_text(
      project_id +
      "\u{0000}" +
      actor +
      "\u{0000}" +
      action +
      "\u{0000}" +
      target_id +
      "\u{0000}" +
      recorded_at,
    )[:24].to_owned(),
    project_id,
    actor,
    action,
    target_kind,
    target_id,
    detail,
    recorded_at,
  }
}

///|
async fn StudioService::save_workspace_activity(
  self : StudioService,
  activity : @workspace.WorkspaceActivity,
) -> Unit {
  save_value(
    self.store,
    workspace_feature_key("activity", activity.project_id, activity.activity_id),
    activity,
  )
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
pub fn StudioService::compare_workspace_graphs(
  self : StudioService,
  request : WorkspaceGraphDiffRequest,
) -> @workspace.GraphDiff raise {
  ignore(self)
  guard request.base.project_id == request.proposed.project_id else {
    raise Invalid(
      code="workspace_graph_project_mismatch",
      message="only graphs in the same project can be compared",
    )
  }
  @workspace.graph_diff(request.base, request.proposed)
}

///|
pub async fn StudioService::fork_workspace_graph(
  self : StudioService,
  project_id : String,
  graph_id : String,
  request : WorkspaceGraphForkRequest,
) -> @workspace.WorkspaceGraph {
  let source = self.get_workspace_graph(project_id, graph_id)
  let forked = @workspace.fork_graph(
    source,
    request.graph_id,
    request.title,
    request.created_by,
    request.created_at,
  ) catch {
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_graph_fork_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_graph_fork_invalid",
        message="workspace graph cannot be forked",
      )
  }
  let saved = self.save_workspace_graph(forked)
  self.save_workspace_activity(
    workspace_activity(
      project_id,
      request.created_by,
      "graph-forked",
      @workspace.GraphTarget,
      forked.graph_id,
      "forked from " + source.graph_id + " r" + source.revision.to_string(),
      request.created_at,
    ),
  )
  saved
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
        ignore(self.record_workspace_run_event(value))
        value
      }
    }
  })
}

///|
/// Starts any installed capsule through the same validation, freeze, and run
/// state machine. It does not execute external effects or human gates.
pub async fn StudioService::start_workspace_recipe(
  self : StudioService,
  capsule_id : String,
  request : WorkspaceRecipeRunRequest,
) -> @workspace.RunRecord {
  let capsules = self.workspace_capsules(request.project_id).capsules
  guard capsules.iter().find_first(value => value.capsule_id == capsule_id)
    is Some(capsule) else {
    raise NotFound(entity="workspace_capsule", id=capsule_id)
  }
  let mut graph = @workspace.instantiate_capsule(
    capsule,
    capsule_id + "-" + request.run_id,
    request.project_id,
    capsule.title,
    request.created_by,
    request.created_at,
  ) catch {
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_recipe_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_recipe_invalid",
        message="workspace recipe cannot be instantiated",
      )
  }
  for supplied in request.public_inputs {
    guard capsule.public_inputs
      .iter()
      .find_first(value => value.port_id == supplied.port_id)
      is Some(port) else {
      raise Invalid(
        code="workspace_public_input_unknown",
        message="capsule does not expose public input " + supplied.port_id,
      )
    }
    graph = @workspace.set_graph_node_parameter(graph, port.node_id, {
      key: "public-input:" + supplied.port_id,
      value: supplied.value,
    }) catch {
      @workspace.InvalidTransition(message) =>
        raise Invalid(code="workspace_public_input_invalid", message~)
      _ =>
        raise Invalid(
          code="workspace_public_input_invalid",
          message="public input could not be bound",
        )
    }
  }
  let plan = self.freeze_workspace_plan({
    graph,
    requested_output_node_ids: request.requested_output_node_ids,
    context: {
      provider: request.provider,
      model: request.model,
      policy_digest: request.policy_digest,
      cached_outputs: [],
    },
    frozen_at: request.created_at,
  })
  self.create_workspace_run({
    plan,
    run_id: request.run_id,
    created_by: request.created_by,
    created_at: request.created_at,
    maximum_retries: request.maximum_retries,
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
    ignore(self.record_workspace_run_event(updated))
    if command.command == "succeed" {
      self.remember_workspace_node_output(
        updated,
        command.node_id,
        command.output_digest,
        command.output_ref,
      )
    }
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
        let entry : @workspace.WorkspaceAssetEntry = {
          contract: "mooncast.workspace-asset-entry.v1",
          artifact,
          tags: [],
          deleted: false,
          indexed_at: artifact.created_at,
          updated_at: artifact.created_at,
        }
        save_value(
          self.store,
          workspace_asset_entry_key(artifact.artifact_id, artifact.version),
          entry,
        )
        artifact
      }
    }
  })
}

///|
pub async fn StudioService::register_utility_concat_workspace_artifact(
  self : StudioService,
  project_id : String,
  job_id : String,
  request : WorkspaceUtilityArtifactRegisterRequest,
) -> @workspace.WorkspaceArtifact {
  let job = self.get_utility_concat(job_id)
  guard job.state == "succeeded" &&
    job.output_digest.has_prefix("sha256:") &&
    !request.actor.is_blank() &&
    !request.recorded_at.is_blank() else {
    raise Conflict(
      code="workspace_utility_artifact_not_ready",
      message="utility concat must succeed before artifact registration",
    )
  }
  let artifact = @workspace.new_workspace_artifact(
    "artifact-" + job.job_id,
    1,
    project_id,
    @workspace.VideoArtifact,
    job.output_digest,
    job.media_url,
    job.media_url,
    job.inputs.map(value => "sha256:" + value.sha256),
    "combine-videos",
    job.job_id,
    "register",
    "",
    "local",
    "ffmpeg-bundled",
    {
      "job_id": job.job_id.to_json(),
      "request_digest": job.request_digest.to_json(),
      "output_size": job.output_size.to_json(),
    },
    "cleared",
    "passed",
    ["concat-completed", "output-digest-recorded"],
    0.0,
    0.0,
    request.recorded_at,
  ) catch {
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_artifact_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_artifact_invalid",
        message="utility artifact is invalid",
      )
  }
  let saved = self.save_workspace_artifact(artifact)
  self.save_workspace_activity(
    workspace_activity(
      project_id,
      request.actor,
      "artifact-registered",
      @workspace.ArtifactTarget,
      artifact.artifact_id,
      artifact.digest,
      request.recorded_at,
    ),
  )
  saved
}

///|
pub async fn StudioService::list_workspace_artifacts(
  self : StudioService,
  project_id? : String = "",
) -> WorkspaceArtifactProjection {
  let artifacts : Array[@workspace.WorkspaceArtifact] = []
  for key in self.store.list_keys(prefix="workspace-artifact-", suffix=".json") {
    let value : @workspace.WorkspaceArtifact? = load_value(self.store, key)
    match value {
      Some(artifact) if project_id.is_blank() ||
        artifact.project_id == project_id => artifacts.push(artifact)
      None => ()
      _ => ()
    }
  }
  {
    contract: "mooncast.workspace-artifacts.v1",
    artifacts,
    publication_authority: false,
  }
}

///|
async fn StudioService::workspace_artifact(
  self : StudioService,
  artifact_id : String,
  version : Int,
) -> @workspace.WorkspaceArtifact {
  let value : @workspace.WorkspaceArtifact? = load_value(
    self.store,
    workspace_artifact_key(artifact_id, version),
  )
  match value {
    Some(artifact) => artifact
    None => raise NotFound(entity="workspace_artifact", id=artifact_id)
  }
}

///|
pub async fn StudioService::compare_workspace_artifacts(
  self : StudioService,
  request : WorkspaceArtifactCompareRequest,
) -> @workspace.ArtifactComparison {
  let artifacts : Array[@workspace.WorkspaceArtifact] = []
  for artifact_id in request.artifact_ids {
    let listed = self.list_workspace_artifacts(project_id=request.project_id)
    guard listed.artifacts
      .iter()
      .find_first(value => value.artifact_id == artifact_id)
      is Some(artifact) else {
      raise NotFound(entity="workspace_artifact", id=artifact_id)
    }
    artifacts.push(artifact)
  }
  @workspace.compare_artifacts(
    request.project_id,
    artifacts,
    request.baseline_artifact_id,
  ) catch {
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_artifact_compare_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_artifact_compare_invalid",
        message="artifact comparison is invalid",
      )
  }
}

///|
pub async fn StudioService::promote_workspace_artifact(
  self : StudioService,
  request : WorkspaceArtifactPromoteRequest,
) -> @workspace.ArtifactPromotion {
  self.with_mutation_lock(() => {
    let artifact = self.workspace_artifact(
      request.artifact_id,
      request.artifact_version,
    )
    guard artifact.project_id == request.project_id else {
      raise NotFound(entity="workspace_artifact", id=request.artifact_id)
    }
    let promotion = @workspace.promote_artifact(
      request.project_id,
      artifact,
      request.channel,
      request.actor,
      request.note,
      request.promoted_at,
    ) catch {
      @workspace.InvalidTransition(message) =>
        raise Invalid(code="workspace_artifact_promotion_invalid", message~)
      _ =>
        raise Invalid(
          code="workspace_artifact_promotion_invalid",
          message="artifact promotion is invalid",
        )
    }
    save_value(
      self.store,
      workspace_feature_key(
        "promotion",
        request.project_id,
        promotion.promotion_id,
      ),
      promotion,
    )
    self.save_workspace_activity(
      workspace_activity(
        request.project_id,
        request.actor,
        "artifact-promoted",
        @workspace.ArtifactTarget,
        request.artifact_id,
        request.channel,
        request.promoted_at,
      ),
    )
    promotion
  })
}

///|
pub async fn StudioService::branch_workspace_artifact(
  self : StudioService,
  request : WorkspaceArtifactBranchRequest,
) -> @workspace.WorkspaceArtifact {
  let source = self.workspace_artifact(
    request.source_artifact_id,
    request.source_version,
  )
  guard source.project_id == request.project_id else {
    raise NotFound(entity="workspace_artifact", id=request.source_artifact_id)
  }
  let branch = @workspace.branch_workspace_artifact(
    source,
    request.artifact_id,
    source.digest,
    source.uri,
    source.preview_uri,
    "branch-" + request.artifact_id,
    "asset-branch",
    request.branched_at,
  ) catch {
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_artifact_branch_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_artifact_branch_invalid",
        message="artifact cannot be branched",
      )
  }
  let saved = self.save_workspace_artifact(branch)
  self.save_workspace_activity(
    workspace_activity(
      request.project_id,
      request.actor,
      "artifact-branched",
      @workspace.ArtifactTarget,
      branch.artifact_id,
      "from " + source.artifact_id + " v" + source.version.to_string(),
      request.branched_at,
    ),
  )
  saved
}

///|
pub async fn StudioService::record_workspace_comment(
  self : StudioService,
  request : WorkspaceCommentCreateRequest,
) -> @workspace.WorkspaceComment {
  self.with_mutation_lock(() => {
    let comment = @workspace.new_workspace_comment(
      request.comment_id,
      request.project_id,
      request.target_kind,
      request.target_id,
      request.body,
      request.actor,
      request.created_at,
      request.start_tick,
      request.end_tick,
    ) catch {
      @workspace.InvalidTransition(message) =>
        raise Invalid(code="workspace_comment_invalid", message~)
      _ =>
        raise Invalid(
          code="workspace_comment_invalid",
          message="workspace comment is invalid",
        )
    }
    let key = workspace_feature_key(
      "comment",
      comment.project_id,
      comment.comment_id,
    )
    let existing : @workspace.WorkspaceComment? = load_value(self.store, key)
    match existing {
      Some(value) if value != comment =>
        raise Conflict(
          code="workspace_comment_conflict",
          message="comment id already has different content",
        )
      Some(value) => value
      None => {
        save_value(self.store, key, comment)
        self.save_workspace_activity(
          workspace_activity(
            comment.project_id,
            comment.actor,
            "comment-created",
            comment.target_kind,
            comment.target_id,
            comment.body,
            comment.created_at,
          ),
        )
        comment
      }
    }
  })
}

///|
pub async fn StudioService::renew_workspace_presence(
  self : StudioService,
  request : WorkspacePresenceRequest,
) -> @workspace.WorkspacePresence {
  let presence = @workspace.renew_workspace_presence(
    request.project_id,
    request.actor_id,
    request.display_name,
    request.target_kind,
    request.target_id,
    request.lease_expires_at,
    request.updated_at,
  ) catch {
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_presence_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_presence_invalid",
        message="workspace presence is invalid",
      )
  }
  save_value(
    self.store,
    workspace_feature_key("presence", presence.project_id, presence.actor_id),
    presence,
  )
  presence
}

///|
pub async fn StudioService::create_workspace_share(
  self : StudioService,
  request : WorkspaceShareCreateRequest,
) -> @workspace.WorkspaceShare {
  self.with_mutation_lock(() => {
    let share = @workspace.create_workspace_share(
      request.share_id,
      request.project_id,
      request.target_kind,
      request.target_id,
      request.mode,
      request.token,
      request.expires_at,
      request.created_by,
      request.created_at,
    ) catch {
      @workspace.InvalidTransition(message) =>
        raise Invalid(code="workspace_share_invalid", message~)
      _ =>
        raise Invalid(
          code="workspace_share_invalid",
          message="workspace share is invalid",
        )
    }
    let key = workspace_feature_key("share", share.project_id, share.share_id)
    let existing : @workspace.WorkspaceShare? = load_value(self.store, key)
    match existing {
      Some(value) => value
      None => {
        save_value(self.store, key, share)
        self.save_workspace_activity(
          workspace_activity(
            share.project_id,
            share.created_by,
            "share-created",
            share.target_kind,
            share.target_id,
            share.mode,
            share.created_at,
          ),
        )
        share
      }
    }
  })
}

///|
pub async fn StudioService::publish_workspace_capsule(
  self : StudioService,
  request : WorkspaceCapsulePublishRequest,
) -> @workspace.CapsulePublication {
  self.with_mutation_lock(() => {
    let publication = @workspace.publish_capsule(
      request.publication_id,
      request.capsule,
      request.visibility,
      request.actor,
      request.published_at,
    ) catch {
      @workspace.InvalidTransition(message) =>
        raise Invalid(code="workspace_capsule_publication_invalid", message~)
      _ =>
        raise Invalid(
          code="workspace_capsule_publication_invalid",
          message="capsule publication is invalid",
        )
    }
    save_value(
      self.store,
      workspace_feature_key(
        "capsule-publication",
        publication.capsule.graph.project_id,
        publication.publication_id,
      ),
      publication,
    )
    self.save_workspace_activity(
      workspace_activity(
        publication.capsule.graph.project_id,
        publication.actor,
        "capsule-published",
        @workspace.GraphTarget,
        publication.capsule.graph.graph_id,
        publication.visibility,
        publication.published_at,
      ),
    )
    publication
  })
}

///|
pub async fn StudioService::publish_builtin_workspace_capsule(
  self : StudioService,
  capsule_id : String,
  request : WorkspaceBuiltinCapsulePublishRequest,
) -> @workspace.CapsulePublication {
  let capsules = self.workspace_capsules(request.project_id).capsules
  guard capsules.iter().find_first(value => value.capsule_id == capsule_id)
    is Some(capsule) else {
    raise NotFound(entity="workspace_capsule", id=capsule_id)
  }
  self.publish_workspace_capsule({
    publication_id: request.publication_id,
    capsule,
    visibility: request.visibility,
    actor: request.actor,
    published_at: request.published_at,
  })
}

///|
pub async fn StudioService::prepare_workspace_dispatch(
  self : StudioService,
  run_id : String,
  node_id : String,
  request : WorkspaceDispatchPrepareRequest,
) -> @workspace.WorkspaceDispatch {
  self.with_mutation_lock(() => {
    let run = self.get_workspace_run(run_id)
    let dispatch = @workspace.prepare_workspace_dispatch(
      run,
      node_id,
      request.input_refs,
      request.created_at,
    ) catch {
      @workspace.UnknownNode(id) => raise NotFound(entity="workspace_node", id~)
      @workspace.InvalidTransition(message) =>
        raise Conflict(code="workspace_dispatch_invalid", message~)
      _ =>
        raise Invalid(
          code="workspace_dispatch_invalid",
          message="workspace dispatch is invalid",
        )
    }
    let key = workspace_dispatch_key(dispatch.dispatch_id)
    let existing : @workspace.WorkspaceDispatch? = load_value(self.store, key)
    match existing {
      Some(value) => value
      None => {
        let running = run.start_node(node_id, request.created_at) catch {
          @workspace.InvalidTransition(message) =>
            raise Conflict(code="workspace_run_transition_invalid", message~)
          _ =>
            raise Conflict(
              code="workspace_run_transition_invalid",
              message="workspace node cannot start",
            )
        }
        save_value(self.store, workspace_run_key(run_id), running)
        save_value(self.store, key, dispatch)
        ignore(self.record_workspace_run_event(running))
        self.save_workspace_activity(
          workspace_activity(
            run.plan.frozen_graph.project_id,
            run.created_by,
            "dispatch-prepared",
            @workspace.NodeTarget,
            node_id,
            dispatch.execution_owner,
            request.created_at,
          ),
        )
        dispatch
      }
    }
  })
}

///|
pub async fn StudioService::apply_workspace_dispatch_receipt(
  self : StudioService,
  dispatch_id : String,
  receipt : @workspace.WorkspaceDispatchReceipt,
) -> @workspace.WorkspaceDispatch {
  self.with_mutation_lock(() => {
    guard dispatch_id == receipt.dispatch_id else {
      raise Invalid(
        code="workspace_dispatch_mismatch",
        message="dispatch receipt does not match route",
      )
    }
    let key = workspace_dispatch_key(dispatch_id)
    let existing : @workspace.WorkspaceDispatch? = load_value(self.store, key)
    guard existing is Some(dispatch) else {
      raise NotFound(entity="workspace_dispatch", id=dispatch_id)
    }
    let updated = @workspace.apply_dispatch_receipt(dispatch, receipt) catch {
      @workspace.InvalidTransition(message) =>
        raise Conflict(code="workspace_dispatch_transition_invalid", message~)
      _ =>
        raise Invalid(
          code="workspace_dispatch_receipt_invalid",
          message="dispatch receipt is invalid",
        )
    }
    save_value(self.store, key, updated)
    let run = self.get_workspace_run(updated.run_id)
    let run_updated = try {
      match updated.state {
        @workspace.SucceededDispatch =>
          run.succeed_node(
            updated.node_id,
            updated.output_digest,
            updated.output_ref,
            updated.updated_at,
          )
        @workspace.FailedDispatch =>
          run.fail_node(
            updated.node_id,
            updated.error_code,
            updated.error_message,
            updated.updated_at,
          )
        @workspace.CancelledDispatch => run.cancel(updated.updated_at)
        _ => run
      }
    } catch {
      @workspace.InvalidTransition(message) =>
        raise Conflict(code="workspace_run_transition_invalid", message~)
      _ =>
        raise Conflict(
          code="workspace_run_transition_invalid",
          message="dispatch cannot update run",
        )
    }
    save_value(self.store, workspace_run_key(updated.run_id), run_updated)
    ignore(self.record_workspace_run_event(run_updated))
    if updated.state == @workspace.SucceededDispatch {
      self.remember_workspace_node_output(
        run_updated,
        updated.node_id,
        updated.output_digest,
        updated.output_ref,
      )
    }
    updated
  })
}

///|
pub async fn StudioService::workspace_features(
  self : StudioService,
  project_id : String,
) -> WorkspaceFeatureProjection {
  guard valid_id(project_id) else {
    raise Invalid(
      code="workspace_project_id_invalid",
      message="workspace project id is invalid",
    )
  }
  let comments : Array[@workspace.WorkspaceComment] = []
  let presence : Array[@workspace.WorkspacePresence] = []
  let promotions : Array[@workspace.ArtifactPromotion] = []
  let shares : Array[@workspace.WorkspaceShare] = []
  let activities : Array[@workspace.WorkspaceActivity] = []
  let publications : Array[@workspace.CapsulePublication] = []
  let dispatches : Array[@workspace.WorkspaceDispatch] = []
  let now = (@runtime.wall_clock_ms() / 1000L).to_string()
  for key in self.store.list_keys(prefix="workspace-", suffix=".json") {
    if key.has_prefix("workspace-comment-") {
      let value : @workspace.WorkspaceComment? = load_value(self.store, key)
      if value is Some(item) && item.project_id == project_id {
        comments.push(item)
      }
    } else if key.has_prefix("workspace-presence-") {
      let value : @workspace.WorkspacePresence? = load_value(self.store, key)
      if value is Some(item) &&
        item.project_id == project_id &&
        (item.lease_expires_at.length() != now.length() || item.lease_expires_at > now) {
        presence.push(item)
      }
    } else if key.has_prefix("workspace-promotion-") {
      let value : @workspace.ArtifactPromotion? = load_value(self.store, key)
      if value is Some(item) && item.project_id == project_id {
        promotions.push(item)
      }
    } else if key.has_prefix("workspace-share-") {
      let value : @workspace.WorkspaceShare? = load_value(self.store, key)
      if value is Some(item) && item.project_id == project_id {
        shares.push(item)
      }
    } else if key.has_prefix("workspace-activity-") {
      let value : @workspace.WorkspaceActivity? = load_value(self.store, key)
      if value is Some(item) && item.project_id == project_id {
        activities.push(item)
      }
    } else if key.has_prefix("workspace-capsule-publication-") {
      let value : @workspace.CapsulePublication? = load_value(self.store, key)
      if value is Some(item) && item.capsule.graph.project_id == project_id {
        publications.push(item)
      }
    } else if key.has_prefix("workspace-dispatch-") {
      let value : @workspace.WorkspaceDispatch? = load_value(self.store, key)
      if value is Some(item) {
        let run = self.get_workspace_run(item.run_id)
        if run.plan.frozen_graph.project_id == project_id {
          dispatches.push(item)
        }
      }
    }
  }
  {
    contract: "mooncast.workspace-features.v1",
    project_id,
    comments,
    presence,
    promotions,
    shares,
    activities,
    publications,
    dispatches,
    publication_authority: false,
  }
}

///|
pub async fn StudioService::search_workspace(
  self : StudioService,
  project_id : String,
  query : String,
) -> WorkspaceSearchProjection {
  let normalized = query.trim().to_owned().to_lower()
  let global = project_id.is_blank()
  let capsule_scope = if global { "workspace-search" } else { project_id }
  let matches : Array[@workspace.WorkspaceSearchMatch] = []
  if !normalized.is_blank() {
    for capsule in self.workspace_capsules(capsule_scope).capsules {
      let haystack = (capsule.title +
      " " +
      capsule.summary +
      " " +
      capsule.capsule_id).to_lower()
      if haystack.contains(normalized) {
        matches.push({
          contract: "mooncast.workspace-search-match.v1",
          project_id: if global {
            ""
          } else {
            project_id
          },
          target_kind: @workspace.GraphTarget,
          target_id: capsule.capsule_id,
          title: capsule.title,
          detail: "Recipe · v" + capsule.version.to_string(),
          score: 90,
        })
      }
    }
    for
      key in self.store.list_keys(
        prefix="workspace-graph-",
        suffix="-latest.json",
      ) {
      let value : @workspace.WorkspaceGraph? = load_value(self.store, key)
      if value is Some(graph) &&
        (global || graph.project_id == project_id) &&
        (graph.title + " " + graph.graph_id).to_lower().contains(normalized) {
        matches.push({
          contract: "mooncast.workspace-search-match.v1",
          project_id: graph.project_id,
          target_kind: @workspace.GraphTarget,
          target_id: graph.graph_id,
          title: graph.title,
          detail: "Graph · r" + graph.revision.to_string(),
          score: 85,
        })
      }
    }
    for key in self.store.list_keys(prefix="workspace-run-", suffix=".json") {
      let value : @workspace.RunRecord? = load_value(self.store, key)
      if value is Some(run) &&
        (global || run.plan.frozen_graph.project_id == project_id) &&
        (run.run_id +
        " " +
        run.plan.frozen_graph.title +
        " " +
        run.state.to_json().stringify())
        .to_lower()
        .contains(normalized) {
        matches.push({
          contract: "mooncast.workspace-search-match.v1",
          project_id: run.plan.frozen_graph.project_id,
          target_kind: @workspace.RunTarget,
          target_id: run.run_id,
          title: run.run_id,
          detail: run.plan.frozen_graph.title +
          " · " +
          run.state.to_json().stringify(),
          score: 80,
        })
      }
    }
    let artifacts = if global {
      self.list_workspace_artifacts().artifacts
    } else {
      self.list_workspace_artifacts(project_id~).artifacts
    }
    for artifact in artifacts {
      let haystack = (artifact.artifact_id +
      " " +
      artifact.kind.to_json().stringify() +
      " " +
      artifact.provider +
      " " +
      artifact.model +
      " " +
      artifact.qc_state).to_lower()
      if haystack.contains(normalized) {
        matches.push({
          contract: "mooncast.workspace-search-match.v1",
          project_id: artifact.project_id,
          target_kind: @workspace.ArtifactTarget,
          target_id: artifact.artifact_id,
          title: artifact.artifact_id,
          detail: artifact.provider + " · " + artifact.qc_state,
          score: if artifact.artifact_id.to_lower().contains(normalized) {
            100
          } else {
            60
          },
        })
      }
    }
    let activities : Array[@workspace.WorkspaceActivity] = []
    if global {
      for
        key in self.store.list_keys(
          prefix="workspace-activity-",
          suffix=".json",
        ) {
        let value : @workspace.WorkspaceActivity? = load_value(self.store, key)
        if value is Some(activity) {
          activities.push(activity)
        }
      }
    } else {
      activities.append(self.workspace_features(project_id).activities)
    }
    for activity in activities {
      let haystack = (activity.action +
      " " +
      activity.detail +
      " " +
      activity.actor).to_lower()
      if haystack.contains(normalized) {
        matches.push({
          contract: "mooncast.workspace-search-match.v1",
          project_id: activity.project_id,
          target_kind: activity.target_kind,
          target_id: activity.target_id,
          title: activity.action,
          detail: activity.detail,
          score: 40,
        })
      }
    }
  }
  matches.sort_by((left, right) => right.score.compare(left.score))
  {
    contract: "mooncast.workspace-search.v1",
    project_id,
    query,
    matches,
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

///|
pub async fn StudioService::save_workspace_proposal(
  self : StudioService,
  proposal : @workspace.AgentGraphProposal,
) -> @workspace.AgentGraphProposal {
  guard valid_id(proposal.project_id) && valid_id(proposal.proposal_id) else {
    raise Invalid(
      code="workspace_proposal_invalid",
      message="proposal identity is invalid",
    )
  }
  let validation = self.validate_workspace_graph(proposal.proposed_graph)
  guard validation.valid else {
    raise Invalid(
      code="workspace_proposal_graph_invalid",
      message=validation.errors.join("; "),
    )
  }
  let key = workspace_proposal_key(proposal.project_id, proposal.proposal_id)
  let existing : @workspace.AgentGraphProposal? = load_value(self.store, key)
  match existing {
    Some(value) if value != proposal =>
      raise Conflict(
        code="workspace_proposal_immutable",
        message="proposal id already binds different content",
      )
    Some(value) => value
    None => {
      save_value(self.store, key, proposal)
      self.save_workspace_activity(
        workspace_activity(
          proposal.project_id,
          proposal.created_by,
          "agent-proposal-created",
          @workspace.GraphTarget,
          proposal.base_graph_id,
          proposal.explanation,
          proposal.created_at,
        ),
      )
      proposal
    }
  }
}

///|
pub async fn StudioService::list_workspace_proposals(
  self : StudioService,
  project_id : String,
) -> WorkspaceProposalProjection {
  let proposals : Array[@workspace.AgentGraphProposal] = []
  for key in self.store.list_keys(prefix="workspace-proposal-", suffix=".json") {
    let value : @workspace.AgentGraphProposal? = load_value(self.store, key)
    if value is Some(item) && item.project_id == project_id {
      proposals.push(item)
    }
  }
  {
    contract: "mooncast.workspace-agent-proposals.v1",
    project_id,
    proposals,
    publication_authority: false,
  }
}

///|
pub async fn StudioService::promote_workspace_run_to_template(
  self : StudioService,
  run_id : String,
  request : WorkspaceRunTemplateRequest,
) -> @workspace.WorkspaceTemplatePromotion {
  let run = self.get_workspace_run(run_id)
  guard run.state == @workspace.SucceededRun else {
    raise Conflict(
      code="workspace_run_not_successful",
      message="only a successful frozen run can become a template",
    )
  }
  let capsule = @workspace.capsule_from_graph(
    run.plan.frozen_graph,
    self.workspace_catalog().definitions,
    request.capsule_id,
    request.title,
    request.summary,
    request.actor,
    request.promoted_at,
  ) catch {
    @workspace.InvalidGraph(errors) =>
      raise Invalid(
        code="workspace_template_invalid",
        message=errors.join("; "),
      )
    @workspace.InvalidTransition(message) =>
      raise Invalid(code="workspace_template_invalid", message~)
    _ =>
      raise Invalid(
        code="workspace_template_invalid",
        message="run cannot become a capsule",
      )
  }
  let promotion : @workspace.WorkspaceTemplatePromotion = {
    contract: "mooncast.workspace-template-promotion.v1",
    promotion_id: request.promotion_id,
    project_id: run.plan.frozen_graph.project_id,
    run_id,
    capsule,
    actor: request.actor,
    promoted_at: request.promoted_at,
    publication_authority: false,
  }
  save_value(
    self.store,
    workspace_feature_key(
      "template-promotion",
      promotion.project_id,
      promotion.promotion_id,
    ),
    promotion,
  )
  self.save_workspace_activity(
    workspace_activity(
      promotion.project_id,
      promotion.actor,
      "run-promoted-to-template",
      @workspace.RunTarget,
      run_id,
      capsule.title,
      promotion.promoted_at,
    ),
  )
  promotion
}
