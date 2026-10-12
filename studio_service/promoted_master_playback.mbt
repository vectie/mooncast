///|
/// Read only: join the canonical master by file digest to an existing promotion
/// receipt and its completed export. A newer export is never a substitute.
async fn StudioService::promoted_master_playback(
  self : StudioService,
  project_id : String,
) -> Json {
  let record = self.get_project(project_id)
  guard record.snapshot.master is Some(master) && master.duration_seconds > 0 else {
    raise Conflict(
      code="promoted_master_unavailable",
      message="Promote a completed master with a known duration before marking cuts.",
    )
  }
  let wanted = normalized_digest(master.video_digest)
  let candidates : Array[@editor_integration.MasterPromotionReceipt] = []
  let keys = self.store.list_keys(prefix="editor-promotion-", suffix=".json")
  keys.push(editor_latest_promotion_key(project_id))
  for key in keys {
    let receipt : @editor_integration.MasterPromotionReceipt? = load_value(
      self.store,
      key,
    )
    if receipt is Some(value) &&
      value.project_id == project_id &&
      normalized_digest(value.digest) == wanted &&
      !candidates.any(item => item.job_id == value.job_id) {
      candidates.push(value)
    }
  }
  guard candidates is [receipt] else {
    raise Conflict(
      code="promoted_master_binding_unavailable",
      message="The promoted master needs one exact export promotion binding. Open Cut Editor to repair it.",
    )
  }
  let job = self.get_editor_job(project_id, receipt.job_id)
  guard job.job.project_id == project_id &&
    job.job.job_id == receipt.job_id &&
    job.job.kind == "export" &&
    normalized_digest(job.job.output_digest) == wanted &&
    job.export_receipt is Some(exported) &&
    normalized_digest(exported.digest) == wanted &&
    exported.size == receipt.size &&
    exported.plan_digest == receipt.plan_digest else {
    raise Conflict(
      code="promoted_master_export_mismatch",
      message="The promoted master no longer matches its completed export receipt.",
    )
  }
  // This verifies the exact selected job's retained bytes, not another export
  // with the same filename or a latest-job fallback. GET/HEAD verify them again.
  let bytes = self.resolve_editor_job_media(project_id, receipt.job_id)
  guard bytes.length() == receipt.size else {
    raise Conflict(
      code="promoted_master_size_mismatch",
      message="The promoted master bytes do not match their promotion receipt.",
    )
  }
  {
    "contract": "mooncast.promoted-master-playback.v1",
    "project_id": project_id,
    "master_id": master.reference.id,
    "master_sha256": master.video_digest,
    "duration_seconds": master.duration_seconds,
    "job_id": receipt.job_id,
    "media_url": "/api/editor/projects/" +
    project_id +
    "/exports/" +
    receipt.job_id +
    "/media?master_sha256=" +
    wanted,
  }
}
