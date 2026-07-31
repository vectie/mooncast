///|
fn digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
pub fn task_digest(task : AnalyzerTask) -> String {
  digest(
    { ..task, reference: { ..task.reference, digest: "" } }
    .to_json()
    .stringify(),
  )
}

///|
pub fn technical_analyzers() -> Array[String] {
  [
    "codec", "duration", "blank-frames", "audio-level", "subtitle-timing", "safe-area",
  ]
}

///|
pub fn semantic_analyzers() -> Array[String] {
  ["flicker", "lip-sync-quality", "identity", "continuity"]
}

///|
pub fn governance_dimension(analyzer : String) -> String {
  if analyzer == "identity" || analyzer == "continuity" {
    "continuity"
  } else {
    "technical"
  }
}

///|
pub fn task_errors(task : AnalyzerTask) -> Array[String] {
  let errors : Array[String] = []
  let technical = technical_analyzers().contains(task.analyzer)
  let semantic = semantic_analyzers().contains(task.analyzer)
  if task.contract != "mooncast.qc-analyzer-task.v1" ||
    (!technical && !semantic) ||
    task.reference.id == "" ||
    task.reference.version < 1 ||
    task.reference.digest != task_digest(task) ||
    task.project_id == "" ||
    task.project_revision < 0 ||
    task.shot_id == "" ||
    task.attempt_digest == "" ||
    task.source_artifact_digest == "" ||
    task.expected_duration_ms < 1 ||
    task.duration_tolerance_ms < 0 ||
    task.permitted_data_class == "" ||
    task.rights_refs.is_empty() ||
    task.cost_ceiling_cny < 0.0 ||
    task.retry_limit < 1 ||
    task.retry_limit > 5 ||
    task.created_at == "" ||
    task.provider_execution_authority ||
    task.publication_authority {
    errors.push(
      "analyzer task identity, source, threshold, rights, budget, retry, or authority is invalid",
    )
  }
  if technical && task.execution_mode != "local-technical" {
    errors.push("technical analyzers must use the deterministic local port")
  }
  if semantic &&
    (
      task.execution_mode != "external-semantic" ||
      task.provider_adapter_id is None ||
      task.provider is None ||
      task.model is None
    ) {
    errors.push(
      "semantic analyzers require an explicit external provider route",
    )
  }
  if task.analyzer == "subtitle-timing" &&
    (task.subtitle_track_digest is None || task.subtitle_cue_count < 1) {
    errors.push("subtitle timing requires an exact subtitle track and cues")
  }
  if task.analyzer == "safe-area" &&
    (task.subtitle_safe_area_ratio < 0.0 || task.subtitle_safe_area_ratio > 1.0) {
    errors.push("subtitle safe-area ratio must be between zero and one")
  }
  if task.analyzer == "identity" && task.identity_refs.is_empty() {
    errors.push("identity analysis requires immutable identity references")
  }
  if task.analyzer == "continuity" && task.continuity_refs.is_empty() {
    errors.push(
      "continuity analysis requires immutable neighboring-shot references",
    )
  }
  errors
}
