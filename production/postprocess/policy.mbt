///|
fn digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
pub fn task_digest(task : PostprocessTask) -> String {
  digest({ ..task, reference: { ..task.reference, digest: "" } }.to_json().stringify())
}

///|
pub fn task_errors(task : PostprocessTask, graph : @project.ProjectGraph) -> Array[String] {
  let errors : Array[String] = []
  if task.contract != "mooncast.postprocess-task.v1" ||
    !["lip-sync", "translation", "upscale"].contains(task.operation) ||
    task.project_id != graph.project_id || task.reference.id == "" ||
    task.reference.version < 1 || task.reference.digest != task_digest(task) ||
    task.source_assets.is_empty() ||
    task.source_assets.any(asset => !asset.immutable || asset.rights_record_id == "") ||
    task.prompt_digest == "" || task.rights_refs.is_empty() ||
    task.provider_adapter_id == "" || task.provider == "" || task.model == "" ||
    task.permitted_data_class == "" || task.cost_ceiling_cny < 0.0 ||
    task.cost_ceiling_cny > graph.maximum_budget_cny ||
    task.retry_limit < 1 || task.retry_limit > 5 || task.created_at == "" ||
    task.provider_execution_authority || task.publication_authority {
    errors.push("task identity, exact sources, provider, budget, retry, or authority is invalid")
  }
  let shot_ids = @project.flattened_shots(graph).map(shot => shot.shot_id)
  if task.shot_ids.any(id => !shot_ids.contains(id)) {
    errors.push("task references a shot outside the current graph")
  }
  match task.operation {
    "lip-sync" =>
      if task.shot_ids.is_empty() ||
        !task.source_assets.any(asset => asset.kind == "voice") ||
        !task.source_assets.any(asset => asset.kind == "character" || asset.kind == "video") {
        errors.push("lip-sync requires shot, exact voice, and character/video sources")
      }
    "translation" =>
      if task.target_locale is None || task.terminology_refs.is_empty() ||
        task.claims_ledger_digest is None {
        errors.push("translation requires locale, terminology, and claims lineage")
      }
    "upscale" =>
      if task.target_width.unwrap_or(0) < 640 ||
        task.target_height.unwrap_or(0) < 360 {
        errors.push("upscale requires an explicit target resolution")
      }
    _ => ()
  }
  errors
}
