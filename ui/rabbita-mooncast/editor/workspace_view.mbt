///|
struct WorkspaceNodeView {
  node_id : String
  title : String
  detail : String
  owner : String
  authority : String
}

///|
fn workspace_nodes(recipe : WorkspaceRecipe) -> Array[WorkspaceNodeView] {
  match recipe {
    CombineVideosRecipe =>
      [
        {
          node_id: "intake",
          title: "Folder intake",
          detail: "Digest-pin ordered local videos",
          owner: "Mooncast",
          authority: "Workspace mutation",
        },
        {
          node_id: "probe",
          title: "Probe media",
          detail: "Inspect streams, codecs and duration",
          owner: "Mooncast",
          authority: "Sandbox execution",
        },
        {
          node_id: "normalize",
          title: "Normalize streams",
          detail: "Reconcile incompatible media safely",
          owner: "Mooncast",
          authority: "Sandbox execution",
        },
        {
          node_id: "concat",
          title: "Concatenate video",
          detail: "Assemble sources in frozen order",
          owner: "Mooncast",
          authority: "Sandbox execution",
        },
        {
          node_id: "verify",
          title: "Verify output",
          detail: "Probe the final output and receipt",
          owner: "Mooncast",
          authority: "Sandbox execution",
        },
        {
          node_id: "register",
          title: "Register artifact",
          detail: "Save immutable lineage and preview",
          owner: "Mooncast",
          authority: "Workspace mutation",
        },
      ]
    BriefToDeliveryRecipe =>
      [
        {
          node_id: "brief",
          title: "Creative brief",
          detail: "Define outcome, audience and constraints",
          owner: "Mooncast",
          authority: "Observe",
        },
        {
          node_id: "validate",
          title: "Validate brief",
          detail: "Check the governed creative contract",
          owner: "Mooncast",
          authority: "Sandbox execution",
        },
        {
          node_id: "project",
          title: "Create project",
          detail: "Materialize a versioned production graph",
          owner: "Mooncast",
          authority: "Workspace mutation",
        },
        {
          node_id: "generate",
          title: "Generate shots",
          detail: "Dispatch provider work with receipts",
          owner: "MoonFlow",
          authority: "External effect",
        },
        {
          node_id: "review",
          title: "Human asset review",
          detail: "A named reviewer accepts or rejects",
          owner: "Human",
          authority: "Human gate",
        },
        {
          node_id: "delivery",
          title: "Package delivery",
          detail: "Assemble only accepted artifacts",
          owner: "Mooncast",
          authority: "Sandbox execution",
        },
      ]
  }
}

///|
fn selected_workspace_node(model : Model) -> WorkspaceNodeView {
  workspace_nodes(model.selected_workspace_recipe)
  .iter()
  .find_first(node => node.node_id == model.selected_workspace_node)
  .unwrap_or(workspace_nodes(model.selected_workspace_recipe)[0])
}

///|
fn workspace_node_state(model : Model, node_id : String) -> String {
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
      @html.h2("Assets"),
      @html.span("\{model.utility_concat.files.length()} selected"),
    ],
    @html.ul(class="workspace-asset-list") <| (if model.utility_concat.files.is_empty() {
      [@html.li("Choose MP4 files in the run drawer.")]
    } else {
      model.utility_concat.files.map(file => {
        @html.li <| [
          @html.strong(file.file_name),
          @html.span("\{file.size_bytes} bytes"),
        ]
      })
    }),
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
  @html.button(
    class="workspace-node state-" + state + selection_class,
    type_="button",
    on_click=dispatch(SelectWorkspaceNode(node.node_id)),
  ) <| [
    @html.span(class="node-state", state),
    @html.strong(node.title),
    @html.small(node.detail),
    @html.span(class="node-port input-port", "in"),
    @html.span(class="node-port output-port", "out"),
  ]
}

///|
fn workspace_canvas(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let (title, output, locality) = match model.selected_workspace_recipe {
    CombineVideosRecipe =>
      ("Combine videos", "Register artifact", "Local provider")
    BriefToDeliveryRecipe =>
      ("Brief to generated delivery", "Package delivery", "MoonFlow providers")
  }
  let nodes = workspace_nodes(model.selected_workspace_recipe)
  @html.section(class="workspace-canvas") <| [
    @html.header(class="canvas-toolbar") <| [
      @html.div <| [
        @html.strong(title),
        @html.small("Graph r1 · valid · selected output: " + output),
      ],
      @html.div(class="tag-row") <| [
        status_tag("pass", "Typed ports"),
        status_tag("pass", "Acyclic"),
        status_tag("neutral", locality),
        status_tag("hold", "No publication authority"),
      ],
    ],
    @html.div(class="workspace-node-flow") <| nodes.mapi((index, node) => {
      @html.div(class="node-with-edge") <| [
        workspace_node_card(dispatch, model, node),
        if index + 1 < nodes.length() {
          @html.span(class="workspace-edge", "→")
        } else {
          @html.nothing
        },
      ]
    }),
    @html.div(class="canvas-help") <| [
      @html.strong("Run selected output"),
      @html.span(
        "Mooncast validates the graph, freezes exact inputs, runs only required ancestors, and records each output as evidence.",
      ),
    ],
  ]
}

///|
fn workspace_inspector(model : Model) -> @rabbita.Html {
  let node = selected_workspace_node(model)
  @html.section(class="workspace-inspector") <| [
    @html.div(class="workspace-section-heading") <| [
      @html.h2("Inspector"),
      @html.span(node.node_id),
    ],
    @html.dl(class="inspector-data") <| [
      @html.dt("Definition"),
      @html.dd("workspace." + node.node_id),
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
    @html.div(class="workspace-agent-card") <| [
      @html.span(class="eyebrow", "MoonClaw collaborator"),
      @html.strong("Graph proposals are review-gated"),
      @html.p(
        "Agents may inspect assets and propose a revision. Applying it requires the exact displayed graph revision; agents cannot satisfy human gates.",
      ),
      @html.button(type_="button", disabled=true, "No pending proposal"),
    ],
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
    workspace_inspector(model),
    @html.section(class="workspace-run-drawer") <| [
      @html.div(class="run-drawer-heading") <| [
        @html.div <| [
          @html.strong("Run & activity"),
          @html.small(utility_concat_progress(model)),
        ],
        @html.span(class="revision-pill", "6-node frozen recipe"),
      ],
      utility_concat_view(dispatch, model),
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
