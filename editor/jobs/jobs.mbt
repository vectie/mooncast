///|
pub(all) struct JobAttempt {
  attempt : Int
  started_at : String
  finished_at : String
  state : String
  error_code : String
  error_message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewRange {
  start_tick : Int
  duration_ticks : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReviewPreviewSpec {
  contract : String
  requested_range : PreviewRange
  render_duration_seconds : Double
  width : Int
  height : Int
  fps : Int
  video_codec : String
  audio_codec : String
  profile : String
  autoplay : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorJob {
  contract : String
  job_id : String
  project_id : String
  kind : String
  state : String
  plan_digest : String
  request_digest : String
  output_digest : String
  output_ref : String
  progress_numerator : Int
  progress_denominator : Int
  retry_count : Int
  maximum_retries : Int
  attempts : Array[JobAttempt]
  created_at : String
  updated_at : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn EditorJob::queued(
  job_id : String,
  project_id : String,
  kind : String,
  plan_digest : String,
  request_digest : String,
  created_at : String,
) -> EditorJob {
  {
    contract: if kind == "export" {
      "mooncast.editor-export-job.v1"
    } else {
      "mooncast.editor-preview-session.v1"
    },
    job_id,
    project_id,
    kind,
    state: "queued",
    plan_digest,
    request_digest,
    output_digest: "",
    output_ref: "",
    progress_numerator: 0,
    progress_denominator: 1,
    retry_count: 0,
    maximum_retries: 2,
    attempts: [],
    created_at,
    updated_at: created_at,
    publication_authority: false,
  }
}

///|
pub fn EditorJob::start(self : EditorJob, now : String) -> EditorJob raise {
  guard self.state == "queued" else {
    fail("job cannot start from current state")
  }
  let attempts = self.attempts.copy()
  attempts.push({
    attempt: attempts.length() + 1,
    started_at: now,
    finished_at: "",
    state: "running",
    error_code: "",
    error_message: "",
  })
  { ..self, state: "running", attempts, updated_at: now }
}

///|
pub fn EditorJob::succeed(
  self : EditorJob,
  output_digest : String,
  output_ref : String,
  now : String,
) -> EditorJob raise {
  guard self.state == "running" else { fail("only a running job can succeed") }
  let attempts = self.attempts.copy()
  let index = attempts.length() - 1
  attempts[index] = { ..attempts[index], state: "succeeded", finished_at: now }
  {
    ..self,
    state: "succeeded",
    output_digest,
    output_ref,
    progress_numerator: self.progress_denominator,
    attempts,
    updated_at: now,
  }
}

///|
pub fn EditorJob::fail(
  self : EditorJob,
  code : String,
  message : String,
  now : String,
) -> EditorJob raise {
  guard self.state == "running" else { fail("only a running job can fail") }
  let attempts = self.attempts.copy()
  let index = attempts.length() - 1
  attempts[index] = {
    ..attempts[index],
    state: "failed",
    finished_at: now,
    error_code: code,
    error_message: message,
  }
  { ..self, state: "failed", attempts, updated_at: now }
}

///|
pub fn EditorJob::retry(self : EditorJob, now : String) -> EditorJob raise {
  guard self.state == "failed" && self.retry_count < self.maximum_retries else {
    fail("job is not retryable")
  }
  {
    ..self,
    state: "queued",
    retry_count: self.retry_count + 1,
    output_digest: "",
    output_ref: "",
    progress_numerator: 0,
    updated_at: now,
  }
}

///|
pub fn EditorJob::cancel(self : EditorJob, now : String) -> EditorJob raise {
  guard self.state == "queued" || self.state == "running" else {
    fail("terminal job cannot be cancelled")
  }
  { ..self, state: "cancelled", updated_at: now }
}

///|
pub fn EditorJob::progress(
  self : EditorJob,
  numerator : Int,
  denominator : Int,
  now : String,
) -> EditorJob raise {
  guard self.state == "running" &&
    denominator > 0 &&
    numerator >= 0 &&
    numerator <= denominator else {
    fail("invalid job progress")
  }
  {
    ..self,
    progress_numerator: numerator,
    progress_denominator: denominator,
    updated_at: now,
  }
}

///|
pub fn recover_after_restart(job : EditorJob, now : String) -> EditorJob {
  if job.state != "running" {
    return job
  }
  let attempts = job.attempts.copy()
  if !attempts.is_empty() {
    let index = attempts.length() - 1
    attempts[index] = {
      ..attempts[index],
      state: "interrupted",
      finished_at: now,
      error_code: "process-restarted",
      error_message: "worker restarted before a terminal receipt",
    }
  }
  if job.retry_count < job.maximum_retries {
    {
      ..job,
      state: "queued",
      retry_count: job.retry_count + 1,
      progress_numerator: 0,
      attempts,
      updated_at: now,
    }
  } else {
    { ..job, state: "failed", attempts, updated_at: now }
  }
}

///|
pub async fn save(
  repository : @editor_store.EditorRepository,
  job : EditorJob,
) -> Unit {
  repository.put_job(job.project_id + "-" + job.job_id, job)
}

///|
pub async fn load(
  repository : @editor_store.EditorRepository,
  project_id : String,
  job_id : String,
) -> EditorJob? {
  repository.get_job(project_id + "-" + job_id)
}
