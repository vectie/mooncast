///|
struct ProjectListResponse {
  projects : Array[ProjectSummary]
} derive(ToJson)

///|
struct EventListResponse {
  events : Array[@kernel.ProjectEvent]
} derive(ToJson)

///|
struct ProviderListResponse {
  jobs : Array[ProviderJobRecord]
  publication_authority : Bool
} derive(ToJson)

///|
struct RoutedListResponse {
  executions : Array[RoutedExecutionRecord]
} derive(ToJson)

///|
struct DeleteRequest {
  expected_revision : Int
} derive(FromJson)

///|
struct DeleteResponse {
  deleted : Bool
  project_id : String
} derive(ToJson)

///|
struct CanonicalCreateRequest {
  graph : @project.ProjectGraph
  recorded_at : String?
} derive(FromJson)

///|
struct LegacyCreateRequest {
  project_id : String
  title : String
  objective : String?
  audience : String?
  channels : Array[String]?
  rights_owner : String?
  rights_confirmed : Bool?
  target_duration_seconds : Int
  max_budget_cny : Double
} derive(FromJson)

///|
struct LegacyCreativeRevisionInput {
  expected_project_revision : Int
  expected_artifact_version : Int
  expected_artifact_digest : String
  actor : String
  content : Json
} derive(FromJson)

///|
struct LegacyCreativeDecisionInput {
  expected_project_revision : Int
  expected_artifact_version : Int
  expected_artifact_digest : String
  actor : String
  actor_role : String
  human_confirmed : Bool
  decision : String
  note : String
} derive(FromJson)

///|
struct LegacyAdvanceInput {
  gate : String
  actor : String
  note : String
} derive(FromJson)

///|
struct ApiErrorDetail {
  code : String
  message : String
} derive(ToJson)

///|
struct ApiErrorResponse {
  error : ApiErrorDetail
} derive(ToJson)

///|
struct ProviderConfigResponse {
  mode : String
  network_execution_enabled : Bool
  publication_authority : Bool
  command_endpoint : String
} derive(ToJson)

///|
struct EditorCommandEnvelope {
  command : @editor_domain.EditCommand
  content_digest : String?
} derive(FromJson)

///|
struct LegacyEditorCommandEnvelope {
  expected_revision : Int
  idempotency_key : String
  command : Json
  content_digest : String?
} derive(FromJson)

///|
struct LegacyPreviewRequest {
  session_id : String
  project_revision : Int
  quality : String
} derive(FromJson)

///|
struct LegacyPromotionRequest {
  job_id : String
  expected_project_revision : Int
  production_binding_digest : String
  production_digest : String
  g4_receipt_digest : String
  actor : String
  authority_ref : String
} derive(FromJson)

///|
struct EditorJobApiResponse {
  session_id : String
  job_id : String
  project_id : String
  state : String
  status : String
  attempts : Int
  max_attempts : Int
  output_digest : String
  media_url : String?
  result : EditorJobView
  publication_authority : Bool
} derive(ToJson)

///|
fn editor_job_api(value : EditorJobView) -> EditorJobApiResponse {
  let state = value.job.state
  {
    session_id: value.job.job_id,
    job_id: value.job.job_id,
    project_id: value.job.project_id,
    state,
    status: state,
    attempts: value.job.attempts.length(),
    max_attempts: value.job.maximum_retries + 1,
    output_digest: value.job.output_digest,
    media_url: value.media_url,
    result: value,
    publication_authority: false,
  }
}

///|
fn[T : ToJson] json_value_response(
  status : Int,
  value : T,
) -> @host_http.Response {
  @host_http.json_response(
    status,
    match status {
      200 => "OK"
      201 => "Created"
      204 => "No Content"
      400 => "Bad Request"
      404 => "Not Found"
      409 => "Conflict"
      422 => "Unprocessable Entity"
      501 => "Not Implemented"
      _ => "Response"
    },
    value.to_json().stringify(),
  )
}

///|
fn api_error(
  status : Int,
  code : String,
  message : String,
) -> @host_http.Response {
  json_value_response(status, { error: { code, message } })
}

///|
fn[T : FromJson] decode_body(request : @host_http.Request) -> T raise {
  let text = @utf8.decode(request.body)
  @json.from_json(@json.parse(text))
}

///|
fn json_member(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn path_segments(path : String) -> Array[String] {
  let values : Array[String] = []
  for part in path.split("/") {
    if !part.is_empty() {
      values.push(part.to_owned())
    }
  }
  values
}

///|
fn creative_kind(value : String) -> @creative.ArtifactKind? {
  match value {
    "brief" => Some(Brief)
    "rights-ledger" => Some(RightsLedger)
    "ip-bible" => Some(IpBible)
    "script" => Some(Script)
    "claims-ledger" => Some(ClaimsLedger)
    "storyboard" => Some(Storyboard)
    "animatic" => Some(Animatic)
    _ => None
  }
}

///|
fn legacy_graph(input : LegacyCreateRequest) -> @project.ProjectGraph {
  @production_app.episode_production_graph(
    input.project_id,
    input.title,
    input.target_duration_seconds,
    input.max_budget_cny,
  )
}

///|
fn now_string() -> String {
  @runtime.wall_clock_ms().to_string()
}

///|
async fn StudioService::project_command_ui(
  self : StudioService,
  response : ProjectCommandResponse,
) -> Json {
  Json::object({
    "project": self.studio_project_projection(response.project),
    "result": response.result.to_json(),
    "idempotent_replay": response.idempotent_replay.to_json(),
  })
}

///|
async fn StudioService::revise_creative_from_ui(
  self : StudioService,
  project_id : String,
  kind : @creative.ArtifactKind,
  input : LegacyCreativeRevisionInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard record.snapshot.revision == input.expected_project_revision &&
    current_creative(record.snapshot, kind) is Some(current) &&
    current.reference.version == input.expected_artifact_version &&
    normalized_digest(current.reference.digest) ==
    normalized_digest(input.expected_artifact_digest) &&
    input.actor.trim() != "" else {
    raise Conflict(
      code="creative_artifact_revision_conflict",
      message="revision must bind the displayed project and exact current artifact",
    )
  }
  let content = input.content.stringify()
  let next_version = current.reference.version + 1
  let digest = "sha256:" +
    sha256_text(
      project_id +
      ":" +
      kind.to_string() +
      ":" +
      next_version.to_string() +
      ":" +
      current.reference.digest +
      ":" +
      input.actor +
      ":" +
      content,
    )
  let artifact : @creative.CreativeArtifact = {
    reference: { ..current.reference, version: next_version, digest },
    kind,
    dependency_digests: current.dependency_digests,
    duration_seconds: current.duration_seconds,
    expected_cost_cny: current.expected_cost_cny,
    rights_cleared: current.rights_cleared,
    content,
  }
  self.record_creative_artifact(project_id, {
    expected_revision: input.expected_project_revision,
    command_id: "creative-revise-" +
    sha256_text(digest + ":" + input.actor)[:20].to_owned(),
    recorded_at: now_string(),
    evidence_digest: digest,
    artifact,
  })
}

///|
async fn StudioService::decide_creative_from_ui(
  self : StudioService,
  project_id : String,
  kind : @creative.ArtifactKind,
  input : LegacyCreativeDecisionInput,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    record.snapshot.revision == input.expected_project_revision &&
    current_creative(record.snapshot, kind) is Some(current) &&
    current.reference.version == input.expected_artifact_version &&
    normalized_digest(current.reference.digest) ==
    normalized_digest(input.expected_artifact_digest) else {
    raise Conflict(
      code="creative_artifact_revision_conflict",
      message="decision must be named-human confirmed and bind the exact current artifact",
    )
  }
  let decision_name = match input.decision {
    "approve" => "approved"
    "reject" => "rejected"
    "request-revision" => "revision-requested"
    value => value
  }
  let decided_at = now_string()
  let evidence_digest = "sha256:" +
    sha256_text(
      current.reference.digest +
      ":" +
      decision_name +
      ":" +
      input.actor +
      ":" +
      input.actor_role +
      ":" +
      input.note +
      ":" +
      decided_at,
    )
  let decision : @creative.CreativeDecision = {
    artifact: current.reference,
    decision: decision_name,
    actor: input.actor,
    role: input.actor_role,
    decided_at,
    note: input.note,
  }
  self.record_creative_decision(project_id, {
    expected_revision: input.expected_project_revision,
    command_id: "creative-decision-" +
    sha256_text(evidence_digest)[:20].to_owned(),
    recorded_at: decided_at,
    evidence_digest,
    decision,
  })
}

///|
async fn StudioService::dispatch_unsafe(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response {
  if self.dispatch_route_extension(request) is Some(extension_response) {
    return extension_response
  }
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (Get, ["api", "workspace", "catalog"]) =>
      json_value_response(200, self.workspace_catalog())
    (Get, ["api", "workspace", "projects", project_id, "capsules"]) =>
      json_value_response(200, self.workspace_capsules(project_id))
    (Get, ["api", "workspace", "projects", project_id, "graphs"]) =>
      json_value_response(200, self.list_workspace_graphs(project_id))
    (
      Post,
      [
        "api",
        "workspace",
        "projects",
        project_id,
        "capsules",
        capsule_id,
        "install",
      ],
    ) => {
      let input : WorkspaceCapsuleInstallRequest = decode_body(request)
      json_value_response(
        200,
        self.install_workspace_capsule(project_id, capsule_id, input),
      )
    }
    (Post, ["api", "workspace", "graphs", "validate"]) => {
      let graph : @workspace.WorkspaceGraph = decode_body(request)
      json_value_response(200, self.validate_workspace_graph(graph))
    }
    (Post, ["api", "workspace", "graphs", "compare"]) => {
      let input : WorkspaceGraphDiffRequest = decode_body(request)
      json_value_response(200, self.compare_workspace_graphs(input))
    }
    (Post, ["api", "workspace", "projects", project_id, "graphs"]) => {
      let graph : @workspace.WorkspaceGraph = decode_body(request)
      guard graph.project_id == project_id else {
        raise Invalid(
          code="workspace_project_mismatch",
          message="workspace graph project does not match route project",
        )
      }
      json_value_response(201, self.save_workspace_graph(graph))
    }
    (Get, ["api", "workspace", "projects", project_id, "graphs", graph_id]) =>
      json_value_response(200, self.get_workspace_graph(project_id, graph_id))
    (
      Post,
      [
        "api",
        "workspace",
        "projects",
        project_id,
        "graphs",
        graph_id,
        "revisions",
      ],
    ) => {
      let input : WorkspaceGraphRevisionRequest = decode_body(request)
      json_value_response(
        201,
        self.revise_workspace_graph(project_id, graph_id, input),
      )
    }
    (
      Post,
      ["api", "workspace", "projects", project_id, "graphs", graph_id, "fork"],
    ) => {
      let input : WorkspaceGraphForkRequest = decode_body(request)
      json_value_response(
        201,
        self.fork_workspace_graph(project_id, graph_id, input),
      )
    }
    (
      Get,
      [
        "api",
        "workspace",
        "projects",
        project_id,
        "graphs",
        graph_id,
        "history",
      ],
    ) =>
      json_value_response(
        200,
        self.workspace_graph_history(project_id, graph_id),
      )
    (Post, ["api", "workspace", "plans"]) => {
      let input : WorkspacePlanRequest = decode_body(request)
      json_value_response(201, self.freeze_workspace_plan(input))
    }
    (Post, ["api", "workspace", "recipes", capsule_id, "runs"]) => {
      let input : WorkspaceRecipeRunRequest = decode_body(request)
      json_value_response(201, self.start_workspace_recipe(capsule_id, input))
    }
    (
      Post,
      ["api", "workspace", "projects", project_id, "graphs", graph_id, "runs"],
    ) => {
      let input : WorkspaceGraphRunRequest = decode_body(request)
      json_value_response(
        201,
        self.start_workspace_graph_run(project_id, graph_id, input),
      )
    }
    (Post, ["api", "workspace", "runs"]) => {
      let input : WorkspaceRunCreateRequest = decode_body(request)
      json_value_response(201, self.create_workspace_run(input))
    }
    (Get, ["api", "workspace", "runs", run_id]) =>
      json_value_response(200, self.get_workspace_run(run_id))
    (Get, ["api", "workspace", "projects", project_id, "runs"]) =>
      json_value_response(
        200,
        self.list_workspace_runs(
          project_id,
          control_tower_query_value(request.query, "state").unwrap_or(""),
          control_tower_query_value(request.query, "offset")
          .map(value => @string.parse_int(value) catch { _ => 0 })
          .unwrap_or(0),
          control_tower_query_value(request.query, "limit")
          .map(value => @string.parse_int(value) catch { _ => 50 })
          .unwrap_or(50),
        ),
      )
    (Post, ["api", "workspace", "runs", run_id, "commands"]) => {
      let input : WorkspaceRunCommand = decode_body(request)
      json_value_response(200, self.apply_workspace_run_command(run_id, input))
    }
    (Post, ["api", "workspace", "runs", run_id, "claim"]) => {
      let input : WorkspaceRunClaimRequest = decode_body(request)
      json_value_response(200, self.claim_workspace_run_node(run_id, input))
    }
    (Post, ["api", "workspace", "runs", run_id, "advance"]) => {
      let input : WorkspaceRunAdvanceRequest = decode_body(request)
      json_value_response(200, self.advance_workspace_run(run_id, input))
    }
    (Get, ["api", "workspace", "runs", run_id, "outputs", node_id]) =>
      json_value_response(
        200,
        self.get_workspace_native_output(run_id, node_id),
      )
    (Post, ["api", "workspace", "runs", run_id, "nodes", node_id, "decision"]) => {
      let input : WorkspaceHumanDecisionRequest = decode_body(request)
      json_value_response(
        200,
        self.decide_workspace_human_gate(run_id, node_id, input),
      )
    }
    (Post, ["api", "workspace", "runs", run_id, "actions", action]) => {
      let input : WorkspaceRunActionRequest = decode_body(request)
      json_value_response(
        200,
        self.apply_workspace_run_action(run_id, action, input),
      )
    }
    (Post, ["api", "workspace", "runs", run_id, "promote-template"]) => {
      let input : WorkspaceRunTemplateRequest = decode_body(request)
      json_value_response(
        201,
        self.promote_workspace_run_to_template(run_id, input),
      )
    }
    (Get, ["api", "workspace", "runs", run_id, "events"]) => {
      let response = @host_http.text_response(
        200,
        "OK",
        self.workspace_run_events_sse(
          run_id,
          control_tower_query_value(request.query, "after").unwrap_or(""),
        ),
        content_type="text/event-stream; charset=utf-8",
      )
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"
      response
    }
    (Get, ["api", "workspace", "runs", run_id, "events", "replay"]) =>
      json_value_response(
        200,
        self.workspace_run_events(
          run_id,
          control_tower_query_value(request.query, "after").unwrap_or(""),
        ),
      )
    (Post, ["api", "workspace", "runs", run_id, "nodes", node_id, "dispatch"]) => {
      let input : WorkspaceDispatchPrepareRequest = decode_body(request)
      json_value_response(
        202,
        self.prepare_workspace_dispatch(run_id, node_id, input),
      )
    }
    (Post, ["api", "workspace", "dispatches", dispatch_id, "receipt"]) => {
      let input : @workspace.WorkspaceDispatchReceipt = decode_body(request)
      json_value_response(
        200,
        self.apply_workspace_dispatch_receipt(dispatch_id, input),
      )
    }
    (Get, ["api", "workspace", "artifacts"]) =>
      json_value_response(200, self.list_workspace_artifacts())
    (Get, ["api", "workspace", "projects", project_id, "artifacts"]) =>
      json_value_response(200, self.list_workspace_artifacts(project_id~))
    (Get, ["api", "workspace", "projects", project_id, "assets"]) =>
      json_value_response(
        200,
        self.list_workspace_asset_library(
          project_id,
          control_tower_query_value(request.query, "q").unwrap_or(""),
          control_tower_query_value(request.query, "kind").unwrap_or(""),
          control_tower_query_value(request.query, "tag").unwrap_or(""),
          control_tower_query_value(request.query, "offset")
          .map(value => @string.parse_int(value) catch { _ => 0 })
          .unwrap_or(0),
          control_tower_query_value(request.query, "limit")
          .map(value => @string.parse_int(value) catch { _ => 50 })
          .unwrap_or(50),
          control_tower_query_value(request.query, "include_deleted") ==
          Some("true"),
        ),
      )
    (Post, ["api", "workspace", "artifacts"]) => {
      let artifact : @workspace.WorkspaceArtifact = decode_body(request)
      json_value_response(201, self.save_workspace_artifact(artifact))
    }
    (Post, ["api", "workspace", "artifacts", "compare"]) => {
      let input : WorkspaceArtifactCompareRequest = decode_body(request)
      json_value_response(200, self.compare_workspace_artifacts(input))
    }
    (Post, ["api", "workspace", "artifacts", "promote"]) => {
      let input : WorkspaceArtifactPromoteRequest = decode_body(request)
      json_value_response(201, self.promote_workspace_artifact(input))
    }
    (Post, ["api", "workspace", "artifacts", "branch"]) => {
      let input : WorkspaceArtifactBranchRequest = decode_body(request)
      json_value_response(201, self.branch_workspace_artifact(input))
    }
    (Post, ["api", "workspace", "assets", artifact_id, version, "tags"]) => {
      let input : WorkspaceAssetTagsRequest = decode_body(request)
      let parsed = @string.parse_int(version) catch { _ => -1 }
      json_value_response(
        200,
        self.tag_workspace_asset(artifact_id, parsed, input),
      )
    }
    (Post, ["api", "workspace", "assets", artifact_id, version, "delete"]) => {
      let input : WorkspaceAssetDeleteRequest = decode_body(request)
      let parsed = @string.parse_int(version) catch { _ => -1 }
      json_value_response(
        200,
        self.delete_workspace_asset(artifact_id, parsed, input),
      )
    }
    (
      Post,
      [
        "api",
        "workspace",
        "projects",
        project_id,
        "utility-concats",
        job_id,
        "register",
      ],
    ) => {
      let input : WorkspaceUtilityArtifactRegisterRequest = decode_body(request)
      json_value_response(
        201,
        self.register_utility_concat_workspace_artifact(
          project_id, job_id, input,
        ),
      )
    }
    (Post, ["api", "workspace", "comments"]) => {
      let input : WorkspaceCommentCreateRequest = decode_body(request)
      json_value_response(201, self.record_workspace_comment(input))
    }
    (Post, ["api", "workspace", "comments", "drafts"]) => {
      let input : WorkspaceCommentDraftRequest = decode_body(request)
      json_value_response(201, self.record_workspace_comment_draft(input))
    }
    (Post, ["api", "workspace", "presence"]) => {
      let input : WorkspacePresenceRequest = decode_body(request)
      json_value_response(200, self.renew_workspace_presence(input))
    }
    (Post, ["api", "workspace", "presence", "leases"]) => {
      let input : WorkspacePresenceLeaseRequest = decode_body(request)
      json_value_response(200, self.renew_workspace_presence_lease(input))
    }
    (Post, ["api", "workspace", "shares"]) => {
      let input : WorkspaceShareCreateRequest = decode_body(request)
      json_value_response(201, self.create_workspace_share(input))
    }
    (Post, ["api", "workspace", "shares", "secure"]) => {
      let input : WorkspaceSecureShareRequest = decode_body(request)
      json_value_response(201, self.create_secure_workspace_share(input))
    }
    (Get, ["api", "workspace", "shares", share_id, "access"]) =>
      json_value_response(
        200,
        self.access_workspace_share(
          share_id,
          control_tower_query_value(request.query, "token").unwrap_or(""),
        ),
      )
    (Post, ["api", "workspace", "shares", share_id, "revoke"]) => {
      let input : WorkspaceShareRevokeRequest = decode_body(request)
      json_value_response(200, self.revoke_workspace_share(share_id, input))
    }
    (Post, ["api", "workspace", "capsules", "publish"]) => {
      let input : WorkspaceCapsulePublishRequest = decode_body(request)
      json_value_response(201, self.publish_workspace_capsule(input))
    }
    (Post, ["api", "workspace", "capsules", capsule_id, "publish"]) => {
      let input : WorkspaceBuiltinCapsulePublishRequest = decode_body(request)
      json_value_response(
        201,
        self.publish_builtin_workspace_capsule(capsule_id, input),
      )
    }
    (Get, ["api", "workspace", "projects", project_id, "features"]) =>
      json_value_response(200, self.workspace_features(project_id))
    (Get, ["api", "workspace", "projects", project_id, "search"]) =>
      json_value_response(
        200,
        self.search_workspace(
          project_id,
          control_tower_query_value(request.query, "q").unwrap_or(""),
        ),
      )
    (Post, ["api", "workspace", "search"]) => {
      let input : WorkspaceSearchRequest = decode_body(request)
      json_value_response(
        200,
        self.search_workspace(input.project_id, input.query),
      )
    }
    (Post, ["api", "workspace", "proposals", "apply"]) => {
      let input : WorkspaceProposalApplyRequest = decode_body(request)
      json_value_response(200, self.apply_workspace_proposal(input))
    }
    (
      Post,
      [
        "api",
        "workspace",
        "projects",
        project_id,
        "proposals",
        proposal_id,
        "apply",
      ],
    ) => {
      let input : WorkspaceProposalApplyByIdRequest = decode_body(request)
      json_value_response(
        200,
        self.apply_saved_workspace_proposal(project_id, proposal_id, input),
      )
    }
    (Post, ["api", "workspace", "proposals"]) => {
      let input : @workspace.AgentGraphProposal = decode_body(request)
      json_value_response(201, self.save_workspace_proposal(input))
    }
    (Get, ["api", "workspace", "projects", project_id, "proposals"]) =>
      json_value_response(200, self.list_workspace_proposals(project_id))
    (Get, ["api", "workspace", "projects", project_id, "proposals", proposal_id]
    ) =>
      json_value_response(
        200,
        self.review_saved_workspace_proposal(project_id, proposal_id),
      )
    (Get, ["api", "config"]) =>
      json_value_response(200, {
        mode: "moonbit-native-canonical",
        network_execution_enabled: false,
        publication_authority: false,
        command_endpoint: "/api/v2/projects/{project_id}/commands",
      })
    (Get, ["api", "v2", "projects"]) =>
      json_value_response(
        200,
        omit_null_fields({ projects: self.list_projects() }.to_json()),
      )
    (Post, ["api", "v2", "projects"]) => {
      let json = @json.parse(@utf8.decode(request.body))
      let (graph, recorded_at, experience) = if json_member(json, "graph")
        is Some(_) {
        let input : CanonicalCreateRequest = @json.from_json(json)
        (input.graph, input.recorded_at.unwrap_or(now_string()), None)
      } else {
        let input : LegacyCreateRequest = @json.from_json(json)
        let experience : ProjectExperienceMetadata = {
          objective: input.objective.unwrap_or(input.title),
          audience: input.audience.unwrap_or("general"),
          channels: input.channels.unwrap_or(["review-only"]),
          rights_owner: input.rights_owner.unwrap_or("unassigned"),
          rights_confirmed: input.rights_confirmed.unwrap_or(false),
        }
        (legacy_graph(input), now_string(), Some(experience))
      }
      let created = self.create_project(graph, recorded_at)
      let ready = match experience {
        Some(value) => {
          self.save_project_experience(created.project_id, value)
          self.seed_initial_creative_drafts(
            created.project_id,
            value,
            recorded_at,
          )
        }
        None => created
      }
      json_value_response(201, self.studio_project_projection(ready))
    }
    (Get, ["api", "v2", "projects", project_id]) =>
      json_value_response(
        200,
        self.studio_project_projection(self.get_project(project_id)),
      )
    (Delete, ["api", "v2", "projects", project_id]) => {
      let input : DeleteRequest = decode_body(request)
      self.delete_project(project_id, input.expected_revision)
      json_value_response(200, { deleted: true, project_id })
    }
    (Get, ["api", "v2", "projects", project_id, "events"]) => {
      let project = self.get_project(project_id)
      json_value_response(200, { events: project.events })
    }
    (Get, ["api", "v2", "projects", project_id, "governance"]) =>
      json_value_response(200, self.governance_view(project_id))
    (Get, ["api", "v2", "projects", project_id, "master", "provenance"]) => {
      let project = self.get_project(project_id)
      match project.snapshot.master {
        Some(master) => json_value_response(200, master)
        None =>
          api_error(404, "master_not_found", "master provenance does not exist")
      }
    }
    (Post, ["api", "v2", "projects", project_id, "commands"]) => {
      let input : ProjectCommandRequest = decode_body(request)
      let response = self.apply_project_command(project_id, input)
      json_value_response(if response.result.ok { 200 } else { 422 }, response)
    }
    (Post, ["api", "v2", "projects", project_id, "advance"]) => {
      let json = @json.parse(@utf8.decode(request.body))
      let input : GateCommandRequest = if json_member(json, "expected_revision")
        is Some(_) {
        @json.from_json(json)
      } else {
        let legacy : LegacyAdvanceInput = @json.from_json(json)
        let record = self.get_project(project_id)
        let recorded_at = now_string()
        let evidence_digest = "sha256:" +
          sha256_text(
            project_id +
            ":" +
            legacy.gate +
            ":" +
            legacy.actor +
            ":" +
            legacy.note +
            ":" +
            recorded_at,
          )
        {
          expected_revision: record.snapshot.revision,
          command_id: "gate-" +
          legacy.gate +
          "-" +
          sha256_text(evidence_digest)[:16].to_owned(),
          recorded_at,
          evidence_digest,
          gate: legacy.gate,
          actor: legacy.actor,
          role: "creative-director",
        }
      }
      let response = self.advance_gate(project_id, input)
      json_value_response(
        if response.result.ok {
          200
        } else {
          422
        },
        self.project_command_ui(response),
      )
    }
    (Get, ["api", "v2", "projects", project_id, "creative", kind]) =>
      match creative_kind(kind) {
        Some(value) =>
          json_value_response(
            200,
            self.creative_workspace_projection(project_id, value),
          )
        None =>
          api_error(
            404, "creative_kind_not_found", "creative artifact kind was not found",
          )
      }
    (Post, ["api", "v2", "projects", project_id, "creative", kind, "revise"]) => {
      guard creative_kind(kind) is Some(wanted) else {
        raise Invalid(
          code="creative_kind_invalid",
          message="creative path kind is invalid",
        )
      }
      let json = @json.parse(@utf8.decode(request.body))
      let response = if json_member(json, "artifact") is Some(_) {
        let input : CreativeArtifactRequest = @json.from_json(json)
        guard wanted == input.artifact.kind else {
          raise Invalid(
            code="creative_kind_mismatch",
            message="path kind does not match typed artifact",
          )
        }
        self.record_creative_artifact(project_id, input)
      } else {
        self.revise_creative_from_ui(project_id, wanted, @json.from_json(json))
      }
      json_value_response(
        if response.result.ok {
          200
        } else {
          422
        },
        self.project_command_ui(response),
      )
    }
    (Post, ["api", "editor", "utility-concats"]) => {
      let input : UtilityConcatCreateRequest = decode_body(request)
      json_value_response(201, self.create_utility_concat(input))
    }
    (Post, ["api", "editor", "utility-concats", job_id, "inputs", index_text]) => {
      let index = @string.parse_int(index_text) catch {
        _ =>
          raise Invalid(
            code="utility_concat_index_invalid",
            message="utility concat input index must be an integer",
          )
      }
      json_value_response(
        201,
        self.upload_utility_concat_input(job_id, index, request.body),
      )
    }
    (Post, ["api", "editor", "utility-concats", job_id, "run"]) =>
      json_value_response(200, self.run_utility_concat(job_id))
    (Get, ["api", "editor", "utility-concats", job_id]) =>
      json_value_response(200, self.get_utility_concat(job_id))
    (Get | Head, ["api", "editor", "utility-concats", job_id, "media"]) => {
      let job = self.get_utility_concat(job_id)
      let content = self.resolve_utility_concat_media(job_id)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        job.output_digest,
        content,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = "video/mp4"
      response.headers["Content-Disposition"] = "attachment; filename=\"mooncast-" +
        job.job_id +
        ".mp4\""
      response
    }
    (Get, ["api", "editor", "projects"]) =>
      json_value_response(200, self.list_editor_projects())
    (Post, ["api", "editor", "projects"]) => {
      let input : EditorCreateRequest = decode_body(request)
      json_value_response(201, self.create_editor_project(input))
    }
    (Get, ["api", "editor", "projects", project_id]) =>
      json_value_response(200, self.get_editor_project(project_id))
    (Get, ["api", "editor", "projects", project_id, "snapshot"]) =>
      json_value_response(200, self.get_editor_project(project_id))
    (
      Post,
      [
        "api",
        "editor",
        "projects",
        project_id,
        "production-import"
        | "production-refresh",
      ],
    ) => {
      let json = @json.parse(@utf8.decode(request.body))
      if json_member(json, "production") is None {
        json_value_response(
          201,
          self.import_editor_from_canonical_project(project_id),
        )
      } else {
        let input : EditorProductionImportRequest = @json.from_json(json)
        guard input.production.snapshot.project_id == project_id else {
          raise Invalid(
            code="editor_project_mismatch",
            message="production import must bind the route project",
          )
        }
        json_value_response(201, self.import_editor_production(input))
      }
    }
    (Post, ["api", "editor", "projects", project_id, "commands"]) => {
      let json = @json.parse(@utf8.decode(request.body))
      let canonical_command = match json_member(json, "command") {
        Some(command_json) => json_member(command_json, "operation") is Some(_)
        None => false
      }
      let (command, supplied_digest) = if canonical_command {
        let input : EditorCommandEnvelope = @json.from_json(json)
        (input.command, input.content_digest)
      } else {
        let input : LegacyEditorCommandEnvelope = @json.from_json(json)
        (self.legacy_editor_command(project_id, input), input.content_digest)
      }
      let digest = supplied_digest.unwrap_or(
        "sha256:" +
        sha256_text(@editor_domain.legacy_command_json(command).stringify()),
      )
      json_value_response(
        200,
        self.dispatch_editor_command(project_id, command, digest),
      )
    }
    (Post, ["api", "editor", "projects", project_id, "review-comments"]) => {
      let input : EditorReviewCommentRequest = decode_body(request)
      json_value_response(
        201,
        self.record_editor_review_comment(project_id, input),
      )
    }
    (Post, ["api", "editor", "projects", project_id, "media-intakes"]) => {
      let input : EditorPrepareIntakeRequest = decode_body(request)
      json_value_response(201, self.prepare_editor_intake(project_id, input))
    }
    (
      Post,
      [
        "api",
        "editor",
        "projects",
        project_id,
        "media-intakes",
        intake_id,
        "content",
      ],
    ) =>
      json_value_response(
        201,
        self.complete_editor_intake(project_id, intake_id, request.body),
      )
    (
      Get,
      ["api", "editor", "projects", project_id, "takes", take_id, "analysis"],
    ) => {
      let take = self.find_editor_take(project_id, take_id)
      let view = self.analyze_editor_media(take.media_digest)
      json_value_response(200, view.analysis)
    }
    (
      Get
      | Head,
      ["api", "editor", "projects", project_id, "takes", take_id, "source"],
    ) => {
      let take = self.find_editor_take(project_id, take_id)
      ignore(self.analyze_editor_media(take.media_digest))
      let (media, content) = self.resolve_editor_media(take.media_digest, false)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        media.digest,
        content,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = media.mime
      response
    }
    (
      Get
      | Head,
      ["api", "editor", "projects", project_id, "takes", take_id, "thumbnail"],
    ) => {
      let take = self.find_editor_take(project_id, take_id)
      let view = self.analyze_editor_media(take.media_digest)
      guard view.analysis.thumbnail.digest is Some(thumbnail_digest) else {
        raise NotFound(entity="editor_thumbnail", id=take_id)
      }
      let (media, content) = self.resolve_editor_media(thumbnail_digest, false)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        media.digest,
        content,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = media.mime
      response
    }
    (Get, ["api", "editor", "media", digest, "analysis"]) =>
      json_value_response(200, self.analyze_editor_media(digest))
    (Get | Head, ["api", "editor", "media", digest]) => {
      let (media, content) = self.resolve_editor_media(digest, false)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        media.digest,
        content,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = media.mime
      response
    }
    (Get | Head, ["api", "editor", "media", digest, "thumbnail"]) => {
      let view = self.analyze_editor_media(digest)
      guard view.analysis.thumbnail.digest is Some(thumbnail_digest) else {
        raise NotFound(entity="editor_thumbnail", id=digest)
      }
      let (media, content) = self.resolve_editor_media(thumbnail_digest, false)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        media.digest,
        content,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = media.mime
      response
    }
    (
      Post,
      [
        "api",
        "editor",
        "projects",
        project_id,
        "preview-sessions"
        | "previews"
        | "jobs",
      ],
    ) => {
      let json = @json.parse(@utf8.decode(request.body))
      let input : EditorPreviewCreateRequest = if json_member(
          json, "expected_editor_revision",
        )
        is Some(_) {
        @json.from_json(json)
      } else {
        let legacy : LegacyPreviewRequest = @json.from_json(json)
        {
          expected_editor_revision: legacy.project_revision,
          idempotency_key: legacy.session_id,
          quality: legacy.quality,
          job_id: Some(legacy.session_id),
        }
      }
      json_value_response(
        202,
        editor_job_api(self.create_editor_preview(project_id, input)),
      )
    }
    (Get, ["api", "editor", "projects", project_id, "jobs", job_id]) =>
      json_value_response(
        200,
        editor_job_api(self.get_editor_job(project_id, job_id)),
      )
    (Post, ["api", "editor", "projects", project_id, "jobs", job_id, "retry"]) =>
      json_value_response(
        200,
        editor_job_api(self.retry_editor_job(project_id, job_id)),
      )
    (
      Get
      | Head,
      ["api", "editor", "projects", project_id, "jobs", job_id, "media"],
    ) => {
      let content = self.resolve_editor_job_media(project_id, job_id)
      let job = self.get_editor_job(project_id, job_id)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        job.job.output_digest,
        content,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = "video/mp4"
      response
    }
    (Post, ["api", "editor", "projects", project_id, "exports"]) => {
      let json = @json.parse(@utf8.decode(request.body))
      guard json_member(json, "export") is Some(export_json) &&
        json_member(json, "idempotency_key") is Some(idempotency_json) else {
        raise Invalid(
          code="editor_export_contract_invalid",
          message="production export requires {export,idempotency_key}",
        )
      }
      let input : EditorExportCreateRequest = @json.from_json(
        Json::object({
          "export_request": export_json,
          "idempotency_key": idempotency_json,
        }),
      )
      json_value_response(
        201,
        editor_job_api(self.create_editor_export(project_id, input)),
      )
    }
    (Get, ["api", "editor", "projects", project_id, "exports", job_id]) =>
      json_value_response(
        200,
        editor_job_api(self.get_editor_job(project_id, job_id)),
      )
    (Post, ["api", "editor", "projects", project_id, "exports", job_id, "retry"]
    ) =>
      json_value_response(
        200,
        editor_job_api(self.retry_editor_job(project_id, job_id)),
      )
    (
      Get
      | Head,
      ["api", "editor", "projects", project_id, "exports", job_id, "media"],
    ) => {
      let content = self.resolve_editor_job_media(project_id, job_id)
      let job = self.get_editor_job(project_id, job_id)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        job.job.output_digest,
        content,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = "video/mp4"
      response
    }
    (
      Get
      | Head,
      ["api", "editor", "projects", project_id, "exports", job_id, "subtitles"],
    ) => {
      let job = self.get_editor_job(project_id, job_id)
      guard job.job.state == "succeeded" &&
        self.editor_render_files.get_blob(
          editor_subtitle_key(project_id, job_id),
        )
        is Some(blob) &&
        !blob.bytes.is_empty() else {
        raise Invalid(
          code="editor_export_subtitle_missing",
          message="verified production subtitle sidecar is missing",
        )
      }
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        "sha256:" + blob.sha256,
        blob.bytes,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = "application/x-subrip; charset=utf-8"
      response
    }
    (
      Get
      | Head,
      ["api", "editor", "projects", project_id, "exports", job_id, "provenance"],
    ) => {
      let job = self.get_editor_job(project_id, job_id)
      guard job.job.state == "succeeded" &&
        self.editor_render_files.get_blob(
          editor_provenance_key(project_id, job_id),
        )
        is Some(blob) &&
        !blob.bytes.is_empty() else {
        raise Invalid(
          code="editor_export_provenance_missing",
          message="verified production provenance manifest is missing",
        )
      }
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        "sha256:" + blob.sha256,
        blob.bytes,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = "application/json; charset=utf-8"
      response
    }
    (
      Post,
      [
        "api",
        "editor",
        "projects",
        project_id,
        "exports",
        job_id,
        "promote-master",
      ],
    ) => {
      let legacy : LegacyPromotionRequest = decode_body(request)
      guard self.editor_production_source(project_id) is Some(source) &&
        source.production_revision == legacy.expected_project_revision &&
        normalized_digest(source.binding_digest) ==
        normalized_digest(legacy.production_binding_digest) &&
        normalized_digest(source.production_digest) ==
        normalized_digest(legacy.production_digest) &&
        normalized_digest(source.g4_receipt_digest) ==
        normalized_digest(legacy.g4_receipt_digest) else {
        raise Conflict(
          code="editor_production_source_mismatch",
          message="promotion must bind the immutable imported production source",
        )
      }
      let envelope : EditorMasterPromotionEnvelope = {
        request: {
          job_id: legacy.job_id,
          expected_project_revision: legacy.expected_project_revision,
          actor: legacy.actor,
          authority_ref: legacy.authority_ref,
        },
        production_source: source,
        master_id: "master-" + job_id,
        subtitle_ref: "/api/editor/projects/" +
        project_id +
        "/exports/" +
        job_id +
        "/subtitles",
        promoted_at: now_string(),
      }
      json_value_response(
        200,
        self.promote_editor_master(project_id, job_id, envelope),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "creative", kind, "decision"]) => {
      guard creative_kind(kind) is Some(wanted) else {
        raise Invalid(
          code="creative_kind_invalid",
          message="creative path kind is invalid",
        )
      }
      let json = @json.parse(@utf8.decode(request.body))
      let response = if json_member(json, "expected_revision") is Some(_) {
        let input : CreativeDecisionRequest = @json.from_json(json)
        let view = self.creative_view(project_id, wanted)
        guard view.artifact is Some(current) else {
          raise Conflict(
            code="creative_artifact_revision_conflict",
            message="canonical current artifact does not exist",
          )
        }
        guard current.reference == input.decision.artifact else {
          raise Conflict(
            code="creative_artifact_revision_conflict",
            message="decision must bind the canonical current artifact",
          )
        }
        self.record_creative_decision(project_id, input)
      } else {
        self.decide_creative_from_ui(project_id, wanted, @json.from_json(json))
      }
      json_value_response(
        if response.result.ok {
          200
        } else {
          422
        },
        self.project_command_ui(response),
      )
    }
    (Get, ["api", "provider-executions"]) =>
      json_value_response(
        200,
        (
          { jobs: self.list_provider_jobs(), publication_authority: false } :
          ProviderListResponse),
      )
    (Get, ["api", "provider-executions", "config"]) =>
      json_value_response(200, {
        mode: "planned-only",
        network_execution_enabled: false,
        publication_authority: false,
        command_endpoint: "/api/provider-executions/{job_id}/commands",
      })
    (Post, ["api", "provider-executions"]) => {
      let input : ProviderAuthorizationRequest = decode_body(request)
      json_value_response(201, self.authorize_provider_job(input))
    }
    (Get, ["api", "assets"]) =>
      @host_http.json_response(
        200, "OK", "{\"assets\":[],\"migration\":\"use /media and /api/editor media registry\"}",
      )
    (Get, ["api", "assets", _]) | (Post, ["api", "generate"]) =>
      api_error(
        410, "unsafe_legacy_asset_alias_removed", "use governed provider execution and content-addressed editor media",
      )
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        _,
        "generate"
        | "assemble"
        | "delivery-plan"
        | "deliver"
        | "analytics"
        | "review",
      ],
    ) =>
      api_error(
        410, "legacy_project_action_removed", "use routed execution, editor export, governance commands, or delivery builds",
      )
    (Post, ["api", "v2", "projects", _, "governance", ..]) =>
      api_error(
        422, "typed_governance_command_required", "submit the corresponding typed ProjectCommand through /commands",
      )
    (Get, ["api", "provider-executions", job_id]) =>
      json_value_response(200, self.get_provider_job(job_id))
    (Post, ["api", "provider-executions", job_id, "commands"]) => {
      let input : @execution.ProviderExecutionCommand = decode_body(request)
      let response = self.apply_provider_command(job_id, input)
      json_value_response(if response.result.ok { 200 } else { 422 }, response)
    }
    (Post, ["api", "v2", "projects", project_id, "routed-executions"]) => {
      let input : RoutedPlanRequest = decode_body(request)
      json_value_response(201, self.plan_routed_execution(project_id, input))
    }
    (Get, ["api", "v2", "projects", project_id, "routed-executions"]) =>
      json_value_response(200, {
        executions: self.list_routed_executions(project_id),
      })
    (
      Get,
      ["api", "v2", "projects", project_id, "routed-executions", execution_id],
    ) =>
      json_value_response(
        200,
        self.get_routed_execution(project_id, execution_id),
      )
    (Get | Head, ["media", media_id]) => {
      let media = self.resolve_media(media_id)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        media_id,
        media.content,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = media.record.content_type
      response
    }
    _ => api_error(404, "not_found", "not found")
  }
}

///|
pub async fn StudioService::dispatch_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response {
  self.dispatch_unsafe(request) catch {
    NotFound(entity~, id~) =>
      api_error(
        404,
        entity + "_not_found",
        entity + " " + id + " was not found",
      )
    Conflict(code~, message~) => api_error(409, code, message)
    Invalid(code~, message~) => api_error(422, code, message)
    @execution_app.AdapterUnavailable(adapter) =>
      api_error(
        409,
        "provider_adapter_unavailable",
        "configured provider adapter is unavailable: " + adapter,
      )
    @execution_app.AuthorityDenied(message) =>
      api_error(403, "provider_authority_denied", message)
    @execution_app.InvalidPlan(message) =>
      api_error(409, "provider_plan_invalid", message)
    @execution_app.RoutedPlanInvalid(message) =>
      api_error(409, "routed_plan_invalid", message)
    _ =>
      api_error(
        400, "request_invalid", "request body or route parameters are invalid",
      )
  }
}
