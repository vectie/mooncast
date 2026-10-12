///|
fn render_delivery_cut_row(
  dispatch : Dispatch[Msg],
  model : Model,
  cut : DeliveryCutDraft,
) -> @rabbita.Html {
  div(class="panel surface-stack", [
    div(class="panel-heading", [
      h3(cut.cut_id),
      div(class="action-row", [
        button(
          disabled=model.busy ||
            model.project_pending.contains("Project") ||
            model.project_load_errors.any(item => item.0 == "Project") ||
            !model.project
            .map(project => {
              project.master
              .map(master => {
                master.sha256 == delivery_cut_drafts(model).master_sha256
              })
              .unwrap_or(false)
            })
            .unwrap_or(false),
          on_click=dispatch(SelectCutPlayer(cut.key)),
          "Mark range for " + cut.cut_id,
        ),
        button(
          disabled=model.busy,
          on_click=dispatch(ToggleDeliveryCut(cut.key)),
          if cut.selected {
            "Included · exclude cut"
          } else {
            "Excluded · include cut"
          },
        ),
        button(
          disabled=model.busy,
          on_click=dispatch(RemoveDeliveryCut(cut.key)),
          "Remove " + cut.cut_id,
        ),
      ]),
    ]),
    div(class="form-grid", [
      form_field("Cut name", cut.cut_id, "e.g. teaser-short", value => {
        dispatch(EditDeliveryCut(cut.key, "name", value))
      }),
      form_field("Channel label", cut.channel, "e.g. client-review", value => {
        dispatch(EditDeliveryCut(cut.key, "channel", value))
      }),
      label(class="field", [
        span("Source variant"),
        @html.select(
          disabled=model.busy,
          on_change=value => dispatch(EditDeliveryCut(cut.key, "source", value)),
          ["master", "horizontal-1080p", "vertical-1080p"].map(source => {
            @html.option(
              value=source,
              selected=cut.source_variant == source,
              source,
            )
          }),
        ),
      ]),
      form_field("Cut start (seconds)", cut.start, "e.g. 12.250", value => {
        dispatch(EditDeliveryCut(cut.key, "start", value))
      }),
      form_field("Cut end (seconds)", cut.end, "e.g. 42.750", value => {
        dispatch(EditDeliveryCut(cut.key, "end", value))
      }),
    ]),
  ])
}

///|
fn render_delivery_cuts(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection,
) -> @rabbita.Html {
  let draft = delivery_cut_drafts(model)
  div(class="surface-stack", [
    h3("Named channel cuts"),
    p(
      "Include up to 12 independently named cuts in one delivery package. Use seconds with up to 3 decimal places; each cut must fit the promoted master and last at most 180 seconds. Channel labels describe intended use and do not authorize publication.",
    ),
    p(
      "Cut drafts autosave in this browser by project and retain their exact master identity. Refresh and project switches keep your edits. The package always includes the master, horizontal and vertical variants, verified captions, rights and AI labels.",
    ),
    match delivery_cut_storage_notice(model) {
      Some(message) => p(class="inline-error", message)
      None => @html.nothing
    },
    div(class="action-row", [
      button(
        disabled=model.busy ||
          draft.cuts.length() >= 12 ||
          project.master is None,
        on_click=dispatch(AddDeliveryCut),
        "Add named cut (\{draft.cuts.length()}/12)",
      ),
      button(
        disabled=model.busy ||
          model.delivery_cut_storage_blocked.contains(project.id),
        on_click=dispatch(SaveDeliveryCutDrafts),
        "Retry saving cut draft",
      ),
      if !draft.cuts.is_empty() &&
        project.master.map(master => master.sha256).unwrap_or("") !=
        draft.master_sha256 {
        button(
          disabled=model.busy || project.master is None,
          on_click=dispatch(RebindDeliveryCuts),
          "Use current master",
        )
      } else {
        @html.nothing
      },
    ]),
    div(
      class="surface-stack",
      draft.cuts.map(cut => render_delivery_cut_row(dispatch, model, cut)),
    ),
    render_cut_player(dispatch, model),
    match delivery_cut_selection(model, project) {
      Ok([]) => p("No cuts selected; full-master captions are unchanged.")
      Ok(cuts) =>
        div(
          class="surface-stack",
          cuts.map(cut => {
            div([
              p(
                "\{cut.cut_id} · channel \{cut.channel} · source \{cut.source_variant} · \{cut.start_ms}–\{cut.end_ms} ms · \{cut.end_ms - cut.start_ms} ms long",
              ),
              a(
                class="primary-link",
                href="/api/v2/projects/\{project.id}/delivery-captions/cut/\{cut.start_ms}/\{cut.end_ms}/view",
                "Preview " + cut.cut_id + " captions and download SRT",
              ),
            ])
          }),
        )
      Err(message) => p(class="inline-error", message)
    },
  ])
}
