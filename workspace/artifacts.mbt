///|
pub fn new_workspace_artifact(
  artifact_id : String,
  version : Int,
  project_id : String,
  kind : ArtifactKind,
  digest : String,
  uri : String,
  preview_uri : String,
  parent_digests : Array[String],
  graph_id : String,
  run_id : String,
  node_id : String,
  prompt_digest : String,
  provider : String,
  model : String,
  provider_receipt : Json,
  rights_state : String,
  qc_state : String,
  qc_results : Array[String],
  cost_cny : Double,
  duration_seconds : Double,
  created_at : String,
) -> WorkspaceArtifact raise WorkspaceError {
  guard !artifact_id.is_blank() &&
    !project_id.is_blank() &&
    version > 0 &&
    digest.has_prefix("sha256:") &&
    !uri.is_blank() &&
    !graph_id.is_blank() &&
    !run_id.is_blank() &&
    !node_id.is_blank() else {
    raise InvalidTransition("artifact identity and provenance are required")
  }
  {
    contract: "mooncast.workspace-artifact.v2",
    artifact_id,
    version,
    project_id,
    kind,
    digest,
    uri,
    preview_uri,
    parent_digests: parent_digests.copy(),
    graph_id,
    run_id,
    node_id,
    prompt_digest,
    provider,
    model,
    provider_receipt,
    rights_state,
    qc_state,
    qc_results: qc_results.copy(),
    cost_cny,
    duration_seconds,
    annotations: [],
    created_at,
    immutable: true,
  }
}

///|
pub fn WorkspaceArtifact::annotate(
  self : WorkspaceArtifact,
  annotation : ArtifactAnnotation,
) -> WorkspaceArtifact raise WorkspaceError {
  guard !annotation.annotation_id.is_blank() &&
    !annotation.actor.is_blank() &&
    !annotation.body.is_blank() &&
    !self.annotations.any(value => {
      value.annotation_id == annotation.annotation_id
    }) else {
    raise InvalidTransition(
      "annotation identity, actor, body, and uniqueness are required",
    )
  }
  guard annotation.start_tick.unwrap_or(0) >= 0 &&
    annotation.end_tick.unwrap_or(annotation.start_tick.unwrap_or(0)) >=
    annotation.start_tick.unwrap_or(0) else {
    raise InvalidTransition("annotation time range is invalid")
  }
  let annotations = self.annotations.copy()
  annotations.push(annotation)
  { ..self, annotations, }
}
