///|
fn view(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div(
    on_mouseup=mouse => {
      ignore(mouse)
      @cmd.batch([
        dispatch(TimelinePointerReleased),
        dispatch(WorkspaceCanvasPointerReleased),
      ])
    },
  ) <| [
    @html.main_(class="mooncast-editor") <| [
      project_header(dispatch, model),
      match model.workspace_lens {
        GraphLens => workspace_graph_view(dispatch, model)
        EditorLens =>
          if editor_needs_workspace(model) {
            @html.section(class="editor-first-use") <| [
              @html.h1("Start an edit"),
              @html.button(
                type_="button",
                disabled=model.busy || model.workspace_graph_saving,
                on_click=dispatch(OpenProject),
                "Create creative workspace",
              ),
            ]
          } else {
            @html.div <| [
              @html.details(class="editor-delivery-drawer") <| [
                @html.summary("Export and delivery"),
                production_handoff_view(dispatch, model),
              ],
              @html.div(class="editor-grid") <| [
                asset_bin(dispatch, model),
                @html.div(class="edit-center") <| [
                  monitor_panel(dispatch, model),
                  timeline_view(dispatch, model),
                ],
                inspector_panel(dispatch, model),
              ],
              @html.section(class="workflow-stack") <| [
                media_intake_view(dispatch, model),
              ],
            ]
          }
        ReviewLens => workspace_review_lens(dispatch, model)
        PlayerLens => standalone_player_view(dispatch, model)
      },
      if model.workspace_lens == PlayerLens ||
        (
          editor_needs_workspace(model) &&
          model.error == "" &&
          model.conflict == "" &&
          !model.busy
        ) {
        @html.nothing
      } else {
        editor_footer(dispatch, model)
      },
    ],
  ]
}

///|
fn editor_needs_workspace(model : Model) -> Bool {
  model.workspace_lens == EditorLens &&
  model.catalog_state == CatalogEmpty &&
  model.workspace is None
}
