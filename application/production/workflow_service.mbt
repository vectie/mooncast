///|
pub(all) struct ProjectActionContext {
  command_id : String
  expected_revision : Int
  recorded_at : String
  evidence_digest : String
  actor : String?
  role : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeRevisionRequest {
  context : ProjectActionContext
  kind : @creative.ArtifactKind
  expected_artifact : @project.VersionRef
  content : String
  dependency_digests : Array[String]
  duration_seconds : Int?
  expected_cost_cny : Double?
  rights_cleared : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeDecisionRequest {
  context : ProjectActionContext
  kind : @creative.ArtifactKind
  expected_artifact : @project.VersionRef
  decision : String
  note : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GateAdvanceRequest {
  context : ProjectActionContext
  gate : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror ProductionWorkflowError {
  ProductionProjectNotFound(String)
  ProductionRevisionConflict(String)
  CreativeArtifactConflict(String)
  CreativeDecisionInvalid(String)
} derive(Debug)

///|
fn blank_command(
  snapshot : @kernel.ProjectSnapshot,
  action : String,
  context : ProjectActionContext,
) -> @kernel.ProjectCommand {
  {
    schema_version: "mooncast.project-command.v2",
    kernel_version: @kernel.production_kernel_version,
    command_id: context.command_id,
    command: action,
    recorded_at: context.recorded_at,
    evidence_digest: context.evidence_digest,
    snapshot,
    gate: None,
    actor: context.actor,
    role: context.role,
    qualification: None,
    creative_artifact: None,
    creative_decision: None,
    routing_plan: None,
    routing_decision: None,
    generation_attempt: None,
    qc_finding: None,
    qc_decision: None,
    master: None,
    master_decision: None,
    delivery_package: None,
    delivery_acceptance: None,
    publication_authorization: None,
    publication_observation: None,
    performance_review: None,
  }
}

///|
async fn ProjectRepository::exact_snapshot(
  self : ProjectRepository,
  project_id : String,
  expected_revision : Int,
) -> @kernel.ProjectSnapshot {
  let snapshot = match self.get(project_id) {
    None => raise ProductionProjectNotFound(project_id)
    Some(value) => value
  }
  if snapshot.revision != expected_revision {
    raise ProductionRevisionConflict(project_id)
  }
  snapshot
}

///|
pub async fn ProjectRepository::readiness(
  self : ProjectRepository,
  project_id : String,
  request : GateAdvanceRequest,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(
    project_id,
    request.context.expected_revision,
  )
  self.handle({
    ..blank_command(snapshot, "readiness", request.context),
    gate: Some(request.gate),
  })
}

///|
pub async fn ProjectRepository::advance_gate(
  self : ProjectRepository,
  project_id : String,
  request : GateAdvanceRequest,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(
    project_id,
    request.context.expected_revision,
  )
  self.handle({
    ..blank_command(snapshot, "advance_gate", request.context),
    gate: Some(request.gate),
  })
}

///|
pub async fn ProjectRepository::revise_creative_artifact(
  self : ProjectRepository,
  project_id : String,
  request : CreativeRevisionRequest,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(
    project_id,
    request.context.expected_revision,
  )
  let current = match
    @creative.current_artifact(snapshot.creative_artifacts, request.kind) {
    None => raise CreativeArtifactConflict(request.kind.to_string())
    Some(value) => value
  }
  if current.reference != request.expected_artifact ||
    request.content.trim() == "" {
    raise CreativeArtifactConflict(request.kind.to_string())
  }
  let version = current.reference.version + 1
  let digest = content_digest(
    request.kind.to_string() +
    ":" +
    version.to_string() +
    ":" +
    request.content +
    ":" +
    request.dependency_digests.join("|"),
  )
  let artifact : @creative.CreativeArtifact = {
    reference: { id: current.reference.id, version, digest },
    kind: request.kind,
    dependency_digests: request.dependency_digests,
    duration_seconds: request.duration_seconds,
    expected_cost_cny: request.expected_cost_cny,
    rights_cleared: request.rights_cleared,
    content: request.content,
  }
  self.handle({
    ..blank_command(snapshot, "record_creative_artifact", request.context),
    creative_artifact: Some(artifact),
  })
}

///|
pub async fn ProjectRepository::decide_creative_artifact(
  self : ProjectRepository,
  project_id : String,
  request : CreativeDecisionRequest,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(
    project_id,
    request.context.expected_revision,
  )
  let current = match
    @creative.current_artifact(snapshot.creative_artifacts, request.kind) {
    None => raise CreativeArtifactConflict(request.kind.to_string())
    Some(value) => value
  }
  if current.reference != request.expected_artifact ||
    (
      request.decision != "approved" &&
      request.decision != "rejected" &&
      request.decision != "revision-requested"
    ) {
    raise CreativeDecisionInvalid(request.kind.to_string())
  }
  let actor = request.context.actor.unwrap_or("")
  let role = request.context.role.unwrap_or("")
  if actor == "" || role == "" {
    raise CreativeDecisionInvalid("named human required")
  }
  let decision : @creative.CreativeDecision = {
    artifact: current.reference,
    decision: request.decision,
    actor,
    role,
    decided_at: request.context.recorded_at,
    note: request.note,
  }
  self.handle({
    ..blank_command(snapshot, "record_creative_decision", request.context),
    creative_decision: Some(decision),
  })
}

///|
pub async fn ProjectRepository::record_qualification(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  qualification : @governance.ClientQualification,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_qualification", context),
    qualification: Some(qualification),
  })
}

///|
pub async fn ProjectRepository::revise_model_routing_plan(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  plan : @governance.ModelRoutingPlan,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_routing_plan", context),
    routing_plan: Some(plan),
  })
}

///|
pub async fn ProjectRepository::decide_model_routing_plan(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  decision : @governance.RoutingDecision,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_routing_decision", context),
    routing_decision: Some(decision),
  })
}

///|
pub async fn ProjectRepository::append_generation_attempt(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  attempt : @governance.GenerationAttempt,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_generation_attempt", context),
    generation_attempt: Some(attempt),
  })
}

///|
pub async fn ProjectRepository::record_shot_qc_finding(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  finding : @governance.QcFinding,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_qc_finding", context),
    qc_finding: Some(finding),
  })
}

///|
pub async fn ProjectRepository::decide_shot_qc(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  decision : @governance.QcDecision,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_qc_decision", context),
    qc_decision: Some(decision),
  })
}

///|
pub async fn ProjectRepository::register_master(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  master : @governance.Master,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_master", context),
    master: Some(master),
  })
}

///|
pub async fn ProjectRepository::decide_master(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  decision : @governance.MasterDecision,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_master_decision", context),
    master_decision: Some(decision),
  })
}

///|
pub async fn ProjectRepository::revise_delivery_package(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  delivery : @governance.DeliveryPackage,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_delivery_package", context),
    delivery_package: Some(delivery),
  })
}

///|
pub async fn ProjectRepository::decide_delivery_milestone(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  acceptance : @governance.DeliveryAcceptance,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_delivery_acceptance", context),
    delivery_acceptance: Some(acceptance),
  })
}

///|
pub async fn ProjectRepository::authorize_publication(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  authorization : @governance.PublicationAuthorization,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_publication_authorization", context),
    publication_authorization: Some(authorization),
  })
}

///|
pub async fn ProjectRepository::observe_publication_receipt(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  observation : @governance.PublicationObservation,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_publication_observation", context),
    publication_observation: Some(observation),
  })
}

///|
pub async fn ProjectRepository::record_performance_review(
  self : ProjectRepository,
  project_id : String,
  context : ProjectActionContext,
  review : @governance.PerformanceReview,
) -> @kernel.CommandResult {
  let snapshot = self.exact_snapshot(project_id, context.expected_revision)
  self.handle({
    ..blank_command(snapshot, "record_performance_review", context),
    performance_review: Some(review),
  })
}
