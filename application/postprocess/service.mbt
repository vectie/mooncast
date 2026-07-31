///|
pub(all) struct PostprocessRunRequest {
  expected_task_version : Int
  expected_task_digest : String
  actor : String
  human_confirmed : Bool
  network_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PostprocessBindRequest {
  output_asset_id : String
  output_asset_version : Int
  destination_kind : String
  destination_id : String
  editor_media_digest : String?
  actor : String
  bound_at : String
  human_confirmed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror PostprocessApplicationError {
  PostprocessInvalid(String)
  PostprocessConflict(String)
} derive(Debug)

///|
pub struct PostprocessService {
  store : @store.AtomicStore
  execution : @execution_app.ProviderExecutionService
}

///|
pub fn PostprocessService::new(
  root : String,
  execution : @execution_app.ProviderExecutionService,
) -> PostprocessService {
  { store: @store.AtomicStore::new(root), execution }
}

///|
fn digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn task_key(project_id : String, version : Int) -> String {
  "postprocess-task-" + project_id + "-v" + version.to_string() + ".json"
}

///|
fn output_key(asset_id : String, version : Int) -> String {
  "postprocess-output-" + asset_id + "-v" + version.to_string() + ".json"
}

///|
pub async fn PostprocessService::record_task(
  self : PostprocessService,
  task : @postprocess_domain.PostprocessTask,
  graph : @project.ProjectGraph,
) -> @postprocess_domain.PostprocessTask {
  let errors = @postprocess_domain.task_errors(task, graph)
  guard errors.is_empty() else { raise PostprocessInvalid(errors.join("; ")) }
  let key = task_key(task.project_id, task.reference.version)
  match self.store.get_json(key) {
    Some(value) => {
      let prior : @postprocess_domain.PostprocessTask = @json.from_json(value)
      guard prior == task else {
        raise PostprocessConflict("task version conflict")
      }
      prior
    }
    None => {
      ignore(self.store.put_json(key, task.to_json()))
      task
    }
  }
}

///|
pub async fn PostprocessService::list_tasks(
  self : PostprocessService,
  project_id : String,
) -> Array[@postprocess_domain.PostprocessTask] {
  let values : Array[@postprocess_domain.PostprocessTask] = []
  for
    key in self.store.list_keys(
      prefix="postprocess-task-" + project_id + "-v",
      suffix=".json",
    ) {
    match self.store.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
async fn PostprocessService::current_task(
  self : PostprocessService,
  project_id : String,
) -> @postprocess_domain.PostprocessTask? {
  let values = self.list_tasks(project_id)
  if values.is_empty() {
    return None
  }
  let mut latest = values[0]
  for value in values {
    if value.reference.version > latest.reference.version {
      latest = value
    }
  }
  Some(latest)
}

///|
pub async fn PostprocessService::run(
  self : PostprocessService,
  project_id : String,
  request : PostprocessRunRequest,
) -> @postprocess_domain.PostprocessOutput {
  guard self.current_task(project_id) is Some(task) &&
    task.reference.version == request.expected_task_version &&
    task.reference.digest == request.expected_task_digest &&
    request.actor != "" &&
    request.human_confirmed &&
    request.network_authority else {
    raise PostprocessConflict(
      "run requires exact task and explicit named provider authority",
    )
  }
  let asset_id = task.project_id +
    "-" +
    task.operation +
    "-" +
    task.reference.version.to_string()
  let key = output_key(asset_id, 1)
  match self.store.get_json(key) {
    Some(value) => return @json.from_json(value)
    None => ()
  }
  let job_id = "postprocess:" +
    task.reference.id +
    ":" +
    task.reference.version.to_string()
  let job = self.execution.authorize_asset_from_catalog(
    {
      contract: "mooncast.asset-provider-request.v1",
      request_id: job_id,
      project_id: task.project_id,
      project_revision: task.project_revision,
      asset_id,
      asset_version: 1,
      variant: 1,
      kind: task.operation,
      capability: task.operation,
      intent_ref: task.reference.digest,
      prompt_digest: task.prompt_digest,
      source_asset_refs: task.source_assets.map(asset => asset.digest),
      rights_refs: task.rights_refs,
      continuity_key: if task.shot_ids.is_empty() {
        task.reference.digest
      } else {
        task.shot_ids.join("|")
      },
      adapter_id: task.provider_adapter_id,
      provider: task.provider,
      model: task.model,
      permitted_data_class: task.permitted_data_class,
      cost_ceiling_cny: task.cost_ceiling_cny,
      retry_limit: task.retry_limit,
      parameters: task.to_json(),
      publication_authority: false,
    },
    request.actor,
    true,
  )
  let executed = if job.job.state == "completed" {
    job
  } else {
    self.execution.execute(job.job.job_id)
  }
  guard executed.job.state == "completed" &&
    executed.job.artifacts.length() == 1 else {
    raise PostprocessConflict("provider job remains retryable or failed")
  }
  let artifact = executed.job.artifacts[0]
  let kind = match task.operation {
    "translation" => "text"
    _ => "video"
  }
  let core : @postprocess_domain.PostprocessOutput = {
    contract: "mooncast.postprocess-output.v1",
    reference: {
      asset_id,
      kind,
      version: 1,
      digest: artifact.artifact_digest,
      uri: "provider-artifact:" + artifact.artifact_id,
      rights_record_id: digest(task.rights_refs.join("|")),
      immutable: true,
    },
    task: task.reference,
    provider_job_id: executed.job.job_id,
    provider_artifact_id: artifact.artifact_id,
    operation: task.operation,
    source_assets: task.source_assets,
    rights_refs: task.rights_refs,
    cost_cny: executed.job.spent_cny,
    provenance_digest: digest(
      task.reference.digest + ":" + artifact.artifact_digest,
    ),
    created_at: executed.updated_at,
    network_effect_performed: executed.host_effect_receipts.any(value => {
      value.network_effect_performed
    }),
    publication_authority: false,
    immutable: true,
  }
  ignore(self.store.put_json(key, core.to_json()))
  core
}

///|
pub async fn PostprocessService::list_outputs(
  self : PostprocessService,
  project_id : String,
) -> Array[@postprocess_domain.PostprocessOutput] {
  let tasks = self.list_tasks(project_id)
  let values : Array[@postprocess_domain.PostprocessOutput] = []
  for key in self.store.list_keys(prefix="postprocess-output-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let output : @postprocess_domain.PostprocessOutput = @json.from_json(
          value,
        )
        if tasks.any(task => task.reference == output.task) {
          values.push(output)
        }
      }
      None => ()
    }
  }
  values
}

///|
pub async fn PostprocessService::bind(
  self : PostprocessService,
  project_id : String,
  request : PostprocessBindRequest,
) -> @postprocess_domain.PostprocessImportBinding {
  let matches = self
    .list_outputs(project_id)
    .filter(value => {
      value.reference.asset_id == request.output_asset_id &&
      value.reference.version == request.output_asset_version
    })
  guard matches.length() == 1 &&
    ["shot", "editor", "delivery"].contains(request.destination_kind) &&
    request.destination_id != "" &&
    request.actor != "" &&
    request.bound_at != "" &&
    request.human_confirmed &&
    (
      request.destination_kind != "editor" ||
      request.editor_media_digest is Some(_)
    ) else {
    raise PostprocessInvalid(
      "import binding must be exact and named-human confirmed",
    )
  }
  let output = matches[0]
  let binding_id = digest(
    output.provenance_digest +
    ":" +
    request.destination_kind +
    ":" +
    request.destination_id,
  )[7:31].to_owned()
  let binding : @postprocess_domain.PostprocessImportBinding = {
    contract: "mooncast.postprocess-import-binding.v1",
    binding_id,
    output: output.reference,
    destination_kind: request.destination_kind,
    destination_id: request.destination_id,
    editor_media_digest: request.editor_media_digest,
    bound_at: request.bound_at,
    actor: request.actor,
    human_confirmed: true,
    publication_authority: false,
    immutable: true,
  }
  ignore(
    self.store.put_json(
      "postprocess-binding-" + binding_id + ".json",
      binding.to_json(),
    ),
  )
  binding
}

///|
pub async fn PostprocessService::workspace(
  self : PostprocessService,
  project_id : String,
) -> @postprocess_domain.PostprocessWorkspace {
  let tasks = self.list_tasks(project_id)
  let outputs = self.list_outputs(project_id)
  let bindings : Array[@postprocess_domain.PostprocessImportBinding] = []
  for key in self.store.list_keys(prefix="postprocess-binding-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let binding : @postprocess_domain.PostprocessImportBinding = @json.from_json(
          value,
        )
        if outputs.any(output => output.reference == binding.output) {
          bindings.push(binding)
        }
      }
      None => ()
    }
  }
  {
    tasks,
    outputs,
    bindings,
    total_cost_cny: outputs.fold(init=0.0, (sum, value) => sum + value.cost_cny),
    publication_authority: false,
    provider_execution_authority: false,
  }
}
