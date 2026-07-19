///|
fn attempt_phase(
  attempt_id : String,
  phase : String,
  state : String,
  timestamp : String,
  error_code? : String,
  error_message? : String,
) -> @execution_domain.ProviderAttemptPhase {
  {
    attempt_id,
    phase,
    state,
    start_timestamp: if phase == "started" {
      Some(timestamp)
    } else {
      None
    },
    end_timestamp: if phase == "completed" {
      Some(timestamp)
    } else {
      None
    },
    error_code,
    error_message,
    phase_digest: sha256(
      @utf8.encode(attempt_id + ":" + phase + ":" + state + ":" + timestamp),
    ),
    usage_cost_receipt_digest: None,
    attachment_receipt_digest: None,
  }
}

///|
fn execution_command(
  record : ProviderJobRecord,
  action : String,
  attempt? : @execution_domain.ProviderAttemptPhase,
  artifacts? : Array[@execution_domain.ProviderResultArtifact] = [],
  cost_cny? : Double,
  project_ingest_digest? : String,
) -> @execution_domain.ProviderExecutionCommand raise {
  {
    contract: "mooncast.provider-execution-command.v1",
    command_id: @runtime.new_id(prefix="provider-command"),
    action,
    actor_id: record.job.authority.actor_id,
    recorded_at: now(),
    evidence_digest: record.job.binding_digest,
    expected_revision: record.job.revision,
    job: record.job,
    attempt,
    artifacts,
    cost_cny,
    project_ingest_digest,
  }
}

///|
fn headers_for(
  config : ProviderAdapterConfig,
) -> Map[String, String] raise ProviderApplicationError {
  let headers : Map[String, String] = {}
  for name, reference in config.secret_refs {
    let env = match env_name(reference) {
      Some(value) => value
      None => raise HostNotReady("invalid host secret reference")
    }
    let secret_ref = match @runtime.SecretRef::from_env(env) {
      Some(value) => value
      None => raise HostNotReady("invalid host secret environment name")
    }
    let value = match secret_ref.resolve() {
      Some(value) if value != "" => value
      _ => raise HostNotReady("provider secret is unavailable")
    }
    headers[name] = value
  }
  headers
}

///|
async fn ProviderExecutionService::materialize_artifacts(
  self : ProviderExecutionService,
  record : ProviderJobRecord,
  result : ProviderWireResult,
  attempt_id : String,
) -> Array[@execution_domain.ProviderResultArtifact] {
  if result.contract != "mooncast.provider-json-result.v1" ||
    result.artifacts.length() == 0 {
    raise ProviderResponseInvalid(
      "provider result contract or artifacts are invalid",
    )
  }
  let provider_receipt_digest = json_digest(result.provider_receipt)
  let normalized : Array[@execution_domain.ProviderResultArtifact] = []
  for artifact in result.artifacts {
    if artifact.modality != record.http_plan.capability {
      raise ProviderResponseInvalid(
        "artifact modality differs from authorized capability",
      )
    }
    let (bytes, media_type) = if artifact.modality == "text" ||
      artifact.modality == "translation" {
      match artifact.text {
        Some(value) if value != "" =>
          (@utf8.encode(value), "text/plain; charset=utf-8")
        _ => raise ProviderResponseInvalid("text artifact is empty")
      }
    } else {
      let encoded = match artifact.content_base64 {
        Some(value) if value != "" => value
        _ => raise ProviderResponseInvalid("media artifact bytes are missing")
      }
      let decoded = @base64.decode(encoded) catch {
        _ => raise ProviderResponseInvalid("media artifact base64 is invalid")
      }
      let mime = match artifact.mime_type {
        Some(value) if value != "" => value
        _ =>
          raise ProviderResponseInvalid("media artifact MIME type is missing")
      }
      (decoded, mime)
    }
    if bytes.length() == 0 {
      raise ProviderResponseInvalid("provider artifact is empty")
    }
    let content_digest = sha256(bytes)
    let artifact_id = "artifact-" + content_digest[7:31].to_owned()
    ignore(
      self.artifact_store.put_blob(
        "content-" + content_digest[7:].to_owned() + ".bin",
        bytes,
      ),
    )
    let metadata_digest = sha256(
      @utf8.encode(
        artifact_id +
        ":" +
        content_digest +
        ":" +
        record.job.plan_digest +
        ":" +
        attempt_id,
      ),
    )
    ignore(
      self.artifact_store.put_blob(provider_output_key(metadata_digest), bytes),
    )
    let item : @execution_domain.ProviderResultArtifact = {
      artifact_id,
      kind: artifact.modality,
      artifact_digest: metadata_digest,
      media_type,
      bytes: bytes.length(),
      rights_refs: artifact.source_refs,
      provider_receipt_digest,
    }
    ignore(
      self.artifact_store.put_json(
        "provider-artifact-" + artifact_id + ".json",
        item.to_json(),
      ),
    )
    normalized.push(item)
  }
  normalized
}

///|
/// The checked-in deterministic adapter is an explicit local validation
/// provider, never a production fallback. It renders exactly one bounded shot
/// with argv-only ffmpeg, returns the same wire contract as a remote provider,
/// and records that no network effect occurred.
async fn ProviderExecutionService::deterministic_fixture_result(
  self : ProviderExecutionService,
  record : ProviderJobRecord,
  attempt_id : String,
) -> ProviderWireResult raise ProviderApplicationError {
  if record.http_plan.body
    is { "contract": "mooncast.asset-provider-request.v1", .. } {
    let input : AssetProviderRequest = @json.from_json(record.http_plan.body) catch {
      _ => raise ProviderResponseInvalid("deterministic asset input is invalid")
    }
    let payload = if input.capability.has_prefix("qc-") {
      let result : Json = {
        "contract": "mooncast.qc-semantic-result.v1",
        "score": 0.96,
        "threshold": 0.80,
        "status": "pass",
        "note": "deterministic validation-only semantic analyzer receipt",
      }
      result.stringify()
    } else {
      "MOONCAST VALIDATION ASSET\n" +
      input.kind +
      "\n" +
      input.asset_id +
      "\nvariant=" +
      input.variant.to_string() +
      "\nprompt=" +
      input.prompt_digest +
      "\ncontinuity=" +
      input.continuity_key
    }
    let mime = match input.capability {
      "text" | "translation" => "text/plain; charset=utf-8"
      "image" => "image/x-mooncast-validation"
      "voice" | "music" => "audio/x-mooncast-validation"
      "video" | "lip-sync" | "upscale" => "video/x-mooncast-validation"
      capability if capability.has_prefix("qc-") => "application/json"
      _ => "application/octet-stream"
    }
    let bytes = @utf8.encode(payload)
    return {
      contract: "mooncast.provider-json-result.v1",
      artifacts: [
        {
          modality: input.capability,
          text: if input.capability == "text" ||
            input.capability == "translation" {
            Some(payload)
          } else {
            None
          },
          content_base64: if input.capability == "text" ||
            input.capability == "translation" {
            None
          } else {
            Some(@base64.encode(bytes))
          },
          mime_type: if input.capability == "text" ||
            input.capability == "translation" {
            None
          } else {
            Some(mime)
          },
          duration_seconds: None,
          source_refs: [
            input.intent_ref,
            input.prompt_digest,
            ..input.source_asset_refs,
            ..input.rights_refs,
          ],
        },
      ],
      usage: {
        "provider": "mooncast-local-deterministic-fixture",
        "validation_only": true,
        "capability": input.capability,
        "variant": input.variant,
      },
      cost: { currency: "CNY", amount: 0.0 },
      provider_receipt: {
        "contract": "mooncast.deterministic-provider-receipt.v1",
        "attempt_id": attempt_id,
        "plan_digest": record.job.plan_digest,
        "output_sha256": sha256(bytes),
        "network_effect_performed": false,
        "commercial_provider_acceptance": false,
      },
    }
  }
  let input : RoutedShotProviderInput = @json.from_json(record.http_plan.body) catch {
    _ => raise ProviderResponseInvalid("deterministic shot input is invalid")
  }
  let duration_seconds = input.shot.duration_ms.to_double() / 1000.0
  if duration_seconds <= 0.0 || duration_seconds > 12.0 {
    raise ProviderResponseInvalid(
      "deterministic fixture shots must be within 1-12 seconds",
    )
  }
  let output_key = "fixture-" + record.job.job_id + "-" + attempt_id + ".mp4"
  let output_path = self.artifact_store.prepare_owned_path(output_key) catch {
    _ => raise HostNotReady("deterministic fixture store is unavailable")
  }
  let render = @host_process.run_capture({
    executable: ".tools/ffmpeg/darwin_arm64/ffmpeg",
    arguments: [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "lavfi",
      "-i",
      "color=c=0x172033:s=960x540:r=24:d=" + duration_seconds.to_string(),
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=330:sample_rate=44100:duration=" +
      duration_seconds.to_string(),
      "-vf",
      "drawtext=text='MOONCAST / AI GENERATED':x=48:y=48:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=12,format=yuv420p",
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-crf",
      "24",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "aac",
      "-b:a",
      "96k",
      "-shortest",
      "-movflags",
      "+faststart",
      "-metadata",
      "title=Mooncast deterministic AI-generated shot",
      "-metadata",
      "comment=plan_digest:" + record.job.plan_digest,
      output_path,
    ],
    working_directory: None,
    timeout_ms: 45000,
    max_output_bytes: 1048576,
  }) catch {
    _ => raise HostNotReady("deterministic ffmpeg fixture could not start")
  }
  if render.exit_code != Some(0) || render.timed_out || render.output_truncated {
    raise HostNotReady("deterministic ffmpeg fixture failed")
  }
  let stored = self.artifact_store.get_blob(output_key) catch {
    _ => raise HostNotReady("deterministic fixture output cannot be read")
  }
  let blob = match stored {
    Some(value) if value.bytes.length() > 0 => value
    _ => raise HostNotReady("deterministic fixture output is missing")
  }
  {
    contract: "mooncast.provider-json-result.v1",
    artifacts: [
      {
        modality: record.http_plan.capability,
        text: None,
        content_base64: Some(@base64.encode(blob.bytes)),
        mime_type: Some("video/mp4"),
        duration_seconds: Some(duration_seconds),
        source_refs: [record.job.plan_digest, input.shot.shot_id],
      },
    ],
    usage: {
      "provider": "mooncast-local-deterministic-fixture",
      "duration_seconds": duration_seconds,
      "validation_only": true,
    },
    cost: { currency: "CNY", amount: duration_seconds * 0.08 },
    provider_receipt: {
      "contract": "mooncast.deterministic-provider-receipt.v1",
      "attempt_id": attempt_id,
      "plan_digest": record.job.plan_digest,
      "output_sha256": "sha256:" + blob.sha256,
      "network_effect_performed": false,
      "commercial_provider_acceptance": false,
    },
  }
}

///|
fn append_effect(
  record : ProviderJobRecord,
  attempt_id : String,
  endpoint : String,
  state : String,
  performed_at : String,
  response_digest : String?,
  network_effect_performed? : Bool = true,
) -> Array[ProviderHostEffectReceipt] {
  let receipts = record.host_effect_receipts.copy()
  receipts.push({
    contract: "mooncast.provider-host-effect-receipt.v1",
    request_id: record.http_plan.request_id,
    attempt_id,
    endpoint_origin_digest: sha256(@utf8.encode(endpoint)),
    response_digest,
    state,
    performed_at,
    network_effect_performed,
    publication_effect_performed: false,
    secret_values_persisted: false,
  })
  receipts
}

///|
async fn ProviderExecutionService::persist_response_failure(
  self : ProviderExecutionService,
  running : ProviderJobRecord,
  config : ProviderAdapterConfig,
  attempt_id : String,
  response_digest : String,
  code : String,
  message : String,
  network_effect_performed? : Bool = true,
) -> ProviderJobRecord {
  let completed_at = now()
  let failed = @execution_domain.reduce_provider_command(
    execution_command(
      running,
      "fail",
      attempt=attempt_phase(
        attempt_id,
        "completed",
        "failed",
        completed_at,
        error_code=code,
        error_message=message,
      ),
    ),
  )
  let durable = {
    ..running,
    job: failed.job,
    response_digest: Some(response_digest),
    host_effect_receipts: append_effect(
      running,
      attempt_id,
      config.endpoint,
      "failed",
      completed_at,
      Some(response_digest),
      network_effect_performed~,
    ),
    updated_at: completed_at,
  }
  self.save_job(durable)
  durable
}

///|
pub async fn ProviderExecutionService::execute(
  self : ProviderExecutionService,
  job_id : String,
) -> ProviderJobRecord {
  let record = match self.load_job(job_id) {
    Some(value) => value
    None => raise JobNotFound(job_id)
  }
  let config = match
    self.catalog.find(record.http_plan.adapter_id, record.http_plan.capability) {
    Some(value) => value
    None => raise AdapterUnavailable(record.http_plan.adapter_id)
  }
  if config_digest(config) != record.job.config_digest {
    raise InvalidPlan("provider configuration changed after authorization")
  }
  let attempt_id = "attempt-" + (record.job.attempt_count + 1).to_string()
  let started_at = now()
  let started = @execution_domain.reduce_provider_command(
    execution_command(
      record,
      "start",
      attempt=attempt_phase(attempt_id, "started", "running", started_at),
    ),
  )
  if !started.ok {
    raise InvalidPlan(
      started.error_code.unwrap_or("provider_job_not_executable"),
    )
  }
  let running = { ..record, job: started.job, updated_at: started_at }
  self.save_job(running)
  let deterministic_fixture = config.api_style ==
    "mooncast-deterministic-ffmpeg-v1"
  let (response_status, response_body, network_effect_performed) = if deterministic_fixture {
    let wire = self.deterministic_fixture_result(running, attempt_id) catch {
      _ => {
        let completed_at = now()
        let failed = @execution_domain.reduce_provider_command(
          execution_command(
            running,
            "retryable_failure",
            attempt=attempt_phase(
              attempt_id,
              "completed",
              "retryable_failure",
              completed_at,
              error_code="deterministic_fixture_failed",
              error_message="bounded local ffmpeg fixture failed",
            ),
          ),
        )
        let durable = {
          ..running,
          job: failed.job,
          host_effect_receipts: append_effect(
            running,
            attempt_id,
            config.endpoint,
            "failed",
            completed_at,
            None,
            network_effect_performed=false,
          ),
          updated_at: completed_at,
        }
        self.save_job(durable)
        return durable
      }
    }
    (200, wire.to_json(), false)
  } else {
    let headers = headers_for(config)
    let response = @transport.send_json({
      request_method: @transport.Post,
      url: config.endpoint,
      headers,
      body: Some(record.http_plan.body),
      timeout_ms: config.timeout_seconds * 1000,
      max_response_bytes: config.max_response_bytes,
    }) catch {
      _ => {
        let completed_at = now()
        let failed = @execution_domain.reduce_provider_command(
          execution_command(
            running,
            "retryable_failure",
            attempt=attempt_phase(
              attempt_id,
              "completed",
              "retryable_failure",
              completed_at,
              error_code="provider_transport_failed",
              error_message="bounded HTTPS provider request failed",
            ),
          ),
        )
        let durable = {
          ..running,
          job: failed.job,
          host_effect_receipts: append_effect(
            running,
            attempt_id,
            config.endpoint,
            "failed",
            completed_at,
            None,
          ),
          updated_at: completed_at,
        }
        self.save_job(durable)
        return durable
      }
    }
    (response.status, response.body, true)
  }
  if response_status < 200 || response_status >= 300 {
    let action = if response_status == 429 || response_status >= 500 {
      "retryable_failure"
    } else {
      "fail"
    }
    let completed_at = now()
    let failed = @execution_domain.reduce_provider_command(
      execution_command(
        running,
        action,
        attempt=attempt_phase(
          attempt_id,
          "completed",
          action,
          completed_at,
          error_code="provider_http_rejected",
          error_message="provider returned non-success status",
        ),
      ),
    )
    let response_digest = json_digest(response_body)
    let durable = {
      ..running,
      job: failed.job,
      response_digest: Some(response_digest),
      host_effect_receipts: append_effect(
        running,
        attempt_id,
        config.endpoint,
        "rejected",
        completed_at,
        Some(response_digest),
        network_effect_performed~,
      ),
      updated_at: completed_at,
    }
    self.save_job(durable)
    return durable
  }
  let response_digest = json_digest(response_body)
  let parsed_wire : ProviderWireResult? = try {
    let parsed : ProviderWireResult = @json.from_json(response_body)
    Some(parsed)
  } catch {
    _ => None
  }
  let wire = match parsed_wire {
    Some(value) => value
    None =>
      return self.persist_response_failure(
        running,
        config,
        attempt_id,
        response_digest,
        "provider_response_invalid",
        "provider JSON result is invalid",
        network_effect_performed~,
      )
  }
  if wire.cost.currency != "CNY" ||
    wire.cost.amount < 0.0 ||
    wire.cost.amount > record.http_plan.cost_ceiling_cny {
    return self.persist_response_failure(
      running,
      config,
      attempt_id,
      response_digest,
      "actual_cost_exceeds_ceiling",
      "provider cost is invalid or exceeds ceiling",
      network_effect_performed~,
    )
  }
  let parsed_artifacts : Array[@execution_domain.ProviderResultArtifact]? = Some(
    self.materialize_artifacts(running, wire, attempt_id),
  ) catch {
    _ => None
  }
  let artifacts = match parsed_artifacts {
    Some(value) => value
    None =>
      return self.persist_response_failure(
        running,
        config,
        attempt_id,
        response_digest,
        "provider_artifact_normalization_failed",
        "provider artifacts could not be normalized",
        network_effect_performed~,
      )
  }
  let completed_at = now()
  let completed = @execution_domain.reduce_provider_command(
    execution_command(
      running,
      "complete",
      attempt=attempt_phase(attempt_id, "completed", "completed", completed_at),
      artifacts~,
      cost_cny=wire.cost.amount,
    ),
  )
  let durable = {
    ..running,
    job: completed.job,
    response_digest: Some(response_digest),
    host_effect_receipts: append_effect(
      running,
      attempt_id,
      config.endpoint,
      "completed",
      completed_at,
      Some(response_digest),
      network_effect_performed~,
    ),
    updated_at: completed_at,
  }
  self.save_job(durable)
  durable
}

///|
pub async fn ProviderExecutionService::resume_job(
  self : ProviderExecutionService,
  job_id : String,
) -> ProviderJobRecord {
  self.execute(job_id)
}

///|
pub async fn ProviderExecutionService::record_project_ingest(
  self : ProviderExecutionService,
  job_id : String,
  project_ingest_digest : String,
) -> ProviderJobRecord {
  let record = match self.load_job(job_id) {
    Some(value) => value
    None => raise JobNotFound(job_id)
  }
  if project_ingest_digest == "" {
    raise InvalidPlan("project ingest digest is required")
  }
  if record.job.project_ingest_digest == Some(project_ingest_digest) {
    return record
  }
  let result = @execution_domain.reduce_provider_command(
    execution_command(record, "ingest", project_ingest_digest~),
  )
  if !result.ok {
    raise InvalidPlan(result.error_code.unwrap_or("provider_ingest_invalid"))
  }
  let durable = { ..record, job: result.job, updated_at: now() }
  self.save_job(durable)
  durable
}

///|
pub async fn ProviderExecutionService::cancel(
  self : ProviderExecutionService,
  job_id : String,
  actor_id : String,
) -> ProviderJobRecord {
  let record = match self.load_job(job_id) {
    Some(value) => value
    None => raise JobNotFound(job_id)
  }
  if !self.catalog.authority_actors.any(actor => actor == actor_id) {
    raise AuthorityDenied("named actor is not authorized")
  }
  let action = if record.job.state == "running" {
    "request_cancel"
  } else {
    "cancel"
  }
  let result = @execution_domain.reduce_provider_command(
    execution_command(record, action),
  )
  if !result.ok {
    raise InvalidPlan(result.error_code.unwrap_or("provider_cancel_invalid"))
  }
  let durable = { ..record, job: result.job, updated_at: now() }
  self.save_job(durable)
  durable
}

///|
pub async fn ProviderExecutionService::recover_interrupted(
  self : ProviderExecutionService,
) -> Int {
  let mut recovered = 0
  for key in self.store.list_keys(prefix="provider-job-", suffix=".json") {
    match self.store.get_json(key) {
      None => ()
      Some(value) => {
        let record : ProviderJobRecord = @json.from_json(value) catch {
          _ => continue
        }
        if record.job.state == "running" ||
          record.job.state == "cancel_requested" {
          let action = if record.job.attempt_count < record.job.max_attempts {
            "retryable_failure"
          } else {
            "fail"
          }
          let result = @execution_domain.reduce_provider_command(
            execution_command(
              record,
              action,
              attempt=attempt_phase(
                "attempt-" + record.job.attempt_count.to_string(),
                "completed",
                action,
                now(),
                error_code="provider_execution_interrupted",
                error_message="host restarted during provider execution",
              ),
            ),
          )
          if result.ok {
            self.save_job({ ..record, job: result.job, updated_at: now() })
            recovered = recovered + 1
          }
        }
      }
    }
  }
  recovered
}
