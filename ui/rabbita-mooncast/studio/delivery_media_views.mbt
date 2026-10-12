///|
fn delivery_video_label(video : DeliveryVideoProjection) -> String {
  let kind = match video.kind {
    "source-master" => "Master"
    "platform-variant" => "Platform variant"
    "channel-cut" => "Named channel cut"
    _ => video.kind
  }
  let range = match (video.in_seconds, video.out_seconds) {
    (Some(start), Some(finish)) =>
      " · source range " +
      start.to_string() +
      "–" +
      finish.to_string() +
      " s"
    _ => " · full length"
  }
  kind +
  " · source " +
  video.source_output_id +
  range +
  " · " +
  video.width.to_string() +
  "×" +
  video.height.to_string() +
  video.orientation.map(value => " · " + value).unwrap_or("")
}

///|
fn render_delivery_media(
  dispatch : Dispatch[Msg],
  model : Model,
  build : DeliveryBuildProjection,
) -> @rabbita.Html {
  let videos = build.videos.unwrap_or([])
  if build.state != "completed" || videos.is_empty() {
    return @html.nothing
  }
  let selected = match model.delivery_media_selection {
    Some((id, _, _)) if id == build.build_id => selected_delivery_video(model)
    _ => None
  }
  div(class="surface-stack delivery-media", [
    h3("Inspect individual videos"),
    p(
      if model.project is Some(project) &&
        project.master is Some(master) &&
        master.sha256.strip_prefix("sha256:").unwrap_or(master.sha256[:]) ==
        build.master_sha256
        .strip_prefix("sha256:")
        .unwrap_or(build.master_sha256[:]) {
        "Select a completed master, variant or named cut. Playback, SRT preview and downloads use this build's saved outputs."
      } else {
        "Historical build: these videos and captions remain bound to the original master, even after a newer master is promoted."
      },
    ),
    div(
      class="surface-stack",
      videos.map(video => {
        article(class="delivery-media-row", [
          h3(video.output_id),
          p(delivery_video_label(video)),
          div(class="action-row", [
            button(
              class="secondary",
              on_click=dispatch(
                SelectDeliveryMedia(build.build_id, video.output_id),
              ),
              if selected.map(item => item.preview_url) ==
                Some(video.preview_url) {
                "Selected · " + video.output_id
              } else {
                "Inspect " + video.output_id
              },
            ),
            a(
              class="primary-link",
              href=video.download_url,
              "Download " + video.output_id + ".mp4",
            ),
            match video.captions {
              Some(captions) =>
                a(
                  class="primary-link",
                  href=captions.download_url,
                  "Download matching SRT",
                )
              None => span("No SRT sidecar in this build")
            },
          ]),
        ])
      }),
    ),
    match selected {
      None =>
        p("Choose Inspect to open the in-page player and matching captions.")
      Some(video) =>
        div(class="surface-stack delivery-media-inspector", [
          h3("Playing: " + video.output_id),
          p(delivery_video_label(video)),
          div(class="delivery-player-transcript-grid", [
            div(
              Map::from_array([
                (
                  video.preview_url +
                  ":" +
                  model.delivery_media_generation.to_string(),
                  @html.video(
                    id=delivery_player_id(model.delivery_media_generation),
                    class="animatic-player",
                    src=video.preview_url,
                    controls=true,
                    preload="metadata",
                    "Your browser could not play this MP4. Use its download link to inspect the exact file.",
                  ),
                ),
              ]),
            ),
            render_delivery_transcript(dispatch, model),
          ]),
          p(
            "If playback is interrupted or unavailable, retry this selection. Retrying reloads the same saved output and starts playback from the beginning.",
          ),
          button(
            class="secondary",
            on_click=dispatch(RetryDeliveryMedia),
            "Retry video and SRT",
          ),
          @html.details([
            @html.summary("Video identity"),
            p(video.name),
            code(video.sha256),
            p("Original master: " + build.master_sha256),
          ]),
          h3("Matching SRT preview"),
          if model.delivery_caption_loading {
            p("Loading exact captions…")
          } else {
            @html.nothing
          },
          match model.delivery_caption_error {
            Some(message) => p(class="inline-error", message)
            None => @html.nothing
          },
          match model.delivery_caption_preview {
            Some(content) =>
              @html.pre(class="delivery-caption-preview", content)
            None =>
              if video.captions is None {
                p("No SRT sidecar was included for this output.")
              } else {
                @html.nothing
              }
          },
        ])
    },
  ])
}
