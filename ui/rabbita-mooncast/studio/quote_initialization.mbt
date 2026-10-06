///|
/// Recovery uses only a unique saved initialization record, never the selected latest
/// quote or today's capacity board. The host validates this original binding.
fn quote_initialization_request(
  model : Model,
  conversion_digest : String,
) -> (String, Json)? {
  guard !model.busy && model.operator.human_confirmed else { return None }
  guard model.commercial is Some(commercial) else { return None }
  let matches = commercial.conversions.filter(item => {
    item.digest == conversion_digest
  })
  guard matches is [conversion] &&
    conversion.initialization_status == Some("pending") else {
    return None
  }
  Some(
    (
      "/api/commercial-intake/quotes/" + conversion.quote_id + "/conversion",
      {
        "expected_version": conversion.quote_version,
        "expected_digest": conversion.quote_digest,
        "expected_capacity_digest": conversion.capacity_digest,
        "human_confirmed": model.operator.human_confirmed,
        "actor": model.operator.actor,
        "actor_role": model.operator.role,
      },
    ),
  )
}

///|
fn refresh_quote_initializations(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @http.get("/api/commercial-intake").expect_json(
    emit.map(result => LoadedCommercial(result)),
  )
}

///|
fn is_quote_initialization_action(label : String) -> Bool {
  label == "Quote conversion" || label == "Draft initialization"
}

///|
fn render_quote_initializations(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.section(class="panel", [
    @html.div(class="panel-heading", [
      @html.div([
        @html.small("Accepted quote recovery"),
        @html.h2("Draft initialization"),
      ]),
      @html.button(
        class="secondary",
        on_click=dispatch(RefreshQuoteInitializations),
        "Refresh initialization status",
      ),
    ]),
    @html.p(
      "Resume an interrupted draft using its original accepted quote and capacity snapshot. Later project edits are preserved.",
    ),
    match model.commercial {
      Some(commercial) if !commercial.conversions.is_empty() =>
        @html.div(
          class="commercial-list",
          commercial.conversions.map(conversion => {
            let pending = conversion.initialization_status == Some("pending")
            @html.article(class="commercial-card", [
              @html.div(class="route-heading", [
                @html.div([
                  @html.small(
                    "\{conversion.quote_id} · v\{conversion.quote_version}",
                  ),
                  @html.h3(conversion.project_id),
                ]),
                status_chip(
                  match conversion.initialization_status {
                    Some("pending") => "initialization pending"
                    Some("completed") => "initialized"
                    Some("preserved-existing") => "existing draft preserved"
                    _ => "initialization untracked"
                  },
                ),
              ]),
              @html.small("Original quote: " + conversion.quote_digest),
              @html.small("Accepted capacity: " + conversion.capacity_digest),
              if pending {
                @html.div(class="review-actions", [
                  @html.button(
                    class="primary",
                    disabled=model.busy || !model.operator.human_confirmed,
                    on_click=dispatch(
                      ResumeQuoteInitialization(conversion.digest),
                    ),
                    "Resume draft initialization",
                  ),
                ])
              } else {
                @html.p(
                  if conversion.initialization_status == Some("completed") {
                    "The original draft initialization is complete."
                  } else if conversion.initialization_status ==
                    Some("preserved-existing") {
                    "The quote is linked to the existing project. Its drafts and details were preserved; missing legacy drafts were not inferred."
                  } else {
                    "This initialization record has no tracked recovery plan. Review the existing project before making changes."
                  },
                )
              },
            ])
          }),
        )
      Some(_) =>
        @html.p(class="empty", "No saved draft initialization records yet.")
      None =>
        @html.p(
          class="empty",
          "Load the commercial ledger to check draft initialization.",
        )
    },
  ])
}
