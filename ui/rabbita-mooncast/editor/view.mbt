///|
fn view(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div(on_mouseup=dispatch.map(_ => TimelinePointerReleased)) <| [
    @html.main_(class="mooncast-editor") <| [
      project_header(dispatch, model),
      production_handoff_view(dispatch, model),
      @html.div(class="editor-grid") <| [
        asset_bin(dispatch, model),
        @html.div(class="edit-center") <| [
          monitor_panel(dispatch, model),
          timeline_view(dispatch, model),
        ],
        inspector_panel(dispatch, model),
      ],
      @html.section(class="workflow-stack") <| [
        utility_concat_view(dispatch, model),
        media_intake_view(dispatch, model),
        review_view(dispatch, model),
      ],
      editor_footer(dispatch, model),
    ],
  ]
}
