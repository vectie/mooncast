///|
pub(all) struct ModelRoute {
  route_id : String
  shot_ids : Array[String]
  asset_kind : String
  provider : String
  model : String
  model_version : String
  permitted_data_class : String
  cost_ceiling_cny : Double
  fallback_route_ids : Array[String]
  retry_limit : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ModelRoutingPlan {
  reference : @project.VersionRef
  routes : Array[ModelRoute]
  total_cost_ceiling_cny : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RoutingDecision {
  plan : @project.VersionRef
  decision : String
  actor : String
  role : String
  decided_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn routing_exact_approved(
  plan : ModelRoutingPlan?,
  decisions : Array[RoutingDecision],
  project_budget_cny : Double,
) -> Bool {
  match plan {
    None => false
    Some(current) =>
      current.routes.length() > 0 &&
      current.total_cost_ceiling_cny > 0.0 &&
      current.total_cost_ceiling_cny <= project_budget_cny &&
      decisions.any(decision => {
        decision.plan == current.reference &&
        decision.decision == "approved" &&
        decision.role == "producer" &&
        decision.actor != ""
      }) &&
      decisions.any(decision => {
        decision.plan == current.reference &&
        decision.decision == "approved" &&
        decision.role == "finance" &&
        decision.actor != ""
      })
  }
}

///|
/// Validates complete, non-overlapping shot coverage and bounded route policy.
pub fn routing_plan_valid(
  plan : ModelRoutingPlan,
  graph : @project.ProjectGraph,
) -> Bool {
  if plan.reference.id == "" ||
    plan.reference.version < 1 ||
    plan.reference.digest == "" ||
    plan.routes.length() == 0 ||
    plan.total_cost_ceiling_cny <= 0.0 ||
    plan.total_cost_ceiling_cny > graph.maximum_budget_cny {
    return false
  }
  let shots = @project.flattened_shots(graph)
  let covered : Array[String] = []
  let mut ceiling = 0.0
  for route in plan.routes {
    if route.route_id == "" ||
      route.shot_ids.length() == 0 ||
      route.asset_kind == "" ||
      route.provider == "" ||
      route.model == "" ||
      route.permitted_data_class == "" ||
      route.cost_ceiling_cny < 0.0 ||
      route.retry_limit < 1 ||
      route.retry_limit > 5 {
      return false
    }
    ceiling = ceiling + route.cost_ceiling_cny
    for shot_id in route.shot_ids {
      if covered.any(id => id == shot_id) ||
        !shots.any(shot => shot.shot_id == shot_id) {
        return false
      }
      covered.push(shot_id)
    }
  }
  covered.length() == shots.length() && ceiling <= plan.total_cost_ceiling_cny
}

///|
pub fn routing_decision_valid(
  plan : ModelRoutingPlan?,
  decision : RoutingDecision,
) -> Bool {
  match plan {
    None => false
    Some(value) =>
      decision.plan == value.reference &&
      (
        decision.decision == "approved" ||
        decision.decision == "rejected" ||
        decision.decision == "revision-requested"
      ) &&
      (decision.role == "producer" || decision.role == "finance") &&
      decision.actor != "" &&
      decision.decided_at != ""
  }
}
