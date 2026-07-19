///|
pub struct StudioService {
  root : String
  store : @host_store.AtomicStore
  mutation_lock : @semaphore.Semaphore
  editor_repository : @editor_store.EditorRepository
  editor_media : @editor_media.MediaRegistry
  editor_render_files : @host_store.AtomicStore
  execution_application : @execution_app.ProviderExecutionService
  production_repository : @production_app.ProjectRepository
  production_pipeline : @pipeline_app.ProductionPipelineService
  delivery_application : @execution_app.DeliveryFactoryService
  commerce_application : @commerce_app.CommercialApplicationService
  handoff_outbox : @handoff_app.OutboundHandoffService
  needs_intake : @intake_app.NeedsIntakeService
  asset_factory : @asset_factory_app.AssetFactoryService
  animatic : @animatic_app.AnimaticService
  postprocess : @postprocess_app.PostprocessService
  route_extensions : Array[RouteExtension]
}

///|
pub fn StudioService::new(
  root : String,
  provider_catalog? : @execution_app.ProviderCatalog = {
    contract: "mooncast.provider-catalog.v1",
    adapters: [],
    authority_actors: ["studio-operator", "creative-director"],
  },
) -> StudioService {
  let execution_application = @execution_app.ProviderExecutionService::new(
    root + "/application/execution/state",
    root + "/application/execution/artifacts",
    provider_catalog,
  )
  let production_repository = @production_app.ProjectRepository::new(
    root + "/application/production",
  )
  let service : StudioService = {
    root,
    store: @host_store.AtomicStore::new(root),
    mutation_lock: @semaphore.Semaphore::new(1),
    editor_repository: @editor_store.EditorRepository::new(
      root + "/editor/repository",
    ),
    editor_media: @editor_media.MediaRegistry::new(root + "/editor/media"),
    editor_render_files: @host_store.AtomicStore::new(
      root + "/editor/render-files",
      max_read_bytes=1073741824,
    ),
    execution_application,
    production_repository,
    production_pipeline: @pipeline_app.ProductionPipelineService::new(
      production_repository, execution_application,
    ),
    delivery_application: @execution_app.DeliveryFactoryService::new(
      root + "/application/delivery/state",
      root + "/application/delivery/outputs",
      "ffmpeg",
    ),
    commerce_application: @commerce_app.CommercialApplicationService::new(
      root + "/application/commerce",
    ),
    handoff_outbox: @handoff_app.OutboundHandoffService::new(
      root + "/application/handoff-outbox",
    ),
    needs_intake: @intake_app.NeedsIntakeService::new(
      root + "/application/needs-intake",
    ),
    asset_factory: @asset_factory_app.AssetFactoryService::new(
      root + "/application/asset-factory",
      execution_application,
    ),
    animatic: @animatic_app.AnimaticService::new(
      root + "/application/animatic/state",
      root + "/application/animatic/media",
    ),
    postprocess: @postprocess_app.PostprocessService::new(
      root + "/application/postprocess",
      execution_application,
    ),
    route_extensions: [],
  }
  service.register_standard_application_routes()
  service.register_production_coordinator_routes()
  service.register_needs_intake_routes()
  service.register_asset_factory_routes()
  service.register_animatic_routes()
  service.register_postprocess_routes()
  service
}

///|
async fn[T] StudioService::with_mutation_lock(
  self : StudioService,
  work : async () -> T,
) -> T {
  self.mutation_lock.acquire()
  defer self.mutation_lock.release()
  work()
}

///|
fn valid_id(value : String) -> Bool {
  if value.length() < 3 || value.length() > 128 {
    return false
  }
  for char in value {
    match char {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' => ()
      _ => return false
    }
  }
  true
}

///|
fn sha256_text(value : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn project_key(project_id : String) -> String {
  "project-" + project_id + ".json"
}

///|
fn provider_key(job_id : String) -> String {
  "provider-" + job_id + ".json"
}

///|
fn routed_key(execution_id : String) -> String {
  "routed-" + execution_id + ".json"
}

///|
fn media_meta_key(media_id : String) -> String {
  "media-" + media_id + ".json"
}

///|
fn media_blob_key(media_id : String) -> String {
  "media-" + media_id + ".blob"
}

///|
fn project_result_key(project_id : String, command_id : String) -> String {
  "project-result-" + sha256_text(project_id + ":" + command_id) + ".json"
}

///|
fn provider_result_key(job_id : String, command_id : String) -> String {
  "provider-result-" + sha256_text(job_id + ":" + command_id) + ".json"
}

///|
async fn[T : FromJson] load_value(
  store : @host_store.AtomicStore,
  key : String,
) -> T? {
  match store.get_json(key) {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
async fn[T : ToJson] save_value(
  store : @host_store.AtomicStore,
  key : String,
  value : T,
) -> Unit {
  store.put_json(key, value.to_json()) |> ignore
}

///|
async fn StudioService::find_project(
  self : StudioService,
  project_id : String,
) -> ProjectRecord? {
  guard valid_id(project_id) else { return None }
  let record : ProjectRecord? = load_value(self.store, project_key(project_id))
  match record {
    Some(value) if !value.deleted => Some(value)
    _ => None
  }
}

///|
async fn StudioService::load_project_record(
  self : StudioService,
  project_id : String,
) -> ProjectRecord? {
  guard valid_id(project_id) else { return None }
  load_value(self.store, project_key(project_id))
}

///|
pub async fn StudioService::get_project(
  self : StudioService,
  project_id : String,
) -> ProjectRecord {
  match self.find_project(project_id) {
    Some(record) => record
    None => raise NotFound(entity="project", id=project_id)
  }
}

///|
fn summarize(record : ProjectRecord) -> ProjectSummary {
  let projection = @kernel.projection(record.snapshot)
  {
    project_id: record.project_id,
    title: record.snapshot.graph.title,
    revision: record.snapshot.revision,
    stage: projection.stage,
    current_gate: projection.current_gate,
    next_gate: projection.next_gate,
    updated_at: record.updated_at,
  }
}

///|
pub async fn StudioService::list_projects(
  self : StudioService,
) -> Array[ProjectSummary] {
  let summaries : Array[ProjectSummary] = []
  let keys = self.store.list_keys(prefix="project-", suffix=".json")
  for key in keys {
    // Command results and UI metadata intentionally share the same atomic
    // store, but they are not project records. Keep the legacy project key
    // stable while making the namespace boundary explicit.
    if key.has_prefix("project-result-") ||
      key.has_prefix("project-experience-") {
      continue
    }
    let found : ProjectRecord? = load_value(self.store, key)
    match found {
      Some(record) if !record.deleted => summaries.push(summarize(record))
      _ => ()
    }
  }
  summaries
}

///|
pub async fn StudioService::create_project(
  self : StudioService,
  graph : @project.ProjectGraph,
  recorded_at : String,
) -> ProjectRecord {
  self.with_mutation_lock(() => {
    guard valid_id(graph.project_id) else {
      raise Invalid(
        code="project_id_invalid",
        message="project id must be a portable flat identifier",
      )
    }
    let validation = @project.validate_graph(graph)
    guard validation.valid else {
      raise Invalid(
        code="project_graph_invalid",
        message=validation.errors.join(","),
      )
    }
    match self.load_project_record(graph.project_id) {
      Some(existing) => {
        if !existing.deleted && existing.snapshot.graph == graph {
          return existing
        }
        raise Conflict(
          code=if existing.deleted {
            "project_tombstoned"
          } else {
            "project_exists"
          },
          message="project id is already bound to durable evidence",
        )
      }
      None => ()
    }
    let snapshot = @kernel.empty_snapshot(graph)
    let record : ProjectRecord = {
      contract: "mooncast.native-project-record.v1",
      project_id: graph.project_id,
      created_at: recorded_at,
      updated_at: recorded_at,
      deleted: false,
      deleted_at: None,
      snapshot,
      events: [],
      command_receipts: [],
    }
    save_value(self.store, project_key(graph.project_id), record)
    ignore(
      self.production_repository.synchronize_canonical(
        snapshot,
        "sha256:" + sha256_text(snapshot.to_json().stringify()),
        recorded_at,
      ),
    )
    record
  })
}

///|
pub async fn StudioService::delete_project(
  self : StudioService,
  project_id : String,
  expected_revision : Int,
) -> Unit {
  self.with_mutation_lock(() => {
    let record = match self.load_project_record(project_id) {
      Some(value) if !value.deleted => value
      _ => raise NotFound(entity="project", id=project_id)
    }
    guard record.snapshot.revision == expected_revision else {
      raise Conflict(
        code="project_revision_conflict",
        message="expected revision does not match canonical snapshot",
      )
    }
    let deleted_at = @runtime.wall_clock_ms().to_string()
    let tombstone = {
      ..record,
      updated_at: deleted_at,
      deleted: true,
      deleted_at: Some(deleted_at),
    }
    save_value(self.store, project_key(project_id), tombstone)
  })
}

///|
fn[T : ToJson] optional_json(value : T?) -> String {
  match value {
    Some(item) => item.to_json().stringify()
    None => "null"
  }
}

///|
fn command_payload_json(command : @kernel.ProjectCommand) -> String {
  match command.command {
    "record_qualification" => optional_json(command.qualification)
    "record_creative_artifact" => optional_json(command.creative_artifact)
    "record_creative_decision" => optional_json(command.creative_decision)
    "record_routing_plan" => optional_json(command.routing_plan)
    "record_routing_decision" => optional_json(command.routing_decision)
    "record_generation_attempt" => optional_json(command.generation_attempt)
    "record_qc_finding" => optional_json(command.qc_finding)
    "record_qc_decision" => optional_json(command.qc_decision)
    "record_master" => optional_json(command.master)
    "record_master_decision" => optional_json(command.master_decision)
    "record_delivery_package" => optional_json(command.delivery_package)
    "record_delivery_acceptance" => optional_json(command.delivery_acceptance)
    "record_publication_authorization" =>
      optional_json(command.publication_authorization)
    "record_publication_observation" =>
      optional_json(command.publication_observation)
    "record_performance_review" => optional_json(command.performance_review)
    _ => "null"
  }
}

///|
fn command_input_digest(command : @kernel.ProjectCommand) -> String {
  sha256_text(
    command.command +
    ":" +
    command.command_id +
    ":" +
    command.recorded_at +
    ":" +
    command.evidence_digest +
    ":" +
    command.gate.unwrap_or("") +
    ":" +
    command.actor.unwrap_or("") +
    ":" +
    command.role.unwrap_or("") +
    ":" +
    command_payload_json(command),
  )
}

///|
pub async fn StudioService::apply_project_command(
  self : StudioService,
  project_id : String,
  request : ProjectCommandRequest,
) -> ProjectCommandResponse {
  self.with_mutation_lock(() => {
    let record = self.get_project(project_id)
    let input_digest = command_input_digest(request.command)
    for receipt in record.command_receipts {
      if receipt.command_id == request.command.command_id {
        guard receipt.input_digest == input_digest else {
          raise Conflict(
            code="idempotency_key_reused",
            message="command id is already bound to another input",
          )
        }
        let stored : @kernel.CommandResult? = load_value(
          self.store,
          receipt.result_key,
        )
        guard stored is Some(result) else {
          raise Invalid(
            code="command_receipt_integrity_failed",
            message="stored command result is missing",
          )
        }
        guard sha256_text(result.to_json().stringify()) == receipt.result_digest else {
          raise Invalid(
            code="command_receipt_integrity_failed",
            message="stored command result is missing or corrupt",
          )
        }
        return { project: record, result, idempotent_replay: true }
      }
    }
    guard request.expected_revision == record.snapshot.revision else {
      raise Conflict(
        code="project_revision_conflict",
        message="expected revision does not match canonical snapshot",
      )
    }
    let command = { ..request.command, snapshot: record.snapshot }
    let result = @kernel.handle(command)
    let result_key = project_result_key(project_id, command.command_id)
    let result_digest = sha256_text(result.to_json().stringify())
    save_value(self.store, result_key, result)
    let events = record.events
    for event in result.emitted_events {
      events.push(event)
    }
    let receipts = record.command_receipts
    receipts.push({
      command_id: command.command_id,
      input_digest,
      result_key,
      result_digest,
      result_revision: result.snapshot.revision,
      ok: result.ok,
    })
    let updated = {
      ..record,
      updated_at: command.recorded_at,
      snapshot: result.snapshot,
      events,
      command_receipts: receipts,
    }
    save_value(self.store, project_key(project_id), updated)
    if result.ok {
      ignore(
        self.production_repository.synchronize_canonical(
          result.snapshot,
          command.evidence_digest,
          command.recorded_at,
        ),
      )
    }
    { project: updated, result, idempotent_replay: false }
  })
}

///|
fn base_command(
  snapshot : @kernel.ProjectSnapshot,
  command_id : String,
  command : String,
  recorded_at : String,
  evidence_digest : String,
) -> @kernel.ProjectCommand {
  {
    schema_version: "mooncast.project-command.v2",
    kernel_version: @kernel.production_kernel_version,
    command_id,
    command,
    recorded_at,
    evidence_digest,
    snapshot,
    gate: None,
    actor: None,
    role: None,
    qualification: None,
    creative_artifact: None,
    creative_decision: None,
    routing_plan: None,
    routing_decision: None,
    generation_attempt: None,
    qc_finding: None,
    qc_decision: None,
    master: None,
    master_decision: None,
    delivery_package: None,
    delivery_acceptance: None,
    publication_authorization: None,
    publication_observation: None,
    performance_review: None,
  }
}

///|
pub async fn StudioService::record_creative_artifact(
  self : StudioService,
  project_id : String,
  request : CreativeArtifactRequest,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  let command = {
    ..base_command(
      record.snapshot,
      request.command_id,
      "record_creative_artifact",
      request.recorded_at,
      request.evidence_digest,
    ),
    creative_artifact: Some(request.artifact),
  }
  self.apply_project_command(project_id, {
    expected_revision: request.expected_revision,
    command,
  })
}

///|
pub async fn StudioService::record_creative_decision(
  self : StudioService,
  project_id : String,
  request : CreativeDecisionRequest,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  let command = {
    ..base_command(
      record.snapshot,
      request.command_id,
      "record_creative_decision",
      request.recorded_at,
      request.evidence_digest,
    ),
    creative_decision: Some(request.decision),
  }
  let response = self.apply_project_command(project_id, {
    expected_revision: request.expected_revision,
    command,
  })
  if !response.result.ok {
    response
  } else {
    let project = self.advance_ready_gates(
      project_id,
      request.decision.actor,
      request.decision.role,
      request.evidence_digest,
    )
    { ..response, project, }
  }
}

///|
pub async fn StudioService::advance_gate(
  self : StudioService,
  project_id : String,
  request : GateCommandRequest,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  let command = {
    ..base_command(
      record.snapshot,
      request.command_id,
      "advance_gate",
      request.recorded_at,
      request.evidence_digest,
    ),
    gate: Some(request.gate),
    actor: Some(request.actor),
    role: Some(request.role),
  }
  self.apply_project_command(project_id, {
    expected_revision: request.expected_revision,
    command,
  })
}

///|
pub async fn StudioService::creative_view(
  self : StudioService,
  project_id : String,
  kind : @creative.ArtifactKind,
) -> CreativeView {
  let record = self.get_project(project_id)
  let history = record.snapshot.creative_artifacts.filter(value => {
    value.kind == kind
  })
  let artifact = @creative.current_artifact(history, kind)
  let decisions = record.snapshot.creative_decisions.filter(value => {
    match artifact {
      Some(current) => value.artifact.id == current.reference.id
      None => false
    }
  })
  { artifact, history, decisions, project_revision: record.snapshot.revision }
}

///|
pub async fn StudioService::governance_view(
  self : StudioService,
  project_id : String,
) -> GovernanceView {
  let record = self.get_project(project_id)
  let snapshot = record.snapshot
  {
    project_revision: snapshot.revision,
    model_routing_plan: snapshot.routing_plan,
    model_routing_history: match snapshot.routing_plan {
      Some(plan) => [plan]
      None => []
    },
    model_routing_decisions: snapshot.routing_decisions,
    generation_attempts: snapshot.generation_attempts,
    shot_qc_findings: snapshot.qc_findings,
    shot_qc_decisions: snapshot.qc_decisions,
    master_lineage: snapshot.master,
    master_decisions: snapshot.master_decisions,
    delivery_package: snapshot.delivery_package,
    delivery_package_history: match snapshot.delivery_package {
      Some(value) => [value]
      None => []
    },
    delivery_milestone_acceptances: snapshot.delivery_acceptances,
    publication_authorizations: snapshot.publication_authorizations,
    publication_receipts: snapshot.publication_observations,
    performance_reviews: snapshot.performance_reviews,
    governance_invalidations: [],
  }
}

///|
async fn StudioService::find_provider_job(
  self : StudioService,
  job_id : String,
) -> ProviderJobRecord? {
  guard valid_id(job_id) else { return None }
  load_value(self.store, provider_key(job_id))
}

///|
pub async fn StudioService::get_provider_job(
  self : StudioService,
  job_id : String,
) -> ProviderJobRecord {
  match self.find_provider_job(job_id) {
    Some(record) => record
    None => raise NotFound(entity="provider_job", id=job_id)
  }
}

///|
pub async fn StudioService::list_provider_jobs(
  self : StudioService,
) -> Array[ProviderJobRecord] {
  let records : Array[ProviderJobRecord] = []
  for key in self.store.list_keys(prefix="provider-", suffix=".json") {
    let found : ProviderJobRecord? = load_value(self.store, key)
    match found {
      Some(record) => records.push(record)
      None => ()
    }
  }
  records
}

///|
pub async fn StudioService::authorize_provider_job(
  self : StudioService,
  request : ProviderAuthorizationRequest,
) -> ProviderJobRecord {
  self.with_mutation_lock(() => {
    let job = request.job
    guard valid_id(job.job_id) &&
      job.contract == "mooncast.provider-execution-job.v1" else {
      raise Invalid(
        code="provider_job_invalid",
        message="provider job identity or contract is invalid",
      )
    }
    guard job.state == "authorized" && job.revision == 0 && job.max_attempts > 0 else {
      raise Invalid(
        code="provider_job_state_invalid",
        message="new provider job must be authorized at revision zero",
      )
    }
    guard job.authority.network_authority &&
      !job.authority.publication_authority &&
      !job.authority.external_effect_performed_by_reducer &&
      !job.publication_authority else {
      raise Invalid(
        code="provider_authority_invalid",
        message="network authority receipt is required and publication authority is forbidden",
      )
    }
    match self.find_provider_job(job.job_id) {
      Some(existing) => {
        if existing.job == job {
          return existing
        }
        raise Conflict(
          code="provider_job_exists",
          message="provider job id already exists",
        )
      }
      None => ()
    }
    let record : ProviderJobRecord = {
      contract: "mooncast.native-provider-job-record.v1",
      job,
      events: [],
      command_receipts: [],
    }
    save_value(self.store, provider_key(job.job_id), record)
    record
  })
}

///|
fn provider_input_digest(
  command : @execution.ProviderExecutionCommand,
) -> String {
  sha256_text(command.to_json().stringify())
}

///|
pub async fn StudioService::apply_provider_command(
  self : StudioService,
  job_id : String,
  supplied : @execution.ProviderExecutionCommand,
) -> ProviderCommandResponse {
  self.with_mutation_lock(() => {
    let record = self.get_provider_job(job_id)
    let input_digest = provider_input_digest(supplied)
    for receipt in record.command_receipts {
      if receipt.command_id == supplied.command_id {
        guard receipt.input_digest == input_digest else {
          raise Conflict(
            code="idempotency_key_reused",
            message="provider command id is already bound to another input",
          )
        }
        let stored : @execution.ProviderExecutionResult? = load_value(
          self.store,
          receipt.result_key,
        )
        guard stored is Some(result) else {
          raise Invalid(
            code="provider_receipt_integrity_failed",
            message="stored provider result is missing",
          )
        }
        guard sha256_text(result.to_json().stringify()) == receipt.result_digest else {
          raise Invalid(
            code="provider_receipt_integrity_failed",
            message="stored provider result is missing or corrupt",
          )
        }
        return { record, result, idempotent_replay: true }
      }
    }
    guard supplied.expected_revision == record.job.revision else {
      raise Conflict(
        code="provider_job_revision_conflict",
        message="expected revision does not match canonical provider job",
      )
    }
    let command = { ..supplied, job: record.job }
    let result = @execution.reduce_provider_command(command)
    let result_key = provider_result_key(job_id, command.command_id)
    let result_digest = sha256_text(result.to_json().stringify())
    save_value(self.store, result_key, result)
    let events = record.events
    for event in result.events {
      events.push(event)
    }
    let receipts = record.command_receipts
    receipts.push({
      command_id: command.command_id,
      input_digest,
      result_key,
      result_digest,
      result_revision: result.job.revision,
      ok: result.ok,
    })
    let updated = {
      ..record,
      job: result.job,
      events,
      command_receipts: receipts,
    }
    save_value(self.store, provider_key(job_id), updated)
    { record: updated, result, idempotent_replay: false }
  })
}

///|
pub async fn StudioService::plan_routed_execution(
  self : StudioService,
  project_id : String,
  request : RoutedPlanRequest,
) -> RoutedExecutionRecord {
  self.with_mutation_lock(() => {
    guard valid_id(request.execution_id) else {
      raise Invalid(
        code="execution_id_invalid",
        message="routed execution id is invalid",
      )
    }
    let project = self.get_project(project_id)
    guard project.snapshot.revision == request.expected_project_revision else {
      raise Conflict(
        code="project_revision_conflict",
        message="expected revision does not match canonical snapshot",
      )
    }
    guard project.snapshot.routing_plan is Some(plan) else {
      raise Invalid(
        code="routing_plan_required",
        message="canonical approved routing plan is required",
      )
    }
    let found : RoutedExecutionRecord? = load_value(
      self.store,
      routed_key(request.execution_id),
    )
    match found {
      Some(existing) => {
        guard existing.project_id == project_id &&
          existing.execution.binding_digest == request.binding_digest else {
          raise Conflict(
            code="routed_execution_exists",
            message="execution id is bound to another plan",
          )
        }
        return existing
      }
      None => ()
    }
    let result = @execution.plan_routed_execution(
      request.execution_id,
      project.snapshot.graph,
      plan,
      request.actor_id,
      request.binding_digest,
      request.created_at,
    )
    guard result.ok else {
      raise Invalid(
        code=result.error_code.unwrap_or("routed_plan_invalid"),
        message="routing plan could not produce one bounded route per shot",
      )
    }
    guard result.execution is Some(execution) else {
      raise Invalid(
        code="routed_plan_missing",
        message="routing plan did not return an execution",
      )
    }
    let record : RoutedExecutionRecord = {
      contract: "mooncast.native-routed-execution-record.v1",
      project_id,
      execution,
    }
    save_value(self.store, routed_key(request.execution_id), record)
    record
  })
}

///|
pub async fn StudioService::list_routed_executions(
  self : StudioService,
  project_id : String,
) -> Array[RoutedExecutionRecord] {
  let records : Array[RoutedExecutionRecord] = []
  for key in self.store.list_keys(prefix="routed-", suffix=".json") {
    let found : RoutedExecutionRecord? = load_value(self.store, key)
    match found {
      Some(record) if record.project_id == project_id => records.push(record)
      _ => ()
    }
  }
  records
}

///|
pub async fn StudioService::get_routed_execution(
  self : StudioService,
  project_id : String,
  execution_id : String,
) -> RoutedExecutionRecord {
  let found : RoutedExecutionRecord? = load_value(
    self.store,
    routed_key(execution_id),
  )
  match found {
    Some(record) if record.project_id == project_id => record
    _ => raise NotFound(entity="routed_execution", id=execution_id)
  }
}

///|
pub async fn StudioService::register_media(
  self : StudioService,
  record : MediaRecord,
  content : Bytes,
) -> MediaRecord {
  self.with_mutation_lock(() => {
    guard valid_id(record.media_id) &&
      record.bytes == content.length() &&
      record.sha256 == @crypto.bytes_to_hex_string(@crypto.sha256(content)) else {
      raise Invalid(
        code="media_record_invalid",
        message="media identity, size, or digest is invalid",
      )
    }
    self.store.put_blob(media_blob_key(record.media_id), content) |> ignore
    save_value(self.store, media_meta_key(record.media_id), record)
    record
  })
}

///|
pub async fn StudioService::resolve_media(
  self : StudioService,
  media_id : String,
) -> ResolvedMedia {
  guard valid_id(media_id) else { raise NotFound(entity="media", id=media_id) }
  let record : MediaRecord = match
    load_value(self.store, media_meta_key(media_id)) {
    Some(value) => value
    None => raise NotFound(entity="media", id=media_id)
  }
  let blob = match self.store.get_blob(media_blob_key(media_id)) {
    Some(value) => value.bytes
    None => raise NotFound(entity="media", id=media_id)
  }
  guard blob.length() == record.bytes &&
    @crypto.bytes_to_hex_string(@crypto.sha256(blob)) == record.sha256 else {
    raise Invalid(
      code="media_integrity_failed",
      message="stored media does not match canonical metadata",
    )
  }
  { record, content: blob }
}
