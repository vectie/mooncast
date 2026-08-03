///|
fn tab_label(tab : StudioTab) -> String {
  match tab {
    Overview => "Overview"
    ControlTower => "Control tower"
    NeedsStrategy => "Needs and strategy"
    Creative => "Creative"
    AssetFactory => "Asset factory"
    StoryboardAnimatic => "Storyboard and animatic"
    Routing => "Provider routing"
    ShotBoard => "Shot board"
    Delivery => "Delivery"
    Commercial => "Commercial"
  }
}

///|
fn tab_short_label(tab : StudioTab) -> String {
  match tab {
    Overview => "Home"
    ControlTower => "Tower"
    NeedsStrategy => "Needs"
    Creative => "Create"
    AssetFactory => "Assets"
    StoryboardAnimatic => "Boards"
    Routing => "Route"
    ShotBoard => "Shots"
    Delivery => "Deliver"
    Commercial => "Sales"
  }
}

///|
fn tab_key(tab : StudioTab) -> String {
  match tab {
    Overview => "overview"
    ControlTower => "control-tower"
    NeedsStrategy => "needs"
    Creative => "creative"
    AssetFactory => "assets"
    StoryboardAnimatic => "storyboard"
    Routing => "routing"
    ShotBoard => "shots"
    Delivery => "delivery"
    Commercial => "commercial"
  }
}

///|
fn tab_icon_path(tab : StudioTab) -> String {
  match tab {
    Overview => "M4 4h6v6H4zM14 4h6v10h-6zM4 14h6v6H4zM14 18h6v2h-6z"
    ControlTower => "M4 20V10M10 20V4M16 20v-7M22 20V7"
    NeedsStrategy => "M4 5h16v14H4zM8 9h8M8 13h5"
    Creative =>
      "M12 3l2.6 5.2 5.7.8-4.1 4 1 5.7-5.2-2.7-5.2 2.7 1-5.7-4.1-4 5.7-.8z"
    AssetFactory => "M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9"
    StoryboardAnimatic => "M3 6h18v12H3zM8 6v12M16 6v12"
    Routing => "M5 6h7a4 4 0 0 1 4 4v8M12 18h8M17 15l3 3-3 3M5 3l2 3-2 3"
    ShotBoard => "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z"
    Delivery => "M4 7l8-4 8 4v10l-8 4-8-4zM4 7l8 4 8-4M12 11v10"
    Commercial => "M4 19V9M10 19v-5M16 19V5M22 19H2"
  }
}

///|
fn studio_icon(tab : StudioTab) -> @rabbita.Html {
  @html.span(
    class="icon-shell",
    attrs=@html.Attrs::build().aria_hidden("true"),
    @svg.svg(class="nav-icon", width=20, height=20, view_box="0 0 24 24", [
      @svg.path(
        d=tab_icon_path(tab),
        fill="none",
        stroke="currentColor",
        stroke_width=2,
        attrs=@svg.Attrs::build()
          .stroke_linecap("round")
          .stroke_linejoin("round"),
      ),
    ]),
  )
}

///|
fn studio_action_icon(kind : String) -> @rabbita.Html {
  let path = match kind {
    "refresh" => "M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"
    "edit" => "M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4"
    "check" => "M5 12l4 4L19 6"
    _ => "M12 4v16M4 12h16"
  }
  @html.span(
    class="icon-shell",
    attrs=@html.Attrs::build().aria_hidden("true"),
    @svg.svg(class="action-icon", width=18, height=18, view_box="0 0 24 24", [
      @svg.path(
        d=path,
        fill="none",
        stroke="currentColor",
        stroke_width=2,
        attrs=@svg.Attrs::build()
          .stroke_linecap("round")
          .stroke_linejoin("round"),
      ),
    ]),
  )
}

///|
fn tab_button(
  dispatch : Dispatch[Msg],
  selected : StudioTab,
  tab : StudioTab,
) -> @rabbita.Html {
  button(
    class=if selected == tab {
      "studio-nav-item active"
    } else {
      "studio-nav-item"
    },
    title=tab_label(tab),
    attrs=@html.Attrs::build()
      .aria_label(tab_label(tab))
      .aria_current(if selected == tab { "page" } else { "false" })
      .data_set("testid", "studio-nav-" + tab_key(tab)),
    on_click=dispatch(SelectTab(tab)),
    [studio_icon(tab), span(class="nav-label", tab_short_label(tab))],
  )
}

///|
fn render_header(dispatch : Dispatch[Msg], model : Model) -> @rabbita.Html {
  header(class="studio-header", [
    div(class="brand", [
      span(class="brand-mark", "M"),
      div([strong("Mooncast"), small("Production OS")]),
    ]),
    nav(
      class="studio-tabs",
      attrs=@html.Attrs::build().aria_label("Mooncast workspaces"),
      [
        tab_button(dispatch, model.tab, Overview),
        tab_button(dispatch, model.tab, ControlTower),
        tab_button(dispatch, model.tab, NeedsStrategy),
        tab_button(dispatch, model.tab, Creative),
        tab_button(dispatch, model.tab, AssetFactory),
        tab_button(dispatch, model.tab, StoryboardAnimatic),
        tab_button(dispatch, model.tab, Routing),
        tab_button(dispatch, model.tab, ShotBoard),
        tab_button(dispatch, model.tab, Delivery),
        tab_button(dispatch, model.tab, Commercial),
      ],
    ),
    div(class="header-actions", [
      button(
        class="secondary icon-action",
        title="Refresh exact revision",
        attrs=@html.Attrs::build().aria_label("Refresh exact project revision"),
        disabled=model.selected_project_id == "" || model.loading,
        on_click=dispatch(RefreshProject),
        [studio_action_icon("refresh"), span(class="action-label", "Refresh")],
      ),
      a(
        class="primary-link icon-action",
        href="/editor",
        title="Open cut editor",
        attrs=@html.Attrs::build().aria_label("Open Mooncast cut editor"),
        [studio_action_icon("edit"), span(class="action-label", "Edit")],
      ),
    ]),
  ])
}

///|
fn render_project_rail(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  aside(
    class="project-rail",
    attrs=@html.Attrs::build().aria_label("Production projects"),
    [
      div(class="rail-heading", [
        div([small("Production ledger"), h2("Projects")]),
        span(class="count", "\{model.projects.length()}"),
      ]),
      div(
        class="project-list",
        if model.projects.is_empty() {
          [
            p(
              class="empty",
              "No project yet. Create the first saleable episode from Home.",
            ),
          ]
        } else {
          model.projects.map(item => {
            button(
              class=if item.project_id == model.selected_project_id {
                "project-item selected"
              } else {
                "project-item"
              },
              title="Open " + item.title,
              attrs=@html.Attrs::build()
                .aria_label(
                  "Open \{item.title}; stage \{item.stage}; next \{item.next_gate.unwrap_or("complete")}",
                )
                .aria_current(
                  if item.project_id == model.selected_project_id {
                    "true"
                  } else {
                    "false"
                  },
                ),
              on_click=dispatch(SelectProject(item.project_id)),
              [
                strong(item.title),
                span([code(item.project_id), status_chip(item.stage)]),
                small(
                  "Revision \{item.revision} · next \{item.next_gate.unwrap_or("complete")}",
                ),
              ],
            )
          })
        },
      ),
      div(class="rail-safety", [
        strong("Human release boundary"),
        p(
          "Plans and reviews are recorded here. Provider, payment, and publication effects always require separate authority.",
        ),
      ]),
    ],
  )
}
