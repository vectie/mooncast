///|
struct DeliveryVideoCaptionsProjection {
  name : String
  sha256 : String
  preview_url : String
  download_url : String
} derive(ToJson)

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
} derive(ToJson)

///|
fn delivery_videos(
  build : @execution.DeliveryBuild,
) -> Array[DeliveryVideoProjection] {
  if build.state != "completed" {
    return []
  }
  build.profile.outputs.filter_map(output => {
    guard output.container == "mp4" &&
      (
        output.kind == "source-master" ||
        output.kind == "platform-variant" ||
        output.kind == "channel-cut"
      ) else {
      return None
    }
    let matches = build.artifacts.filter(artifact => {
      artifact.artifact_id == output.output_id &&
      artifact.kind == output.kind &&
      artifact.media_type == "video/mp4" &&
      artifact.filename == build.build_id + "-" + output.output_id + ".mp4"
    })
    guard matches is [artifact] else { return None }
    let base = "/api/v2/projects/" +
      build.project_id +
      "/delivery-builds/" +
      build.build_id +
      "/media/" +
      output.output_id
    let url = base +
      "/" +
      artifact.digest
      .strip_prefix("sha256:")
      .unwrap_or(artifact.digest[:])
      .to_owned()
    let caption_id = build.build_id +
      (if output.kind == "channel-cut" { "-" + output.output_id } else { "" }) +
      "-subtitles"
    let sidecars = build.artifacts.filter(item => {
      output.subtitle_mode == "sidecar" &&
      item.artifact_id == caption_id &&
      item.kind == "subtitle-sidecar" &&
      item.filename == caption_id + ".srt" &&
      item.media_type == "application/x-subrip"
    })
    let captions = match sidecars {
      [sidecar] => {
        let caption_url = base +
          "/captions/" +
          sidecar.digest
          .strip_prefix("sha256:")
          .unwrap_or(sidecar.digest[:])
          .to_owned()
        Some(DeliveryVideoCaptionsProjection::{
          name: sidecar.filename,
          sha256: sidecar.digest,
          preview_url: caption_url + "/preview",
          download_url: caption_url + "/download",
        })
      }
      _ => None
    }
    Some({
      output_id: output.output_id,
      kind: output.kind,
      source_output_id: output.source_output_id.unwrap_or("master"),
      orientation: output.orientation,
      in_seconds: output.in_seconds,
      out_seconds: output.out_seconds,
      width: output.width,
      height: output.height,
      name: artifact.filename,
      sha256: artifact.digest,
      preview_url: url,
      download_url: url + "/download",
      captions,
    })
  })
}

///|
async fn StudioService::delivery_media_response(
  self : StudioService,
  project_id : String,
  build_id : String,
  output_id : String,
  digest : String,
  captions : Bool,
  action : String,
  request : @host_http.Request,
) -> @host_http.Response {
  let verified = if captions {
    self.delivery_application.verified_delivery_video_captions(
      project_id, build_id, output_id, digest,
    )
  } else {
    self.delivery_application.verified_delivery_video(
      project_id, build_id, output_id, digest,
    )
  }
  guard verified is Some((artifact, blob)) else {
    return api_error(
      404, "delivery_media_unavailable", "This exact completed output is unavailable or its bytes no longer match the saved digest. Retry or refresh the build; no current master or different sidecar was substituted.",
    )
  }
  if captions && action == "preview" {
    let response = json_value_response(
      200,
      Json::object({
        "name": artifact.filename,
        "sha256": artifact.digest,
        "content": @utf8.decode(blob.bytes),
      }),
    )
    response.headers["Cache-Control"] = "no-store"
    return response
  }
  let range = request.headers.get("range")
  let if_none_match = request.headers.get("if-none-match")
  let response = @host_http.static_response(
    artifact.filename,
    blob.bytes,
    range?,
    if_none_match?,
  )
  response.headers["Content-Type"] = if captions {
    "application/x-subrip; charset=utf-8"
  } else {
    "video/mp4"
  }
  response.headers["Content-Disposition"] = (if action == "download" {
      "attachment"
    } else {
      "inline"
    }) +
    "; filename=\"" +
    artifact.filename +
    "\""
  response.headers["Cache-Control"] = "no-store"
  response
}
