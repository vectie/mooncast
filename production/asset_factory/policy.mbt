///|
fn sha256_text(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn digest_valid(value : String) -> Bool {
  value.has_prefix("sha256:") && value.length() == 71
}

///|
pub fn supported_capability(value : String) -> Bool {
  ["text", "image", "video", "voice", "music"].contains(value)
}

///|
pub fn supported_kind(value : String) -> Bool {
  [
    "character", "location", "prop", "voice", "music", "motion", "image", "text",
  ].contains(value)
}

///|
pub fn kind_capability_valid(kind : String, capability : String) -> Bool {
  match kind {
    "character" | "location" | "prop" | "image" => capability == "image"
    "voice" => capability == "voice"
    "music" => capability == "music"
    "motion" => capability == "video"
    "text" => capability == "text"
    _ => false
  }
}

///|
pub fn plan_digest(plan : AssetFactoryPlan) -> String {
  sha256_text({ ..plan, plan: { ..plan.plan, digest: "" } }.to_json().stringify())
}

///|
pub fn plan_errors(
  plan : AssetFactoryPlan,
  graph : @project.ProjectGraph,
  project_revision : Int,
) -> Array[String] {
  let errors : Array[String] = []
  if plan.contract != "mooncast.asset-factory-plan.v1" ||
    plan.project_id != graph.project_id ||
    plan.project_revision != project_revision ||
    plan.plan.id == "" ||
    plan.plan.version < 1 ||
    plan.created_at == "" ||
    plan.publication_authority ||
    plan.provider_execution_authority {
    errors.push("plan identity, project binding, time, and authority boundary are invalid")
  }
  if plan.specs.is_empty() {
    errors.push("at least one reusable asset spec is required")
  }
  let shot_ids = @project.flattened_shots(graph).map(shot => shot.shot_id)
  let mut total = 0.0
  for index, spec in plan.specs {
    total = total + spec.cost_ceiling_cny * spec.variant_limit.to_double()
    if spec.asset_id == "" || spec.asset_version < 1 ||
      !supported_kind(spec.kind) ||
      !supported_capability(spec.capability) ||
      !kind_capability_valid(spec.kind, spec.capability) ||
      spec.title == "" ||
      spec.intent.source_id == "" ||
      spec.intent.source_version == "" ||
      !digest_valid(spec.intent.source_digest) ||
      spec.intent.provenance_ref == "" ||
      !digest_valid(spec.prompt_digest) ||
      spec.rights_refs.is_empty() ||
      spec.continuity_key == "" ||
      spec.provider_adapter_id == "" ||
      spec.provider == "" ||
      spec.model == "" ||
      spec.permitted_data_class == "" ||
      spec.variant_limit < 1 ||
      spec.variant_limit > 4 ||
      spec.retry_limit < 1 ||
      spec.retry_limit > 5 ||
      spec.cost_ceiling_cny < 0.0 ||
      spec.dependent_shot_ids.is_empty() ||
      spec.dependent_shot_ids.any(id => !shot_ids.contains(id)) {
      errors.push("asset spec \{index} is incomplete or outside bounded policy")
    }
    for other = index + 1; other < plan.specs.length(); other = other + 1 {
      if spec.asset_id == plan.specs[other].asset_id &&
        spec.asset_version == plan.specs[other].asset_version {
        errors.push("asset id/version pairs must be unique")
      }
    }
  }
  if total != plan.total_cost_ceiling_cny ||
    total > graph.maximum_budget_cny ||
    plan.plan.digest != plan_digest(plan) {
    errors.push("plan digest or aggregate cost ceiling is invalid")
  }
  errors
}

///|
pub fn plan_valid(
  plan : AssetFactoryPlan,
  graph : @project.ProjectGraph,
  project_revision : Int,
) -> Bool {
  plan_errors(plan, graph, project_revision).is_empty()
}

///|
pub fn required_qc_dimensions() -> Array[String] {
  ["technical", "identity", "continuity", "rights", "safety"]
}

///|
pub fn variant_passes_qc(
  variant_id : String,
  findings : ArrayView[AssetQcFinding],
) -> Bool {
  required_qc_dimensions().all(dimension => {
    let matches = findings.filter(value => {
      value.variant_id == variant_id && value.dimension == dimension
    })
    !matches.is_empty() && matches[matches.length() - 1].status == "pass"
  })
}
