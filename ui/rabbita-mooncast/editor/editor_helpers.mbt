///|
fn parse_number(value : String, fallback : Double) -> Double {
  @string.parse_double(value.trim()) catch {
    _ => fallback
  }
}

///|
fn parse_whole(value : String, fallback : Int) -> Int {
  @string.parse_int(value.trim().to_owned()) catch {
    _ => fallback
  }
}

///|
fn[T] option_or(first : T?, second : T?) -> T? {
  match first {
    Some(value) => Some(value)
    None => second
  }
}

///|
fn take_position(items : Array[@api.TakeVariant], id : String) -> Int {
  for index, item in items {
    if item.take_id == id {
      break index
    }
  } nobreak {
    0
  }
}

///|
fn clip_position(items : Array[@api.Clip], id : String) -> Int {
  for index, item in items {
    if item.clip_id == id {
      break index
    }
  } nobreak {
    0
  }
}

///|
fn append_string(items : Array[String], value : String) -> Array[String] {
  let next : Array[String] = []
  for item in items {
    next.push(item)
  }
  next.push(value)
  next
}

///|
fn drop_last_string(items : Array[String]) -> Array[String] {
  let next : Array[String] = []
  for index, item in items {
    if index + 1 < items.length() {
      next.push(item)
    }
  }
  next
}

///|
fn last_string(items : Array[String]) -> String? {
  if items.length() == 0 {
    None
  } else {
    Some(items[items.length() - 1])
  }
}

///|
fn flatten_tracks(items : Array[@api.Track]) -> Array[@api.Clip] {
  let result : Array[@api.Clip] = []
  for track in items {
    for clip in track.clips {
      result.push(clip)
    }
  }
  result
}

///|
fn bounded_tick(model : Model, tick : Int) -> Int {
  Int::min(Int::max(0, tick), duration_ticks(model))
}

///|
fn take_is_eligible(take : @api.TakeVariant) -> Bool {
  take.approved && !take.already_placed && take.add_clip_template is Some(_)
}

///|
fn take_eligibility(take : @api.TakeVariant?) -> String {
  match take {
    None => "Select a take to inspect eligibility."
    Some(value) if value.already_placed =>
      "Already placed on the authoritative timeline."
    Some(value) if value.qc.status != "passed" =>
      "QC \{value.qc.status}; adding is blocked."
    Some(value) if value.rights.status != "cleared" =>
      "Rights \{value.rights.status}; adding is blocked."
    Some(value) if !value.approved || value.add_clip_template is None =>
      "No server-approved add template is available."
    Some(value) => "Eligible for \{value.track_id}."
  }
}

///|
fn lower(value : String) -> String {
  value.to_lower()
}

///|
fn take_kind_matches(filter : String, take : @api.TakeVariant) -> Bool {
  let role = lower(take.role)
  let mime = lower(take.source.mime.unwrap_or(""))
  match filter {
    "all" => true
    "video" => take.track_kind == "video" && mime.has_prefix("video/")
    "image" => mime.has_prefix("image/")
    "audio" => take.track_kind == "audio"
    "voice" => role == "voice" || role == "dialogue"
    "music" => role == "music" || role == "sfx"
    "overlay" => take.track_kind == "overlay"
    "subtitle" => role == "subtitle"
    _ => lower(take.track_kind) == filter
  }
}

///|
fn take_origin(take : @api.TakeVariant) -> String {
  if take.provider_ref is Some(_) || take.attempt_id is Some(_) {
    "Generated"
  } else if take.local_media is Some(_) {
    "Local"
  } else {
    "Declared"
  }
}

///|
fn take_matches(model : Model, take : @api.TakeVariant) -> Bool {
  let filters = model.filters
  let query = lower(filters.search.trim().to_owned())
  let haystack = lower(
    "\{take.take_id} \{take.asset_id} \{take.shot_id} \{take.scene_id} \{take.variant} \{take.role} \{take.registry_digest}",
  )
  let eligible = take_is_eligible(take)
  (query == "" || haystack.contains(query)) &&
  take_kind_matches(filters.kind, take) &&
  (
    filters.qc == "all" ||
    (filters.qc == "passed" && take.qc.status == "passed") ||
    (filters.qc == "other" && take.qc.status != "passed")
  ) &&
  (
    filters.rights == "all" ||
    (filters.rights == "cleared" && take.rights.status == "cleared") ||
    (filters.rights == "other" && take.rights.status != "cleared")
  ) &&
  (
    filters.placement == "all" ||
    (filters.placement == "eligible" && eligible) ||
    (filters.placement == "placed" && take.already_placed) ||
    (filters.placement == "unplaced" && !take.already_placed) ||
    (filters.placement == "ineligible" && !eligible)
  )
}

///|
fn filtered_takes(model : Model) -> Array[@api.TakeVariant] {
  takes(model).filter(take => take_matches(model, take))
}

///|
fn decode_project_response(value : Json) -> Array[@api.ProjectSummary]? {
  let direct : Array[NativeProjectSummary] = @json.from_json(value) catch {
    _ => {
      let envelope : @api.ProjectListEnvelope = @json.from_json(value) catch {
        _ => return None
      }
      return Some(envelope.data)
    }
  }
  Some(
    direct.map(item => {
      project_id: item.project_id,
      revision: item.revision,
      title: item.project_id,
      fixture: false,
      publication_authority: false,
      provider_authority: false,
    }),
  )
}

///|
fn native_take_variant(
  value : NativeTakeRecord,
  snapshot : @api.CanonicalSnapshot,
) -> @api.TakeVariant {
  let placed = flatten_tracks(snapshot.timeline.tracks)
    .iter()
    .find_first(clip => clip.media_ref_id == value.media_ref_id)
  let template_clip = value.add_clip_template.map(item => item.clip)
  let clip = option_or(template_clip, placed)
  let duration = clip.map(item => item.duration_ticks).unwrap_or(1)
  let intent_ref = clip
    .map(item => item.intent.intent_ref)
    .unwrap_or("mooncast:editor-role:" + value.role)
  {
    take_id: value.take_id,
    role: value.role,
    variant: "canonical",
    project_id: value.identity.project_id,
    episode_id: value.identity.episode_id,
    scene_id: value.identity.scene_id,
    shot_id: value.identity.shot_id,
    asset_id: value.identity.asset_id,
    duration_ticks: duration,
    qc: {
      status: if value.approved {
        "passed"
      } else {
        "pending"
      },
      findings: Some([]),
    },
    rights: {
      status: if value.approved {
        "cleared"
      } else {
        "pending"
      },
      findings: Some([]),
    },
    provider_ref: None,
    model_ref: None,
    model_version: None,
    prompt_digest: None,
    attempt_id: None,
    media_ref_id: value.media_ref_id,
    registry_digest: value.media_digest,
    local_media: None,
    track_id: value.track_id,
    track_kind: value.track_kind,
    already_placed: value.already_placed || placed is Some(_),
    approved: value.approved,
    intent_ref,
    source: {
      state: if value.source_url == "" {
        "unavailable"
      } else {
        "available"
      },
      mime: Some(value.mime_type),
      media_url: if value.source_url == "" {
        None
      } else {
        Some(value.source_url)
      },
      analysis_url: if value.analysis_url == "" {
        None
      } else {
        Some(value.analysis_url)
      },
      thumbnail_url: if value.thumbnail_url == "" {
        None
      } else {
        Some(value.thumbnail_url)
      },
      proxy_state: Some(value.proxy_state),
      proxy_digest: if value.proxy_state == "ready" {
        Some(value.media_digest)
      } else {
        None
      },
      proxy_profile: if value.proxy_state == "ready" {
        Some("canonical-editor-proxy")
      } else {
        None
      },
      proxy_url: if value.proxy_state == "ready" && value.source_url != "" {
        Some(value.source_url)
      } else {
        None
      },
      digest: Some(value.media_digest),
    },
    add_clip_template: value.add_clip_template,
  }
}

///|
fn native_workspace(value : NativeEditorOpen) -> @api.WorkspaceSnapshot {
  let comments = value.review_comments.map(item => {
    (
      {
        annotation_id: None,
        comment_id: Some(item.comment_id),
        kind: "review",
        start_tick: Some(item.range.start_tick),
        end_tick: Some(item.range.start_tick + item.range.duration_ticks),
        range: Some({
          start_tick: item.range.start_tick,
          end_tick: item.range.start_tick + item.range.duration_ticks,
        }),
        text: Some(item.text),
      } : @api.Annotation)
  })
  {
    project_id: Some(value.project_id),
    revision: value.revision,
    navigator: Some(value.snapshot.identity_graph.unwrap_or([])),
    identity_graph: value.snapshot.identity_graph,
    take_variants: Some(
      value.takes.map(take => native_take_variant(take, value.snapshot)),
    ),
    timeline: Some(value.snapshot.timeline),
    snapshot: Some(value.snapshot),
    command_log: Some(value.command_log),
    continuity_qc_overlays: Some([]),
    review_comments: Some(comments),
    delivery_intents: Some([]),
    production_source: value.production_source,
    master_promotion: value.master_promotion,
    publication_authority: Some(value.publication_authority),
    provider_authority: Some(value.provider_authority),
  }
}

///|
fn decode_workspace_response(value : Json) -> @api.WorkspaceSnapshot? {
  let direct : NativeEditorOpen = @json.from_json(value) catch {
    _ => {
      let envelope : @api.WorkspaceEnvelope = @json.from_json(value) catch {
        _ => return None
      }
      return Some(envelope.data)
    }
  }
  Some(native_workspace(direct))
}

///|
fn decode_api_error(value : Json) -> @api.ApiErrorBody? {
  let envelope : @api.ErrorEnvelope = @json.from_json(value) catch {
    _ => return None
  }
  envelope.error
}

///|
fn decode_mutation_response(
  value : Json,
  current : @api.WorkspaceSnapshot,
) -> @api.WorkspaceSnapshot? {
  let direct : NativeEditorOpen = @json.from_json(value) catch {
    _ => {
      let envelope : @api.MutationEnvelope = @json.from_json(value) catch {
        _ => return None
      }
      return Some({
        ..current,
        revision: envelope.data.revision,
        snapshot: Some(envelope.data.snapshot),
      })
    }
  }
  Some(native_workspace(direct))
}

///|
fn decode_analysis_response(value : Json) -> @api.MediaAnalysis? {
  let direct : NativeMediaAnalysis = @json.from_json(value) catch {
    _ => {
      let envelope : @api.AnalysisEnvelope = @json.from_json(value) catch {
        _ => return None
      }
      return Some(envelope.data)
    }
  }
  Some({
    contract: direct.contract,
    state: direct.state,
    source_digest: direct.source_digest,
    analysis_digest: direct.analysis_digest,
    thumbnail_url: direct.thumbnail_url,
    duration_seconds: direct.duration_seconds,
    thumbnail: Some(direct.thumbnail),
    waveform: Some({
      state: direct.waveform.state,
      peaks: direct.waveform.peaks.map(value => Double::from_int(value)),
    }),
    video: Some(direct.video),
    audio: Some(direct.audio),
  })
}

///|
fn decode_intake_prepared(value : Json) -> NativePreparedIntake? {
  let direct : NativePreparedIntake = @json.from_json(value) catch {
    _ => {
      let envelope : @api.IntakeEnvelope = @json.from_json(value) catch {
        _ => return None
      }
      return Some({
        intake_id: envelope.data.intake_id,
        upload_url: envelope.data.upload_url,
        status: "awaiting-content",
      })
    }
  }
  Some(direct)
}

///|
fn merge_workspace(
  current : @api.WorkspaceSnapshot?,
  incoming : @api.WorkspaceSnapshot,
) -> @api.WorkspaceSnapshot {
  match current {
    None => incoming
    Some(previous) =>
      {
        ..previous,
        revision: incoming.revision,
        navigator: option_or(incoming.navigator, previous.navigator),
        identity_graph: option_or(
          incoming.identity_graph,
          previous.identity_graph,
        ),
        take_variants: option_or(incoming.take_variants, previous.take_variants),
        timeline: option_or(incoming.timeline, previous.timeline),
        snapshot: option_or(incoming.snapshot, previous.snapshot),
        command_log: option_or(incoming.command_log, previous.command_log),
        continuity_qc_overlays: option_or(
          incoming.continuity_qc_overlays,
          previous.continuity_qc_overlays,
        ),
        review_comments: option_or(
          incoming.review_comments,
          previous.review_comments,
        ),
        delivery_intents: option_or(
          incoming.delivery_intents,
          previous.delivery_intents,
        ),
        production_source: option_or(
          incoming.production_source,
          previous.production_source,
        ),
        master_promotion: option_or(
          incoming.master_promotion,
          previous.master_promotion,
        ),
      }
  }
}

///|
fn normalized_after_snapshot(
  model : Model,
  workspace : @api.WorkspaceSnapshot,
) -> Model {
  let merged = merge_workspace(model.workspace, workspace)
  let available_takes = merged.take_variants.unwrap_or([])
  let take_id = if available_takes.any(take => {
      take.take_id == model.selected_take_id
    }) {
    model.selected_take_id
  } else {
    option_or(
      available_takes.iter().find_first(take_is_eligible),
      available_takes.get(0),
    )
    .map(take => take.take_id)
    .unwrap_or("")
  }
  let canonical_clips = match merged.snapshot {
    Some(value) => flatten_tracks(value.timeline.tracks)
    None =>
      merged.timeline.map(value => flatten_tracks(value.tracks)).unwrap_or([])
  }
  let selected = model.selected_clip_ids.filter(id => {
    canonical_clips.any(clip => clip.clip_id == id)
  })
  let selected = if selected.length() == 0 && canonical_clips.length() > 0 {
    [canonical_clips[0].clip_id]
  } else {
    selected
  }
  let export_state = match merged.master_promotion {
    Some(promotion) => {
      let preserve_handoff = model.export_state.job_id == promotion.job_id
      {
        ..model.export_state,
        actor: promotion.actor,
        authority_ref: promotion.authority_ref,
        job_id: promotion.job_id,
        download_url: promotion.video_ref,
        promoted: true,
        handed_off: preserve_handoff && model.export_state.handed_off,
        receipt_state: "succeeded",
        canonical_revision: promotion.project_revision,
        timeline_revision: promotion.editor_revision,
        output_digest: promotion.digest,
        render_plan_digest: promotion.plan_digest,
        handoff_record_id: if preserve_handoff {
          model.export_state.handoff_record_id
        } else {
          ""
        },
        handoff_record_digest: if preserve_handoff {
          model.export_state.handoff_record_digest
        } else {
          ""
        },
        handoff_request_id: if preserve_handoff {
          model.export_state.handoff_request_id
        } else {
          ""
        },
        handoff_status: if preserve_handoff {
          model.export_state.handoff_status
        } else {
          "not-prepared"
        },
      }
    }
    None => model.export_state
  }
  {
    ..model,
    workspace: Some(merged),
    selected_take_id: take_id,
    selected_clip_ids: selected,
    export_state,
    playhead_ticks: Int::min(
      model.playhead_ticks,
      canonical_clips.fold(init=0, (n, clip) => {
        Int::max(n, clip.start_tick + clip.duration_ticks)
      }),
    ),
    loading: false,
    busy: false,
    error: "",
    conflict: "",
    retry: None,
    status: "Saved · authoritative revision \{merged.revision}",
  }
}

///|
fn selected_clip_track(model : Model) -> (@api.Clip, @api.Track)? {
  guard selected_clip(model) is Some(clip) else { return None }
  guard track_for_clip(model, clip.clip_id) is Some(track) else { return None }
  Some((clip, track))
}

///|
fn editor_base_color(value : String) -> String {
  if value.length() >= 7 {
    value[:7].to_owned()
  } else {
    value
  }
}

///|
fn inspector_for_clip(model : Model, clip_id : String) -> InspectorDraft {
  let draft = model.inspector
  guard clips(model).iter().find_first(clip => clip.clip_id == clip_id)
    is Some(clip) else {
    return draft
  }
  let settings = clip.settings
  let color = settings.bind(value => value.color)
  let effect = settings.bind(value => value.effect)
  let overlay = settings.bind(value => value.overlay)
  let track_mix = track_for_clip(model, clip_id).bind(track => track.mix)
  {
    ..draft,
    brightness: option_or(
      settings.bind(value => value.brightness),
      color.map(value => value.brightness),
    )
    .map(value => value.to_string())
    .unwrap_or(draft.brightness),
    contrast: option_or(
      settings.bind(value => value.contrast),
      color.map(value => value.contrast),
    )
    .map(value => value.to_string())
    .unwrap_or(draft.contrast),
    saturation: option_or(
      settings.bind(value => value.saturation),
      color.map(value => value.saturation),
    )
    .map(value => value.to_string())
    .unwrap_or(draft.saturation),
    gamma: option_or(
      settings.bind(value => value.gamma),
      color.map(value => value.gamma),
    )
    .map(value => value.to_string())
    .unwrap_or(draft.gamma),
    opacity: option_or(
      settings.bind(value => value.opacity),
      effect.map(value => value.opacity),
    )
    .map(value => value.to_string())
    .unwrap_or(draft.opacity),
    scale: option_or(
      settings.bind(value => value.scale),
      effect.map(value => value.scale),
    )
    .map(value => value.to_string())
    .unwrap_or(draft.scale),
    position_x: option_or(
      settings.bind(value => value.position_x),
      effect.map(value => value.x),
    )
    .map(value => value.to_string())
    .unwrap_or(draft.position_x),
    position_y: option_or(
      settings.bind(value => value.position_y),
      effect.map(value => value.y),
    )
    .map(value => value.to_string())
    .unwrap_or(draft.position_y),
    overlay_text: overlay.map(value => value.text).unwrap_or(draft.overlay_text),
    overlay_position: overlay
    .map(value => value.position)
    .unwrap_or(draft.overlay_position),
    overlay_size: overlay
    .map(value => value.font_size.to_string())
    .unwrap_or(draft.overlay_size),
    overlay_color: overlay
    .map(value => editor_base_color(value.color))
    .unwrap_or(draft.overlay_color),
    overlay_background: overlay
    .map(value => editor_base_color(value.background))
    .unwrap_or(draft.overlay_background),
    track_volume_db: track_mix
    .map(value => value.volume_db.to_string())
    .unwrap_or(draft.track_volume_db),
    track_pan: track_mix
    .map(value => value.pan.to_string())
    .unwrap_or(draft.track_pan),
    track_muted: track_mix
    .map(value => value.muted)
    .unwrap_or(draft.track_muted),
  }
}

///|
fn make_command_body(model : Model, kind : String, payload : Json) -> Json {
  {
    "command": { "type": kind, "payload": payload },
    "expected_revision": selected_revision(model),
    "idempotency_key": fresh_key(model, kind),
  }
}

///|
fn editor_job_payload(response : EditorJobResponse) -> EditorJobPayload {
  match response.data {
    Some(value) => value
    None =>
      {
        session_id: response.session_id,
        job_id: response.job_id,
        state: response.state,
        status: response.status,
        attempts: response.attempts,
        max_attempts: response.max_attempts,
        output_digest: response.output_digest,
        media_url: response.media_url,
        result: response.result,
      }
  }
}

///|
fn response_error_message(error : @api.ApiErrorBody?) -> String? {
  error.map(value => value.code + ": " + value.message)
}

///|
fn valid_sha256(value : String) -> Bool {
  value.has_prefix("sha256:") && value.length() == 71
}

///|
fn accepted_editor_job_response(
  response : EditorJobResponse,
  expected_job_id : String,
  export_receipt_required : Bool,
) -> EditorJobPayload? {
  guard response.error is None else { return None }
  let job = editor_job_payload(response)
  let id = job_id(job)
  let state = option_or(job.state, job.status).unwrap_or("")
  guard !id.is_blank() &&
    (expected_job_id.is_blank() || id == expected_job_id) &&
    (
      state == "queued" ||
      state == "running" ||
      state == "failed" ||
      state == "succeeded"
    ) else {
    return None
  }
  if export_receipt_required && state == "succeeded" {
    guard job.result.bind(value => value.export_receipt) is Some(receipt) &&
      valid_sha256(receipt.digest) &&
      valid_sha256(receipt.plan_digest) &&
      receipt.output_ref is Some(output_ref) &&
      !output_ref.is_blank() &&
      job.output_digest == Some(receipt.digest) &&
      job.media_url == Some(output_ref) else {
      return None
    }
  }
  Some(job)
}

///|
fn job_id(job : EditorJobPayload) -> String {
  option_or(job.session_id, job.job_id).unwrap_or("")
}

///|
fn preview_state(job : EditorJobPayload) -> String {
  option_or(job.state, job.status).unwrap_or("queued")
}

///|
fn editor_digest(seed : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(seed)))
}

///|
fn record_ref_json(id : String, digest : String, provenance : String) -> Json {
  {
    "record_id": id,
    "record_version": "1",
    "record_digest": digest,
    "provenance_ref": provenance,
  }
}

///|
fn exact_production_source(model : Model) -> @api.ProductionSource? {
  guard model.workspace.bind(value => value.production_source) is Some(source) &&
    source.contract == Some("mooncast.editor-production-source-binding.v1") &&
    source.project_id == Some(model.project_id) &&
    source.episode_id is Some(episode_id) &&
    !episode_id.is_blank() &&
    source.production_revision is Some(production_revision) &&
    production_revision > 0 &&
    source.g4_snapshot_revision is Some(g4_revision) &&
    g4_revision > 0 &&
    g4_revision <= production_revision &&
    source.production_digest is Some(production_digest) &&
    valid_sha256(production_digest) &&
    source.g4_evidence_digest is Some(g4_evidence_digest) &&
    valid_sha256(g4_evidence_digest) &&
    source.g4_receipt_digest is Some(g4_receipt_digest) &&
    valid_sha256(g4_receipt_digest) &&
    source.binding_digest is Some(binding_digest) &&
    valid_sha256(binding_digest) &&
    source.provenance_ref is Some(provenance_ref) &&
    !provenance_ref.is_blank() &&
    source.publication_authority == Some(false) &&
    source.provider_authority == Some(false) else {
    return None
  }
  Some(source)
}

///|
fn episode_id(model : Model) -> String {
  exact_production_source(model).bind(source => source.episode_id).unwrap_or("")
}

///|
fn deliverable_record_id(model : Model) -> String {
  "deliverable-" + model.project_id + "-" + model.export_state.job_id
}

///|
fn handoff_source_refs(model : Model) -> Array[Json]? {
  guard exact_production_source(model) is Some(source) &&
    source.project_id is Some(production_project_id) &&
    source.production_revision is Some(production_revision) &&
    source.binding_digest is Some(binding_digest) &&
    source.provenance_ref is Some(provenance_ref) else {
    return None
  }
  let revision = selected_revision(model)
  Some([
    record_ref_json(
      model.project_id + "-editor-workflow-r" + revision.to_string(),
      editor_digest(
        model.project_id + ":editor-workflow:" + revision.to_string(),
      ),
      "/api/editor/projects/" + model.project_id + "/snapshot",
    ),
    record_ref_json(
      model.export_state.job_id + "-render-plan",
      model.export_state.render_plan_digest,
      "/api/editor/projects/" +
      model.project_id +
      "/exports/" +
      model.export_state.job_id,
    ),
    record_ref_json(
      production_project_id +
      "-production-source-r" +
      production_revision.to_string(),
      binding_digest,
      provenance_ref,
    ),
  ])
}

///|
fn timeline_scale(model : Model) -> Double {
  96.0 * model.zoom / Double::from_int(ticks_per_second(model))
}

///|
fn quantize_ticks(model : Model, value : Int) -> Int {
  guard model.snap else { return value }
  let frame = Int::max(1, frame_ticks(model))
  if value >= 0 {
    (value + frame / 2) / frame * frame
  } else {
    (value - frame / 2) / frame * frame
  }
}

///|
fn snap_target(model : Model, wanted : Int, ignored_clip_id : String) -> Int {
  guard model.snap else { return wanted }
  let threshold = Int::max(frame_ticks(model) * 3, ticks_per_second(model) / 20)
  let points : Array[Int] = [0, model.playhead_ticks]
  for clip in clips(model) {
    if clip.clip_id != ignored_clip_id &&
      !model.selected_clip_ids.contains(clip.clip_id) {
      points.push(clip.start_tick)
      points.push(clip.start_tick + clip.duration_ticks)
    }
  }
  let mut best = wanted
  let mut distance = threshold + 1
  for point in points {
    let gap = (point - wanted).abs()
    if gap < distance {
      best = point
      distance = gap
    }
  }
  if distance <= threshold {
    best
  } else {
    wanted
  }
}

///|
fn drag_delta(model : Model, drag : TimelineDrag, mouse_x : Int) -> Int {
  guard clips(model).iter().find_first(clip => clip.clip_id == drag.clip_id)
    is Some(clip) else {
    return 0
  }
  let raw = (Double::from_int(mouse_x - drag.origin_client_x) /
  timeline_scale(model)).to_int()
  let rounded = quantize_ticks(model, raw)
  let anchor = match drag.mode {
    DragMove | DragTrimStart => clip.start_tick
    DragTrimEnd => clip.start_tick + clip.duration_ticks
  }
  let snapped = snap_target(model, anchor + rounded, clip.clip_id) - anchor
  let chosen = clips(model).filter(item => {
    model.selected_clip_ids.contains(item.clip_id)
  })
  match drag.mode {
    DragMove => {
      let earliest = chosen.fold(init=clip.start_tick, (value, item) => {
        Int::min(value, item.start_tick)
      })
      Int::max(-earliest, snapped)
    }
    DragTrimStart => {
      let shrink = chosen.fold(init=clip.duration_ticks - frame_ticks(model), (
        value,
        item,
      ) => Int::min(value, item.duration_ticks - frame_ticks(model)))
      let extend = chosen.fold(init=clip.source_in_tick, (value, item) => {
        Int::min(value, item.source_in_tick)
      })
      Int::min(shrink, Int::max(-extend, snapped))
    }
    DragTrimEnd => {
      let shrink = chosen.fold(init=clip.duration_ticks - frame_ticks(model), (
        value,
        item,
      ) => Int::min(value, item.duration_ticks - frame_ticks(model)))
      let available = chosen.fold(
        init=Int::max(
          0,
          take_for_clip(model, clip)
          .map(take => take.duration_ticks - clip.source_out_tick)
          .unwrap_or(0),
        ),
        (value, item) => {
          Int::min(
            value,
            Int::max(
              0,
              take_for_clip(model, item)
              .map(take => take.duration_ticks - item.source_out_tick)
              .unwrap_or(0),
            ),
          )
        },
      )
      Int::max(-shrink, Int::min(available, snapped))
    }
  }
}

///|
fn preview_geometry(model : Model, clip : @api.Clip) -> (Int, Int) {
  match model.timeline_drag {
    Some(drag) if model.selected_clip_ids.contains(clip.clip_id) =>
      match drag.mode {
        DragMove =>
          (clip.start_tick + drag.preview_delta_ticks, clip.duration_ticks)
        DragTrimStart =>
          (
            clip.start_tick + drag.preview_delta_ticks,
            clip.duration_ticks - drag.preview_delta_ticks,
          )
        DragTrimEnd =>
          (clip.start_tick, clip.duration_ticks + drag.preview_delta_ticks)
      }
    _ => (clip.start_tick, clip.duration_ticks)
  }
}

///|
fn clip_is_active(clip : @api.Clip, tick : Int) -> Bool {
  tick >= clip.start_tick && tick < clip.start_tick + clip.duration_ticks
}

///|
fn take_for_clip(model : Model, clip : @api.Clip) -> @api.TakeVariant? {
  takes(model).iter().find_first(take => take.media_ref_id == clip.media_ref_id)
}

///|
fn program_media_url(take : @api.TakeVariant) -> String {
  option_or(take.source.proxy_url, take.source.media_url).unwrap_or("")
}

///|
fn program_media_id(clip : @api.Clip) -> String {
  "program-media-" + clip.clip_id
}

///|
fn active_track_clip(model : Model, track : @api.Track) -> @api.Clip? {
  track.clips
  .iter()
  .find_first(clip => clip_is_active(clip, model.playhead_ticks))
}

///|
fn vertical_output(model : Model) -> Bool {
  timeline(model)
  .bind(value => value.output)
  .bind(value => value.preset)
  .unwrap_or(model.export_state.output_preset)
  .contains("vertical")
}

///|
fn program_width(model : Model) -> Double {
  if vertical_output(model) {
    540.0
  } else {
    960.0
  }
}

///|
fn program_height(model : Model) -> Double {
  if vertical_output(model) {
    960.0
  } else {
    540.0
  }
}

///|
fn editor_subscriptions(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @sub.Sub {
  let subscriptions = [
    @sub.on_key_down(key => dispatch(KeyPressed(key))),
    @sub.on_resize(size => dispatch(Resized(size))),
    @sub.on_url_request(request => dispatch(UrlRequested(request))),
  ]
  if model.playing {
    subscriptions.push(
      @sub.on_animation_frame(now => dispatch(AnimationFrame(now))),
    )
  } else if model.monitor_mode == ProgramMonitor &&
    model.program_surface == InteractiveProxy &&
    model.workspace is Some(_) {
    subscriptions.push(@sub.every(250, dispatch(RefreshProgramMedia)))
  }
  if model.timeline_drag is Some(_) {
    subscriptions.push(
      @sub.on_mouse_move(mouse => dispatch(TimelinePointerMoved(mouse))),
    )
  }
  if model.workspace_canvas_drag is Some(_) {
    subscriptions.push(
      @sub.on_mouse_move(mouse => dispatch(WorkspaceCanvasPointerMoved(mouse))),
    )
  }
  if !model.workspace_run_id.is_blank() &&
    !model.workspace_run_state.contains("SucceededRun") &&
    !model.workspace_run_state.contains("FailedRun") &&
    !model.workspace_run_state.contains("CancelledRun") {
    subscriptions.push(@sub.every(1000, dispatch(PollWorkspaceRun)))
  }
  match model.preview_job {
    Some(job) if preview_state(job) == "queued" ||
      preview_state(job) == "running" ||
      preview_state(job) == "pending" =>
      subscriptions.push(
        @sub.every(500, dispatch(PollPreview(model.preview_generation))),
      )
    _ => ()
  }
  @sub.batch(subscriptions)
}

///|
fn draw_proxy_media(
  context : @dom.CanvasRenderingContext2D,
  clip : @api.Clip,
  take : @api.TakeVariant,
  canvas_width : Double,
  canvas_height : Double,
) -> Bool {
  guard @dom.document().get_element_by_id(program_media_id(clip)).to_option()
    is Some(element) else {
    return false
  }
  let effect = clip.settings.bind(value => value.effect)
  let scale = option_or(
    clip.settings.bind(value => value.scale),
    effect.map(value => value.scale),
  ).unwrap_or(1.0)
  let x = option_or(
    clip.settings.bind(value => value.position_x),
    effect.map(value => value.x),
  ).unwrap_or(0.0)
  let y = option_or(
    clip.settings.bind(value => value.position_y),
    effect.map(value => value.y),
  ).unwrap_or(0.0)
  let width = canvas_width * scale
  let height = canvas_height * scale
  let dx = (canvas_width - width) / 2.0 +
    x * (canvas_width - Double::min(canvas_width, width)) / 2.0
  let dy = (canvas_height - height) / 2.0 +
    y * (canvas_height - Double::min(canvas_height, height)) / 2.0
  let mime = take.source.mime.unwrap_or("")
  if mime.has_prefix("video/") {
    guard element.to_html_video_element() is Some(video) else { return false }
    guard video.get_ready_state() >= 2 else { return false }
    let source : @dom.ImageUnion = @js.Union7::from2(video)
    context.draw_image_with_size(source, dx, dy, width, height)
    true
  } else if mime.has_prefix("image/") {
    guard element.to_html_image_element() is Some(image) else { return false }
    guard image.get_complete() else { return false }
    let source : @dom.ImageUnion = @js.Union7::from0(image)
    context.draw_image_with_size(source, dx, dy, width, height)
    true
  } else {
    false
  }
}

///|
fn draw_text_overlay(
  context : @dom.CanvasRenderingContext2D,
  clip : @api.Clip,
  canvas_width : Double,
  canvas_height : Double,
) -> Bool {
  guard clip.settings.bind(value => value.overlay) is Some(overlay) else {
    return false
  }
  guard !overlay.text.trim().is_empty() else { return false }
  let y = match overlay.position {
    "top" => canvas_height * 0.14
    "center" => canvas_height * 0.5
    _ => canvas_height * 0.87
  }
  context.set_fill_style(@js.Union3::from0(overlay.background))
  context.fill_rect(
    canvas_width * 0.06,
    y - Double::from_int(overlay.font_size) - 16.0,
    canvas_width * 0.88,
    Double::from_int(overlay.font_size) + 30.0,
  )
  context.set_fill_style(@js.Union3::from0(overlay.color))
  context.set_font("700 \{overlay.font_size}px ui-sans-serif")
  context.fill_text(overlay.text, canvas_width * 0.085, y)
  true
}

///|
/// Paint the current canonical edit from typed proxy video/image elements.
/// Missing or not-yet-decoded media falls back to a visible evidence frame.
fn paint_program_canvas(model : Model) -> Unit {
  // The interactive compositor currently uses the typed Canvas2D surface;
  // export provider routing remains governed by the canonical render plan.
  guard @canvas.get_context2d("program-canvas") is Some(context) else { return }
  let width = program_width(model)
  let height = program_height(model)
  context.clear_rect(0.0, 0.0, width, height)
  let gradient = context.create_linear_gradient(0.0, 0.0, width, height)
  gradient.add_color_stop(0.0, "#111a35")
  gradient.add_color_stop(1.0, "#050815")
  context.set_fill_style(@js.Union3::from1(gradient))
  context.fill_rect(0.0, 0.0, width, height)
  let mut painted = false
  for track in tracks(model) {
    if track.kind == "video" || track.kind == "overlay" {
      match active_track_clip(model, track) {
        Some(clip) => {
          match take_for_clip(model, clip) {
            Some(take) =>
              if draw_proxy_media(context, clip, take, width, height) {
                painted = true
              }
            None => ()
          }
          if track.kind == "overlay" &&
            draw_text_overlay(context, clip, width, height) {
            painted = true
          }
        }
        None => ()
      }
    }
  }
  if !painted {
    context.set_fill_style(@js.Union3::from0("#73e7c5"))
    context.set_font("600 28px ui-sans-serif")
    context.fill_text("PROXY MEDIA PREPARING", 42.0, 64.0)
    context.set_fill_style(@js.Union3::from0("#8995b8"))
    context.set_font("400 22px ui-sans-serif")
    let line = match
      clips(model)
      .iter()
      .find_first(clip => clip_is_active(clip, model.playhead_ticks)) {
      Some(clip) => "\{clip.clip_id} · proxy decode pending"
      None => "No visual clip at the playhead"
    }
    context.fill_text(line, 42.0, 108.0)
  }
  context.set_fill_style(@js.Union3::from0("rgba(4, 8, 18, 0.72)"))
  context.fill_rect(24.0, 20.0, Double::min(300.0, width - 48.0), 42.0)
  context.set_fill_style(@js.Union3::from0("#dce5ff"))
  context.set_font("500 24px ui-monospace")
  context.fill_text(timecode(model, model.playhead_ticks), 38.0, 49.0)
  let total = Int::max(1, duration_ticks(model))
  let progress = Double::from_int(model.playhead_ticks) /
    Double::from_int(total)
  context.set_fill_style(@js.Union3::from0("#24304f"))
  let progress_width = width - 84.0
  context.fill_rect(42.0, height - 58.0, progress_width, 12.0)
  context.set_fill_style(@js.Union3::from0("#73e7c5"))
  context.fill_rect(42.0, height - 58.0, progress_width * progress, 12.0)
}

///|
fn sync_program_media(model : Model, force_seek : Bool) -> Unit {
  let master_volume = Double::min(
    1.0,
    Double::max(0.0, parse_number(model.volume, 1.0)),
  )
  for track in tracks(model) {
    for clip in track.clips {
      match
        @dom.document().get_element_by_id(program_media_id(clip)).to_option() {
        Some(element) =>
          match element.to_html_media_element() {
            Some(media) => {
              let active = clip_is_active(clip, model.playhead_ticks)
              let mix = track.mix
              let level = Double::min(
                1.0,
                Double::max(
                  0.0,
                  1.0 + mix.map(value => value.volume_db).unwrap_or(0.0) / 60.0,
                ),
              )
              media.set_autoplay(active && model.playing)
              media.set_muted(
                model.muted ||
                mix.map(value => value.muted).unwrap_or(false) ||
                track.kind == "video",
              )
              media.set_volume(master_volume * level)
              if active && force_seek {
                let local_tick = clip.source_in_tick +
                  model.playhead_ticks -
                  clip.start_tick
                media.load()
                media.set_current_time(
                  Double::from_int(Int::max(0, local_tick)) /
                  Double::from_int(ticks_per_second(model)),
                )
              }
              if !active || !model.playing {
                media.pause()
              }
            }
            None => ()
          }
        None => ()
      }
    }
  }
}

///|
fn sync_authoritative_media(model : Model) -> Unit {
  guard @dom.document().get_element_by_id("authoritative-preview").to_option()
    is Some(element) else {
    return
  }
  guard element.to_html_video_element() is Some(video) else { return }
  video.set_current_time(
    Double::from_int(model.playhead_ticks) /
    Double::from_int(ticks_per_second(model)),
  )
  video.set_muted(model.muted)
  video.set_volume(
    Double::min(1.0, Double::max(0.0, parse_number(model.volume, 1.0))),
  )
}

///|
fn timecode(model : Model, ticks : Int) -> String {
  let fps = 24
  let tps = Int::max(1, ticks_per_second(model))
  let seconds = Int::max(0, ticks) / tps
  let frames = Int::max(0, ticks) % tps * fps / tps
  fn pad(value : Int) -> String {
    if value < 10 {
      "0\{value}"
    } else {
      value.to_string()
    }
  }
  "\{pad(seconds / 3600)}:\{pad((seconds / 60) % 60)}:\{pad(seconds % 60)}:\{pad(frames)}"
}
