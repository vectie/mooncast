///|
fn append_attempt(
  job : ProviderExecutionJob,
  attempt : ProviderAttemptPhase?,
) -> Array[ProviderAttemptPhase] {
  let history = job.attempt_history.copy()
  match attempt {
    Some(value) => history.push(value)
    None => ()
  }
  history
}

///|
pub fn apply_provider_event(
  job : ProviderExecutionJob,
  event : ProviderExecutionEvent,
) -> ProviderExecutionJob {
  let updated = match event.kind {
    "execution-started" =>
      {
        ..job,
        state: "running",
        attempt_count: job.attempt_count + 1,
        attempt_history: append_attempt(job, event.attempt),
        last_error_code: None,
        last_error_message: None,
      }
    "execution-completed" =>
      {
        ..job,
        state: "completed",
        attempt_history: append_attempt(job, event.attempt),
        artifacts: event.artifacts,
        spent_cny: event.cost_cny.unwrap_or(job.spent_cny),
        project_ingest_digest: event.project_ingest_digest,
      }
    "execution-retryable-failure" =>
      {
        ..job,
        state: "retryable_failure",
        attempt_history: append_attempt(job, event.attempt),
        last_error_code: event.attempt.map(value => {
          value.error_code.unwrap_or("provider_attempt_failed")
        }),
        last_error_message: event.attempt.map(value => {
          value.error_message.unwrap_or("provider attempt failed")
        }),
      }
    "execution-failed" =>
      {
        ..job,
        state: "failed",
        attempt_history: append_attempt(job, event.attempt),
        last_error_code: event.attempt.map(value => {
          value.error_code.unwrap_or("provider_attempt_failed")
        }),
        last_error_message: event.attempt.map(value => {
          value.error_message.unwrap_or("provider attempt failed")
        }),
      }
    "execution-cancel-requested" => { ..job, state: "cancel_requested" }
    "execution-cancelled" =>
      {
        ..job,
        state: "cancelled",
        attempt_history: append_attempt(job, event.attempt),
      }
    "execution-ingested" =>
      { ..job, project_ingest_digest: event.project_ingest_digest }
    _ => job
  }
  { ..updated, revision: updated.revision + 1 }
}

///|
pub fn replay_provider_job(
  initial : ProviderExecutionJob,
  events : Array[ProviderExecutionEvent],
) -> ProviderExecutionJob {
  let mut job = initial
  for event in events {
    job = apply_provider_event(job, event)
  }
  job
}

///|
fn provider_failure(
  command : ProviderExecutionCommand,
  code : String,
) -> ProviderExecutionResult {
  {
    contract: "mooncast.provider-execution-result.v1",
    command_id: command.command_id,
    ok: false,
    error_code: Some(code),
    job: command.job,
    events: [],
    external_effect_performed: false,
    publication_authority: false,
  }
}

///|
pub fn reduce_provider_command(
  command : ProviderExecutionCommand,
) -> ProviderExecutionResult {
  if command.contract != "mooncast.provider-execution-command.v1" {
    return provider_failure(command, "contract_unsupported")
  }
  if command.expected_revision != command.job.revision {
    return provider_failure(command, "provider_job_revision_conflict")
  }
  if command.job.publication_authority ||
    command.job.authority.publication_authority {
    return provider_failure(command, "publication_authority_forbidden")
  }
  let event_kind = match command.action {
    "start" if command.job.state == "authorized" ||
      command.job.state == "retryable_failure" ||
      command.job.state == "timed_out" =>
      if command.job.attempt_count < command.job.max_attempts {
        Some("execution-started")
      } else {
        None
      }
    "complete" if command.job.state == "running" &&
      command.artifacts.length() > 0 &&
      command.cost_cny.unwrap_or(-1.0) >= 0.0 &&
      command.cost_cny.unwrap_or(-1.0) <= command.job.plan.cost_ceiling_cny =>
      Some("execution-completed")
    "retryable_failure" if command.job.state == "running" =>
      Some("execution-retryable-failure")
    "fail" if command.job.state == "running" => Some("execution-failed")
    "request_cancel" if command.job.state == "running" =>
      Some("execution-cancel-requested")
    "cancel" if command.job.state == "cancel_requested" ||
      command.job.state == "authorized" => Some("execution-cancelled")
    "ingest" if command.job.state == "completed" &&
      command.project_ingest_digest is Some(_) => Some("execution-ingested")
    _ => None
  }
  match event_kind {
    None => provider_failure(command, "provider_transition_invalid")
    Some(kind) => {
      let event : ProviderExecutionEvent = {
        contract: "mooncast.provider-execution-event.v1",
        event_id: command.command_id,
        kind,
        recorded_at: command.recorded_at,
        evidence_digest: command.evidence_digest,
        attempt: command.attempt,
        artifacts: command.artifacts,
        cost_cny: command.cost_cny,
        project_ingest_digest: command.project_ingest_digest,
      }
      let job = apply_provider_event(command.job, event)
      {
        contract: "mooncast.provider-execution-result.v1",
        command_id: command.command_id,
        ok: true,
        error_code: None,
        job,
        events: [event],
        external_effect_performed: false,
        publication_authority: false,
      }
    }
  }
}
