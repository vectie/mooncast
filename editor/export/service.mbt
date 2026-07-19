///|
pub(all) struct ExportWorkOrder {
  contract : String
  request_id : String
  plan : @plan.RenderPlan
  spec : FrozenExportSpec
  job : @jobs.EditorJob
  invocation : @render_exec.RenderInvocation
  expectation : @render_exec.OutputExpectation
  subtitle_sidecar : @render_exec.SubtitleSidecar
  publication_authority : Bool
} derive(Debug)

///|
/// Freezes or resumes a complete export work order without invoking a provider.
pub async fn prepare_export(
  repository : @editor_store.EditorRepository,
  request_id : String,
  job_id : String,
  plan : @plan.RenderPlan,
  cost_ceiling : Double,
  container : String,
  video_codec : String,
  audio_codec : String,
  subtitle_mode : String,
  ai_label_mode : String,
  retain_sources : Bool,
  maximum_attempts : Int,
  now : String,
  ffmpeg : String,
  media : Array[@render_exec.ResolvedMedia],
  output_path : String,
) -> ExportWorkOrder {
  let duration_seconds = plan.range.duration_ticks.to_double() /
    plan.timebase.ticks_per_second.to_double()
  guard duration_seconds >= 180.0 && duration_seconds <= 480.0 else {
    fail("production export must be a 3-8 minute episode")
  }
  let spec = freeze_spec(
    plan, cost_ceiling, container, video_codec, audio_codec, subtitle_mode, ai_label_mode,
    retain_sources, false,
  )
  let existing : @jobs.EditorJob? = repository.get_job(
    plan.project_id + "-" + job_id,
  )
  let job = create_or_resume(
    existing, job_id, request_id, plan, spec, maximum_attempts, now,
  )
  @jobs.save(repository, job)
  let audio_required = plan.tracks.any(track => {
    track.kind == "audio" ||
    track.clips.any(clip => clip.audio_bus_id is Some(_))
  })
  guard audio_required else {
    fail("production export requires an audio program")
  }
  let sidecar = @render_exec.subtitle_sidecar(plan)
  guard sidecar.cue_count > 0 else {
    fail("production export requires subtitle cues")
  }
  {
    contract: "mooncast.editor-export-work-order.v1",
    request_id,
    plan,
    spec,
    job,
    invocation: @render_exec.compile_with_encoding(
      ffmpeg,
      plan,
      media,
      output_path,
      @render_exec.delivery_encoding(container, video_codec, audio_codec),
    ),
    expectation: {
      project_id: plan.project_id,
      plan_digest: plan.plan_digest,
      duration_seconds,
      width: plan.output.width,
      height: plan.output.height,
      fps: plan.output.fps,
      container,
      video_codec,
      audio_codec,
      audio_required,
      subtitle_required: true,
    },
    subtitle_sidecar: sidecar,
    publication_authority: false,
  }
}

///|
pub async fn observe_export(
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
pub async fn completed_export(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  request_id : String,
  plan : @plan.RenderPlan,
) -> ExportEnvelope {
  let key = "export-" + job_id
  if repository.get_workspace(project_id, key) is Some(raw) {
    let stored : ExportEnvelope = raw
    guard stored.request.request_id == request_id &&
      stored.request.project_revision == plan.project_revision &&
      stored.request.timeline_revision == plan.timeline_revision else {
      fail("immutable export envelope conflict")
    }
    return stored
  }
  guard @jobs.load(repository, project_id, job_id) is Some(job) else {
    fail("editor export not found")
  }
  let result = envelope(job, request_id, plan)
  repository.put_workspace(project_id, key, result)
  result
}

///|
pub async fn export_media(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
  size_bytes : Int,
) -> @download.DownloadDescriptor {
  guard @jobs.load(repository, project_id, job_id) is Some(job) else {
    fail("editor export not found")
  }
  @download.export_download(job, size_bytes)
}
