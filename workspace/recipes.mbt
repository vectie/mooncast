///|
fn recipe_node(
  node_id : String,
  definition_id : String,
  title : String,
  x : Int,
) -> WorkflowNode {
  { node_id, definition_id, title, x, y: 120, parameters: [], collapsed: false }
}

///|
fn recipe_edge(
  edge_id : String,
  source : String,
  source_port : String,
  target : String,
  target_port : String,
) -> WorkflowEdge {
  {
    edge_id,
    source_node_id: source,
    source_port_id: source_port,
    target_node_id: target,
    target_port_id: target_port,
  }
}

///|
/// The first executable workspace recipe reuses the editor's governed concat
/// operation while making every stage inspectable on the canvas.
pub fn combine_videos_capsule(
  project_id : String,
  created_by : String,
  created_at : String,
) -> CreativeCapsule {
  let graph : WorkspaceGraph = {
    contract: "mooncast.workspace-graph.v1",
    graph_id: "combine-videos",
    project_id,
    revision: 1,
    title: "Combine videos",
    nodes: [
      recipe_node("intake", "workspace.folder-intake", "Choose videos", 40),
      recipe_node("probe", "workspace.media-probe", "Probe media", 280),
      recipe_node(
        "normalize", "workspace.media-normalize", "Normalize streams", 520,
      ),
      recipe_node("concat", "workspace.media-concat", "Concatenate", 760),
      recipe_node("verify", "workspace.media-verify", "Verify output", 1000),
      recipe_node(
        "register", "workspace.artifact-register", "Register asset", 1240,
      ),
    ],
    edges: [
      recipe_edge("e-intake-probe", "intake", "media", "probe", "media"),
      recipe_edge("e-probe-normalize", "probe", "probed", "normalize", "media"),
      recipe_edge(
        "e-normalize-concat", "normalize", "normalized", "concat", "media",
      ),
      recipe_edge("e-concat-verify", "concat", "video", "verify", "video"),
      recipe_edge(
        "e-verify-register", "verify", "verified", "register", "artifact",
      ),
    ],
    output_node_ids: ["register"],
    created_by,
    created_at,
  }
  {
    contract: "mooncast.creative-capsule.v1",
    capsule_id: "combine-videos",
    version: 1,
    title: "Combine videos",
    summary: "Import, inspect, normalize, concatenate, verify, and register ordered local videos.",
    graph,
    public_inputs: [
      {
        port_id: "videos",
        node_id: "intake",
        node_port_id: "media",
        label: "Local videos",
        artifact_kind: MediaCollection,
      },
    ],
    public_outputs: [
      {
        port_id: "combined-video",
        node_id: "register",
        node_port_id: "registered",
        label: "Combined video",
        artifact_kind: VideoArtifact,
      },
    ],
    exposed_parameters: [],
    policy_constraints: [
      "Input bytes must be digest-pinned before execution", "No publication authority is granted",
      "The output must pass media verification before registration",
    ],
    provider_constraints: ["Local ffmpeg and ffprobe only"],
    example_asset_refs: [],
    thumbnail_uri: "",
    minimum_mooncast_version: "0.2.3",
    created_by,
    created_at,
  }
}

///|
/// A provider-backed content recipe assembled entirely from the pack manifest.
/// External generation and every human decision remain visible graph nodes.
pub fn brief_to_delivery_capsule(
  project_id : String,
  created_by : String,
  created_at : String,
) -> CreativeCapsule {
  let graph : WorkspaceGraph = {
    contract: "mooncast.workspace-graph.v1",
    graph_id: "brief-to-generated-delivery",
    project_id,
    revision: 1,
    title: "Brief to generated delivery",
    nodes: [
      recipe_node("brief", "workspace.brief-input", "Creative brief", 40),
      recipe_node("validate", "tool:brief.validate", "Validate brief", 280),
      recipe_node("project", "tool:project.create", "Create project", 520),
      recipe_node("generate", "tool:shots.generate", "Generate shots", 760),
      recipe_node("review", "tool:asset.review", "Human asset review", 1000),
      recipe_node("delivery", "tool:delivery.package", "Package delivery", 1240),
    ],
    edges: [
      recipe_edge("e-brief-validate", "brief", "brief", "validate", "input"),
      recipe_edge(
        "e-validate-project", "validate", "output", "project", "input",
      ),
      recipe_edge(
        "e-project-generate", "project", "output", "generate", "input",
      ),
      recipe_edge("e-generate-review", "generate", "output", "review", "input"),
      recipe_edge("e-review-delivery", "review", "output", "delivery", "input"),
    ],
    output_node_ids: ["delivery"],
    created_by,
    created_at,
  }
  {
    contract: "mooncast.creative-capsule.v1",
    capsule_id: "brief-to-generated-delivery",
    version: 1,
    title: "Brief to generated delivery",
    summary: "Validate a brief, create a project, generate shots, require human review, and package the accepted result.",
    graph,
    public_inputs: [
      {
        port_id: "brief",
        node_id: "brief",
        node_port_id: "brief",
        label: "Creative brief",
        artifact_kind: TextArtifact,
      },
    ],
    public_outputs: [
      {
        port_id: "delivery",
        node_id: "delivery",
        node_port_id: "output",
        label: "Delivery package",
        artifact_kind: DeliveryPackageArtifact,
      },
    ],
    exposed_parameters: [],
    policy_constraints: [
      "Rights and provider policies are evaluated before generation", "Asset review requires a named human decision",
      "The agent cannot approve its own generated output",
    ],
    provider_constraints: [
      "Provider choice is resolved by the governed routing plan", "Secrets remain host-injected and never enter the graph",
    ],
    example_asset_refs: [],
    thumbnail_uri: "",
    minimum_mooncast_version: "0.2.3",
    created_by,
    created_at,
  }
}

///|
/// Materializes an immutable catalog capsule as a project-owned graph with a
/// fresh revision lineage.
pub fn instantiate_capsule(
  capsule : CreativeCapsule,
  graph_id : String,
  project_id : String,
  title : String,
  created_by : String,
  created_at : String,
) -> WorkspaceGraph raise WorkspaceError {
  guard !graph_id.is_blank() &&
    !project_id.is_blank() &&
    !title.is_blank() &&
    !created_by.is_blank() else {
    raise InvalidTransition(
      "capsule installation requires graph, project, title, and actor identities",
    )
  }
  {
    ..capsule.graph,
    graph_id,
    project_id,
    revision: 1,
    title,
    created_by,
    created_at,
  }
}
