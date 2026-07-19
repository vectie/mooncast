///|
pub(all) struct AnalyticsObservation {
  contract : String
  observation_id : String
  project_id : String
  source : String
  views : Int
  completion_rate : Double
  accepted_minutes : Double
  recorded_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EconomicsProjection {
  contract : String
  project_id : String
  provider_cost_cny : Double
  recognized_revenue_cny : Double
  labor_cost_cny : Double
  other_cost_cny : Double
  gross_margin_cny : Double
  cost_per_accepted_minute_cny : Double
  founder_hours : Double
  refreshed_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub async fn ProjectRepository::record_analytics(
  self : ProjectRepository,
  project_id : String,
  expected_revision : Int,
  source : String,
  views : Int,
  completion_rate : Double,
  recorded_at : String,
) -> AnalyticsObservation {
  let snapshot = self.exact_snapshot(project_id, expected_revision)
  if source.trim() == "" ||
    views < 0 ||
    completion_rate < 0.0 ||
    completion_rate > 1.0 {
    raise ProductionRevisionConflict("analytics_invalid")
  }
  let core = project_id +
    ":" +
    source +
    ":" +
    views.to_string() +
    ":" +
    completion_rate.to_string() +
    ":" +
    recorded_at
  let observation : AnalyticsObservation = {
    contract: "mooncast.analytics-observation.v1",
    observation_id: @runtime.new_id(prefix="analytics"),
    project_id,
    source,
    views,
    completion_rate,
    accepted_minutes: snapshot.graph.target_duration_seconds.to_double() / 60.0,
    recorded_at,
    digest: content_digest(core),
  }
  ignore(
    self.store.put_json(
      "analytics-" + project_id + "-" + observation.observation_id + ".json",
      observation.to_json(),
    ),
  )
  let invalidated = @kernel.invalidate_from_gate(snapshot, "G7")
  ignore(
    self.store.put_json(
      project_key(project_id),
      { ..invalidated, revision: snapshot.revision + 1 }.to_json(),
    ),
  )
  observation
}

///|
pub async fn ProjectRepository::analytics(
  self : ProjectRepository,
  project_id : String,
) -> Array[AnalyticsObservation] {
  let observations : Array[AnalyticsObservation] = []
  for
    key in self.store.list_keys(
      prefix="analytics-" + project_id + "-",
      suffix=".json",
    ) {
    match self.store.get_json(key) {
      None => ()
      Some(value) => {
        let observation : AnalyticsObservation = @json.from_json(value) catch {
          _ => continue
        }
        observations.push(observation)
      }
    }
  }
  observations
}

///|
pub async fn ProjectRepository::refresh_economics(
  self : ProjectRepository,
  project_id : String,
  recognized_revenue_cny : Double,
  labor_cost_cny : Double,
  other_cost_cny : Double,
  founder_hours : Double,
  refreshed_at : String,
) -> EconomicsProjection {
  let snapshot = match self.get(project_id) {
    None => raise ProductionProjectNotFound(project_id)
    Some(value) => value
  }
  if recognized_revenue_cny < 0.0 ||
    labor_cost_cny < 0.0 ||
    other_cost_cny < 0.0 ||
    founder_hours < 0.0 {
    raise ProductionRevisionConflict("economics_invalid")
  }
  let mut provider_cost = 0.0
  for attempt in snapshot.generation_attempts {
    if attempt.status == "succeeded" {
      provider_cost = provider_cost + attempt.cost_cny
    }
  }
  let gross = recognized_revenue_cny -
    provider_cost -
    labor_cost_cny -
    other_cost_cny
  let accepted_minutes = snapshot.graph.target_duration_seconds.to_double() /
    60.0
  let core = project_id +
    ":" +
    provider_cost.to_string() +
    ":" +
    recognized_revenue_cny.to_string() +
    ":" +
    gross.to_string() +
    ":" +
    refreshed_at
  let projection : EconomicsProjection = {
    contract: "mooncast.economics-projection.v1",
    project_id,
    provider_cost_cny: provider_cost,
    recognized_revenue_cny,
    labor_cost_cny,
    other_cost_cny,
    gross_margin_cny: gross,
    cost_per_accepted_minute_cny: provider_cost / accepted_minutes,
    founder_hours,
    refreshed_at,
    digest: content_digest(core),
  }
  ignore(
    self.store.put_json(
      "economics-" + project_id + ".json",
      projection.to_json(),
    ),
  )
  projection
}

///|
pub async fn ProjectRepository::economics(
  self : ProjectRepository,
  project_id : String,
) -> EconomicsProjection? {
  match self.store.get_json("economics-" + project_id + ".json") {
    None => None
    Some(value) => {
      let projection : EconomicsProjection = @json.from_json(value) catch {
        _ => raise ProductionProjectNotFound(project_id)
      }
      Some(projection)
    }
  }
}
