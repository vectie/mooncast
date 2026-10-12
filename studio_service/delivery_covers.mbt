///|
struct DeliveryCoverFrameProjection {
  cover_id : String
  source_variant : String
  timestamp_seconds : Double
  format : String
  name : String
  sha256 : String
  preview_url : String
} derive(ToJson)

///|
fn delivery_cover_frames(
  build : @execution.DeliveryBuild,
) -> Array[DeliveryCoverFrameProjection] {
  if build.state != "completed" {
    return []
  }
  build.profile.outputs.filter_map(output => {
    guard output.kind == "cover-frame" &&
      output.source_output_id is Some(source_variant) &&
      output.timestamp_seconds is Some(timestamp_seconds) else {
      return None
    }
    guard build.artifacts
      .iter()
      .find_first(artifact => {
        artifact.artifact_id == output.output_id &&
        artifact.kind == "cover-frame"
      })
      is Some(artifact) else {
      return None
    }
    Some({
      cover_id: output.output_id,
      source_variant,
      timestamp_seconds,
      format: output.container,
      name: artifact.filename,
      sha256: artifact.digest,
      preview_url: "/api/v2/projects/" +
      build.project_id +
      "/delivery-builds/" +
      build.build_id +
      "/covers/" +
      output.output_id +
      "/" +
      artifact.digest
      .strip_prefix("sha256:")
      .unwrap_or(artifact.digest[:])
      .to_owned(),
    })
  })
}

///|
async fn StudioService::delivery_cover_response(
  self : StudioService,
  project_id : String,
  build_id : String,
  cover_id : String,
  expected_sha256 : String,
  download : Bool,
) -> @host_http.Response {
  match
    self.delivery_application.verified_cover_frame(
      project_id, build_id, cover_id, expected_sha256,
    ) {
    Some((artifact, blob)) =>
      {
        status: 200,
        reason: "OK",
        headers: {
          "Content-Type": artifact.media_type,
          "Content-Disposition": (if download {
            "attachment"
          } else {
            "inline"
          }) +
          "; filename=\"" +
          artifact.filename +
          "\"",
          "Cache-Control": "no-store",
          "X-Content-Type-Options": "nosniff",
        },
        body: blob.bytes,
      }
    None =>
      api_error(
        404, "delivery_cover_unavailable", "This exact completed cover is unavailable or its bytes no longer match the saved digest. Refresh the build and retry; no image was substituted.",
      )
  }
}
