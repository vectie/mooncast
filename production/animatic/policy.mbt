///|
fn digest_text(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
pub fn plan_digest(plan : AnimaticPlan) -> String {
  digest_text(
    { ..plan, reference: { ..plan.reference, digest: "" } }
    .to_json()
    .stringify(),
  )
}

///|
fn exact_artifact(
  artifacts : Array[@creative.CreativeArtifact],
  kind : @creative.ArtifactKind,
  reference : @project.VersionRef,
) -> Bool {
  @creative.current_artifact(artifacts, kind)
  .map(value => value.reference == reference)
  .unwrap_or(false)
}

///|
pub fn plan_errors(
  plan : AnimaticPlan,
  graph : @project.ProjectGraph,
  artifacts : Array[@creative.CreativeArtifact],
) -> Array[String] {
  let errors : Array[String] = []
  if plan.contract != "mooncast.animatic-plan.v1" ||
    plan.project_id != graph.project_id ||
    plan.reference.id == "" ||
    plan.reference.version < 1 ||
    plan.reference.digest != plan_digest(plan) ||
    !exact_artifact(artifacts, @creative.IpBible, plan.bible) ||
    !exact_artifact(artifacts, @creative.Script, plan.script) ||
    !exact_artifact(artifacts, @creative.Storyboard, plan.storyboard) ||
    plan.caption_language == "" ||
    plan.provider == "" ||
    plan.model == "" ||
    plan.cost_ceiling_cny < 0.0 ||
    plan.cost_ceiling_cny > graph.maximum_budget_cny ||
    plan.retry_limit < 1 ||
    plan.retry_limit > 5 ||
    plan.created_at == "" ||
    plan.process_authority ||
    plan.publication_authority {
    errors.push(
      "plan identity, creative lineage, budget, retry, or authority is invalid",
    )
  }
  let shots = @project.flattened_shots(graph)
  if plan.panels.length() != shots.length() || plan.approved_assets.is_empty() {
    errors.push(
      "every shot and at least one approved reusable asset are required",
    )
  }
  for shot in shots {
    let matches = plan.panels.filter(panel => panel.shot_id == shot.shot_id)
    if matches.length() != 1 ||
      matches[0].duration_ms != shot.duration_ms ||
      matches[0].order != shot.order ||
      matches[0].caption.trim() == "" ||
      matches[0].transition != "cut" ||
      matches[0].visual_asset_ids.is_empty() ||
      matches[0].visual_asset_ids.any(id => {
        !plan.approved_assets.any(asset => asset.asset_id == id)
      }) {
      errors.push(
        "panels must bind exact shot timing, captions, transitions, and assets",
      )
    }
  }
  if plan.approved_assets.any(asset => {
      !asset.immutable || asset.digest == "" || asset.rights_record_id == ""
    }) ||
    plan.temporary_voice_asset_ids.is_empty() ||
    plan.temporary_music_asset_ids.is_empty() ||
    plan.temporary_voice_asset_ids.any(id => {
      !plan.approved_assets.any(asset => {
        asset.asset_id == id && asset.kind == "voice"
      })
    }) ||
    plan.temporary_music_asset_ids.any(id => {
      !plan.approved_assets.any(asset => {
        asset.asset_id == id && asset.kind == "music"
      })
    }) {
    errors.push(
      "immutable rights-cleared visual, temporary voice, and music assets are required",
    )
  }
  errors
}

///|
pub fn approval_digest(value : RenderedAnimaticApproval) -> String {
  digest_text({ ..value, approval_digest: "" }.to_json().stringify())
}

///|
pub fn exact_approved_render(
  animatic : @creative.CreativeArtifact?,
  decisions : Array[@creative.CreativeDecision],
  artifacts : Array[@creative.CreativeArtifact],
  graph : @project.ProjectGraph,
) -> RenderedAnimaticApproval? {
  guard animatic is Some(artifact) &&
    @creative.exact_approval(Some(artifact), decisions) else {
    return None
  }
  let approval : RenderedAnimaticApproval = @json.from_json(
    @json.parse(artifact.content),
  ) catch {
    _ => return None
  }
  guard approval.contract == "mooncast.rendered-animatic-approval.v1" &&
    approval.decision == "approve" &&
    approval.human_confirmed &&
    approval.actor != "" &&
    approval.actor_role != "" &&
    approval.approval_digest == approval_digest(approval) &&
    approval.rendered.project_id == graph.project_id &&
    approval.rendered.duration_seconds == graph.target_duration_seconds &&
    approval.rendered.panel_count == @project.flattened_shots(graph).length() &&
    approval.rendered.budget.within_ceiling &&
    approval.rendered.budget.actual_cny <= graph.maximum_budget_cny &&
    approval.rendered.video_digest != "" &&
    approval.rendered.storyboard_sheet_digest != "" &&
    approval.rendered.provenance_digest != "" &&
    approval.rendered.immutable &&
    !approval.rendered.publication_authority &&
    exact_artifact(artifacts, @creative.IpBible, approval.rendered.bible) &&
    exact_artifact(artifacts, @creative.Script, approval.rendered.script) &&
    exact_artifact(
      artifacts,
      @creative.Storyboard,
      approval.rendered.storyboard,
    ) &&
    approval.rendered.approved_assets.all(asset => asset.immutable) else {
    return None
  }
  Some(approval)
}
