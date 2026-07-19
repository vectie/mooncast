///|
pub(all) struct ProjectSummary {
  project_id : String
  revision : Int
  timeline_id : String
  timeline_revision : Int
  content_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceSnapshot {
  contract : String
  snapshot : @domain.EditorProject
  command_log : Array[@domain.CommandLogRecord]
  revision : Int
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceReviewComment {
  contract : String
  project_id : String
  comment_id : String
  kind : String
  start_tick : Int
  end_tick : Int
  text : String
  revision_round : Int
  expected_editor_revision : Int
  created_by : String
  created_at : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceIntake {
  contract : String
  prepared : @media.PreparedIntake
  completed : @media.CompletedIntake?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SourceTakeProjection {
  contract : String
  take : @integration.GeneratedTake
  registry_digest : String
  source : @media.MediaAvailability
  proxy : @media.MediaObjectRecord?
  media_path : String?
  analysis_path : String
  thumbnail_path : String?
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn timeline_duration(project : @domain.EditorProject) -> Int {
  project.timeline.tracks.fold(init=0, (end_tick, track) => {
    track.clips.fold(init=end_tick, (value, clip) => {
      Int::max(value, clip.start_tick + clip.duration_ticks)
    })
  })
}

///|
pub async fn list_projects(
  repository : @editor_store.EditorRepository,
) -> Array[ProjectSummary] {
  repository
  .list_snapshots()
  .map(record => {
    project_id: record.project_id,
    revision: record.current_snapshot.revision,
    timeline_id: record.current_snapshot.timeline.timeline_id,
    timeline_revision: record.current_snapshot.timeline.revision,
    content_digest: record.content_digest,
  })
}

///|
pub async fn open_project(
  repository : @editor_store.EditorRepository,
  project_id : String,
) -> @editor_store.SnapshotRecord? {
  repository.load_snapshot(project_id)
}

///|
pub async fn snapshot(
  repository : @editor_store.EditorRepository,
  project_id : String,
) -> WorkspaceSnapshot? {
  match repository.load_snapshot(project_id) {
    None => None
    Some(record) =>
      Some({
        contract: "mooncast.editor-workspace-snapshot.v1",
        snapshot: record.current_snapshot,
        command_log: record.command_log,
        revision: record.current_snapshot.revision,
        publication_authority: false,
        provider_authority: false,
      })
  }
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
  if repository.get_workspace(project.project_id, "production-import")
    is Some(raw) {
    let previous : @integration.ProductionImportResult = raw
    let current = repository.load_snapshot(project.project_id)
    guard current is Some(record) &&
      record.current_snapshot.revision == intent.expected_editor_revision else {
      fail("stale editor revision")
    }
    guard previous.lineage == takes &&
      previous.annotations == intent.annotations &&
      previous.review_comments == intent.review_comments &&
      previous.delivery_intents == intent.delivery_intents &&
      previous.track_roles == intent.track_role_map else {
      fail("production import changed after workspace creation")
    }
    return {
      ..previous,
      snapshot: record.current_snapshot,
      command_log: record.command_log,
    }
  }
  let existing = match repository.load_snapshot(project.project_id) {
    Some(value) => Some(value.current_snapshot)
    None => None
  }
  let result = @integration.import_production_materialized(
    project, takes, intent, payloads, registry, existing, actor_id,
  )
  let session = @domain.replay(
    result.base_snapshot,
    result.command_log.map(record => record.command),
  )
  ignore(repository.save_session(session, result.import_digest))
  repository.put_workspace(project.project_id, "production-import", result)
  result
}

///|
fn take_record(
  imported : @integration.ProductionImportResult,
  take_id : String,
) -> (@integration.GeneratedTake, @media.MediaObjectRecord) raise {
  for take in imported.lineage {
    if take.take_id == take_id {
      for record in imported.media_records {
        if record.digest == take.content_sha256 {
          return (take, record)
        }
      }
      fail("source take registry binding is missing")
    }
  }
  fail("source take not found")
}

///|
pub async fn source_take(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  take_id : String,
) -> SourceTakeProjection {
  guard repository.get_workspace(project_id, "production-import") is Some(raw) else {
    fail("production import metadata not found")
  }
  let imported : @integration.ProductionImportResult = raw
  let (take, record) = take_record(imported, take_id)
  let availability = registry.availability(record.digest)
  let proxies = registry.list_proxies(record.digest)
  let proxy = proxies
    .filter(item => {
      item.provenance_refs.contains("mooncast-review-source-proxy@1.0.0")
    })
    .get(0)
  let selected = match proxy {
    Some(value) => Some(value.digest)
    None =>
      if take.mime_type.has_prefix("image/") {
        Some(record.digest)
      } else {
        None
      }
  }
  let analysis = registry.analysis(record.digest)
  {
    contract: "mooncast.editor-source-take.v1",
    take,
    registry_digest: record.digest,
    source: availability,
    proxy,
    media_path: selected.map(digest => "/api/editor/media/" + digest),
    analysis_path: "/api/editor/projects/" +
    project_id +
    "/takes/" +
    take_id +
    "/analysis",
    thumbnail_path: if analysis is Some(value) &&
      value.thumbnail.state == "available" {
      Some(
        "/api/editor/projects/" +
        project_id +
        "/takes/" +
        take_id +
        "/thumbnail",
      )
    } else {
      None
    },
    publication_authority: false,
    provider_authority: false,
  }
}

///|
pub async fn source_analysis(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  take_id : String,
) -> @media.MediaAnalysis {
  let source = source_take(repository, registry, project_id, take_id)
  match registry.analysis(source.registry_digest) {
    Some(value) => value
    None =>
      {
        contract: "mooncast.editor-media-analysis.v1",
        analysis_version: "pending",
        analysis_id: "analysis:" + source.registry_digest,
        source_digest: source.registry_digest,
        source_size: source.source.size.unwrap_or(0),
        source_mime: source.source.mime.unwrap_or("application/octet-stream"),
        state: if source.source.state == "available" {
          "pending"
        } else {
          source.source.state
        },
        duration_seconds: None,
        video: { state: "unavailable", width: None, height: None, codec: None },
        audio: {
          state: "unavailable",
          channels: None,
          sample_rate: None,
          codec: None,
        },
        thumbnail: {
          state: "unavailable",
          digest: None,
          mime: None,
          width: None,
          height: None,
        },
        waveform: {
          state: "unavailable",
          peak_count: 0,
          peaks: [],
          digest: None,
        },
        analysis_digest: None,
        source_url: source.media_path,
        thumbnail_url: None,
        publication_authority: false,
        provider_authority: false,
      }
  }
}

///|
pub async fn source_media(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  take_id : String,
) -> @download.DownloadDescriptor {
  let source = source_take(repository, registry, project_id, take_id)
  let selected = match source.proxy {
    Some(value) => value
    None => {
      guard source.take.mime_type.has_prefix("image/") &&
        registry.get(source.registry_digest) is Some(value) else {
        fail("interactive review proxy is not ready")
      }
      value
    }
  }
  guard registry.describe_range(selected.digest, 0, selected.size)
    is Some(descriptor) else {
    fail("source media is unavailable")
  }
  @download.media_download(descriptor, source.take.take_id)
}

///|
pub async fn source_thumbnail(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  take_id : String,
) -> @download.DownloadDescriptor {
  let source = source_take(repository, registry, project_id, take_id)
  guard registry.analysis_thumbnail(source.registry_digest) is Some(descriptor) else {
    fail("source thumbnail is unavailable")
  }
  @download.media_download(descriptor, source.take.take_id + "-thumbnail")
}

///|
pub async fn save_review_comment(
  repository : @editor_store.EditorRepository,
  comment : WorkspaceReviewComment,
) -> WorkspaceReviewComment {
  guard repository.load_snapshot(comment.project_id) is Some(record) else {
    fail("editor project not found")
  }
  guard record.current_snapshot.revision == comment.expected_editor_revision else {
    fail("editor revision conflict")
  }
  guard comment.contract == "mooncast.editor-review-comment.v1" &&
    !comment.comment_id.is_blank() &&
    comment.comment_id.length() <= 128 else {
    fail("invalid review comment")
  }
  guard comment.kind == "continuity" ||
    comment.kind == "qc" ||
    comment.kind == "review" else {
    fail("invalid review comment kind")
  }
  guard comment.start_tick >= 0 &&
    comment.end_tick > comment.start_tick &&
    comment.end_tick <= timeline_duration(record.current_snapshot) else {
    fail("review comment is outside timeline")
  }
  guard !comment.text.is_blank() &&
    comment.text.length() <= 4096 &&
    comment.revision_round >= 0 &&
    comment.revision_round <= 2 else {
    fail("invalid review comment content")
  }
  guard !comment.created_by.is_blank() &&
    !comment.created_at.is_blank() &&
    !comment.publication_authority else {
    fail("review comment authority is invalid")
  }
  repository.put_review(comment.project_id, comment.comment_id, comment)
  comment
}

///|
pub async fn list_review_comments(
  repository : @editor_store.EditorRepository,
  project_id : String,
) -> Array[WorkspaceReviewComment] {
  repository.list_reviews(project_id)
}

///|
pub async fn prepare_local_media_intake(
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
) -> WorkspaceIntake {
  guard repository.load_snapshot(project_id) is Some(record) else {
    fail("editor project not found")
  }
  let prepared = @media.prepare_intake(
    record.current_snapshot,
    expected_revision,
    idempotency_key,
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
  match repository.get_intake(project_id, prepared.intake_id) {
    Some(existing) => {
      let value : WorkspaceIntake = existing
      guard value.prepared.request.request_digest ==
        prepared.request.request_digest else {
        fail("intake idempotency conflict")
      }
      value
    }
    None => {
      let value : WorkspaceIntake = {
        contract: "mooncast.editor-workspace-intake.v1",
        prepared,
        completed: None,
      }
      repository.put_intake(project_id, prepared.intake_id, value)
      value
    }
  }
}

///|
pub async fn complete_local_media_intake(
  repository : @editor_store.EditorRepository,
  registry : @media.MediaRegistry,
  project_id : String,
  intake_id : String,
  bytes : Bytes,
  media_ref_id : String,
  receipt_digest : String,
) -> WorkspaceIntake {
  guard repository.get_intake(project_id, intake_id) is Some(raw) else {
    fail("local media intake not found")
  }
  let existing : WorkspaceIntake = raw
  if existing.completed is Some(_) {
    return existing
  }
  guard repository.load_snapshot(project_id) is Some(record) else {
    fail("editor project not found")
  }
  guard record.current_snapshot.revision ==
    existing.prepared.request.expected_editor_revision else {
    fail("timeline changed after intake preparation")
  }
  let raw_completed = @media.complete_intake(
    registry,
    existing.prepared.request,
    bytes,
    record.current_snapshot.timeline.timebase.ticks_per_second,
    intake_id,
    media_ref_id,
    receipt_digest,
  )
  guard repository.get_workspace(project_id, "production-import")
    is Some(import_raw) else {
    fail("production track roles are unavailable")
  }
  let imported : @integration.ProductionImportResult = import_raw
  let target_role = match existing.prepared.request.role {
    "image" => "effect"
    "logo" => "AI-label"
    value => value
  }
  guard imported.track_roles.filter(value => value.role == target_role).get(0)
    is Some(track_role) else {
    fail("local media target track is unavailable")
  }
  let receipt = { ..raw_completed.receipt, track_id: track_role.track_id }
  let actual_receipt_digest = "sha256:" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(receipt.to_json().stringify())),
    )
  guard receipt_digest == actual_receipt_digest else {
    fail("local media receipt digest mismatch")
  }
  let binding = {
    ..raw_completed.binding,
    intake_receipt: receipt,
    intake_receipt_digest: actual_receipt_digest,
  }
  let completed = { ..raw_completed, receipt, binding }
  let media_refs = record.base_snapshot.media_refs.copy()
  let declarations = media_refs.filter(value => {
    value.media_ref_id == completed.media_ref.media_ref_id
  })
  guard declarations.is_empty() ||
    (declarations.length() == 1 && declarations[0] == completed.media_ref) else {
    fail("local media declaration conflicts")
  }
  if declarations.is_empty() {
    media_refs.push(completed.media_ref)
  }
  let base = { ..record.base_snapshot, media_refs, }
  let replayed = @domain.replay(
    base,
    record.command_log.map(entry => entry.command),
  )
  ignore(repository.save_session(replayed, receipt_digest))
  let value = { ..existing, completed: Some(completed) }
  repository.put_intake(project_id, intake_id, value)
  value
}

///|
pub async fn local_media_bindings(
  repository : @editor_store.EditorRepository,
  project_id : String,
) -> Array[@domain.LocalMediaBinding] {
  let intakes : Array[WorkspaceIntake] = repository.list_intakes(project_id)
  intakes.filter_map(value => value.completed.map(done => done.binding))
}

///|
pub async fn start_preview(
  repository : @editor_store.EditorRepository,
  plan : @plan.RenderPlan,
  request : @jobs.PreviewRequest,
  job_id : String,
  request_digest : String,
  provenance_digest : String,
  snapshot_digest : String,
  command_prefix_digest : String,
  created_at : String,
  anchor_digest : String,
) -> @jobs.EditorJob {
  guard plan.ready &&
    request.project_id == plan.project_id &&
    request.project_revision == plan.project_revision &&
    request.timeline_id == plan.timeline_id &&
    request.timeline_revision == plan.timeline_revision &&
    request.plan_digest == plan.plan_digest else {
    fail("preview request does not match frozen render plan")
  }
  let authority = @jobs.preview_authority(
    request, job_id, request_digest, provenance_digest, snapshot_digest, command_prefix_digest,
    created_at, anchor_digest,
  )
  repository.put_authority(plan.project_id, job_id, authority)
  let existing : @jobs.EditorJob? = repository.get_job(
    plan.project_id + "-" + job_id,
  )
  match existing {
    Some(job) => {
      guard job.plan_digest == plan.plan_digest &&
        job.request_digest == request_digest else {
        fail("preview idempotency conflict")
      }
      job
    }
    None => {
      let job = @jobs.EditorJob::queued(
        job_id,
        plan.project_id,
        "preview",
        plan.plan_digest,
        request_digest,
        created_at,
      )
      @jobs.save(repository, job)
      job
    }
  }
}

///|
pub async fn poll_job(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
) -> @observation.JobObservation? {
  match @jobs.load(repository, project_id, job_id) {
    Some(job) => Some(@observation.observe_job(job))
    None => None
  }
}

///|
pub async fn retry_job(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  now : String,
) -> @jobs.EditorJob {
  guard @jobs.load(repository, project_id, job_id) is Some(job) else {
    fail("editor job not found")
  }
  let queued = job.retry(now)
  @jobs.save(repository, queued)
  queued
}

///|
pub async fn cancel_job(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  now : String,
) -> @jobs.EditorJob {
  guard @jobs.load(repository, project_id, job_id) is Some(job) else {
    fail("editor job not found")
  }
  let cancelled = job.cancel(now)
  @jobs.save(repository, cancelled)
  cancelled
}

///|
/// Recovers every interrupted worker attempt after a host restart.
pub async fn recover_jobs(
  repository : @editor_store.EditorRepository,
  project_id : String,
  now : String,
) -> Array[@jobs.EditorJob] {
  let jobs : Array[@jobs.EditorJob] = repository.list_jobs(project_id)
  let recovered : Array[@jobs.EditorJob] = []
  for job in jobs {
    let value = @jobs.recover_after_restart(job, now)
    if value != job {
      @jobs.save(repository, value)
    }
    recovered.push(value)
  }
  recovered
}
