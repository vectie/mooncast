///|
fn render_delivery_transcript(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let transcript = model.delivery_transcript
  let generation = model.delivery_media_generation
  let active = transcript.cues.filter(cue => {
    delivery_cue_active(cue, transcript)
  })
  let matching = delivery_matching_cues(transcript)
  div(class="delivery-transcript surface-stack", [
    h3("Searchable output transcript"),
    p(
      "Timestamps are local to this saved output, starting at zero. Tab to a cue and press Enter or Space to seek. Searching does not change playback.",
    ),
    match transcript.media_error {
      Some(message) => p(class="inline-error", message)
      None => @html.nothing
    },
    match transcript.parse_error {
      Some(message) => p(class="inline-error", message)
      None => @html.nothing
    },
    if transcript.cues.is_empty() {
      @html.nothing
    } else {
      div(class="delivery-transcript-grid", [
        div(class="delivery-active-cues", [
          h3("Active captions"),
          if !transcript.ready {
            p(
              "Waiting for playable metadata before seeking or showing active captions.",
            )
          } else if active.is_empty() {
            p("No caption at the current position.")
          } else {
            div(
              active.map(cue => {
                @html.pre(class="delivery-active-caption", cue.text)
              }),
            )
          },
        ]),
        div(class="surface-stack", [
          @html.label([
            span("Search caption text or timestamp"),
            input(
              value=transcript.query,
              placeholder="Search this output's captions",
              on_input=value => {
                dispatch(SearchDeliveryTranscript(generation, value))
              },
            ),
          ]),
          p(
            matching.length().to_string() +
            " of " +
            transcript.cues.length().to_string() +
            " cues",
          ),
          if matching.is_empty() {
            p("No matching cues. Clear the search to see all captions.")
          } else {
            div(
              class="delivery-cue-list",
              matching.map(cue => {
                button(
                  class=if delivery_cue_active(cue, transcript) {
                    "delivery-cue is-active"
                  } else {
                    "delivery-cue"
                  },
                  disabled=delivery_cue_seek_target(
                      model,
                      generation,
                      cue.index,
                    )
                    is None,
                  on_click=dispatch(SeekDeliveryCue(generation, cue.index)),
                  [
                    span(
                      class="delivery-cue-time",
                      (if delivery_cue_active(cue, transcript) {
                        "Active · "
                      } else {
                        ""
                      }) +
                      "Seek " +
                      cue.timestamp,
                    ),
                    span(class="delivery-cue-text", cue.text),
                  ],
                )
              }),
            )
          },
        ]),
      ])
    },
  ])
}
