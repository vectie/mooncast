///|
pub(all) struct FrozenExportSpec {
  contract : String
  width : Int
  height : Int
  fps : @domain.FrameRate
  container : String
  video_codec : String
  audio_codec : String
  subtitle_mode : String
  ai_label_mode : String
  retain_sources : Bool
  project_id : String
  timeline_id : String
  project_revision : Int
  timeline_revision : Int
  cost_ceiling : String
  estimated_cost : String
  estimate_method : String
  test_only : Bool
  publication_authority : Bool
  spec_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExportRequestProjection {
  request_id : String
  project_id : String
  timeline_id : String
  project_revision : Int
  timeline_revision : Int
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExportJobProjection {
  job_id : String
  request_id : String
  state : String
  project_id : String
  timeline_id : String
  project_revision : Int
  timeline_revision : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExportResultProjection {
  job_id : String
  state : String
  output_refs : Array[String]
  publication_authority : Bool
  project_id : String
  timeline_id : String
  project_revision : Int
  timeline_revision : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExportEnvelope {
  contract : String
  request : ExportRequestProjection
  job : ExportJobProjection
  result : ExportResultProjection
} derive(Debug, Eq, ToJson, FromJson)

///|
fn digest_json(value : Json) -> String {
  "sha256:" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value.stringify())))
}

///|
pub fn freeze_spec(
  render_plan : @plan.RenderPlan,
  cost_ceiling : Double,
  container : String,
  video_codec : String,
  audio_codec : String,
  subtitle_mode : String,
  ai_label_mode : String,
  retain_sources : Bool,
  test_only : Bool,
) -> FrozenExportSpec raise {
  let supported = (
      container == "mp4" && video_codec == "h264" && audio_codec == "aac"
    ) ||
    (container == "webm" && video_codec == "vp9" && audio_codec == "opus") ||
    (
      container == "mkv" &&
      (
        (video_codec == "h264" && audio_codec == "aac") ||
        (video_codec == "vp9" && audio_codec == "opus")
      )
    )
  guard supported else { fail("unsupported export codec combination") }
  guard cost_ceiling >= 0.0 else {
    fail("export cost ceiling cannot be negative")
  }
  let seconds = render_plan.range.duration_ticks.to_double() /
    render_plan.timebase.ticks_per_second.to_double()
  let fps = render_plan.output.fps.numerator.to_double() /
    render_plan.output.fps.denominator.to_double()
  let estimate = seconds *
    fps *
    render_plan.output.width.to_double() *
    render_plan.output.height.to_double() /
    1000000000.0
  guard estimate <= cost_ceiling else {
    fail("estimated export cost exceeds ceiling")
  }
  let provisional : FrozenExportSpec = {
    contract: "mooncast.editor-export.v1",
    width: render_plan.output.width,
    height: render_plan.output.height,
    fps: render_plan.output.fps,
    container,
    video_codec,
    audio_codec,
    subtitle_mode,
    ai_label_mode,
    retain_sources,
    project_id: render_plan.project_id,
    timeline_id: render_plan.timeline_id,
    project_revision: render_plan.project_revision,
    timeline_revision: render_plan.timeline_revision,
    cost_ceiling: cost_ceiling.to_string(),
    estimated_cost: estimate.to_string(),
    estimate_method: "decimal-mpix-frames-v1",
    test_only,
    publication_authority: false,
    spec_digest: "",
  }
  { ..provisional, spec_digest: digest_json(provisional.to_json()) }
}

///|
pub fn create_or_resume(
  existing : @jobs.EditorJob?,
  job_id : String,
  request_id : String,
  render_plan : @plan.RenderPlan,
  spec : FrozenExportSpec,
  maximum_attempts : Int,
  now : String,
) -> @jobs.EditorJob raise {
  guard request_id != "" else { fail("export request identity is required") }
  guard render_plan.ready && render_plan.plan_digest != "" else {
    fail("ready frozen plan is required")
  }
  guard spec.project_revision == render_plan.project_revision &&
    spec.timeline_revision == render_plan.timeline_revision else {
    fail("export spec revision mismatch")
  }
  match existing {
    Some(job) => {
      guard job.job_id == job_id &&
        job.plan_digest == render_plan.plan_digest &&
        job.request_digest == spec.spec_digest else {
        fail("export job identity conflict")
      }
      job
    }
    None => {
      let job = @jobs.EditorJob::queued(
        job_id,
        render_plan.project_id,
        "export",
        render_plan.plan_digest,
        spec.spec_digest,
        now,
      )
      { ..job, maximum_retries: Int::max(0, maximum_attempts - 1) }
    }
  }
}

///|
pub fn envelope(
  job : @jobs.EditorJob,
  request_id : String,
  render_plan : @plan.RenderPlan,
) -> ExportEnvelope raise {
  guard job.state == "succeeded" && job.output_digest.has_prefix("sha256:") else {
    fail("successful export is required")
  }
  let request = {
    request_id,
    project_id: render_plan.project_id,
    timeline_id: render_plan.timeline_id,
    project_revision: render_plan.project_revision,
    timeline_revision: render_plan.timeline_revision,
    publication_authority: false,
  }
  let projected_job = {
    job_id: job.job_id,
    request_id,
    state: "succeeded",
    project_id: render_plan.project_id,
    timeline_id: render_plan.timeline_id,
    project_revision: render_plan.project_revision,
    timeline_revision: render_plan.timeline_revision,
  }
  let result = {
    job_id: job.job_id,
    state: "succeeded",
    output_refs: [
      "editor-export:" + job.job_id + ":video",
      "editor-export:" + job.job_id + ":subtitle",
    ],
    publication_authority: false,
    project_id: render_plan.project_id,
    timeline_id: render_plan.timeline_id,
    project_revision: render_plan.project_revision,
    timeline_revision: render_plan.timeline_revision,
  }
  { contract: "mooncast.editor-export.v1", request, job: projected_job, result }
}
