///|
fn render_cut_player(dispatch : Dispatch[Msg], model : Model) -> @rabbita.Html {
  guard current_cut_player(model) is Some(player) else { return @html.nothing }
  let cut = delivery_cut_drafts(model).cuts
    .iter()
    .find_first(cut => cut.key == player.row_key)
    .unwrap()
  let range = cut_player_range(model, player)
  div(class="panel surface-stack cut-range-player", [
    h3("Mark range for " + cut.cut_id),
    p(
      "Promoted-master timing preview. This plays the original master, including when a horizontal or vertical source is selected. The final crop and cut appear only after an explicit delivery build.",
    ),
    p(
      "Seek with the player, then Mark in or Mark out. Marks round to the nearest millisecond (half milliseconds round up). Manual decimal entries stay unchanged until you mark that boundary.",
    ),
    if player.loading {
      p("Verifying the exact promoted master…")
    } else {
      @html.nothing
    },
    match player.projection {
      None => @html.nothing
      Some(projection) =>
        div(
          Map::from_array([
            (
              cut_player_id(player.generation),
              @html.video(
                id=cut_player_id(player.generation),
                class="animatic-player",
                src=projection.media_url,
                controls=true,
                preload="metadata",
                "Master playback unavailable. Retry or enter the range manually.",
              ),
            ),
          ]),
        )
    },
    p(
      if player.ready {
        "Master position: " +
        cut_player_mark_text(player.current_seconds) +
        " seconds"
      } else {
        "Marking and range preview wait for playable metadata."
      },
    ),
    match player.error {
      Some(message) => p(class="inline-error", message)
      None => @html.nothing
    },
    div(class="action-row", [
      button(
        disabled=model.busy || !player.ready,
        on_click=dispatch(MarkCutPlayer(player.generation, "mark-start")),
        "Mark in",
      ),
      button(
        disabled=model.busy || !player.ready,
        on_click=dispatch(MarkCutPlayer(player.generation, "mark-end")),
        "Mark out",
      ),
      button(
        disabled=model.busy || range is Err(_),
        on_click=dispatch(PreviewCutPlayer(player.generation)),
        "Preview selected range",
      ),
      button(
        disabled=model.busy,
        on_click=dispatch(RetryCutPlayer),
        "Retry master playback",
      ),
      button(on_click=dispatch(CloseCutPlayer), "Close range player"),
    ]),
    match range {
      Ok((start, finish)) =>
        p(
          "Selected master range: " +
          start.to_string() +
          "–" +
          finish.to_string() +
          " ms. Preview pauses at the out point.",
        )
      Err(message) => p(class="inline-error", message)
    },
    p(
      "Marks only update this cut's browser-autosaved draft. No delivery is built by playback, seeking, marking, previewing or retrying.",
    ),
  ])
}
