///|
pub(all) struct ShotJobBinding {
  shot_id : String
  route_id : String
  job_id : String
  cost_ceiling_cny : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RoutedExecution {
  contract : String
  execution_id : String
  project_id : String
  project_revision_anchor : Int
  routing_plan : @project.VersionRef
  binding_digest : String
  aggregate_cost_ceiling_cny : Double
  currency : String
  actor_id : String
  state : String
  revision : Int
  shots : Array[ShotJobBinding]
  created_at : String
  updated_at : String
  publication_authority : Bool
  record_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RoutedPlanResult {
  ok : Bool
  error_code : String?
  execution : RoutedExecution?
  external_effect_performed : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn routes_for_shot(
  plan : @governance.ModelRoutingPlan,
  shot_id : String,
) -> Array[@governance.ModelRoute] {
  plan.routes.filter(route => route.shot_ids.any(value => value == shot_id))
}

///|
/// Creates a route-bound job plan. A host must separately create/authorize jobs.
pub fn plan_routed_execution(
  execution_id : String,
  graph : @project.ProjectGraph,
  plan : @governance.ModelRoutingPlan,
  actor_id : String,
  binding_digest : String,
  created_at : String,
) -> RoutedPlanResult {
  let bindings : Array[ShotJobBinding] = []
  let mut total = 0.0
  for episode in graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        let routes = routes_for_shot(plan, shot.shot_id)
        if routes.length() != 1 || routes[0].asset_kind != "video" {
          return {
            ok: false,
            error_code: Some("routed_plan_ambiguous"),
            execution: None,
            external_effect_performed: false,
            publication_authority: false,
          }
        }
        let route = routes[0]
        total = total + route.cost_ceiling_cny
        bindings.push({
          shot_id: shot.shot_id,
          route_id: route.route_id,
          job_id: "",
          cost_ceiling_cny: route.cost_ceiling_cny,
        })
      }
    }
  }
  if total > plan.total_cost_ceiling_cny {
    return {
      ok: false,
      error_code: Some("routed_cost_ceiling_exceeded"),
      execution: None,
      external_effect_performed: false,
      publication_authority: false,
    }
  }
  {
    ok: true,
    error_code: None,
    execution: Some({
      contract: "mooncast.routed-execution.v1",
      execution_id,
      project_id: graph.project_id,
      project_revision_anchor: graph.revision,
      routing_plan: plan.reference,
      binding_digest,
      aggregate_cost_ceiling_cny: total,
      currency: "CNY",
      actor_id,
      state: "ready",
      revision: 1,
      shots: bindings,
      created_at,
      updated_at: created_at,
      publication_authority: false,
      record_digest: binding_digest,
    }),
    external_effect_performed: false,
    publication_authority: false,
  }
}

///|
pub fn routed_state(jobs : Array[ProviderExecutionJob]) -> String {
  if jobs.length() == 0 {
    return "ready"
  }
  if jobs.all(job => job.state == "completed") {
    return "completed"
  }
  if jobs.all(job => job.state == "cancelled") {
    return "cancelled"
  }
  if jobs.any(job => job.state == "running" || job.state == "cancel_requested") {
    return "running"
  }
  if jobs.any(job => {
      job.state == "failed" ||
      job.state == "cost_ceiling_exceeded" ||
      job.state == "ingest_failed"
    }) {
    return "attention-required"
  }
  "ready"
}
