///|
fn render_delivery_cover_row(
  dispatch : Dispatch[Msg],
  model : Model,
  cover : DeliveryCoverDraft,
) -> @rabbita.Html {
  div(class="panel surface-stack", [
    div(class="panel-heading", [
      h3(cover.cover_id),
      div(class="action-row", [
        button(
          disabled=model.busy,
          on_click=dispatch(ToggleDeliveryCover(cover.key)),
          if cover.selected {
            "Included · exclude cover"
          } else {
            "Excluded · include cover"
          },
        ),
        button(
          disabled=model.busy,
          on_click=dispatch(RemoveDeliveryCover(cover.key)),
          "Remove " + cover.cover_id,
        ),
      ]),
    ]),
    div(class="form-grid", [
      form_field("Cover name", cover.cover_id, "e.g. launch-poster", value => {
        dispatch(EditDeliveryCover(cover.key, "name", value))
      }),
      label(class="field", [
        span("Cover source"),
        @html.select(
          disabled=model.busy,
          on_change=value => {
            dispatch(EditDeliveryCover(cover.key, "source", value))
          },
          ["master", "horizontal-1080p", "vertical-1080p"].map(source => {
            @html.option(
              value=source,
              selected=cover.source_variant == source,
              source,
            )
          }),
        ),
      ]),
      form_field("Frame time (seconds)", cover.timestamp, "e.g. 12.250", value => {
        dispatch(EditDeliveryCover(cover.key, "timestamp", value))
      }),
      label(class="field", [
        span("Image format"),
        @html.select(
          disabled=model.busy,
          on_change=value => {
            dispatch(EditDeliveryCover(cover.key, "format", value))
          },
          ["png", "jpg"].map(format => {
            @html.option(
              value=format,
              selected=cover.format == format,
              format.to_upper(),
            )
          }),
        ),
      ]),
    ]),
  ])
}

///|
fn render_delivery_covers(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection,
) -> @rabbita.Html {
  let draft = delivery_cover_drafts(model)
  section(class="panel surface-stack", [
    h3("Timestamped covers"),
    p(
      "Choose up to 8 named frames from the master or a horizontal/vertical variant. Times use seconds with up to 3 decimal places and must be before the video's end. Image framing and dimensions follow the selected source.",
    ),
    p(
      "Your cover draft autosaves by project in this browser. Create and run a delivery build to see the actual images below; previewing or downloading a cover does not record acceptance or publication.",
    ),
    match delivery_cover_storage_notice(model) {
      Some(message) => p(class="inline-error", message)
      None => @html.nothing
    },
    div(class="action-row", [
      button(
        disabled=model.busy ||
          draft.covers.length() >= 8 ||
          project.master is None,
        on_click=dispatch(AddDeliveryCover),
        "Add named cover (\{draft.covers.length()}/8)",
      ),
      if delivery_cover_storage_notice(model) is Some(_) &&
        !model.delivery_cover_storage_blocked.contains(project.id) {
        button(
          disabled=model.busy,
          on_click=dispatch(SaveDeliveryCoverDrafts),
          "Retry saving cover draft",
        )
      } else {
        @html.nothing
      },
      if !draft.covers.is_empty() &&
        project.master.map(master => master.sha256).unwrap_or("") !=
        draft.master_sha256 {
        button(
          disabled=model.busy || project.master is None,
          on_click=dispatch(RebindDeliveryCovers),
          "Use current master for covers",
        )
      } else {
        @html.nothing
      },
    ]),
    div(
      class="surface-stack",
      draft.covers.map(cover => {
        render_delivery_cover_row(dispatch, model, cover)
      }),
    ),
    match delivery_cover_selection(model, project) {
      Ok([]) => p("No covers selected.")
      Ok(covers) =>
        div(
          class="surface-stack",
          covers.map(cover => {
            p(
              "\{cover.cover_id} · \{cover.source_variant} · \{cover.timestamp_ms} ms · \{cover.format.to_upper()}",
            )
          }),
        )
      Err(message) => p(class="inline-error", message)
    },
  ])
}

///|
fn render_delivery_cover_gallery(
  model : Model,
  build : DeliveryBuildProjection,
) -> @rabbita.Html {
  let covers = build.cover_frames.unwrap_or([])
  if build.state != "completed" || covers.is_empty() {
    return @html.nothing
  }
  div(class="surface-stack", [
    h3("Cover preview"),
    p(
      if model.project is Some(project) &&
        project.master is Some(master) &&
        master.sha256.strip_prefix("sha256:").unwrap_or(master.sha256[:]) ==
        build.master_sha256
        .strip_prefix("sha256:")
        .unwrap_or(build.master_sha256[:]) {
        "Actual images from this completed build. Each download is checked against its saved digest."
      } else {
        "Historical build: these images belong to its original master. Changes to your current draft do not replace them."
      },
    ),
    div(
      class="delivery-cover-gallery",
      covers.map(cover => {
        article(class="delivery-cover-frame", [
          a(
            href=cover.preview_url,
            @html.img(
              class="delivery-cover-image",
              src=cover.preview_url,
              alt="Cover " +
                cover.cover_id +
                " at " +
                cover.timestamp_seconds.to_string() +
                " seconds from " +
                cover.source_variant,
              loading="lazy",
            ),
          ),
          h3(cover.cover_id),
          p(
            "\{cover.source_variant} · \{cover.timestamp_seconds} seconds · \{cover.format.to_upper()}",
          ),
          a(
            class="primary-link",
            href=cover.preview_url + "/download",
            "Download " + cover.cover_id + "." + cover.format,
          ),
          @html.details([
            @html.summary("Image identity"),
            p(cover.name),
            code(cover.sha256),
          ]),
        ])
      }),
    ),
  ])
}
