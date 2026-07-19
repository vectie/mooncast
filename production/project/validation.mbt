///|
fn contains(values : Array[String], wanted : String) -> Bool {
  values.any(value => value == wanted)
}

///|
/// Accepts the canonical public project identifier shape used by the v2 API.
pub fn valid_project_id(project_id : String) -> Bool {
  if project_id.length() < 3 || project_id.length() > 64 {
    return false
  }
  for index, char in project_id {
    let valid = match char {
      'a'..='z' | '0'..='9' | '-' => true
      _ => false
    }
    if !valid || (index == 0 && char == '-') {
      return false
    }
  }
  true
}

///|
/// Returns shots in canonical graph order without exposing persistence layout.
pub fn flattened_shots(graph : ProjectGraph) -> Array[Shot] {
  let shots : Array[Shot] = []
  for episode in graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        shots.push(shot)
      }
    }
  }
  shots.sort_by((left, right) => left.order.compare(right.order))
  shots
}

///|
/// Validates saleable v1 duration and all graph references without performing IO.
pub fn validate_graph(graph : ProjectGraph) -> GraphValidation {
  let errors : Array[String] = []
  let episode_ids : Array[String] = []
  let scene_ids : Array[String] = []
  let shot_ids : Array[String] = []
  let asset_ids = graph.assets.map(asset => asset.asset_id)
  let mut scene_count = 0
  let mut shot_count = 0
  let mut planned_duration_ms = 0
  if !valid_project_id(graph.project_id) {
    errors.push("project_id_required")
  }
  if graph.target_duration_seconds < 180 || graph.target_duration_seconds > 480 {
    errors.push("target_duration_must_be_180_to_480_seconds")
  }
  if graph.maximum_budget_cny <= 0.0 {
    errors.push("positive_budget_required")
  }
  if graph.episodes.length() == 0 {
    errors.push("episode_required")
  }
  for episode in graph.episodes {
    if episode.episode_id == "" || contains(episode_ids, episode.episode_id) {
      errors.push("episode_id_missing_or_duplicate")
    } else {
      episode_ids.push(episode.episode_id)
    }
    if episode.scenes.length() == 0 {
      errors.push("scene_required")
    }
    for scene in episode.scenes {
      scene_count = scene_count + 1
      if scene.scene_id == "" || contains(scene_ids, scene.scene_id) {
        errors.push("scene_id_missing_or_duplicate")
      } else {
        scene_ids.push(scene.scene_id)
      }
      if scene.shots.length() == 0 {
        errors.push("shot_required")
      }
      for shot in scene.shots {
        shot_count = shot_count + 1
        planned_duration_ms = planned_duration_ms + shot.duration_ms
        if shot.shot_id == "" || contains(shot_ids, shot.shot_id) {
          errors.push("shot_id_missing_or_duplicate")
        } else {
          shot_ids.push(shot.shot_id)
        }
        if shot.duration_ms <= 0 {
          errors.push("shot_duration_must_be_positive")
        }
        for asset_id in shot.source_asset_ids {
          if !contains(asset_ids, asset_id) {
            errors.push("shot_asset_reference_missing")
          }
        }
      }
    }
  }
  if planned_duration_ms != graph.target_duration_seconds * 1000 {
    errors.push("shot_duration_total_must_match_project_target")
  }
  {
    valid: errors.length() == 0,
    errors,
    episode_count: graph.episodes.length(),
    scene_count,
    shot_count,
    planned_duration_ms,
  }
}
