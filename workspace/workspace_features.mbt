///|
pub fn specialized_lens_for(kind : ArtifactKind) -> SpecializedLens {
  match kind {
    TextArtifact => ScriptLens
    ImageArtifact => ImageCompareLens
    AudioArtifact => AudioTranscriptLens
    VideoArtifact | TimelineArtifact => TimelineLens
    ShotCollection | MediaCollection => StoryboardLens
    ReviewDecisionArtifact => ReviewLens
    DeliveryPackageArtifact => DeliveryLens
    DataArtifact | AnyArtifact => DataLens
  }
}

///|
pub fn branch_workspace_artifact(
  source : WorkspaceArtifact,
  artifact_id : String,
  digest : String,
  uri : String,
  preview_uri : String,
  run_id : String,
  node_id : String,
  created_at : String,
) -> WorkspaceArtifact raise WorkspaceError {
  guard artifact_id != source.artifact_id &&
    !artifact_id.is_blank() &&
    digest.has_prefix("sha256:") &&
    !uri.is_blank() &&
    !run_id.is_blank() &&
    !node_id.is_blank() else {
    raise InvalidTransition(
      "artifact branch requires a new identity, digest, source, run, and node",
    )
  }
  {
    ..source,
    contract: "mooncast.workspace-artifact.v2",
    artifact_id,
    version: 1,
    digest,
    uri,
    preview_uri,
    parent_digests: source.parent_digests + [source.digest],
    run_id,
    node_id,
    annotations: [],
    created_at,
  }
}

///|
pub fn capsule_from_graph(
  graph : WorkspaceGraph,
  catalog : Array[NodeDefinition],
  capsule_id : String,
  title : String,
  summary : String,
  created_by : String,
  created_at : String,
) -> CreativeCapsule raise WorkspaceError {
  let validation = validate_graph(graph, catalog)
  guard validation.valid &&
    !capsule_id.is_blank() &&
    !title.is_blank() &&
    !created_by.is_blank() else {
    raise InvalidGraph(
      validation.errors + ["capsule identity, title, and actor are required"],
    )
  }
  let public_inputs : Array[CapsulePort] = []
  let public_outputs : Array[CapsulePort] = []
  let exposed_parameters : Array[CapsuleParameter] = []
  for node in graph.nodes {
    guard catalog
      .iter()
      .find_first(value => value.definition_id == node.definition_id)
      is Some(definition) else {
      raise UnknownNode(node.node_id)
    }
    if definition.node_kind == InputNode {
      for port in definition.outputs {
        public_inputs.push({
          port_id: node.node_id + "-" + port.port_id,
          node_id: node.node_id,
          node_port_id: port.port_id,
          label: node.title + " · " + port.label,
          artifact_kind: port.artifact_kind,
        })
      }
    }
    if graph.output_node_ids.contains(node.node_id) {
      for port in definition.outputs {
        public_outputs.push({
          port_id: node.node_id + "-" + port.port_id,
          node_id: node.node_id,
          node_port_id: port.port_id,
          label: node.title + " · " + port.label,
          artifact_kind: port.artifact_kind,
        })
      }
    }
    for parameter in node.parameters {
      exposed_parameters.push({
        parameter_id: node.node_id + "-" + parameter.key,
        node_id: node.node_id,
        node_parameter_key: parameter.key,
        label: node.title + " · " + parameter.key,
        default_value: parameter.value,
      })
    }
  }
  guard !public_inputs.is_empty() && !public_outputs.is_empty() else {
    raise InvalidTransition(
      "capsule requires at least one public input and output",
    )
  }
  {
    contract: "mooncast.creative-capsule.v1",
    capsule_id,
    version: 1,
    title,
    summary,
    graph,
    public_inputs,
    public_outputs,
    exposed_parameters,
    policy_constraints: [
      "Frozen graph validation is required", "Publication authority is never implied",
    ],
    provider_constraints: [],
    example_asset_refs: [],
    thumbnail_uri: "",
    minimum_mooncast_version: "0.2.3",
    created_by,
    created_at,
  }
}

///|
pub fn compare_artifacts(
  project_id : String,
  artifacts : Array[WorkspaceArtifact],
  baseline_artifact_id : String,
) -> ArtifactComparison raise WorkspaceError {
  guard !project_id.is_blank() && artifacts.length() >= 2 else {
    raise InvalidTransition(
      "artifact comparison requires a project and two variants",
    )
  }
  guard artifacts.any(value => value.artifact_id == baseline_artifact_id) else {
    raise InvalidTransition(
      "artifact comparison baseline is not in the selection",
    )
  }
  let kinds = artifacts.map(value => value.kind)
  let comparable = kinds.all(value => value == kinds[0])
  let differences : Array[String] = []
  if !comparable {
    differences.push("artifact-kind")
  }
  if artifacts.any(value => value.provider != artifacts[0].provider) {
    differences.push("provider")
  }
  if artifacts.any(value => value.model != artifacts[0].model) {
    differences.push("model")
  }
  if artifacts.any(value => {
      value.duration_seconds != artifacts[0].duration_seconds
    }) {
    differences.push("duration")
  }
  if artifacts.any(value => value.qc_state != artifacts[0].qc_state) {
    differences.push("qc-state")
  }
  if artifacts.any(value => value.rights_state != artifacts[0].rights_state) {
    differences.push("rights-state")
  }
  {
    contract: "mooncast.workspace-artifact-comparison.v1",
    project_id,
    artifact_ids: artifacts.map(value => value.artifact_id),
    baseline_artifact_id,
    comparable,
    differences,
  }
}

///|
pub fn promote_artifact(
  project_id : String,
  artifact : WorkspaceArtifact,
  channel : String,
  actor : String,
  note : String,
  promoted_at : String,
) -> ArtifactPromotion raise WorkspaceError {
  guard !project_id.is_blank() &&
    !channel.is_blank() &&
    !actor.is_blank() &&
    !promoted_at.is_blank() &&
    artifact.immutable else {
    raise InvalidTransition(
      "artifact promotion requires immutable provenance, actor, channel, and time",
    )
  }
  guard artifact.qc_state == "passed" && artifact.rights_state == "cleared" else {
    raise InvalidTransition(
      "only rights-cleared artifacts that passed QC can be promoted",
    )
  }
  {
    contract: "mooncast.workspace-artifact-promotion.v1",
    promotion_id: "promotion-" +
    sha256_text(
      project_id + "\u{0000}" + artifact.digest + "\u{0000}" + channel,
    )[:20].to_owned(),
    project_id,
    artifact_id: artifact.artifact_id,
    artifact_version: artifact.version,
    channel,
    actor,
    note,
    promoted_at,
    publication_authority: false,
  }
}

///|
pub fn new_workspace_comment(
  comment_id : String,
  project_id : String,
  target_kind : WorkspaceTargetKind,
  target_id : String,
  body : String,
  actor : String,
  created_at : String,
  start_tick : Int?,
  end_tick : Int?,
) -> WorkspaceComment raise WorkspaceError {
  guard !comment_id.is_blank() &&
    !project_id.is_blank() &&
    !target_id.is_blank() &&
    !body.trim().is_blank() &&
    !actor.is_blank() &&
    !created_at.is_blank() else {
    raise InvalidTransition(
      "comment identity, target, body, actor, and time are required",
    )
  }
  let start = start_tick.unwrap_or(0)
  guard start >= 0 && end_tick.unwrap_or(start) >= start else {
    raise InvalidTransition("comment time range is invalid")
  }
  {
    contract: "mooncast.workspace-comment.v1",
    comment_id,
    project_id,
    target_kind,
    target_id,
    body: body.trim().to_owned(),
    actor,
    start_tick,
    end_tick,
    created_at,
    resolved: false,
  }
}

///|
pub fn renew_workspace_presence(
  project_id : String,
  actor_id : String,
  display_name : String,
  target_kind : WorkspaceTargetKind,
  target_id : String,
  lease_expires_at : String,
  updated_at : String,
) -> WorkspacePresence raise WorkspaceError {
  guard !project_id.is_blank() &&
    !actor_id.is_blank() &&
    !display_name.is_blank() &&
    !target_id.is_blank() &&
    !lease_expires_at.is_blank() &&
    !updated_at.is_blank() else {
    raise InvalidTransition(
      "presence lease requires project, actor, target, and timestamps",
    )
  }
  {
    contract: "mooncast.workspace-presence.v1",
    project_id,
    actor_id,
    display_name,
    target_kind,
    target_id,
    lease_expires_at,
    updated_at,
  }
}

///|
pub fn create_workspace_share(
  share_id : String,
  project_id : String,
  target_kind : WorkspaceTargetKind,
  target_id : String,
  mode : String,
  token : String,
  expires_at : String,
  created_by : String,
  created_at : String,
) -> WorkspaceShare raise WorkspaceError {
  guard !share_id.is_blank() &&
    !project_id.is_blank() &&
    !target_id.is_blank() &&
    (mode == "read-only" || mode == "client-review") &&
    token.length() >= 16 &&
    !expires_at.is_blank() &&
    !created_by.is_blank() else {
    raise InvalidTransition(
      "share requires a target, read-only mode, strong token, expiry, and actor",
    )
  }
  {
    contract: "mooncast.workspace-share.v1",
    share_id,
    project_id,
    target_kind,
    target_id,
    mode,
    token_digest: sha256_text(token),
    expires_at,
    created_by,
    created_at,
    revoked: false,
    publication_authority: false,
  }
}

///|
pub fn publish_capsule(
  publication_id : String,
  capsule : CreativeCapsule,
  visibility : String,
  actor : String,
  published_at : String,
) -> CapsulePublication raise WorkspaceError {
  guard !publication_id.is_blank() &&
    (visibility == "project" || visibility == "workspace") &&
    !actor.is_blank() &&
    !published_at.is_blank() else {
    raise InvalidTransition(
      "capsule publication identity, visibility, actor, and time are required",
    )
  }
  {
    contract: "mooncast.workspace-capsule-publication.v1",
    publication_id,
    capsule,
    visibility,
    actor,
    published_at,
    immutable_digest: sha256_text(capsule.to_json().stringify()),
    publication_authority: false,
  }
}

///|
pub fn prepare_workspace_dispatch(
  run : RunRecord,
  node_id : String,
  input_refs : Array[String],
  created_at : String,
) -> WorkspaceDispatch raise WorkspaceError {
  guard run.nodes.any(node => node.node_id == node_id && node.state == Ready) else {
    raise InvalidTransition("only a ready workspace node can be dispatched")
  }
  guard run.plan.nodes.iter().find_first(node => node.node_id == node_id)
    is Some(planned) else {
    raise UnknownNode(node_id)
  }
  guard planned.execution_owner != "human" else {
    raise InvalidTransition("human gates must be decided by a named reviewer")
  }
  let input_digest = "sha256:" +
    sha256_text(
      input_refs.map(value => value.to_json().stringify()).join("\u{0000}"),
    )
  let idempotency_key = "workspace-dispatch-" +
    sha256_text(run.run_id + "\u{0000}" + node_id + "\u{0000}" + input_digest)[:24].to_owned()
  {
    contract: "mooncast.workspace-dispatch.v1",
    dispatch_id: "dispatch-" + sha256_text(idempotency_key)[:20].to_owned(),
    run_id: run.run_id,
    node_id,
    execution_owner: planned.execution_owner,
    operation: planned.definition_id,
    input_digest,
    input_refs: input_refs.copy(),
    idempotency_key,
    state: PreparedDispatch,
    output_digest: "",
    output_ref: "",
    provider_receipt: Json::empty_object(),
    error_code: "",
    error_message: "",
    created_at,
    updated_at: created_at,
    publication_authority: false,
  }
}

///|
pub fn apply_dispatch_receipt(
  dispatch : WorkspaceDispatch,
  receipt : WorkspaceDispatchReceipt,
) -> WorkspaceDispatch raise WorkspaceError {
  guard dispatch.dispatch_id == receipt.dispatch_id &&
    dispatch.idempotency_key == receipt.idempotency_key else {
    raise InvalidTransition(
      "dispatch receipt identity does not match prepared work",
    )
  }
  guard dispatch.state == PreparedDispatch || dispatch.state == AcceptedDispatch else {
    raise InvalidTransition("terminal workspace dispatch cannot be changed")
  }
  guard receipt.state != PreparedDispatch else {
    raise InvalidTransition(
      "a provider receipt cannot move dispatch back to prepared",
    )
  }
  guard receipt.state != SucceededDispatch ||
    (
      receipt.output_digest.has_prefix("sha256:") &&
      !receipt.output_ref.is_blank()
    ) else {
    raise InvalidTransition(
      "successful dispatch receipt requires content-addressed output",
    )
  }
  {
    ..dispatch,
    state: receipt.state,
    output_digest: receipt.output_digest,
    output_ref: receipt.output_ref,
    provider_receipt: receipt.provider_receipt,
    error_code: receipt.error_code,
    error_message: receipt.error_message,
    updated_at: receipt.recorded_at,
  }
}

///|
pub fn workspace_run_event(
  run : RunRecord,
  recorded_at : String,
) -> WorkspaceRunEvent {
  {
    contract: "mooncast.workspace-run-event.v1",
    event_id: "event-" +
    sha256_text(run.run_id + "\u{0000}" + run.updated_at)[:20].to_owned(),
    event_name: "workspace-run-snapshot",
    run_id: run.run_id,
    run,
    recorded_at,
  }
}

///|
pub fn workspace_sse(event : WorkspaceRunEvent) -> String {
  "retry: 1000\n" +
  "id: " +
  event.event_id +
  "\n" +
  "event: " +
  event.event_name +
  "\n" +
  "data: " +
  event.to_json().stringify() +
  "\n\n"
}
