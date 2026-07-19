///|
fn content_digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
pub(all) struct NewProductionRequest {
  project_id : String
  title : String
  objective : String
  audience : String
  rights_owner : String
  rights_confirmed : Bool
  target_duration_seconds : Int
  maximum_budget_cny : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Build the first saleable Mooncast unit: one complete episode split into
/// bounded provider shots and production-sized scenes. The episode boundary is
/// stable for later 10–60 minute formats; extending duration adds scenes and
/// shots instead of inventing synthetic episodes.
pub fn episode_production_graph(
  project_id : String,
  title : String,
  target_duration_seconds : Int,
  maximum_budget_cny : Double,
) -> @project.ProjectGraph {
  let shot_count = (target_duration_seconds + 11) / 12
  let scenes : Array[@project.Scene] = []
  let mut remaining_ms = target_duration_seconds * 1000
  let mut global_order = 1
  let scene_count = (shot_count + 4) / 5
  for scene_index = 0; scene_index < scene_count; scene_index = scene_index + 1 {
    let shots : Array[@project.Shot] = []
    let start = scene_index * 5
    let end = if start + 5 < shot_count { start + 5 } else { shot_count }
    for shot_index = start; shot_index < end; shot_index = shot_index + 1 {
      let duration_ms = if remaining_ms > 12000 { 12000 } else { remaining_ms }
      remaining_ms = remaining_ms - duration_ms
      shots.push({
        shot_id: project_id + "-shot-" + global_order.to_string(),
        order: global_order,
        duration_ms,
        character_ids: [],
        location_id: project_id + "-world",
        source_asset_ids: [],
      })
      global_order = global_order + 1
    }
    scenes.push({
      scene_id: project_id + "-scene-" + (scene_index + 1).to_string(),
      order: scene_index + 1,
      title: "Scene " + (scene_index + 1).to_string(),
      shots,
    })
  }
  {
    project_id,
    revision: 1,
    title,
    target_duration_seconds,
    maximum_budget_cny,
    episodes: [
      { episode_id: project_id + "-episode-1", order: 1, title, scenes },
    ],
    assets: [],
  }
}

///|
fn default_graph(request : NewProductionRequest) -> @project.ProjectGraph {
  episode_production_graph(
    request.project_id,
    request.title,
    request.target_duration_seconds,
    request.maximum_budget_cny,
  )
}

///|
fn creative_artifact(
  project_id : String,
  kind : @creative.ArtifactKind,
  content : String,
  dependencies : Array[String],
  duration? : Int,
  expected_cost? : Double,
  rights_cleared? : Bool = false,
) -> @creative.CreativeArtifact {
  let digest = content_digest(
    kind.to_string() + ":" + content + ":" + dependencies.join("|"),
  )
  {
    reference: { id: project_id + "-" + kind.to_string(), version: 1, digest },
    kind,
    dependency_digests: dependencies,
    duration_seconds: duration,
    expected_cost_cny: expected_cost,
    rights_cleared,
    content,
  }
}

///|
pub fn new_production_snapshot(
  request : NewProductionRequest,
) -> @kernel.ProjectSnapshot? {
  if !@project.valid_project_id(request.project_id) ||
    request.title == "" ||
    request.title.length() > 200 ||
    request.objective == "" ||
    request.objective.length() > 1000 ||
    request.audience == "" ||
    request.rights_owner == "" ||
    !request.rights_confirmed ||
    request.target_duration_seconds < 180 ||
    request.target_duration_seconds > 480 ||
    request.maximum_budget_cny <= 0.0 ||
    request.maximum_budget_cny > 5000.0 {
    return None
  }
  let graph = default_graph(request)
  let brief = creative_artifact(
    request.project_id,
    Brief,
    "objective=" +
    request.objective +
    ";audience=" +
    request.audience +
    ";title=" +
    request.title,
    [],
  )
  let rights = creative_artifact(
    request.project_id,
    RightsLedger,
    "owner=" + request.rights_owner + ";confirmed=true",
    [brief.reference.digest],
    rights_cleared=true,
  )
  let bible = creative_artifact(
    request.project_id,
    IpBible,
    "world=default;style=brand-safe",
    [brief.reference.digest, rights.reference.digest],
  )
  let script = creative_artifact(
    request.project_id,
    Script,
    request.title + " — " + request.objective,
    [bible.reference.digest],
  )
  let claims = creative_artifact(
    request.project_id,
    ClaimsLedger,
    "claims=pending-review",
    [script.reference.digest],
  )
  let storyboard = creative_artifact(
    request.project_id,
    Storyboard,
    "deterministic-shot-board",
    [script.reference.digest, claims.reference.digest],
    duration=request.target_duration_seconds,
  )
  let animatic = creative_artifact(
    request.project_id,
    Animatic,
    "timed-animatic",
    [storyboard.reference.digest],
    duration=request.target_duration_seconds,
    expected_cost=0.0,
  )
  let routes : Array[@governance.ModelRoute] = []
  for episode in graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        routes.push({
          route_id: "route-" + shot.shot_id,
          shot_ids: [shot.shot_id],
          asset_kind: "video",
          provider: "mooncast-local",
          model: "ffmpeg-lavfi-motion-v1",
          model_version: "1",
          permitted_data_class: "public-or-rights-cleared",
          cost_ceiling_cny: 0.96,
          fallback_route_ids: [],
          retry_limit: 1,
        })
      }
    }
  }
  let route_digest = content_digest(routes.to_json().stringify())
  let routing : @governance.ModelRoutingPlan = {
    reference: {
      id: request.project_id + "-model-routing",
      version: 1,
      digest: route_digest,
    },
    routes,
    total_cost_ceiling_cny: routes.length().to_double() * 0.96,
  }
  let snapshot = @kernel.empty_snapshot(graph)
  Some({
    ..snapshot,
    creative_artifacts: [
      brief, rights, bible, script, claims, storyboard, animatic,
    ],
    routing_plan: Some(routing),
  })
}

///|
pub(all) struct ProductionBreakdown {
  project_id : String
  episode_count : Int
  scene_count : Int
  shot_count : Int
  duration_seconds : Int
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn derive_production_breakdown(
  snapshot : @kernel.ProjectSnapshot,
) -> ProductionBreakdown {
  let validation = @project.validate_graph(snapshot.graph)
  {
    project_id: snapshot.graph.project_id,
    episode_count: validation.episode_count,
    scene_count: validation.scene_count,
    shot_count: validation.shot_count,
    duration_seconds: validation.planned_duration_ms / 1000,
    digest: content_digest(snapshot.graph.to_json().stringify()),
  }
}
