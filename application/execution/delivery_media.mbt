///|
/// Resolve an exact completed video output. Never consult the current master.
/// `expected_sha256` is the lowercase digest without the `sha256:` prefix.
pub async fn DeliveryFactoryService::verified_delivery_video(
  self : DeliveryFactoryService,
  project_id : String,
  build_id : String,
  output_id : String,
  expected_sha256 : String,
) -> (@execution_domain.DeliveryBuildArtifact, @store.StoredBlob)? {
  guard self.load(build_id) is Some(record) &&
    record.build.project_id == project_id &&
    record.build.state == "completed" else {
    return None
  }
  let outputs = record.build.profile.outputs.filter(output => {
    output.output_id == output_id &&
    output.container == "mp4" &&
    (
      output.kind == "source-master" ||
      output.kind == "platform-variant" ||
      output.kind == "channel-cut"
    )
  })
  guard outputs is [output] else { return None }
  let matches = record.build.artifacts.filter(artifact => {
    artifact.artifact_id == output_id &&
    artifact.kind == output.kind &&
    artifact.filename == build_id + "-" + output_id + ".mp4" &&
    artifact.media_type == "video/mp4"
  })
  guard matches is [artifact] else { return None }
  self.verified_delivery_blob(artifact, expected_sha256)
}

///|
/// Resolve only the sidecar recorded for this video's exact output. A named
/// cut must use its own trimmed SRT, never the full-master sidecar.
/// `expected_sha256` is the lowercase digest without the `sha256:` prefix.
pub async fn DeliveryFactoryService::verified_delivery_video_captions(
  self : DeliveryFactoryService,
  project_id : String,
  build_id : String,
  output_id : String,
  expected_sha256 : String,
) -> (@execution_domain.DeliveryBuildArtifact, @store.StoredBlob)? {
  guard self.load(build_id) is Some(record) &&
    record.build.project_id == project_id &&
    record.build.state == "completed" else {
    return None
  }
  let outputs = record.build.profile.outputs.filter(output => {
    output.output_id == output_id &&
    output.container == "mp4" &&
    output.subtitle_mode == "sidecar" &&
    (
      output.kind == "source-master" ||
      output.kind == "platform-variant" ||
      output.kind == "channel-cut"
    )
  })
  guard outputs is [output] else { return None }
  let id = build_id +
    (if output.kind == "channel-cut" { "-" + output_id } else { "" }) +
    "-subtitles"
  let matches = record.build.artifacts.filter(artifact => {
    artifact.artifact_id == id &&
    artifact.kind == "subtitle-sidecar" &&
    artifact.filename == id + ".srt" &&
    artifact.media_type == "application/x-subrip"
  })
  guard matches is [artifact] else { return None }
  self.verified_delivery_blob(artifact, expected_sha256)
}

///|
async fn DeliveryFactoryService::verified_delivery_blob(
  self : DeliveryFactoryService,
  artifact : @execution_domain.DeliveryBuildArtifact,
  expected_sha256 : String,
) -> (@execution_domain.DeliveryBuildArtifact, @store.StoredBlob)? {
  guard expected_sha256.length() == 64 &&
    normalized_sha256(artifact.digest) == expected_sha256 &&
    self.outputs.get_blob(artifact.filename) is Some(blob) &&
    blob.sha256 == expected_sha256 &&
    artifact.bytes == blob.bytes.length() &&
    artifact.bytes > 0 else {
    return None
  }
  Some((artifact, blob))
}
