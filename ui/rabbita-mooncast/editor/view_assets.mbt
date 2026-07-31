///|
fn project_header(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.header(class="appbar") <| [
    @html.div(class="brand") <| [
      @html.span(class="brand-mark", "M"),
      @html.div <| [
        @html.strong("Mooncast Cut Editor"),
        @html.small("Governed project → episode → scene → shot → asset"),
      ],
    ],
    @html.nav(class="project-controls") <| [
      @html.select(on_change=dispatch.map(value => SelectProject(value))) <| model.projects.map(project => {
          @html.option(
            value=project.project_id,
            selected=project.project_id == model.project_id,
          ) <| [
            @html.span("\{project.title} · r\{project.revision}"),
          ]
        },
      ),
      @html.button(
        type_="button",
        disabled=model.loading,
        on_click=dispatch(OpenProject),
        "Open project",
      ),
      @html.span(class="revision-pill", "r\{selected_revision(model)}"),
    ],
  ]
}

///|
fn project_tree(model : Model) -> @rabbita.Html {
  let identities = model.workspace
    .bind(workspace => option_or(workspace.navigator, workspace.identity_graph))
    .unwrap_or([])
  let identity = identities.get(0)
  @html.section(class="navigator-card") <| [
    @html.div(class="pane-heading") <| [
      @html.h2("Project tree"),
      @html.span("\{identities.length()} bindings"),
    ],
    match identity {
      None =>
        @html.p(class="empty-note", "No canonical project identity loaded.")
      Some(item) =>
        @html.ol(class="asset-tree") <| [
          @html.li <| [
            @html.strong("Project"),
            @html.span(item.project_id),
          ],
          @html.li <| [
            @html.strong("Episode"),
            @html.span(item.episode_id),
          ],
          @html.li <| [
            @html.strong("Scene"),
            @html.span(item.scene_id),
          ],
          @html.li <| [
            @html.strong("Shot"),
            @html.span(item.shot_id),
          ],
          @html.li(class="is-current") <| [
            @html.strong("Asset"),
            @html.span(item.asset_id),
          ],
        ]
    },
  ]
}

///|
fn status_tag(class_name : String, label : String) -> @rabbita.Html {
  @html.span(class="tag " + class_name, label)
}

///|
fn take_row(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  take : @api.TakeVariant,
) -> @rabbita.Html {
  let selected = take.take_id == model.selected_take_id
  let source = take.source
  @html.button(
    type_="button",
    class="take-row" +
      (if selected { " is-selected" } else { "" }) +
      (if take_is_eligible(take) { "" } else { " is-ineligible" }),
    on_click=dispatch(SelectTake(take.take_id)),
  ) <| [
    match source.thumbnail_url {
      Some(url) =>
        @html.img(class="take-thumb", src=url, alt="", loading="lazy")
      None => @html.span(class="take-thumb take-thumb-fallback", source.state)
    },
    @html.div(class="take-copy") <| [
      @html.strong(take.take_id),
      @html.span(
        "\{take.variant} · \{take.track_kind} · \{timecode(model, take.duration_ticks)}",
      ),
      @html.small("\{take_origin(take)} \{take.role} → \{take.track_id}"),
      @html.small(
        "\{take.project_id} › \{take.episode_id} › \{take.scene_id} › \{take.shot_id} › \{take.asset_id}",
      ),
      @html.small(
        "Provenance: \{take.provider_ref.unwrap_or("fixture")} / \{take.model_ref.unwrap_or("local")} / \{take.attempt_id.unwrap_or("—")}",
      ),
      @html.div(class="tag-row") <| [
        status_tag(
          if take.qc.status == "passed" {
            "pass"
          } else {
            "hold"
          },
          "QC \{take.qc.status}",
        ),
        status_tag(
          if take.rights.status == "cleared" {
            "pass"
          } else {
            "hold"
          },
          "Rights \{take.rights.status}",
        ),
        status_tag(
          "neutral",
          if take.already_placed {
            "Placed"
          } else if take_is_eligible(take) {
            "Eligible"
          } else {
            "Blocked"
          },
        ),
        status_tag(
          if take_origin(take) == "Generated" {
            "generated"
          } else {
            "neutral"
          },
          take_origin(take),
        ),
        status_tag(
          if source.proxy_state.unwrap_or("missing") == "ready" {
            "pass"
          } else {
            "hold"
          },
          "Proxy \{source.proxy_state.unwrap_or("missing")}",
        ),
      ],
    ],
  ]
}

///|
fn asset_filters(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div(class="filter-grid") <| [
    @html.input(
      input_type=@html.Search,
      value=model.filters.search,
      placeholder="Search takes, assets, lineage…",
      on_input=dispatch.map(value => FilterSearchChanged(value)),
    ),
    @html.select(on_change=dispatch.map(value => FilterKindChanged(value))) <| [
      @html.option(
        value="all",
        selected=model.filters.kind == "all",
        "All kinds",
      ),
      @html.option(
        value="video",
        selected=model.filters.kind == "video",
        "Video",
      ),
      @html.option(
        value="image",
        selected=model.filters.kind == "image",
        "Image",
      ),
      @html.option(
        value="audio",
        selected=model.filters.kind == "audio",
        "Audio",
      ),
      @html.option(
        value="voice",
        selected=model.filters.kind == "voice",
        "Voice/dialogue",
      ),
      @html.option(
        value="music",
        selected=model.filters.kind == "music",
        "Music/SFX",
      ),
      @html.option(
        value="overlay",
        selected=model.filters.kind == "overlay",
        "Overlay/title",
      ),
      @html.option(
        value="subtitle",
        selected=model.filters.kind == "subtitle",
        "Subtitle",
      ),
    ],
    @html.select(on_change=dispatch.map(value => FilterQcChanged(value))) <| [
      @html.option(value="all", selected=model.filters.qc == "all", "All QC"),
      @html.option(
        value="passed",
        selected=model.filters.qc == "passed",
        "QC passed",
      ),
      @html.option(
        value="other",
        selected=model.filters.qc == "other",
        "QC review",
      ),
    ],
    @html.select(on_change=dispatch.map(value => FilterRightsChanged(value))) <| [
      @html.option(
        value="all",
        selected=model.filters.rights == "all",
        "All rights",
      ),
      @html.option(
        value="cleared",
        selected=model.filters.rights == "cleared",
        "Rights cleared",
      ),
      @html.option(
        value="other",
        selected=model.filters.rights == "other",
        "Rights hold",
      ),
    ],
    @html.select(on_change=dispatch.map(value => FilterPlacementChanged(value))) <| [
      @html.option(
        value="all",
        selected=model.filters.placement == "all",
        "All placement",
      ),
      @html.option(
        value="eligible",
        selected=model.filters.placement == "eligible",
        "Eligible",
      ),
      @html.option(
        value="unplaced",
        selected=model.filters.placement == "unplaced",
        "Unplaced",
      ),
      @html.option(
        value="placed",
        selected=model.filters.placement == "placed",
        "Placed",
      ),
      @html.option(
        value="ineligible",
        selected=model.filters.placement == "ineligible",
        "Ineligible",
      ),
    ],
  ]
}

///|
fn asset_bin(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let visible = filtered_takes(model)
  @html.aside(class="asset-pane") <| [
    project_tree(model),
    @html.section(class="asset-card") <| [
      @html.div(class="pane-heading") <| [
        @html.h2("Takes & media"),
        @html.span("\{visible.length()} / \{takes(model).length()}"),
      ],
      asset_filters(dispatch, model),
      @html.div(
        class="take-list",
        if visible.length() == 0 {
          [
            @html.p(
              class="empty-note",
              "No matching takes. Filters are local to this editor view.",
            ),
          ]
        } else {
          visible.map(take => take_row(dispatch, model, take))
        },
      ),
      @html.div(class="take-actions") <| [
        @html.button(
          type_="button",
          on_click=dispatch(SelectAdjacentTake(-1)),
          "↑ Previous",
        ),
        @html.button(
          type_="button",
          on_click=dispatch(SelectAdjacentTake(1)),
          "↓ Next",
        ),
        @html.button(
          class="primary",
          type_="button",
          disabled=model.busy ||
            selected_take(model).map(take_is_eligible).unwrap_or(false) == false,
          on_click=dispatch(AddSelectedTake),
          match selected_take(model) {
            Some(take) if take.already_placed => "Already placed"
            Some(take) => "Add \{take.role} → \{take.track_id}"
            None => "Add selected to timeline"
          },
        ),
      ],
      @html.p(class="eligibility-note", take_eligibility(selected_take(model))),
    ],
  ]
}
