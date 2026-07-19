///|
pub(all) struct RoutedIngestResult {
  contract : String
  execution : @execution.RoutedExecution
  project_result : @kernel.CommandResult?
  provider_artifact_ingested : Bool
  external_effect_performed_by_pipeline : Bool
  publication_effect_performed : Bool
} derive(Debug, ToJson)

///|
pub suberror PipelineApplicationError {
  PipelineProjectNotFound(String)
  PipelineRoutingConflict(String)
  PipelineProviderJobMissing(String)
} derive(Debug)

///|
pub struct ProductionPipelineService {
  projects : @production_app.ProjectRepository
  providers : @execution_app.ProviderExecutionService
}

///|
pub fn ProductionPipelineService::new(
  projects : @production_app.ProjectRepository,
  providers : @execution_app.ProviderExecutionService,
) -> ProductionPipelineService {
  { projects, providers }
}

///|
fn shot_for(graph : @project.ProjectGraph, shot_id : String) -> @project.Shot? {
  for shot in @project.flattened_shots(graph) {
    if shot.shot_id == shot_id {
      return Some(shot)
    }
  }
  None
}

///|
pub async fn ProductionPipelineService::routed_action_and_ingest(
  self : ProductionPipelineService,
  project_id : String,
  execution_id : String,
  shot_id : String,
  action : String,
  expected_execution_revision : Int,
  actor_id : String,
) -> RoutedIngestResult {
  let routed = self.providers.routed_action(
    execution_id, shot_id, action, expected_execution_revision, actor_id,
  )
  let snapshot = match self.projects.get(project_id) {
    None => raise PipelineProjectNotFound(project_id)
    Some(value) => value
  }
  let routing = match snapshot.routing_plan {
    None => raise PipelineRoutingConflict("current routing plan is absent")
    Some(value) => value
  }
  if routed.execution.project_id != project_id ||
    routed.execution.routing_plan != routing.reference {
    raise PipelineRoutingConflict(
      "routed execution no longer binds the current routing plan",
    )
  }
  let bindings = routed.execution.shots.filter(binding => {
    binding.shot_id == shot_id
  })
  if bindings.length() != 1 {
    raise PipelineRoutingConflict("shot binding is absent")
  }
  let provider_record = match self.providers.load_job(bindings[0].job_id) {
    None => raise PipelineProviderJobMissing(bindings[0].job_id)
    Some(value) => value
  }
  if provider_record.job.state != "completed" ||
    provider_record.job.artifacts.length() == 0 {
    return {
      contract: "mooncast.routed-ingest-result.v1",
      execution: routed.execution,
      project_result: None,
      provider_artifact_ingested: false,
      external_effect_performed_by_pipeline: false,
      publication_effect_performed: false,
    }
  }
  let attempt_id = provider_record.job.job_id +
    "-attempt-" +
    provider_record.job.attempt_count.to_string()
  if snapshot.generation_attempts.any(attempt => {
      attempt.attempt.id == attempt_id
    }) {
    return {
      contract: "mooncast.routed-ingest-result.v1",
      execution: routed.execution,
      project_result: None,
      provider_artifact_ingested: true,
      external_effect_performed_by_pipeline: false,
      publication_effect_performed: false,
    }
  }
  let shot = match shot_for(snapshot.graph, shot_id) {
    None => raise PipelineRoutingConflict("shot no longer exists")
    Some(value) => value
  }
  let source_digests : Array[String] = []
  for asset_id in shot.source_asset_ids {
    for asset in snapshot.graph.assets {
      if asset.asset_id == asset_id {
        source_digests.push(asset.digest)
      }
    }
  }
  let output_digest = provider_record.job.artifacts[0].artifact_digest
  let attempt : @governance.GenerationAttempt = {
    attempt: {
      id: attempt_id,
      version: provider_record.job.attempt_count,
      digest: provider_record.job.binding_digest,
    },
    shot_id,
    route_id: bindings[0].route_id,
    route_plan: routing.reference,
    prompt_digest: provider_record.job.plan.input_digest,
    source_asset_digests: source_digests,
    seed: None,
    duration_ms: shot.duration_ms,
    cost_cny: provider_record.job.spent_cny,
    output_digest,
    status: "succeeded",
  }
  let context : @production_app.ProjectActionContext = {
    command_id: @runtime.new_id(prefix="provider-ingest"),
    expected_revision: snapshot.revision,
    recorded_at: provider_record.updated_at,
    evidence_digest: output_digest,
    actor: Some(actor_id),
    role: Some("provider-execution-host"),
  }
  let project_result = self.projects.append_generation_attempt(
    project_id, context, attempt,
  )
  ignore(
    self.providers.record_project_ingest(
      provider_record.job.job_id,
      output_digest,
    ),
  )
  {
    contract: "mooncast.routed-ingest-result.v1",
    execution: routed.execution,
    project_result: Some(project_result),
    provider_artifact_ingested: true,
    external_effect_performed_by_pipeline: false,
    publication_effect_performed: false,
  }
}
