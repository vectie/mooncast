///|
fn artifact_kind_for_schema(schema_id : String) -> ArtifactKind {
  let value = schema_id.to_lower()
  if value.contains("delivery") || value.contains("publication") {
    DeliveryPackageArtifact
  } else if value.contains("review") ||
    value.contains("decision") ||
    value.contains("approval") ||
    value.contains("gate") {
    ReviewDecisionArtifact
  } else if value.contains("timeline") || value.contains("render-plan") {
    TimelineArtifact
  } else if value.contains("shot") || value.contains("storyboard") {
    ShotCollection
  } else if value.contains("video") ||
    value.contains("animatic") ||
    value.contains("master") {
    VideoArtifact
  } else if value.contains("audio") ||
    value.contains("voice") ||
    value.contains("music") {
    AudioArtifact
  } else if value.contains("image") {
    ImageArtifact
  } else if value.contains("brief") ||
    value.contains("script") ||
    value.contains("text") ||
    value.contains("subtitle") {
    TextArtifact
  } else {
    DataArtifact
  }
}

///|
fn display_name_for_tool(tool_id : String) -> String {
  tool_id.replace_all(old=".", new=" / ").replace_all(old="-", new=" ")
}

///|
fn category_for_tool(tool_id : String) -> String {
  match tool_id.split(".").next() {
    Some(value) => value.to_owned()
    None => "operation"
  }
}

///|
fn execution_owner_for_tool(tool : @pack.ToolDeclaration) -> String {
  match tool.authority {
    ExternalEffect | PhysicalEffect => "moonflow"
    _ => "mooncast"
  }
}

///|
/// Requiring a later review does not make an operation a human gate. Only
/// explicit decision tools pause the graph for a named human action.
fn node_kind_for_tool(tool_id : String) -> WorkspaceNodeKind {
  let value = tool_id.to_lower()
  if value.contains("review") ||
    value.contains("approve") ||
    value.contains("accept") ||
    value.contains("decide") ||
    value.contains("authorize") {
    HumanGateNode
  } else {
    OperationNode
  }
}

///|
/// Converts manifest declarations into canvas nodes. This is intentionally a
/// pure projection: the pack manifest remains the capability source of truth.
pub fn catalog_from_tools(
  tools : Array[@pack.ToolDeclaration],
) -> Array[NodeDefinition] {
  tools.map(tool => {
    definition_id: "tool:" + tool.id,
    display_name: display_name_for_tool(tool.id),
    category: category_for_tool(tool.id),
    node_kind: node_kind_for_tool(tool.id),
    tool_id: tool.id,
    inputs: [
      {
        port_id: "input",
        label: "Input",
        schema_id: tool.input_schema_id,
        artifact_kind: artifact_kind_for_schema(tool.input_schema_id),
        cardinality: One,
        required: true,
      },
    ],
    outputs: [
      {
        port_id: "output",
        label: "Output",
        schema_id: tool.output_schema_id,
        artifact_kind: artifact_kind_for_schema(tool.output_schema_id),
        cardinality: One,
        required: true,
      },
    ],
    authority: tool.authority,
    execution_owner: execution_owner_for_tool(tool),
    idempotent: tool.idempotent,
    review_required: tool.review_required,
    evidence_outputs: tool.evidence_outputs.copy(),
  })
}

///|
pub fn builtin_workspace_catalog() -> Array[NodeDefinition] {
  let operations : Array[NodeDefinition] = [
    {
      definition_id: "workspace.brief-input",
      display_name: "Creative brief",
      category: "input",
      node_kind: InputNode,
      tool_id: "workspace.brief-input",
      inputs: [],
      outputs: [
        {
          port_id: "brief",
          label: "Creative brief",
          schema_id: "creative-brief",
          artifact_kind: TextArtifact,
          cardinality: One,
          required: true,
        },
      ],
      authority: Observe,
      execution_owner: "mooncast",
      idempotent: true,
      review_required: false,
      evidence_outputs: ["workspace/intakes"],
    },
    {
      definition_id: "workspace.folder-intake",
      display_name: "Folder intake",
      category: "input",
      node_kind: InputNode,
      tool_id: "workspace.folder-intake",
      inputs: [],
      outputs: [
        {
          port_id: "media",
          label: "Selected media",
          schema_id: "workspace-media-collection",
          artifact_kind: MediaCollection,
          cardinality: Many,
          required: true,
        },
      ],
      authority: Observe,
      execution_owner: "mooncast",
      idempotent: true,
      review_required: false,
      evidence_outputs: ["workspace/intakes"],
    },
    {
      definition_id: "workspace.media-probe",
      display_name: "Probe media",
      category: "media",
      node_kind: OperationNode,
      tool_id: "workspace.media-probe",
      inputs: [
        {
          port_id: "media",
          label: "Media",
          schema_id: "workspace-media-collection",
          artifact_kind: MediaCollection,
          cardinality: Many,
          required: true,
        },
      ],
      outputs: [
        {
          port_id: "probed",
          label: "Probed media",
          schema_id: "workspace-media-collection",
          artifact_kind: MediaCollection,
          cardinality: Many,
          required: true,
        },
      ],
      authority: SandboxExecution,
      execution_owner: "mooncast",
      idempotent: true,
      review_required: false,
      evidence_outputs: ["workspace/media-probes"],
    },
    {
      definition_id: "workspace.media-normalize",
      display_name: "Normalize streams",
      category: "media",
      node_kind: OperationNode,
      tool_id: "workspace.media-normalize",
      inputs: [
        {
          port_id: "media",
          label: "Probed media",
          schema_id: "workspace-media-collection",
          artifact_kind: MediaCollection,
          cardinality: Many,
          required: true,
        },
      ],
      outputs: [
        {
          port_id: "normalized",
          label: "Normalized media",
          schema_id: "workspace-media-collection",
          artifact_kind: MediaCollection,
          cardinality: Many,
          required: true,
        },
      ],
      authority: SandboxExecution,
      execution_owner: "mooncast",
      idempotent: true,
      review_required: false,
      evidence_outputs: ["workspace/normalized-media"],
    },
    {
      definition_id: "workspace.media-concat",
      display_name: "Concatenate video",
      category: "media",
      node_kind: OperationNode,
      tool_id: "workspace.media-concat",
      inputs: [
        {
          port_id: "media",
          label: "Ordered media",
          schema_id: "workspace-media-collection",
          artifact_kind: MediaCollection,
          cardinality: Many,
          required: true,
        },
      ],
      outputs: [
        {
          port_id: "video",
          label: "Combined video",
          schema_id: "workspace-artifact",
          artifact_kind: VideoArtifact,
          cardinality: One,
          required: true,
        },
      ],
      authority: SandboxExecution,
      execution_owner: "mooncast",
      idempotent: true,
      review_required: false,
      evidence_outputs: ["workspace/runs", "workspace/artifacts"],
    },
    {
      definition_id: "workspace.media-verify",
      display_name: "Verify output",
      category: "quality",
      node_kind: OperationNode,
      tool_id: "workspace.media-verify",
      inputs: [
        {
          port_id: "video",
          label: "Video",
          schema_id: "workspace-artifact",
          artifact_kind: VideoArtifact,
          cardinality: One,
          required: true,
        },
      ],
      outputs: [
        {
          port_id: "verified",
          label: "Verified video",
          schema_id: "workspace-artifact",
          artifact_kind: VideoArtifact,
          cardinality: One,
          required: true,
        },
      ],
      authority: SandboxExecution,
      execution_owner: "mooncast",
      idempotent: true,
      review_required: false,
      evidence_outputs: ["workspace/verifications"],
    },
    {
      definition_id: "workspace.artifact-register",
      display_name: "Register artifact",
      category: "output",
      node_kind: OutputNode,
      tool_id: "workspace.artifact-register",
      inputs: [
        {
          port_id: "artifact",
          label: "Artifact",
          schema_id: "workspace-artifact",
          artifact_kind: AnyArtifact,
          cardinality: One,
          required: true,
        },
      ],
      outputs: [
        {
          port_id: "registered",
          label: "Registered asset",
          schema_id: "workspace-artifact",
          artifact_kind: AnyArtifact,
          cardinality: One,
          required: true,
        },
      ],
      authority: WorkspaceMutation,
      execution_owner: "mooncast",
      idempotent: true,
      review_required: false,
      evidence_outputs: ["workspace/artifacts"],
    },
  ]
  operations + bounded_control_catalog()
}

///|
fn control_node_definition(
  definition_id : String,
  display_name : String,
  input_cardinality : PortCardinality,
  output_kind : ArtifactKind,
  output_cardinality : PortCardinality,
  node_kind? : WorkspaceNodeKind = ControlNode,
  authority? : @pack.AuthorityClass = SandboxExecution,
  review_required? : Bool = false,
) -> NodeDefinition {
  {
    definition_id,
    display_name,
    category: "control",
    node_kind,
    tool_id: definition_id,
    inputs: [
      {
        port_id: "input",
        label: "Input",
        schema_id: "workspace-artifact",
        artifact_kind: AnyArtifact,
        cardinality: input_cardinality,
        required: true,
      },
    ],
    outputs: [
      {
        port_id: "output",
        label: "Output",
        schema_id: "workspace-artifact",
        artifact_kind: output_kind,
        cardinality: output_cardinality,
        required: true,
      },
    ],
    authority,
    execution_owner: "mooncast",
    idempotent: true,
    review_required,
    evidence_outputs: ["workspace/runs"],
  }
}

///|
/// These are deliberately finite orchestration primitives, never arbitrary
/// code nodes. Their parameters remain data in the versioned graph.
pub fn bounded_control_catalog() -> Array[NodeDefinition] {
  [
    control_node_definition(
      "workspace.control.generate-variants",
      "Generate variants",
      One,
      AnyArtifact,
      Many,
    ),
    control_node_definition(
      "workspace.control.map",
      "Map over assets",
      Many,
      AnyArtifact,
      Many,
    ),
    control_node_definition(
      "workspace.control.select",
      "Select or rank",
      Many,
      AnyArtifact,
      One,
    ),
    control_node_definition(
      "workspace.control.merge",
      "Merge assets",
      Many,
      AnyArtifact,
      One,
    ),
    control_node_definition(
      "workspace.control.policy-gate",
      "Conditional policy gate",
      One,
      AnyArtifact,
      One,
      review_required=true,
    ),
    control_node_definition(
      "workspace.control.human-approval",
      "Human approval",
      One,
      ReviewDecisionArtifact,
      One,
      node_kind=HumanGateNode,
      authority=@pack.WorkspaceMutation,
      review_required=true,
    ),
    control_node_definition(
      "workspace.control.subgraph",
      "Reusable subgraph",
      Many,
      AnyArtifact,
      Many,
      node_kind=CapsuleNode,
    ),
  ]
}

///|
pub fn complete_node_catalog(
  tools : Array[@pack.ToolDeclaration],
) -> Array[NodeDefinition] {
  let values = builtin_workspace_catalog()
  values.append(
    catalog_from_tools(
      tools.filter(tool => {
        !values.any(definition => definition.tool_id == tool.id)
      }),
    ),
  )
  values
}
