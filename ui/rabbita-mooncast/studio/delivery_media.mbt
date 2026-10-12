///|
struct DeliveryVideoCaptionsProjection {
  name : String
  sha256 : String
  preview_url : String
  download_url : String
} derive(FromJson)

///|
struct DeliveryVideoProjection {
  output_id : String
  kind : String
  source_output_id : String
  orientation : String?
  in_seconds : Double?
  out_seconds : Double?
  width : Int
  height : Int
  name : String
  sha256 : String
  preview_url : String
  download_url : String
  captions : DeliveryVideoCaptionsProjection?
} derive(FromJson)

///|
struct DeliveryCaptionPreviewProjection {
  name : String
  sha256 : String
  content : String
} derive(FromJson)

///|
fn selected_delivery_video(model : Model) -> DeliveryVideoProjection? {
  guard model.delivery_media_selection is Some((build_id, output_id, sha256)) else {
    return None
  }
  guard model.delivery_builds
    .iter()
    .find_first(build => {
      build.build_id == build_id && build.state == "completed"
    })
    is Some(build) else {
    return None
  }
  build.videos
  .unwrap_or([])
  .iter()
  .find_first(video => video.output_id == output_id && video.sha256 == sha256)
}

///|
fn reconcile_delivery_media(model : Model) -> Model {
  if selected_delivery_video(model) is Some(video) &&
    video.captions.map(c => (c.name, c.sha256, c.preview_url)) ==
    model.delivery_caption_identity {
    return model
  }
  invalidate_delivery_media(model)
}

///|
fn select_delivery_media(
  emit : @rabbita.Emit[Msg],
  model : Model,
  build_id : String,
  output_id : String,
) -> (@rabbita.Cmd, Model) {
  guard model.delivery_builds
    .iter()
    .find_first(build => {
      build.build_id == build_id && build.state == "completed"
    })
    is Some(build) else {
    return (@rabbita.none, model)
  }
  guard build.videos
    .unwrap_or([])
    .iter()
    .find_first(video => video.output_id == output_id)
    is Some(video) else {
    return (@rabbita.none, model)
  }
  let generation = model.delivery_media_generation + 1
  let command = match video.captions {
    None => @rabbita.none
    Some(captions) =>
      @http.get(captions.preview_url).expect_json(
        emit.map(result => {
          LoadedDeliveryMediaCaptions(generation, captions.preview_url, result)
        }),
      )
  }
  (
    command,
    {
      ..model,
      delivery_media_selection: Some((build_id, output_id, video.sha256)),
      delivery_media_generation: generation,
      delivery_caption_preview: None,
      delivery_caption_error: None,
      delivery_caption_loading: video.captions is Some(_),
      delivery_caption_identity: video.captions.map(c => {
        (c.name, c.sha256, c.preview_url)
      }),
      delivery_transcript: empty_delivery_transcript(),
    },
  )
}

///|
fn receive_delivery_captions(
  model : Model,
  generation : Int,
  url : String,
  result : Result[DeliveryCaptionPreviewProjection, Error],
) -> Model {
  guard generation == model.delivery_media_generation &&
    model.delivery_caption_loading &&
    selected_delivery_video(model) is Some(video) &&
    video.captions is Some(captions) &&
    captions.preview_url == url else {
    return model
  }
  match result {
    Ok(preview) if preview.name == captions.name &&
      preview.sha256 == captions.sha256 =>
      {
        ..model,
        delivery_caption_loading: false,
        delivery_caption_preview: Some(preview.content),
        delivery_caption_error: None,
        delivery_transcript: match parse_delivery_transcript(preview.content) {
          Ok(cues) => { ..model.delivery_transcript, cues, parse_error: None, }
          Err(message) =>
            {
              ..model.delivery_transcript,
              cues: [],
              parse_error: Some(message),
            }
        },
      }
    _ =>
      {
        ..model,
        delivery_caption_loading: false,
        delivery_caption_preview: None,
        delivery_caption_error: Some(
          "The exact SRT preview could not be loaded or its identity changed. Retry this selection.",
        ),
      }
  }
}
