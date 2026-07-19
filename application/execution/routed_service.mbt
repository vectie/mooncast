///|
pub(all) struct ShotProviderAuthorization {
  shot_id : String
  http_plan : ProviderHttpPlan
  authority : ProviderAuthorityReceipt
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RoutedExecutionRecord {
  contract : String
  execution : @execution_domain.RoutedExecution
  job_ids : Array[String]
  updated_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct RoutedShotProviderInput {
  contract : String
  project_id : String
  project_revision : Int
  shot : @project.Shot
  source_assets : Array[@project.Asset]
  route : @governance.ModelRoute
  default_parameters : Json
  publication_authority : Bool
} derive(ToJson, FromJson)

///|
pub suberror RoutedApplicationError {
  RoutedPlanInvalid(String)
  RoutedExecutionNotFound(String)
  RoutedRevisionConflict(String)
  RoutedShotNotFound(String)
} derive(Debug)

///|
fn routed_key(execution_id : String) -> String {
  "routed-execution-" + execution_id + ".json"
}

///|
fn routed_identity(
  graph : @project.ProjectGraph,
  routing : @governance.ModelRoutingPlan,
) -> String {
  let digest = sha256(
    @utf8.encode(
      graph.project_id +
      ":" +
      graph.revision.to_string() +
      ":" +
      routing.reference.digest,
    ),
  )
  "routed-" + digest[7:31].to_owned()
}

///|
fn ProviderExecutionService::route_adapter(
  self : ProviderExecutionService,
  route : @governance.ModelRoute,
) -> ProviderAdapterConfig? {
  let matches = self.catalog.adapters.filter(config => {
    config.provider == route.provider &&
    config.model == route.model &&
    (
      config.capability == "video" ||
      config.capability == "video-generation" ||
      config.capability == route.asset_kind
    )
  })
  if matches.length() == 1 {
    Some(matches[0])
  } else {
    None
  }
}

///|
fn route_for_shot(
  routing : @governance.ModelRoutingPlan,
  shot_id : String,
) -> @governance.ModelRoute? {
  let matches = routing.routes.filter(route => route.shot_ids.contains(shot_id))
  if matches.length() == 1 {
    Some(matches[0])
  } else {
    None
  }
}

///|
fn source_assets_for_shot(
  graph : @project.ProjectGraph,
  shot : @project.Shot,
) -> Array[@project.Asset] {
  graph.assets.filter(asset => shot.source_asset_ids.contains(asset.asset_id))
}

///|
/// Expands one named, host-authorized routing decision into an exact provider
/// request and authority receipt for every shot. This is application
/// composition: the pure execution package still has no network authority.
pub async fn ProviderExecutionService::create_routed_from_catalog(
  self : ProviderExecutionService,
  graph : @project.ProjectGraph,
  routing : @governance.ModelRoutingPlan,
  actor_id : String,
  binding_digest : String,
  network_authority : Bool,
) -> RoutedExecutionRecord {
  if !network_authority {
    raise AuthorityDenied("network authority must be explicitly granted")
  }
  if !@governance.routing_plan_valid(routing, graph) {
    raise RoutedPlanInvalid(
      "routing plan is not valid for the current project graph",
    )
  }
  let execution_id = routed_identity(graph, routing)
  match self.load_routed_execution(execution_id) {
    Some(existing) => {
      if existing.execution.binding_digest != binding_digest ||
        existing.execution.actor_id != actor_id {
        raise RoutedPlanInvalid("routed execution identity conflicts")
      }
      return self.refresh_routed(existing)
    }
    None => ()
  }
  let authorizations : Array[ShotProviderAuthorization] = []
  for shot in @project.flattened_shots(graph) {
    let route = match route_for_shot(routing, shot.shot_id) {
      Some(value) => value
      None =>
        raise RoutedPlanInvalid("every shot needs exactly one approved route")
    }
    let config = match self.route_adapter(route) {
      Some(value) => value
      None => raise AdapterUnavailable(route.provider + ":" + route.model)
    }
    let request_id = execution_id + ":" + shot.shot_id
    let body = RoutedShotProviderInput::{
      contract: "mooncast.routed-shot-provider-input.v1",
      project_id: graph.project_id,
      project_revision: graph.revision,
      shot,
      source_assets: source_assets_for_shot(graph, shot),
      route,
      default_parameters: config.default_parameters,
      publication_authority: false,
    }.to_json()
    let plan = match
      config.request_plan(request_id, body, route.cost_ceiling_cny) {
      Some(value) => value
      None =>
        raise InvalidPlan(
          "provider catalog could not materialize the routed shot request",
        )
    }
    let granted_at = now()
    let receipt_id = "provider-authority:" +
      execution_id +
      ":" +
      shot.order.to_string()
    let receipt_core = receipt_id +
      ":" +
      actor_id +
      ":" +
      plan.plan_digest +
      ":" +
      config_digest(config) +
      ":" +
      route.cost_ceiling_cny.to_string() +
      ":" +
      granted_at
    let authority : ProviderAuthorityReceipt = {
      contract: "mooncast.provider-execution-authority.v1",
      receipt_id,
      actor_id,
      decision: "authorize",
      plan_digest: plan.plan_digest,
      config_digest: config_digest(config),
      cost_ceiling_cny: route.cost_ceiling_cny,
      max_attempts: route.retry_limit,
      network_authority: true,
      publication_authority: false,
      granted_at,
      receipt_digest: sha256(@utf8.encode(receipt_core)),
    }
    authorizations.push({ shot_id: shot.shot_id, http_plan: plan, authority })
  }
  self.create_routed_execution(
    graph, routing, actor_id, binding_digest, authorizations,
  )
}

///|
pub async fn ProviderExecutionService::create_routed_execution(
  self : ProviderExecutionService,
  graph : @project.ProjectGraph,
  routing : @governance.ModelRoutingPlan,
  actor_id : String,
  binding_digest : String,
  shots : Array[ShotProviderAuthorization],
) -> RoutedExecutionRecord {
  if !self.catalog.authority_actors.any(actor => actor == actor_id) {
    raise AuthorityDenied("named actor is not authorized")
  }
  let execution_id = routed_identity(graph, routing)
  match self.load_routed_execution(execution_id) {
    Some(existing) => {
      if existing.execution.binding_digest != binding_digest ||
        existing.execution.actor_id != actor_id {
        raise RoutedPlanInvalid("routed execution identity conflicts")
      }
      return self.refresh_routed(existing)
    }
    None => ()
  }
  let planned = @execution_domain.plan_routed_execution(
    execution_id,
    graph,
    routing,
    actor_id,
    binding_digest,
    now(),
  )
  let base = match planned.execution {
    Some(value) if planned.ok => value
    _ =>
      raise RoutedPlanInvalid(
        planned.error_code.unwrap_or("routed_plan_invalid"),
      )
  }
  let bindings : Array[@execution_domain.ShotJobBinding] = []
  let job_ids : Array[String] = []
  for binding in base.shots {
    let matches = shots.filter(item => item.shot_id == binding.shot_id)
    if matches.length() != 1 {
      raise RoutedPlanInvalid(
        "every shot needs exactly one provider authorization",
      )
    }
    let authorization = matches[0]
    if authorization.http_plan.cost_ceiling_cny != binding.cost_ceiling_cny ||
      authorization.http_plan.body
      .stringify()
      .contains("\"publication_authority\":true") {
      raise RoutedPlanInvalid(
        "shot authorization differs from route ceiling or authority",
      )
    }
    let job = self.authorize(authorization.http_plan, authorization.authority)
    bindings.push({ ..binding, job_id: job.job.job_id })
    job_ids.push(job.job.job_id)
  }
  let execution = { ..base, shots: bindings }
  let record : RoutedExecutionRecord = {
    contract: "mooncast.routed-execution-record.v1",
    execution,
    job_ids,
    updated_at: now(),
  }
  ignore(self.store.put_json(routed_key(execution_id), record.to_json()))
  record
}

///|
pub async fn ProviderExecutionService::load_routed_execution(
  self : ProviderExecutionService,
  execution_id : String,
) -> RoutedExecutionRecord? {
  match self.store.get_json(routed_key(execution_id)) {
    None => None
    Some(value) => {
      let record : RoutedExecutionRecord = @json.from_json(value) catch {
        _ => raise RoutedExecutionNotFound(execution_id)
      }
      Some(record)
    }
  }
}

///|
pub async fn ProviderExecutionService::list_routed_executions(
  self : ProviderExecutionService,
  project_id : String,
) -> Array[@execution_domain.RoutedExecution] {
  let executions : Array[@execution_domain.RoutedExecution] = []
  for key in self.store.list_keys(prefix="routed-execution-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let record : RoutedExecutionRecord = @json.from_json(value) catch {
          _ => continue
        }
        if record.execution.project_id == project_id {
          let refreshed = self.refresh_routed(record)
          executions.push(refreshed.execution)
        }
      }
      None => ()
    }
  }
  executions
}

///|
async fn ProviderExecutionService::refresh_routed(
  self : ProviderExecutionService,
  record : RoutedExecutionRecord,
) -> RoutedExecutionRecord {
  let jobs : Array[@execution_domain.ProviderExecutionJob] = []
  for job_id in record.job_ids {
    match self.load_job(job_id) {
      Some(job) => jobs.push(job.job)
      None => ()
    }
  }
  let state = @execution_domain.routed_state(jobs)
  let updated = if state == record.execution.state {
    record
  } else {
    {
      ..record,
      execution: {
        ..record.execution,
        state,
        revision: record.execution.revision + 1,
        updated_at: now(),
      },
      updated_at: now(),
    }
  }
  ignore(
    self.store.put_json(
      routed_key(updated.execution.execution_id),
      updated.to_json(),
    ),
  )
  updated
}

///|
pub async fn ProviderExecutionService::routed_action(
  self : ProviderExecutionService,
  execution_id : String,
  shot_id : String,
  action : String,
  expected_revision : Int,
  actor_id : String,
) -> RoutedExecutionRecord {
  let record = match self.load_routed_execution(execution_id) {
    Some(value) => value
    None => raise RoutedExecutionNotFound(execution_id)
  }
  if record.execution.revision != expected_revision {
    raise RoutedRevisionConflict(execution_id)
  }
  let matches = record.execution.shots.filter(item => item.shot_id == shot_id)
  if matches.length() != 1 {
    raise RoutedShotNotFound(shot_id)
  }
  let binding = matches[0]
  match action {
    "execute" => ignore(self.execute(binding.job_id))
    "resume" => ignore(self.resume_job(binding.job_id))
    "cancel" => ignore(self.cancel(binding.job_id, actor_id))
    _ => raise RoutedPlanInvalid("action must be execute, resume, or cancel")
  }
  self.refresh_routed(record)
}
