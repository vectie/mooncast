///|
pub(all) struct JobFailureProjection {
  code : String
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct JobOutputProjection {
  digest : String
  output_ref : String
  download_path : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct JobObservation {
  contract : String
  cursor : String
  project_id : String
  job_id : String
  session_id : String
  kind : String
  state : String
  attempts : Int
  max_attempts : Int
  progress_numerator : Int
  progress_denominator : Int
  plan_digest : String
  request_digest : String
  output : JobOutputProjection?
  error : JobFailureProjection?
  created_at : String
  updated_at : String
  retryable : Bool
  terminal : Bool
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn observe_job(job : @jobs.EditorJob) -> JobObservation {
  let failure = if job.state == "failed" && job.attempts.last() is Some(attempt) {
    Some({ code: attempt.error_code, message: attempt.error_message })
  } else {
    None
  }
  let output = if job.state == "succeeded" {
    Some({
      digest: job.output_digest,
      output_ref: job.output_ref,
      download_path: "/api/editor/projects/" +
      job.project_id +
      "/jobs/" +
      job.job_id +
      "/media",
    })
  } else {
    None
  }
  {
    contract: "mooncast.editor-job-observation.v1",
    cursor: job.updated_at + ":" + job.retry_count.to_string() + ":" + job.state,
    project_id: job.project_id,
    job_id: job.job_id,
    session_id: job.job_id,
    kind: job.kind,
    state: job.state,
    attempts: job.attempts.length(),
    max_attempts: job.maximum_retries + 1,
    progress_numerator: job.progress_numerator,
    progress_denominator: job.progress_denominator,
    plan_digest: job.plan_digest,
    request_digest: job.request_digest,
    output,
    error: failure,
    created_at: job.created_at,
    updated_at: job.updated_at,
    retryable: job.state == "failed" && job.retry_count < job.maximum_retries,
    terminal: job.state == "succeeded" ||
    job.state == "failed" ||
    job.state == "cancelled",
    publication_authority: false,
    provider_authority: false,
  }
}

///|
pub fn job_stream_descriptor() -> @host_ports.StreamDescriptor {
  {
    transport: "sse-or-poll",
    path_template: "/api/editor/projects/:project_id/jobs/:job_id/events",
    event_contract: "mooncast.editor-job-observation.v1",
    heartbeat_seconds: 15,
    replay_cursor_parameter: "after",
  }
}

///|
pub fn sse_event(value : JobObservation) -> String {
  "id: " +
  value.cursor +
  "\nevent: editor-job\ndata: " +
  value.to_json().stringify() +
  "\n\n"
}
