///|
pub(all) struct RouteDescriptor {
  request_method : String
  path_template : String
  handler : String
  body_contract : String
  response_contract : String
  authority : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct HttpErrorBody {
  code : String
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct HttpFailure {
  ok : Bool
  dirty : Bool
  saved : Bool
  revision : Int?
  conflict : Bool
  error : HttpErrorBody
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct HttpSuccess {
  ok : Bool
  dirty : Bool
  saved : Bool
  revision : Int?
  conflict : Bool
  error : HttpErrorBody?
  data : Json
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn failure(code : String, message : String) -> HttpFailure {
  {
    ok: false,
    dirty: false,
    saved: false,
    revision: None,
    conflict: code == "revision_conflict",
    error: { code, message },
  }
}

///|
pub fn[T : ToJson] success(
  value : T,
  revision : Int?,
  dirty : Bool,
  saved : Bool,
) -> HttpSuccess {
  {
    ok: true,
    dirty,
    saved,
    revision,
    conflict: false,
    error: None,
    data: value.to_json(),
  }
}

///|
/// Accepts only locator-free ASCII identifiers suitable for URLs and store keys.
pub fn require_id(value : String) -> String raise {
  guard !value.is_blank() &&
    value.length() <= 128 &&
    value != "." &&
    value != ".." else {
    fail("invalid identifier")
  }
  let bytes = @utf8.encode(value)
  for byte in bytes {
    let code = byte.to_int()
    let allowed = (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 46 ||
      code == 95 ||
      code == 45
    guard allowed else { fail("invalid identifier") }
  }
  value
}

///|
pub fn require_relative_path(value : String) -> String raise {
  guard !value.is_blank() && !value.has_prefix("/") && !value.contains("\\") else {
    fail("invalid relative path")
  }
  for part in value.split("/") {
    guard !part.is_blank() && part != "." && part != ".." else {
      fail("invalid relative path")
    }
  }
  value
}

///|
pub fn require_expected_revision(value : Int) -> Int raise {
  guard value >= 0 else { fail("expected revision must be non-negative") }
  value
}

///|
pub fn require_idempotency_key(value : String) -> String raise {
  guard !value.is_blank() && value.length() <= 160 else {
    fail("invalid idempotency key")
  }
  for byte in @utf8.encode(value) {
    guard byte.to_int() >= 32 else { fail("invalid idempotency key") }
  }
  value
}

///|
pub fn routes() -> Array[RouteDescriptor] {
  [
    {
      request_method: "GET",
      path_template: "/api/editor/projects",
      handler: "list_projects",
      body_contract: "none",
      response_contract: "mooncast.editor-project-list.v1",
      authority: "observe",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects",
      handler: "create_project",
      body_contract: "mooncast.editor-project.v1",
      response_contract: "mooncast.editor-store-record.v1",
      authority: "workspace-mutation",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id",
      handler: "get_project",
      body_contract: "none",
      response_contract: "mooncast.editor-store-record.v1",
      authority: "observe",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/snapshot",
      handler: "get_snapshot",
      body_contract: "none",
      response_contract: "mooncast.editor-workspace-snapshot.v1",
      authority: "observe",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/production-import",
      handler: "import_production",
      body_contract: "mooncast.editor-production-import-request.v1",
      response_contract: "mooncast.editor-production-import.v1",
      authority: "workspace-mutation",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/commands",
      handler: "dispatch_project_command",
      body_contract: "mooncast.editor-edit-command.v1",
      response_contract: "mooncast.editor-store-record.v1",
      authority: "workspace-mutation",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/review-comments",
      handler: "save_review_comment",
      body_contract: "mooncast.editor-review-comment.v1",
      response_contract: "mooncast.editor-review-comment.v1",
      authority: "workspace-mutation",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/media-intakes",
      handler: "prepare_media_intake",
      body_contract: "mooncast.editor-local-media-intake.v1",
      response_contract: "mooncast.editor-workspace-intake.v1",
      authority: "workspace-mutation",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/media-intakes/:intake_id/content",
      handler: "complete_media_intake",
      body_contract: "bytes+mooncast.editor-local-media-intake.v1",
      response_contract: "mooncast.editor-local-media-binding.v1",
      authority: "workspace-mutation",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/media/:digest",
      handler: "describe_media",
      body_contract: "none",
      response_contract: "mooncast.editor-media-byte-descriptor.v1",
      authority: "observe",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/takes/:take_id/analysis",
      handler: "source_analysis",
      body_contract: "none",
      response_contract: "mooncast.editor-media-analysis.v1",
      authority: "observe",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/takes/:take_id/media",
      handler: "source_media",
      body_contract: "none",
      response_contract: "mooncast.editor-download-descriptor.v1",
      authority: "observe",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/takes/:take_id/thumbnail",
      handler: "source_thumbnail",
      body_contract: "none",
      response_contract: "mooncast.editor-download-descriptor.v1",
      authority: "observe",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/render-plans",
      handler: "freeze_render_plan",
      body_contract: "mooncast.editor-render-plan-request.v1",
      response_contract: "mooncast.editor-render-plan.v1",
      authority: "sandbox-execution",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/previews",
      handler: "queue_preview",
      body_contract: "mooncast.editor-preview.v1",
      response_contract: "mooncast.editor-preview-session.v1",
      authority: "sandbox-execution",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/preview-sessions",
      handler: "queue_preview",
      body_contract: "mooncast.editor-preview.v1",
      response_contract: "mooncast.editor-preview-session.v1",
      authority: "sandbox-execution",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/jobs/:job_id",
      handler: "observe_job",
      body_contract: "none",
      response_contract: "mooncast.editor-job-observation.v1",
      authority: "observe",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/jobs/:job_id/events",
      handler: "stream_job",
      body_contract: "none",
      response_contract: "text/event-stream+mooncast.editor-job-observation.v1",
      authority: "observe",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/jobs/:job_id/retry",
      handler: "retry_job",
      body_contract: "mooncast.editor-job-retry.v1",
      response_contract: "mooncast.editor-job-observation.v1",
      authority: "sandbox-execution",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/jobs/:job_id/cancel",
      handler: "cancel_job",
      body_contract: "mooncast.editor-job-cancel.v1",
      response_contract: "mooncast.editor-job-observation.v1",
      authority: "workspace-mutation",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/jobs/:job_id/media",
      handler: "job_media",
      body_contract: "none",
      response_contract: "mooncast.editor-download-descriptor.v1",
      authority: "observe",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/exports",
      handler: "queue_export",
      body_contract: "mooncast.editor-production-export-request.v1",
      response_contract: "mooncast.editor-export-job.v1",
      authority: "workspace-mutation",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/exports/:job_id",
      handler: "get_export",
      body_contract: "none",
      response_contract: "mooncast.editor-export.v1",
      authority: "observe",
    },
    {
      request_method: "GET",
      path_template: "/api/editor/projects/:project_id/exports/:job_id/download",
      handler: "export_download",
      body_contract: "none",
      response_contract: "mooncast.editor-download-descriptor.v1",
      authority: "observe",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/exports/:job_id/promote-master",
      handler: "promote_master_bundle",
      body_contract: "mooncast.editor-master-promotion.v1",
      response_contract: "mooncast.editor-master-promotion-bundle.v1",
      authority: "external-effect-approval",
    },
    {
      request_method: "POST",
      path_template: "/api/editor/projects/:project_id/exports/:job_id/moonflow-candidate",
      handler: "moonflow_candidate",
      body_contract: "mooncast.editor-moonflow-candidate-request.v1",
      response_contract: "mooncast.moonflow-final-deliverable-candidate.v1",
      authority: "handoff-only",
    },
  ]
}

///|
pub async fn create_project(
  repository : @editor_store.EditorRepository,
  project : @domain.EditorProject,
  content_digest : String,
) -> @editor_store.SnapshotRecord {
  repository.save_session(@domain.EditorSession::new(project), content_digest)
}

///|
pub async fn get_project(
  repository : @editor_store.EditorRepository,
  project_id : String,
) -> @editor_store.SnapshotRecord? {
  repository.load_snapshot(project_id)
}

///|
pub async fn list_projects(
  repository : @editor_store.EditorRepository,
) -> Array[@workspace.ProjectSummary] {
  @workspace.list_projects(repository)
}

///|
pub async fn get_snapshot(
  repository : @editor_store.EditorRepository,
  project_id : String,
) -> @workspace.WorkspaceSnapshot? {
  @workspace.snapshot(repository, project_id)
}

///|
pub async fn save_review_comment(
  repository : @editor_store.EditorRepository,
  comment : @workspace.WorkspaceReviewComment,
) -> @workspace.WorkspaceReviewComment {
  @workspace.save_review_comment(repository, comment)
}

///|
pub async fn source_analysis(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  take_id : String,
) -> @media.MediaAnalysis {
  @workspace.source_analysis(
    repository,
    registry,
    require_id(project_id),
    require_id(take_id),
  )
}

///|
pub async fn source_media(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  take_id : String,
) -> @download.DownloadDescriptor {
  @workspace.source_media(
    repository,
    registry,
    require_id(project_id),
    require_id(take_id),
  )
}

///|
pub async fn source_thumbnail(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  take_id : String,
) -> @download.DownloadDescriptor {
  @workspace.source_thumbnail(
    repository,
    registry,
    require_id(project_id),
    require_id(take_id),
  )
}

///|
pub async fn observe_job(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
) -> @observation.JobObservation? {
  @workspace.poll_job(repository, require_id(project_id), require_id(job_id))
}

///|
pub async fn retry_job(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  now : String,
) -> @observation.JobObservation {
  @observation.observe_job(
    @workspace.retry_job(
      repository,
      require_id(project_id),
      require_id(job_id),
      now,
    ),
  )
}

///|
pub async fn cancel_job(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  now : String,
) -> @observation.JobObservation {
  @observation.observe_job(
    @workspace.cancel_job(
      repository,
      require_id(project_id),
      require_id(job_id),
      now,
    ),
  )
}

///|
pub async fn get_export(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  request_id : String,
  plan : @plan.RenderPlan,
) -> @export.ExportEnvelope {
  @export.completed_export(
    repository,
    require_id(project_id),
    require_id(job_id),
    require_id(request_id),
    plan,
  )
}

///|
pub async fn export_download(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  size_bytes : Int,
) -> @download.DownloadDescriptor {
  @export.export_media(
    repository,
    require_id(project_id),
    require_id(job_id),
    size_bytes,
  )
}

///|
pub async fn dispatch_project_command(
  repository : @editor_store.EditorRepository,
  project_id : String,
  command : @domain.EditCommand,
  content_digest : String,
) -> @editor_store.SnapshotRecord {
  guard repository.load_snapshot(project_id) is Some(record) else {
    fail("editor project not found")
  }
  let session = @domain.replay(
    record.base_snapshot,
    record.command_log.map(entry => entry.command),
  )
  let updated = session.dispatch(command)
  repository.save_session(updated, content_digest)
}

///|
pub async fn complete_media_intake_raw(
  registry : @media.MediaRegistry,
  request : @media.IntakeRequest,
  bytes : Bytes,
  ticks_per_second : Int,
  intake_id : String,
  media_ref_id : String,
  receipt_digest : String,
) -> @media.CompletedIntake {
  @media.complete_intake(
    registry, request, bytes, ticks_per_second, intake_id, media_ref_id, receipt_digest,
  )
}

///|
pub async fn prepare_media_intake(
  repository : @editor_store.EditorRepository,
  project_id : String,
  expected_revision : Int,
  idempotency_key : String,
  role : String,
  file_name : String,
  mime_type : String,
  size_bytes : Int,
  sha256 : String,
  duration_ticks : Int,
  identity : @domain.ProductionIdentity,
  rights : @domain.RightsAttestation,
  source : @domain.MediaSourceAttestation,
  created_by : String,
  created_at : String,
) -> @workspace.WorkspaceIntake {
  @workspace.prepare_local_media_intake(
    repository,
    require_id(project_id),
    require_expected_revision(expected_revision),
    require_idempotency_key(idempotency_key),
    role,
    file_name,
    mime_type,
    size_bytes,
    sha256,
    duration_ticks,
    identity,
    rights,
    source,
    created_by,
    created_at,
  )
}

///|
pub async fn complete_media_intake(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  intake_id : String,
  bytes : Bytes,
  media_ref_id : String,
  receipt_digest : String,
) -> @workspace.WorkspaceIntake {
  @workspace.complete_local_media_intake(
    repository,
    registry,
    require_id(project_id),
    require_id(intake_id),
    bytes,
    require_id(media_ref_id),
    receipt_digest,
  )
}

///|
pub async fn import_production(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project : @integration.ProductionProjectBinding,
  takes : Array[@integration.GeneratedTake],
  intent : @integration.ProductionIntent,
  payloads : Array[@integration.TakePayload],
  actor_id : String,
) -> @integration.ProductionImportResult {
  @workspace.import_production(
    repository, registry, project, takes, intent, payloads, actor_id,
  )
}

///|
pub async fn describe_media(
  registry : @media.MediaRegistry,
  digest : String,
  start : Int,
  length : Int,
) -> @media.MediaByteDescriptor? {
  registry.describe_range(digest, start, length)
}

///|
pub async fn freeze_render_plan(
  repository : @editor_store.EditorRepository,
  project_id : String,
  bindings : Array[@domain.LocalMediaBinding],
  quality : String,
) -> @plan.RenderPlan {
  guard repository.load_snapshot(project_id) is Some(record) else {
    fail("editor project not found")
  }
  let durable = @workspace.local_media_bindings(repository, project_id)
  let merged = bindings.copy()
  for binding in durable {
    if !merged.any(value => value.media_digest == binding.media_digest) {
      merged.push(binding)
    }
  }
  @plan.freeze(record.current_snapshot, merged, quality)
}

///|
pub async fn queue_job(
  repository : @editor_store.EditorRepository,
  job_id : String,
  project_id : String,
  kind : String,
  plan_digest : String,
  request_digest : String,
  created_at : String,
) -> @jobs.EditorJob {
  if @jobs.load(repository, project_id, job_id) is Some(existing) {
    guard existing.kind == kind &&
      existing.plan_digest == plan_digest &&
      existing.request_digest == request_digest else {
      fail("editor job idempotency conflict")
    }
    return existing
  }
  let job = @jobs.EditorJob::queued(
    job_id, project_id, kind, plan_digest, request_digest, created_at,
  )
  @jobs.save(repository, job)
  job
}

///|
pub async fn recover_job(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  now : String,
) -> @jobs.EditorJob? {
  match @jobs.load(repository, project_id, job_id) {
    None => None
    Some(job) => {
      let recovered = @jobs.recover_after_restart(job, now)
      @jobs.save(repository, recovered)
      Some(recovered)
    }
  }
}

///|
pub fn promote_master(
  project_id : String,
  current_project_revision : Int,
  editor_revision : Int,
  request : @integration.MasterPromotionRequest,
  export_receipt : @integration.ExportReceipt,
  master_id : String,
  subtitle_ref : String,
  promoted_at : String,
) -> @integration.MasterPromotionReceipt raise {
  @integration.promote_master(
    project_id, current_project_revision, editor_revision, request, export_receipt,
    master_id, subtitle_ref, promoted_at,
  )
}

///|
pub fn promote_master_bundle(
  project_id : String,
  current_project_revision : Int,
  editor_revision : Int,
  request : @integration.MasterPromotionRequest,
  export_receipt : @integration.ExportReceipt,
  master : @integration.MasterProvenance,
  shot_attempt_digests : Array[@integration.ShotAttemptBinding],
  supersedes_master_digest : String?,
  command_id : String,
  master_version : Int,
  master_digest : String,
  audio_digest : String,
  subtitle_digest : String,
  provenance_digest : String,
) -> @integration.MasterPromotionBundle raise {
  @integration.promote_master_bundle(
    project_id, current_project_revision, editor_revision, request, export_receipt,
    master, shot_attempt_digests, supersedes_master_digest, command_id, master_version,
    master_digest, audio_digest, subtitle_digest, provenance_digest,
  )
}

///|
pub fn moonflow_candidate(
  request : @integration.MoonFlowCandidateRequest,
  bindings : @integration.AuthoritativeDeliveryBindings,
  editor_export : @export.ExportEnvelope,
  editor_output_digest : String,
  artifact_evidence_digest : String,
) -> @integration.MoonFlowHandoffCandidate raise {
  @integration.materialize_handoff_candidate(
    request, bindings, editor_export, editor_output_digest, artifact_evidence_digest,
  )
}
