///|
fn sha256(bytes : Bytes) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn json_digest(value : Json) -> String {
  sha256(@utf8.encode(value.stringify()))
}

///|
fn now() -> String {
  @runtime.wall_clock_ms().to_string()
}

///|
pub struct ProviderExecutionService {
  store : @store.AtomicStore
  artifact_store : @store.AtomicStore
  catalog : ProviderCatalog
}

///|
pub fn ProviderExecutionService::new(
  state_root : String,
  artifact_root : String,
  catalog : ProviderCatalog,
) -> ProviderExecutionService {
  {
    store: @store.AtomicStore::new(state_root, max_read_bytes=16777216),
    artifact_store: @store.AtomicStore::new(artifact_root),
    catalog,
  }
}

///|
pub fn ProviderExecutionService::capabilities(
  self : ProviderExecutionService,
) -> ProviderExecutionCapabilities {
  {
    contract: "mooncast.provider-execution-capabilities.v1",
    adapters: self.catalog.readiness(),
    authority_actor_count: self.catalog.authority_actors.length(),
    secret_resolver_connected: true,
    json_post_transport_connected: true,
    publication_authority: false,
  }
}

///|
fn job_key(job_id : String) -> String {
  "provider-job-" + job_id + ".json"
}

///|
fn provider_output_key(digest : String) -> String {
  let normalized = if digest.has_prefix("sha256:") {
    digest[7:].to_owned()
  } else {
    digest
  }
  "output-" + normalized + ".bin"
}

///|
pub async fn ProviderExecutionService::artifact_metadata(
  self : ProviderExecutionService,
  output_digest : String,
) -> @execution_domain.ProviderResultArtifact? {
  for job in self.list_jobs() {
    for artifact in job.artifacts {
      if artifact.artifact_digest == output_digest {
        return Some(artifact)
      }
    }
  }
  None
}

///|
pub async fn ProviderExecutionService::artifact_bytes(
  self : ProviderExecutionService,
  output_digest : String,
) -> Bytes? {
  self.artifact_store
  .get_blob(provider_output_key(output_digest))
  .map(blob => blob.bytes)
}

///|
pub async fn ProviderExecutionService::load_job(
  self : ProviderExecutionService,
  job_id : String,
) -> ProviderJobRecord? {
  match self.store.get_json(job_key(job_id)) {
    None => None
    Some(value) => {
      let record : ProviderJobRecord = @json.from_json(value) catch {
        _ => raise JobCorrupt(job_id)
      }
      if record.job.job_id != job_id {
        raise JobCorrupt(job_id)
      }
      Some(record)
    }
  }
}

///|
pub async fn ProviderExecutionService::list_jobs(
  self : ProviderExecutionService,
) -> Array[@execution_domain.ProviderExecutionJob] {
  let jobs : Array[@execution_domain.ProviderExecutionJob] = []
  for key in self.store.list_keys(prefix="provider-job-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let record : ProviderJobRecord = @json.from_json(value) catch {
          _ => continue
        }
        jobs.push(record.job)
      }
      None => ()
    }
  }
  jobs
}

///|
pub async fn ProviderExecutionService::attempt_projection(
  self : ProviderExecutionService,
  job_id : String,
) -> Array[@execution_domain.ProviderAttemptPhase] {
  match self.load_job(job_id) {
    None => []
    Some(record) => record.job.attempt_history
  }
}

///|
async fn ProviderExecutionService::save_job(
  self : ProviderExecutionService,
  record : ProviderJobRecord,
) -> Unit {
  ignore(self.store.put_json(job_key(record.job.job_id), record.to_json()))
}

///|
fn config_digest(config : ProviderAdapterConfig) -> String {
  json_digest(config.to_json())
}

///|
pub fn provider_authority_receipt_digest(
  authority : ProviderAuthorityReceipt,
) -> String {
  sha256(
    @utf8.encode(
      authority.receipt_id +
      ":" +
      authority.actor_id +
      ":" +
      authority.plan_digest +
      ":" +
      authority.config_digest +
      ":" +
      authority.cost_ceiling_cny.to_string() +
      ":" +
      authority.granted_at,
    ),
  )
}

///|
fn plan_matches(
  plan : ProviderHttpPlan,
  config : ProviderAdapterConfig,
) -> Bool {
  let mut secrets_match = plan.secret_refs.length() ==
    config.secret_refs.length()
  for name, reference in config.secret_refs {
    if plan.secret_refs.get(name) != Some(reference) {
      secrets_match = false
    }
  }
  plan.contract == "mooncast.provider-request-plan.v1" &&
  plan.adapter_id == config.adapter_id &&
  plan.capability == config.capability &&
  plan.provider == config.provider &&
  plan.endpoint == config.endpoint &&
  plan.request_method == "POST" &&
  plan.model == config.model &&
  plan.api_style == config.api_style &&
  secrets_match &&
  plan.timeout_seconds == config.timeout_seconds &&
  !plan.network_authority &&
  !plan.publication_authority &&
  plan.cost_ceiling_cny >= 0.0 &&
  plan.plan_digest == provider_plan_digest(plan)
}

///|
pub async fn ProviderExecutionService::authorize(
  self : ProviderExecutionService,
  plan : ProviderHttpPlan,
  authority : ProviderAuthorityReceipt,
) -> ProviderJobRecord {
  let config = match self.catalog.find(plan.adapter_id, plan.capability) {
    Some(value) => value
    None => raise AdapterUnavailable(plan.adapter_id)
  }
  let digest = config_digest(config)
  if !plan_matches(plan, config) {
    raise InvalidPlan("plan differs from provider catalog")
  }
  if authority.contract != "mooncast.provider-execution-authority.v1" ||
    authority.decision != "authorize" ||
    !authority.network_authority ||
    authority.publication_authority ||
    authority.plan_digest != plan.plan_digest ||
    authority.config_digest != digest ||
    authority.cost_ceiling_cny != plan.cost_ceiling_cny ||
    authority.max_attempts < 1 ||
    authority.max_attempts > 5 ||
    authority.receipt_id == "" ||
    authority.receipt_digest == "" ||
    authority.receipt_digest != provider_authority_receipt_digest(authority) ||
    !self.catalog.authority_actors.any(actor => actor == authority.actor_id) {
    raise AuthorityDenied("exact named host authority is required")
  }
  let binding_digest = json_digest(
    [plan.to_json(), authority.to_json()].to_json(),
  )
  let identity_digest = sha256(
    @utf8.encode(
      plan.plan_digest + ":" + digest + ":" + authority.receipt_digest,
    ),
  )
  let job_id = "job-" + identity_digest[7:31].to_owned()
  match self.load_job(job_id) {
    Some(existing) => {
      if existing.job.binding_digest != binding_digest {
        raise InvalidPlan("provider job identity conflicts")
      }
      return existing
    }
    None => ()
  }
  let secret_refs : Array[String] = []
  for _, reference in plan.secret_refs {
    secret_refs.push(reference)
  }
  let domain_plan : @execution_domain.ProviderRequestPlan = {
    contract: plan.contract,
    request_id: plan.request_id,
    adapter_id: plan.adapter_id,
    capability: plan.capability,
    provider: plan.provider,
    endpoint: plan.endpoint,
    request_method: plan.request_method,
    model: plan.model,
    timeout_seconds: plan.timeout_seconds,
    max_attempts: authority.max_attempts,
    cost_ceiling_cny: plan.cost_ceiling_cny,
    secret_refs,
    input_digest: json_digest(plan.body),
    plan_digest: plan.plan_digest,
  }
  let job : @execution_domain.ProviderExecutionJob = {
    contract: "mooncast.provider-execution-job.v1",
    job_id,
    state: "authorized",
    revision: 1,
    plan: domain_plan,
    plan_digest: plan.plan_digest,
    config_digest: digest,
    binding_digest,
    authority: {
      actor_id: authority.actor_id,
      authority_receipt_digest: authority.receipt_digest,
      network_authority: true,
      publication_authority: false,
      external_effect_performed_by_reducer: false,
    },
    attempt_count: 0,
    max_attempts: authority.max_attempts,
    attempt_history: [],
    artifacts: [],
    spent_cny: 0.0,
    last_error_code: None,
    last_error_message: None,
    project_ingest_digest: None,
    publication_authority: false,
  }
  let record : ProviderJobRecord = {
    contract: "mooncast.provider-job-record.v1",
    job,
    http_plan: plan,
    response_digest: None,
    host_effect_receipts: [],
    updated_at: now(),
  }
  self.save_job(record)
  record
}
