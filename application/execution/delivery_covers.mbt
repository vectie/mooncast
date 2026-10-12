///|
/// Read one completed cover by exact project, build, artifact and digest.
/// Preview is a local read and is independent of client acceptance.
/// Returns `None` for missing, incomplete, foreign, non-cover or changed bytes.
/// `expected_sha256` is the lowercase 64-character digest without `sha256:`.
pub async fn DeliveryFactoryService::verified_cover_frame(
  self : DeliveryFactoryService,
  project_id : String,
  build_id : String,
  cover_id : String,
  expected_sha256 : String,
) -> (@execution_domain.DeliveryBuildArtifact, @store.StoredBlob)? {
  guard self.load(build_id) is Some(record) &&
    record.build.project_id == project_id &&
    record.build.state == "completed" else {
    return None
  }
  let matching = record.build.artifacts.filter(artifact => {
    artifact.artifact_id == cover_id && artifact.kind == "cover-frame"
  })
  guard matching is [artifact] &&
    (artifact.media_type == "image/png" || artifact.media_type == "image/jpeg") &&
    normalized_sha256(artifact.digest) == expected_sha256 else {
    return None
  }
  guard record.build.profile.outputs.any(output => {
    output.output_id == cover_id &&
    output.kind == "cover-frame" &&
    artifact.filename == build_id + "-" + cover_id + "." + output.container
  }) else {
    return None
  }
  guard self.outputs.get_blob(artifact.filename) is Some(blob) &&
    blob.sha256 == expected_sha256 &&
    artifact.bytes == blob.bytes.length() &&
    artifact.bytes > 0 else {
    return None
  }
  Some((artifact, blob))
}
