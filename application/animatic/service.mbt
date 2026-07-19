///|
pub(all) struct AnimaticRenderRequest {
  expected_plan_version : Int
  expected_plan_digest : String
  actor : String
  rendered_at : String
  human_confirmed : Bool
  process_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnimaticApprovalRequest {
  expected_render_version : Int
  expected_render_digest : String
  actor : String
  actor_role : String
  note : String
  approved_at : String
  human_confirmed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror AnimaticApplicationError {
  AnimaticInvalid(String)
  AnimaticConflict(String)
  AnimaticRenderFailed(String)
  AnimaticNotFound(String)
} derive(Debug)

///|
pub struct AnimaticService {
  state : @store.AtomicStore
  media : @store.AtomicStore
  ffmpeg : String
}

///|
pub fn AnimaticService::new(
  state_root : String,
  media_root : String,
  ffmpeg? : String = ".tools/ffmpeg/darwin_arm64/ffmpeg",
) -> AnimaticService {
  {
    state: @store.AtomicStore::new(state_root),
    media: @store.AtomicStore::new(media_root, max_read_bytes=1073741824),
    ffmpeg,
  }
}

///|
fn plan_key(project_id : String, version : Int) -> String {
  "animatic-plan-" + project_id + "-v" + version.to_string() + ".json"
}

///|
fn render_key(project_id : String, version : Int) -> String {
  "animatic-render-" + project_id + "-v" + version.to_string() + ".json"
}

///|
fn attempt_key(attempt_id : String) -> String {
  "animatic-attempt-" + attempt_id + ".json"
}

///|
fn approval_key(project_id : String, version : Int) -> String {
  "animatic-approval-" + project_id + "-v" + version.to_string() + ".json"
}

///|
fn digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn ffmpeg_text(value : String) -> String {
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old=":", new="\\:")
  .replace_all(old="'", new="’")
  .replace_all(old="\n", new=" ")
}

///|
pub async fn AnimaticService::record_plan(
  self : AnimaticService,
  plan : @animatic_domain.AnimaticPlan,
  graph : @project.ProjectGraph,
  artifacts : Array[@creative.CreativeArtifact],
) -> @animatic_domain.AnimaticPlan {
  let errors = @animatic_domain.plan_errors(plan, graph, artifacts)
  guard errors.is_empty() else { raise AnimaticInvalid(errors.join("; ")) }
  let key = plan_key(plan.project_id, plan.reference.version)
  match self.state.get_json(key) {
    Some(value) => {
      let prior : @animatic_domain.AnimaticPlan = @json.from_json(value)
      guard prior == plan else {
        raise AnimaticConflict("plan version conflict")
      }
      prior
    }
    None => {
      for prior in self.list_plans(plan.project_id) {
        if prior.reference.version > plan.reference.version {
          raise AnimaticConflict("older plan cannot supersede current plan")
        }
      }
      ignore(self.state.put_json(key, plan.to_json()))
      plan
    }
  }
}

///|
pub async fn AnimaticService::list_plans(
  self : AnimaticService,
  project_id : String,
) -> Array[@animatic_domain.AnimaticPlan] {
  let values : Array[@animatic_domain.AnimaticPlan] = []
  for
    key in self.state.list_keys(
      prefix="animatic-plan-" + project_id + "-v",
      suffix=".json",
    ) {
    match self.state.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
pub async fn AnimaticService::current_plan(
  self : AnimaticService,
  project_id : String,
) -> @animatic_domain.AnimaticPlan? {
  let values = self.list_plans(project_id)
  if values.is_empty() {
    return None
  }
  let mut latest = values[0]
  for value in values {
    if value.reference.version > latest.reference.version {
      latest = value
    }
  }
  Some(latest)
}

///|
async fn AnimaticService::persist_attempt(
  self : AnimaticService,
  value : @animatic_domain.AnimaticRenderAttempt,
) -> Unit {
  ignore(self.state.put_json(attempt_key(value.attempt_id), value.to_json()))
}

///|
async fn AnimaticService::render_media(
  self : AnimaticService,
  plan : @animatic_domain.AnimaticPlan,
  sheet_key : String,
  video_key : String,
) -> Unit {
  let sheet_path = self.media.prepare_owned_path(sheet_key)
  let video_path = self.media.prepare_owned_path(video_key)
  let sheet_rows = (plan.panels.length() + 2) / 3
  let sheet_height = Int::max(1080, sheet_rows * 150 + 120)
  let sheet_filters : Array[String] = []
  for index, panel in plan.panels {
    let column = index % 3
    let row = index / 3
    sheet_filters.push(
      "drawtext=text='" +
      ffmpeg_text("\{panel.order}. " + panel.caption) +
      "':x=" +
      (40 + column * 620).to_string() +
      ":y=" +
      (70 + row * 150).to_string() +
      ":fontsize=22:fontcolor=white:box=1:boxcolor=0x101826@0.85:boxborderw=12",
    )
  }
  let sheet = @host_process.run_capture({
    executable: self.ffmpeg,
    arguments: [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "lavfi",
      "-i",
      "color=c=0x172033:s=1920x" + sheet_height.to_string() + ":r=1:d=1",
      "-vf",
      sheet_filters.join(","),
      "-frames:v",
      "1",
      sheet_path,
    ],
    working_directory: None,
    timeout_ms: 45000,
    max_output_bytes: 1048576,
  })
  guard sheet.exit_code == Some(0) && !sheet.timed_out else {
    raise AnimaticRenderFailed("storyboard_sheet_failed")
  }
  let filters : Array[String] = []
  let mut cursor = 0.0
  for panel in plan.panels {
    let end = cursor + panel.duration_ms.to_double() / 1000.0
    filters.push(
      "drawtext=text='" +
      ffmpeg_text("\{panel.order}. " + panel.caption) +
      "':x=(w-text_w)/2:y=(h-text_h)/2:fontsize=34:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=18:enable='between(t," +
      cursor.to_string() +
      "," +
      end.to_string() +
      ")'",
    )
    cursor = end
  }
  filters.push(
    "drawtext=text='ANIMATIC / TEMP AUDIO / NOT FOR PUBLICATION':x=30:y=30:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.7:boxborderw=8",
  )
  let duration = plan.panels
    .fold(init=0, (sum, panel) => sum + panel.duration_ms)
    .to_double() /
    1000.0
  let video = @host_process.run_capture({
    executable: self.ffmpeg,
    arguments: [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "lavfi",
      "-i",
      "color=c=0x172033:s=960x540:r=24:d=" + duration.to_string(),
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=220:sample_rate=44100:duration=" + duration.to_string(),
      "-vf",
      filters.join(","),
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-crf",
      "25",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "aac",
      "-b:a",
      "96k",
      "-shortest",
      "-movflags",
      "+faststart",
      "-metadata",
      "comment=animatic-plan:" + plan.reference.digest,
      video_path,
    ],
    working_directory: None,
    timeout_ms: 120000,
    max_output_bytes: 1048576,
  })
  guard video.exit_code == Some(0) && !video.timed_out else {
    raise AnimaticRenderFailed("timed_animatic_failed")
  }
}

///|
pub async fn AnimaticService::render(
  self : AnimaticService,
  project_id : String,
  request : AnimaticRenderRequest,
) -> @animatic_domain.RenderedAnimatic {
  guard self.current_plan(project_id) is Some(plan) &&
    plan.reference.version == request.expected_plan_version &&
    plan.reference.digest == request.expected_plan_digest &&
    request.actor != "" &&
    request.rendered_at != "" &&
    request.human_confirmed &&
    request.process_authority else {
    raise AnimaticConflict(
      "render must bind exact plan and explicit local process authority",
    )
  }
  match self.state.get_json(render_key(project_id, plan.reference.version)) {
    Some(value) => return @json.from_json(value)
    None => ()
  }
  let attempts = self
    .list_attempts(project_id)
    .filter(value => value.plan == plan.reference)
  guard attempts.length() < plan.retry_limit else {
    raise AnimaticConflict("animatic retry limit exhausted")
  }
  let number = attempts.length() + 1
  let attempt_id = project_id +
    "-v" +
    plan.reference.version.to_string() +
    "-a" +
    number.to_string()
  let running : @animatic_domain.AnimaticRenderAttempt = {
    contract: "mooncast.animatic-render-attempt.v1",
    attempt_id,
    plan: plan.reference,
    attempt: number,
    state: "running",
    started_at: request.rendered_at,
    completed_at: None,
    failure: None,
    process_effect_performed: false,
    network_effect_performed: false,
    publication_authority: false,
  }
  self.persist_attempt(running)
  let media_id = digest(plan.reference.digest)[7:31].to_owned()
  let sheet_key = "storyboard-sheet-" + media_id + ".png"
  let video_key = "timed-animatic-" + media_id + ".mp4"
  self.render_media(plan, sheet_key, video_key) catch {
    error => {
      self.persist_attempt({
        ..running,
        state: "failed",
        completed_at: Some(request.rendered_at),
        failure: Some("native_render_failed"),
        process_effect_performed: true,
      })
      raise error
    }
  }
  guard self.media.get_blob(sheet_key) is Some(sheet) &&
    self.media.get_blob(video_key) is Some(video) else {
    raise AnimaticRenderFailed("rendered_media_missing")
  }
  let actual = plan.panels.length().to_double() * 0.1
  let budget : @animatic_domain.AnimaticBudgetReceipt = {
    currency: "CNY",
    planned_cny: plan.cost_ceiling_cny,
    actual_cny: actual,
    within_ceiling: actual <= plan.cost_ceiling_cny,
    evidence_digest: digest(plan.reference.digest + ":" + actual.to_string()),
  }
  guard budget.within_ceiling else {
    raise AnimaticRenderFailed("cost_ceiling_exceeded")
  }
  let version = plan.reference.version
  let core : @animatic_domain.RenderedAnimatic = {
    contract: "mooncast.rendered-animatic.v1",
    reference: { id: project_id + "-rendered-animatic", version, digest: "" },
    plan: plan.reference,
    project_id,
    project_revision_anchor: plan.project_revision,
    bible: plan.bible,
    script: plan.script,
    storyboard: plan.storyboard,
    approved_assets: plan.approved_assets,
    temporary_voice_asset_ids: plan.temporary_voice_asset_ids,
    temporary_music_asset_ids: plan.temporary_music_asset_ids,
    panel_count: plan.panels.length(),
    duration_seconds: plan.panels.fold(init=0, (sum, panel) => {
      sum + panel.duration_ms
    }) /
    1000,
    storyboard_sheet_key: sheet.key,
    storyboard_sheet_digest: "sha256:" + sheet.sha256,
    video_key: video.key,
    video_digest: "sha256:" + video.sha256,
    caption_language: plan.caption_language,
    transitions: plan.panels.map(panel => panel.transition),
    provider: plan.provider,
    model: plan.model,
    budget,
    provenance_digest: "",
    created_at: request.rendered_at,
    process_effect_performed: true,
    network_effect_performed: false,
    publication_authority: false,
    immutable: true,
  }
  let provenance = digest(core.to_json().stringify())
  let exact = {
    ..core,
    reference: {
      ..core.reference,
      digest: digest(provenance + ":" + video.sha256),
    },
    provenance_digest: provenance,
  }
  ignore(self.state.put_json(render_key(project_id, version), exact.to_json()))
  self.persist_attempt({
    ..running,
    state: "completed",
    completed_at: Some(request.rendered_at),
    process_effect_performed: true,
  })
  exact
}

///|
pub async fn AnimaticService::list_attempts(
  self : AnimaticService,
  project_id : String,
) -> Array[@animatic_domain.AnimaticRenderAttempt] {
  let values : Array[@animatic_domain.AnimaticRenderAttempt] = []
  for
    key in self.state.list_keys(
      prefix="animatic-attempt-" + project_id + "-",
      suffix=".json",
    ) {
    match self.state.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
pub async fn AnimaticService::list_renders(
  self : AnimaticService,
  project_id : String,
) -> Array[@animatic_domain.RenderedAnimatic] {
  let values : Array[@animatic_domain.RenderedAnimatic] = []
  for
    key in self.state.list_keys(
      prefix="animatic-render-" + project_id + "-",
      suffix=".json",
    ) {
    match self.state.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
pub async fn AnimaticService::approve(
  self : AnimaticService,
  project_id : String,
  request : AnimaticApprovalRequest,
) -> @animatic_domain.RenderedAnimaticApproval {
  let matches = self
    .list_renders(project_id)
    .filter(value => {
      value.reference.version == request.expected_render_version &&
      value.reference.digest == request.expected_render_digest
    })
  guard matches.length() == 1 &&
    request.actor != "" &&
    request.actor_role != "" &&
    request.approved_at != "" &&
    request.human_confirmed else {
    raise AnimaticConflict("approval must bind exact render and named human")
  }
  let base : @animatic_domain.RenderedAnimaticApproval = {
    contract: "mooncast.rendered-animatic-approval.v1",
    rendered: matches[0],
    decision: "approve",
    actor: request.actor,
    actor_role: request.actor_role,
    note: request.note,
    approved_at: request.approved_at,
    human_confirmed: true,
    approval_digest: "",
    publication_authority: false,
    immutable: true,
  }
  let exact = {
    ..base,
    approval_digest: @animatic_domain.approval_digest(base),
  }
  let key = approval_key(project_id, request.expected_render_version)
  match self.state.get_json(key) {
    Some(value) => {
      let prior : @animatic_domain.RenderedAnimaticApproval = @json.from_json(
        value,
      )
      guard prior == exact else {
        raise AnimaticConflict("render version already decided")
      }
      prior
    }
    None => {
      ignore(self.state.put_json(key, exact.to_json()))
      exact
    }
  }
}

///|
pub async fn AnimaticService::list_approvals(
  self : AnimaticService,
  project_id : String,
) -> Array[@animatic_domain.RenderedAnimaticApproval] {
  let values : Array[@animatic_domain.RenderedAnimaticApproval] = []
  for
    key in self.state.list_keys(
      prefix="animatic-approval-" + project_id + "-",
      suffix=".json",
    ) {
    match self.state.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
pub async fn AnimaticService::workspace(
  self : AnimaticService,
  project_id : String,
) -> @animatic_domain.AnimaticWorkspace {
  {
    plans: self.list_plans(project_id),
    attempts: self.list_attempts(project_id),
    renders: self.list_renders(project_id),
    approvals: self.list_approvals(project_id),
    publication_authority: false,
  }
}

///|
pub async fn AnimaticService::media(
  self : AnimaticService,
  project_id : String,
  version : Int,
  kind : String,
) -> @store.StoredBlob {
  let matches = self
    .list_renders(project_id)
    .filter(value => value.reference.version == version)
  guard matches.length() == 1 else { raise AnimaticNotFound(project_id) }
  let key = if kind == "sheet" {
    matches[0].storyboard_sheet_key
  } else {
    matches[0].video_key
  }
  guard self.media.get_blob(key) is Some(blob) else {
    raise AnimaticNotFound(key)
  }
  blob
}
