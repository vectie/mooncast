///|
struct AnalyzerTaskRequest {
  task : @automated_qc.AnalyzerTask
} derive(FromJson)

///|
async fn StudioService::record_analyzer_task(
  self : StudioService,
  project_id : String,
  input : AnalyzerTaskRequest,
) -> @automated_qc.AnalyzerTask {
  let canonical = self.get_project(project_id)
  guard canonical.snapshot.generation_attempts.any(attempt => {
    attempt.shot_id == input.task.shot_id &&
    attempt.status == "succeeded" &&
    normalized_digest(attempt.output_digest) ==
    normalized_digest(input.task.attempt_digest)
  }) else {
    raise Conflict(
      code="analyzer_attempt_required",
      message="analyzer task must bind the current successful shot output",
    )
  }
  let base = {
    ..input.task,
    project_id,
    project_revision: canonical.snapshot.revision,
    reference: { ..input.task.reference, digest: "" },
    provider_execution_authority: false,
    publication_authority: false,
  }
  let exact = {
    ..base,
    reference: { ..base.reference, digest: @automated_qc.task_digest(base) },
  }
  self.automated_qc.record_task(exact)
}

///|
async fn StudioService::run_analyzer(
  self : StudioService,
  project_id : String,
  input : @automated_qc_app.AnalyzerRunRequest,
) -> @automated_qc.AnalyzerReceipt {
  let canonical = self.get_project(project_id)
  let tasks = self.automated_qc
    .list_tasks(project_id)
    .filter(task => {
      task.reference.version == input.expected_task_version &&
      task.reference.digest == input.expected_task_digest
    })
  guard tasks.length() == 1 else {
    raise Conflict(
      code="analyzer_task_conflict",
      message="exact analyzer task not found",
    )
  }
  let task = tasks[0]
  guard canonical.snapshot.generation_attempts.any(attempt => {
    attempt.shot_id == task.shot_id &&
    attempt.status == "succeeded" &&
    normalized_digest(attempt.output_digest) ==
    normalized_digest(task.attempt_digest)
  }) else {
    raise Conflict(
      code="analyzer_attempt_stale",
      message="analyzer source attempt is no longer current",
    )
  }
  let source = match
    self.execution_application.artifact_bytes(task.source_artifact_digest) {
    Some(bytes) => Some(bytes)
    None =>
      self.editor_media.bytes(normalized_digest(task.source_artifact_digest))
  }
  let receipt = self.automated_qc.run(task, source, input)
  let dimension = if receipt.finding.governance_dimension == "continuity" {
    @governance.Continuity
  } else {
    @governance.Technical
  }
  let refreshed = self.get_project(project_id)
  let current = refreshed.snapshot.qc_findings.filter(finding => {
    finding.shot_id == task.shot_id &&
    finding.dimension == dimension &&
    normalized_digest(finding.attempt_digest) ==
    normalized_digest(task.attempt_digest)
  })
  let expected_version = if current.is_empty() {
    None
  } else {
    Some(current[current.length() - 1].finding.version)
  }
  let expected_digest = if current.is_empty() {
    None
  } else {
    Some(current[current.length() - 1].finding.digest)
  }
  ignore(
    self.record_qc_finding_feature(project_id, task.shot_id, dimension, {
      expected_project_revision: refreshed.snapshot.revision,
      expected_attempt_digest: task.attempt_digest,
      expected_finding_version: expected_version,
      expected_finding_digest: expected_digest,
      status: receipt.finding.status,
      evidence_digest: receipt.finding.evidence_digest,
      note: task.analyzer +
      ": " +
      receipt.finding.note +
      "; named human decision still required",
      reported_by: "analyzer:" + input.actor,
    }),
  )
  receipt
}

///|
async fn StudioService::dispatch_automated_qc_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  match (request.request_method, path_segments(request.path)) {
    (Get, ["api", "v2", "projects", project_id, "automated-qc"]) =>
      Some(json_value_response(200, self.automated_qc.workspace(project_id)))
    (Post, ["api", "v2", "projects", project_id, "automated-qc", "tasks"]) => {
      let input : AnalyzerTaskRequest = decode_body(request)
      Some(
        json_value_response(201, self.record_analyzer_task(project_id, input)),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "automated-qc", "run"]) => {
      let input : @automated_qc_app.AnalyzerRunRequest = decode_body(request)
      Some(json_value_response(201, self.run_analyzer(project_id, input)))
    }
    _ => None
  }
}

///|
pub fn StudioService::register_automated_qc_routes(
  self : StudioService,
) -> Unit {
  self.register_route_extension(
    RouteExtension::new("/api/v2/projects", async fn(request) {
      self.dispatch_automated_qc_http(request)
    }),
  )
}
