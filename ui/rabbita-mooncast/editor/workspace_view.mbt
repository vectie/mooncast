///|
struct WorkspaceNodeView {
  node_id : String
  definition_id : String
  title : String
  detail : String
  owner : String
  authority : String
  inputs : Array[WorkspacePortSummary]
  outputs : Array[WorkspacePortSummary]
  collapsed : Bool
}

///|
fn workspace_nodes(recipe : WorkspaceRecipe) -> Array[WorkspaceNodeView] {
  match recipe {
    CombineVideosRecipe =>
      [
        {
          node_id: "intake",
          definition_id: "workspace.folder-intake",
          title: "Folder intake",
          detail: "Digest-pin ordered local videos",
          owner: "Mooncast",
          authority: "Workspace mutation",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "probe",
          definition_id: "workspace.media-probe",
          title: "Probe media",
          detail: "Inspect streams, codecs and duration",
          owner: "Mooncast",
          authority: "Sandbox execution",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "normalize",
          definition_id: "workspace.media-normalize",
          title: "Normalize streams",
          detail: "Reconcile incompatible media safely",
          owner: "Mooncast",
          authority: "Sandbox execution",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "concat",
          definition_id: "workspace.media-concat",
          title: "Concatenate video",
          detail: "Assemble sources in frozen order",
          owner: "Mooncast",
          authority: "Sandbox execution",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "verify",
          definition_id: "workspace.media-verify",
          title: "Verify output",
          detail: "Probe the final output and receipt",
          owner: "Mooncast",
          authority: "Sandbox execution",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "register",
          definition_id: "workspace.artifact-register",
          title: "Register artifact",
          detail: "Save immutable lineage and preview",
          owner: "Mooncast",
          authority: "Workspace mutation",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
      ]
    BriefToDeliveryRecipe =>
      [
        {
          node_id: "brief",
          definition_id: "workspace.brief-input",
          title: "Creative brief",
          detail: "Define outcome, audience and constraints",
          owner: "Mooncast",
          authority: "Observe",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "validate",
          definition_id: "tool:brief.validate",
          title: "Validate brief",
          detail: "Check the governed creative contract",
          owner: "Mooncast",
          authority: "Sandbox execution",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "project",
          definition_id: "tool:project.create",
          title: "Create project",
          detail: "Materialize a versioned production graph",
          owner: "Mooncast",
          authority: "Workspace mutation",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "generate",
          definition_id: "tool:shots.generate",
          title: "Generate shots",
          detail: "Dispatch provider work with receipts",
          owner: "MoonFlow",
          authority: "External effect",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "review",
          definition_id: "tool:asset.review",
          title: "Human asset review",
          detail: "A named reviewer accepts or rejects",
          owner: "Human",
          authority: "Human gate",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
        {
          node_id: "delivery",
          definition_id: "tool:delivery.package",
          title: "Package delivery",
          detail: "Assemble only accepted artifacts",
          owner: "Mooncast",
          authority: "Sandbox execution",
          inputs: [],
          outputs: [],
          collapsed: false,
        },
      ]
  }
}

///|
fn selected_workspace_node(model : Model) -> WorkspaceNodeView {
  let nodes = visible_workspace_nodes(model)
  match
    nodes
    .iter()
    .find_first(node => node.node_id == model.selected_workspace_node) {
    Some(node) => node
    None =>
      nodes
      .get(0)
      .unwrap_or({
        node_id: "",
        definition_id: "",
        title: "No node selected",
        detail: "Add a manifest-backed node from the palette.",
        owner: "none",
        authority: "None",
        inputs: [],
        outputs: [],
        collapsed: false,
      })
  }
}

///|
fn workspace_node_position(
  model : Model,
  node_id : String,
) -> WorkspaceNodePosition {
  if workspace_graph_node(model, node_id) is Some(node) {
    return { x: node.x, y: node.y }
  }
  { x: 40, y: 80 }
}

///|
fn workspace_node_state(model : Model, node_id : String) -> String {
  let utility_is_active = model.selected_workspace_recipe == CombineVideosRecipe &&
    model.utility_concat.phase != "idle" &&
    model.utility_concat.phase != "selected"
  if !utility_is_active &&
    model.workspace_run_nodes.iter().find_first(node => node.node_id == node_id)
    is Some(node) {
    return match node.state {
      Blocked => "blocked"
      Ready => "ready"
      Running => "running"
      Cached => "cached"
      Succeeded => "succeeded"
      Failed => "failed"
      Cancelled => "cancelled"
    }
  }
  if workspace_graph_node(model, node_id) is Some(node) &&
    node.node_id.has_prefix("node-") {
    return "ready"
  }
  let phase = model.utility_concat.phase
  match node_id {
    "intake" =>
      if model.utility_concat.files.is_empty() {
        "ready"
      } else {
        "succeeded"
      }
    "probe" =>
      match phase {
        "hashing" | "creating" | "uploading" => "running"
        "running" | "succeeded" => "succeeded"
        "failed" => "failed"
        _ => "blocked"
      }
    "normalize" =>
      match phase {
        "running" => "running"
        "succeeded" => "succeeded"
        "failed" => "failed"
        _ => "blocked"
      }
    "concat" =>
      match phase {
        "running" => "running"
        "succeeded" => "succeeded"
        "failed" => "failed"
        _ => "blocked"
      }
    "verify" | "register" =>
      match phase {
        "succeeded" => "succeeded"
        "failed" => "failed"
        _ => "blocked"
      }
    "brief" => "ready"
    _ => "blocked"
  }
}

///|
fn workspace_recipe_rail(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let combine_class = if model.selected_workspace_recipe == CombineVideosRecipe {
    "recipe-card is-active"
  } else {
    "recipe-card"
  }
  let delivery_class = if model.selected_workspace_recipe ==
    BriefToDeliveryRecipe {
    "recipe-card is-active"
  } else {
    "recipe-card"
  }
  @html.section(class="workspace-rail") <| [
    @html.label(class="workspace-search") <| [
      @html.span("Search workspace"),
      @html.input(
        input_type=@html.Search,
        value=model.workspace_search,
        placeholder="Assets, runs, comments…",
        on_input=dispatch.map(value => WorkspaceSearchChanged(value)),
      ),
    ],
    if model.workspace_search_results.is_empty() {
      @html.nothing
    } else {
      @html.div(class="workspace-search-results") <| model.workspace_search_results.map(result => {
          @html.div(
            class="workspace-search-result",
            title="Project " + result.project_id + " · " + result.target_id,
          ) <| [
            @html.strong(result.title),
            @html.small(result.detail),
          ]
        },
      )
    },
    @html.div(class="workspace-section-heading") <| [
      @html.h2("Recipes"),
      @html.span("2 installed"),
    ],
    @html.button(
      class=combine_class,
      type_="button",
      on_click=dispatch(SelectWorkspaceRecipe(CombineVideosRecipe)),
    ) <| [
      @html.strong("Combine videos"),
      @html.span("Local · deterministic · 6 nodes"),
    ],
    @html.button(
      class=delivery_class,
      type_="button",
      on_click=dispatch(SelectWorkspaceRecipe(BriefToDeliveryRecipe)),
    ) <| [
      @html.strong("Brief to generated delivery"),
      @html.span("Provider-backed · human-gated · 6 nodes"),
    ],
    @html.div(class="workspace-section-heading") <| [
      @html.h2("Node palette"),
      @html.span("\{model.workspace_catalog.length()} governed"),
    ],
    @html.label(class="workspace-search") <| [
      @html.span("Find a tool or control"),
      @html.input(
        input_type=@html.Search,
        value=model.workspace_node_palette_search,
        placeholder="Search 97 pack capabilities…",
        on_input=dispatch.map(value => WorkspaceNodePaletteChanged(value)),
      ),
    ],
    @html.div(class="workspace-node-palette") <| workspace_palette_definitions(
      model,
    ).map(definition => {
      @html.button(
        type_="button",
        on_click=dispatch(AddWorkspaceNode(definition.definition_id)),
        title=definition.tool_id,
      ) <| [
        @html.strong(definition.display_name),
        @html.small(
          definition.category +
          " · " +
          workspace_authority_label(definition.authority),
        ),
      ]
    }),
    @html.div(class="workspace-graph-actions") <| [
      @html.button(
        type_="button",
        disabled=!model.workspace_graph_dirty || model.workspace_graph_saving,
        on_click=dispatch(SaveWorkspaceGraph("")),
        "Save revision",
      ),
      @html.button(
        type_="button",
        disabled=model.workspace_graph_undo.is_empty(),
        on_click=dispatch(WorkspaceGraphUndo),
        "Undo",
      ),
      @html.button(
        type_="button",
        disabled=model.workspace_graph_redo.is_empty(),
        on_click=dispatch(WorkspaceGraphRedo),
        "Redo",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_workspace_node.is_blank(),
        on_click=dispatch(DuplicateSelectedWorkspaceNode),
        "Duplicate",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_workspace_node.is_blank(),
        on_click=dispatch(ToggleSelectedWorkspaceNodeCollapsed),
        "Collapse",
      ),
      @html.button(
        class="danger",
        type_="button",
        disabled=model.selected_workspace_node.is_blank(),
        on_click=dispatch(DeleteSelectedWorkspaceNode),
        "Delete",
      ),
    ],
    @html.div(class="workspace-section-heading") <| [
      @html.h2("Assets"),
      @html.span(
        "\{model.selected_workspace_asset_ids.length()} selected · \{model.workspace_asset_total} total",
      ),
    ],
    @html.ul(class="workspace-asset-list") <| (if model.workspace_assets.is_empty() {
      [
        @html.li(
          "No indexed output yet. Completed runs register immutable, searchable asset versions here.",
        ),
      ]
    } else {
      model.workspace_assets.map(entry => {
        let artifact = entry.artifact
        let selected = model.selected_workspace_asset_ids.contains(
          artifact.artifact_id,
        )
        @html.li(
          class=if selected { "is-selected" } else { "" },
          attrs=@html.Attrs::build()
            .draggable("true")
            .on_dragstart(event => {
              ignore(event)
              dispatch(WorkspaceAssetDragStarted(artifact.artifact_id))
            }),
        ) <| [
          @html.button(
            type_="button",
            on_click=dispatch(
              ToggleWorkspaceAssetSelection(artifact.artifact_id),
            ),
          ) <| [
            @html.strong(
              artifact.artifact_id + " v" + artifact.version.to_string(),
            ),
            @html.span(
              workspace_artifact_kind_label(artifact.kind) +
              " · " +
              artifact.qc_state +
              " · " +
              artifact.rights_state,
            ),
            @html.small(
              if entry.tags.is_empty() {
                "untagged"
              } else {
                entry.tags.join(", ")
              },
            ),
          ],
          @html.button(
            type_="button",
            on_click=dispatch(WorkspaceAssetAddRequested(artifact.artifact_id)),
            "Add input node",
          ),
        ]
      })
    }),
    @html.div(class="workspace-asset-actions") <| [
      @html.button(
        type_="button",
        on_click=dispatch(CompareWorkspaceAssets),
        "Compare",
      ),
      @html.button(
        type_="button",
        on_click=dispatch(PromoteWorkspaceAsset),
        "Promote",
      ),
      @html.button(
        type_="button",
        on_click=dispatch(BranchWorkspaceAsset),
        "Branch",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_workspace_asset_ids.is_empty(),
        on_click=dispatch(TagSelectedWorkspaceAsset),
        "Toggle review tag",
      ),
      @html.button(
        class="danger",
        type_="button",
        disabled=model.selected_workspace_asset_ids.is_empty(),
        on_click=dispatch(DeleteSelectedWorkspaceAsset),
        "Hide",
      ),
    ],
    @html.div(class="workspace-section-heading") <| [
      @html.h2("More outcomes"),
      @html.span("Manifest-backed"),
    ],
    @html.ul(class="workspace-capability-list") <| [
      @html.li("Brief → social clip"),
      @html.li("Long-form episode"),
      @html.li("Generate asset variants"),
      @html.li("Localize campaign"),
      @html.li("Review → delivery package"),
    ],
    @html.div(class="workspace-section-heading") <| [
      @html.h2("Activity"),
      @html.span("\{model.workspace_activity.length()} events"),
    ],
    @html.ul(class="workspace-activity-list") <| model.workspace_activity
    .filter(value => {
      model.workspace_search.is_blank() ||
      value.to_lower().contains(model.workspace_search.to_lower())
    })
    .map(value => @html.li(value)),
  ]
}

///|
fn workspace_node_card(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  node : WorkspaceNodeView,
) -> @rabbita.Html {
  let state = workspace_node_state(model, node.node_id)
  let selection_class = if model.selected_workspace_node == node.node_id {
    " is-selected"
  } else {
    ""
  }
  let position = workspace_node_position(model, node.node_id)
  let connecting = if model.workspace_connect_from == node.node_id {
    " is-connecting"
  } else {
    ""
  }
  @html.div(
    class="workspace-node state-" +
      state +
      selection_class +
      (if node.collapsed { " is-collapsed" } else { "" }),
    style=["left: \{position.x}px", "top: \{position.y}px"],
    on_mousedown=mouse => {
      dispatch(WorkspaceCanvasPointerDown(node.node_id, mouse))
    },
  ) <| [
    @html.span(class="node-state", state),
    @html.button(
      class="workspace-node-select" + connecting,
      type_="button",
      on_click=dispatch(SelectWorkspaceNode(node.node_id)),
      attrs=@html.Attrs::build().aria_label(
        node.title + ". " + node.detail + ". State " + state,
      ),
    ) <| [
      @html.strong(node.title),
      @html.small(node.detail),
    ],
    @html.div(class="workspace-node-inputs") <| node.inputs.map(port => {
      @html.button(
        class="node-port input-port",
        type_="button",
        title="Connect " +
          workspace_artifact_kind_label(port.artifact_kind) +
          " input",
        on_click=dispatch(
          WorkspacePortActivated(node.node_id, port.port_id, false),
        ),
        attrs=@html.Attrs::build().aria_label(
          "Connect " + port.label + " input to " + node.title,
        ),
        port.label,
      )
    }),
    @html.div(class="workspace-node-outputs") <| node.outputs.map(port => {
      @html.button(
        class="node-port output-port" +
          (if model.workspace_connect_from == node.node_id &&
            model.workspace_connect_port == port.port_id {
            " is-connecting"
          } else {
            ""
          }),
        type_="button",
        title="Start " +
          workspace_artifact_kind_label(port.artifact_kind) +
          " connection",
        on_click=dispatch(
          WorkspacePortActivated(node.node_id, port.port_id, true),
        ),
        attrs=@html.Attrs::build().aria_label(
          "Start connection from " + node.title + " " + port.label,
        ),
        port.label,
      )
    }),
    @html.div(class="node-keyboard-move") <| [
      @html.button(
        type_="button",
        on_click=dispatch(WorkspaceNodeNudged(node.node_id, -24, 0)),
        attrs=@html.Attrs::build().aria_label("Move node left"),
        "←",
      ),
      @html.button(
        type_="button",
        on_click=dispatch(WorkspaceNodeNudged(node.node_id, 24, 0)),
        attrs=@html.Attrs::build().aria_label("Move node right"),
        "→",
      ),
    ],
  ]
}

///|
fn workspace_edge_view(
  model : Model,
  source_id : String,
  target_id : String,
  extra : Bool,
) -> @rabbita.Html {
  let source = workspace_node_position(model, source_id)
  let target = workspace_node_position(model, target_id)
  let left = source.x + 190
  let top = source.y + 62
  let width = Int::max(24, target.x - left)
  @html.div(
    class=if extra { "canvas-edge is-extra" } else { "canvas-edge" },
    style=["left: \{left}px", "top: \{top}px", "width: \{width}px"],
    title=source_id + " → " + target_id,
  ) <| [
    @html.span("›"),
  ]
}

///|
fn workspace_app_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let (title, input_label, input_help) = match model.selected_workspace_recipe {
    CombineVideosRecipe =>
      (
        "Combine videos", "Local videos", "Choose the ordered videos in the run panel below.",
      )
    BriefToDeliveryRecipe =>
      (
        "Brief to generated delivery", "Creative brief", "Describe the audience, outcome, constraints, and intended channels.",
      )
  }
  @html.div(class="workspace-app-view") <| [
    @html.span(class="eyebrow", "Published recipe app view"),
    @html.h1(title),
    @html.p(input_help),
    if model.selected_workspace_recipe == BriefToDeliveryRecipe {
      @html.label <| [
        @html.span(input_label),
        @html.textarea(
          value=model.workspace_public_input,
          rows=8,
          placeholder="Create a 30-second launch film for…",
          on_input=dispatch.map(value => WorkspacePublicInputChanged(value)),
          "",
        ),
      ]
    } else {
      @html.div(class="app-input-summary") <| [
        @html.strong(input_label),
        @html.span("\{model.utility_concat.files.length()} selected"),
      ]
    },
    @html.button(
      class="primary",
      type_="button",
      disabled=model.busy,
      on_click=dispatch(StartWorkspaceRecipe),
      "Run recipe",
    ),
    @html.small(
      "The graph is validated and frozen before work starts. Provider work remains pending until a MoonFlow receipt arrives.",
    ),
  ]
}

///|
fn workspace_canvas(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let graph = model.workspace_graph
  let title = graph
    .map(value => value.title)
    .unwrap_or(workspace_recipe_title(model.selected_workspace_recipe))
  let locality = if graph.map(value => value.graph_id).unwrap_or("") ==
    "combine-videos" {
    "Local provider"
  } else {
    "MoonFlow providers"
  }
  let nodes = visible_workspace_nodes(model)
  let edges = graph.map(value => value.edges).unwrap_or([])
  let canvas_children = edges.map(edge => {
      workspace_edge_view(
        model,
        edge.source_node_id,
        edge.target_node_id,
        false,
      )
    }) +
    nodes.map(node => workspace_node_card(dispatch, model, node))
  @html.section(class="workspace-canvas") <| [
    @html.header(class="canvas-toolbar") <| [
      @html.div <| [
        @html.strong(title),
        @html.small(
          "Graph r" +
          graph.map(value => value.revision.to_string()).unwrap_or("—") +
          (if model.workspace_graph_dirty {
            " · unsaved edits"
          } else {
            " · saved"
          }),
        ),
      ],
      @html.div(class="tag-row") <| [
        status_tag("pass", "Typed ports"),
        status_tag(
          if model.workspace_graph_dirty {
            "hold"
          } else {
            "pass"
          },
          if model.workspace_graph_dirty {
            "Validate on save"
          } else {
            "Validated"
          },
        ),
        status_tag("neutral", locality),
        status_tag("hold", "No publication authority"),
        @html.button(
          type_="button",
          on_click=dispatch(WorkspaceZoomChanged(-0.1)),
          attrs=@html.Attrs::build().aria_label("Zoom out canvas"),
          "−",
        ),
        @html.span("\{(model.workspace_canvas_zoom * 100.0).to_int()}%"),
        @html.button(
          type_="button",
          on_click=dispatch(WorkspaceZoomChanged(0.1)),
          attrs=@html.Attrs::build().aria_label("Zoom in canvas"),
          "+",
        ),
        @html.button(
          type_="button",
          on_click=dispatch(ToggleWorkspaceAppView),
          if model.workspace_app_view {
            "Graph view"
          } else {
            "App view"
          },
        ),
      ],
    ],
    if model.workspace_app_view {
      workspace_app_view(dispatch, model)
    } else {
      @html.div(
        class="workspace-node-viewport",
        attrs=@html.Attrs::build()
          .on_dragover(event => {
            event.prevent_default()
            @rabbita.none
          })
          .on_drop(event => {
            event.prevent_default()
            dispatch(WorkspaceAssetDropped)
          })
          .aria_label(
            "Infinite workflow canvas. Drop an asset to create an input node.",
          ),
      ) <| [
        @html.div(
          class="workspace-node-surface",
          style=["transform: scale(\{model.workspace_canvas_zoom})"],
        ) <| canvas_children,
      ]
    },
    @html.div(class="canvas-help") <| [
      @html.strong("Run selected output"),
      @html.span(
        "Mooncast validates the graph, freezes exact inputs, runs only required ancestors, and records each output as evidence.",
      ),
    ],
  ]
}

///|
fn workspace_specialized_editor(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  node : WorkspaceNodeView,
) -> @rabbita.Html {
  match node.node_id {
    "brief" | "validate" =>
      @html.div(class="specialized-editor script-lens") <| [
        @html.span(class="eyebrow", "Script lens"),
        @html.textarea(
          value=model.workspace_public_input,
          rows=7,
          placeholder="Creative brief or script…",
          on_input=dispatch.map(value => WorkspacePublicInputChanged(value)),
          "",
        ),
        @html.small("Versioned text becomes the public recipe input."),
      ]
    "generate" => {
      let selected = model.workspace_assets.filter(entry => {
        model.selected_workspace_asset_ids.contains(entry.artifact.artifact_id)
      })
      @html.div(class="specialized-editor image-lens") <| [
        @html.span(class="eyebrow", "Artifact compare lens"),
        @html.div(class="variant-grid") <| (if selected.is_empty() {
          [
            @html.p(
              "Select two indexed assets in the library to compare evidence.",
            ),
          ]
        } else {
          selected.map(entry => {
            @html.div <| [
              @html.strong(entry.artifact.artifact_id),
              @html.span(entry.artifact.digest),
            ]
          })
        }),
        @html.button(
          type_="button",
          disabled=selected.length() < 2,
          on_click=dispatch(CompareWorkspaceAssets),
          "Compare selected evidence",
        ),
      ]
    }
    "review" =>
      @html.div(class="specialized-editor review-lens") <| [
        @html.span(class="eyebrow", "Review lens"),
        @html.p(
          "Named human decision required. Agents cannot approve their own output.",
        ),
        status_tag("hold", "Awaiting reviewer"),
      ]
    "delivery" | "register" => {
      let selected = model.selected_workspace_asset_ids
        .last()
        .bind(id => {
          model.workspace_assets
          .iter()
          .find_first(entry => entry.artifact.artifact_id == id)
        })
      @html.div(class="specialized-editor delivery-lens") <| [
        @html.span(class="eyebrow", "Delivery inspector"),
        @html.dl(class="inspector-data") <| [
          @html.dt("Artifact"),
          @html.dd(
            selected
            .map(entry => entry.artifact.digest)
            .unwrap_or("Select an asset"),
          ),
          @html.dt("Rights"),
          @html.dd(
            selected
            .map(entry => entry.artifact.rights_state)
            .unwrap_or("Unknown"),
          ),
          @html.dt("QC"),
          @html.dd(
            selected.map(entry => entry.artifact.qc_state).unwrap_or("Unknown"),
          ),
        ],
      ]
    }
    _ =>
      @html.div(class="specialized-editor timeline-lens") <| [
        @html.span(class="eyebrow", "Timeline editor handoff"),
        @html.p(
          "Open the project’s real timeline and monitor for frame-accurate trim, audio, captions, and effects.",
        ),
        @html.button(
          type_="button",
          on_click=dispatch(SwitchWorkspaceLens(EditorLens)),
          "Open timeline editor",
        ),
      ]
  }
}

///|
fn workspace_inspector(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let node = selected_workspace_node(model)
  @html.section(class="workspace-inspector") <| [
    @html.div(class="workspace-section-heading") <| [
      @html.h2("Inspector"),
      @html.span(node.node_id),
    ],
    @html.dl(class="inspector-data") <| [
      @html.dt("Definition"),
      @html.dd(node.definition_id),
      @html.dt("Owner"),
      @html.dd(node.owner),
      @html.dt("Authority"),
      @html.dd(node.authority),
      @html.dt("State"),
      @html.dd(workspace_node_state(model, node.node_id)),
      @html.dt("Cache"),
      @html.dd("Content-addressed"),
      @html.dt("Review"),
      @html.dd("Explicit when required"),
    ],
    @html.div(class="workspace-parameter-editor") <| [
      @html.span(class="eyebrow", "Versioned parameters"),
      match workspace_graph_node(model, node.node_id) {
        None => @html.nothing
        Some(graph_node) =>
          @html.ul <| graph_node.parameters.map(parameter => {
            @html.li <| [
              @html.code(parameter.key + " = " + parameter.value.stringify()),
              @html.button(
                type_="button",
                on_click=dispatch(DeleteWorkspaceNodeParameter(parameter.key)),
                "Remove",
              ),
            ]
          })
      },
      @html.input(
        value=model.workspace_parameter_key,
        placeholder="parameter key",
        on_input=dispatch.map(value => WorkspaceParameterKeyChanged(value)),
      ),
      @html.input(
        value=model.workspace_parameter_value,
        placeholder="string value",
        on_input=dispatch.map(value => WorkspaceParameterValueChanged(value)),
      ),
      @html.button(
        type_="button",
        on_click=dispatch(SetWorkspaceNodeParameter),
        "Set parameter",
      ),
    ],
    @html.div(class="workspace-collaboration") <| [
      @html.span(class="eyebrow", "Live collaboration"),
      @html.p(
        if model.workspace_presence.any(value => value.target_id == node.node_id) {
          model.workspace_presence
          .filter(value => value.target_id == node.node_id)
          .map(value => value.display_name)
          .join(", ") +
          " viewing this node"
        } else {
          "No active collaborator lease on this node"
        },
      ),
      @html.ul <| model.workspace_comments
      .filter(value => value.target_id == node.node_id)
      .map(comment => {
        @html.li <| [
          @html.strong(comment.actor),
          @html.span(comment.body),
        ]
      }),
    ],
    match model.workspace_proposals.last() {
      None =>
        @html.div(class="workspace-agent-card") <| [
          @html.span(class="eyebrow", "MoonClaw collaborator"),
          @html.strong("No pending graph proposal"),
          @html.p(
            "MoonClaw may inspect this workspace and save a review-gated proposal. It cannot satisfy human gates.",
          ),
        ]
      Some(proposal) => {
        let providers = if proposal.provider_ids.is_empty() {
          "none"
        } else {
          proposal.provider_ids.join(", ")
        }
        let approvals = if proposal.required_approvals.is_empty() {
          "none"
        } else {
          proposal.required_approvals.join(", ")
        }
        @html.div(class="workspace-agent-card") <| [
          @html.span(class="eyebrow", "MoonClaw proposal"),
          @html.strong(proposal.proposal_id),
          @html.p(proposal.explanation),
          @html.small(
            "Base revision " +
            proposal.base_graph_revision.to_string() +
            " · nodes: " +
            proposal.affected_node_ids.join(", ") +
            " · providers: " +
            providers,
          ),
          @html.small(
            "Expected provider cost CNY " +
            proposal.expected_cost_cny.to_string() +
            " · approvals: " +
            approvals,
          ),
          status_tag(
            if proposal.applied {
              "good"
            } else {
              "hold"
            },
            if proposal.applied {
              "Applied"
            } else {
              "Exact-revision review required"
            },
          ),
          @html.button(
            type_="button",
            on_click=dispatch(ReviewWorkspaceProposal(proposal.proposal_id)),
            "Inspect exact diff",
          ),
          match model.workspace_proposal_review {
            None => @html.nothing
            Some(review) =>
              @html.small(
                "Current r" +
                review.current_graph_revision.to_string() +
                (if review.stale { " · stale" } else { " · current" }) +
                " · graph " +
                (if review.diff.changed_graph_fields.is_empty() {
                  "unchanged"
                } else {
                  review.diff.changed_graph_fields.join(", ")
                }) +
                " · nodes +" +
                review.diff.added_node_ids.length().to_string() +
                " / -" +
                review.diff.removed_node_ids.length().to_string() +
                " / ~" +
                review.diff.modified_node_ids.length().to_string() +
                " · edges +" +
                review.diff.added_edge_ids.length().to_string() +
                " / -" +
                review.diff.removed_edge_ids.length().to_string() +
                " / ~" +
                review.diff.modified_edge_ids.length().to_string(),
              )
          },
          if proposal.applied {
            @html.span("")
          } else {
            @html.button(
              type_="button",
              disabled=model.busy,
              on_click=dispatch(ApplyWorkspaceProposal(proposal.proposal_id)),
              "Review and apply exact revision",
            )
          },
        ]
      }
    },
    @html.div(class="workspace-evidence-card") <| [
      @html.strong("Execution boundary"),
      @html.p(
        if node.owner == "MoonFlow" {
          "Dispatched to MoonFlow with typed receipts."
        } else {
          "Executed pack-locally by Mooncast."
        },
      ),
    ],
    workspace_specialized_editor(dispatch, model, node),
    @html.label(class="workspace-comment-form") <| [
      @html.span("Comment on selected node"),
      @html.textarea(
        value=model.workspace_comment,
        rows=3,
        placeholder="Mention a change, finding, or timecode…",
        on_input=dispatch.map(value => WorkspaceCommentChanged(value)),
        "",
      ),
      @html.button(
        type_="button",
        disabled=model.busy,
        on_click=dispatch(PostWorkspaceNodeComment),
        "Post comment",
      ),
    ],
    @html.div(class="workspace-governance-actions") <| [
      @html.button(
        type_="button",
        disabled=model.busy,
        on_click=dispatch(PublishWorkspaceCapsule),
        "Publish recipe version",
      ),
      @html.button(
        type_="button",
        disabled=model.busy,
        on_click=dispatch(ShareWorkspaceRun),
        "Create client review link",
      ),
      if model.workspace_share_url.is_blank() {
        @html.span("")
      } else {
        @html.a(
          href=model.workspace_share_url,
          target=@html.Blank,
          rel="noreferrer",
          "Open latest secure review link",
        )
      },
      if model.workspace_share_id.is_blank() {
        @html.span("")
      } else {
        @html.button(
          class="danger",
          type_="button",
          disabled=model.busy,
          on_click=dispatch(RevokeWorkspaceShare),
          "Revoke latest link",
        )
      },
    ],
  ]
}

///|
fn workspace_graph_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(class="workspace-shell") <| [
    workspace_recipe_rail(dispatch, model),
    workspace_canvas(dispatch, model),
    workspace_inspector(dispatch, model),
    @html.section(class="workspace-run-drawer") <| [
      @html.div(class="run-drawer-heading") <| [
        @html.div <| [
          @html.strong("Run & activity"),
          @html.small(utility_concat_progress(model)),
        ],
        @html.span(
          class="revision-pill",
          if model.workspace_run_id.is_blank() {
            "6-node frozen recipe"
          } else {
            model.workspace_run_state
          },
        ),
      ],
      if model.selected_workspace_recipe == CombineVideosRecipe {
        utility_concat_view(dispatch, model)
      } else {
        @html.div(class="provider-run-panel") <| [
          @html.label <| [
            @html.span("Public creative brief"),
            @html.textarea(
              value=model.workspace_public_input,
              rows=4,
              placeholder="Outcome, audience, duration, channel, constraints…",
              on_input=dispatch.map(value => WorkspacePublicInputChanged(value)),
              "",
            ),
          ],
          @html.button(
            class="primary",
            type_="button",
            disabled=model.busy,
            on_click=dispatch(StartWorkspaceRecipe),
            "Validate, freeze & queue",
          ),
          @html.button(
            class="secondary",
            type_="button",
            disabled=model.busy,
            on_click=dispatch(StartWorkspaceSelectedOutput),
            "Run through selected node",
          ),
          @html.div(class="provider-boundary-note") <| [
            status_tag("neutral", "MoonClaw tool surface"),
            status_tag("neutral", "MoonFlow receipt boundary"),
            status_tag("hold", "Human review cannot be automated"),
            @html.small(
              "Live state reconnects through /events (SSE) or one-second snapshots. Queued does not mean generated.",
            ),
          ],
        ]
      },
      if model.workspace_run_id.is_blank() {
        @html.nothing
      } else {
        @html.div(class="workspace-run-actions") <| [
          @html.button(
            type_="button",
            on_click=dispatch(PollWorkspaceRun),
            "Replay new events",
          ),
          @html.button(
            type_="button",
            disabled=model.busy,
            on_click=dispatch(ClaimWorkspaceNode),
            "Claim next local node",
          ),
          @html.button(
            type_="button",
            disabled=model.busy,
            on_click=dispatch(RetryWorkspaceNode),
            "Retry selected node",
          ),
          @html.button(
            class="danger",
            type_="button",
            disabled=model.busy,
            on_click=dispatch(CancelWorkspaceRun),
            "Cancel run",
          ),
        ]
      },
    ],
  ]
}

///|
fn workspace_review_lens(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(class="workspace-review") <| [
    @html.header(class="review-lens-heading") <| [
      @html.div <| [
        @html.h1("Review workspace"),
        @html.p("Comments, QC findings, approval gates, and delivery evidence."),
      ],
      @html.button(
        type_="button",
        on_click=dispatch(SwitchWorkspaceLens(EditorLens)),
        "Open timeline",
      ),
    ],
    review_view(dispatch, model),
  ]
}
