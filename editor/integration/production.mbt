///|
pub(all) struct TrackRole {
  role : String
  track_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Money {
  amount : String
  currency : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TakeRights {
  status : String
  refs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TakeQc {
  status : String
  findings : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GeneratedTake {
  contract : String
  take_id : String
  attempt_id : String
  project_id : String
  episode_id : String
  scene_id : String
  shot_id : String
  asset_id : String
  role : String
  variant : String
  provider_ref : String
  model_ref : String
  model_version : String
  seed : Int
  prompt_digest : String
  content_sha256 : String
  mime_type : String
  duration_ticks : Int
  source_asset_ids : Array[String]
  cost : Money
  rights : TakeRights
  qc : TakeQc
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TakeSelection {
  shot_id : String
  take_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Placement {
  placement_id : String
  take_id : String
  role : String
  start_tick : Int
  duration_ticks : Int
  source_in_tick : Int
  source_start_tick : Int
  intent_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TimelineAnnotation {
  annotation_id : String
  kind : String
  range : @plan.TickRange
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReviewComment {
  comment_id : String
  range : @plan.TickRange
  text : String
  revision_round : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryIntent {
  delivery_id : String
  orientation : String
  width : Int
  height : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionIntent {
  contract : String
  project_id : String
  expected_production_revision : Int
  expected_editor_revision : Int
  ticks_per_second : Int
  budget_ceiling : Money
  current_client_revision_rounds : Int
  max_client_revision_rounds : Int
  take_selections : Array[TakeSelection]
  placements : Array[Placement]
  track_role_map : Array[TrackRole]
  annotations : Array[TimelineAnnotation]
  review_comments : Array[ReviewComment]
  delivery_intents : Array[DeliveryIntent]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionImport {
  contract : String
  snapshot : @domain.EditorProject
  command_log : Array[@domain.CommandLogRecord]
  media_records : Array[@media.MediaObjectRecord]
  lineage : Array[GeneratedTake]
  annotations : Array[TimelineAnnotation]
  review_comments : Array[ReviewComment]
  delivery_intents : Array[DeliveryIntent]
  track_roles : Array[TrackRole]
  import_digest : String
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionSourceBinding {
  contract : String
  project_id : String
  episode_id : String
  production_revision : Int
  production_digest : String
  g4_evidence_digest : String
  g4_receipt_digest : String
  g4_snapshot_revision : Int
  provenance_ref : String
  binding_digest : String
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A pack-owned, point-in-time view of the production graph needed by the editor.
/// The editor does not depend on the production store or its implementation types.
pub(all) struct ProductionProjectBinding {
  contract : String
  project_id : String
  revision : Int
  maximum_cost_cny : String
  identities : Array[@domain.ProductionIdentity]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Bytes are supplied explicitly by the host and are verified before registry writes.
pub(all) struct TakePayload {
  take_id : String
  bytes : Bytes
} derive(Debug, Eq)

///|
/// Complete materialized import result; no provider or publication authority is granted.
pub(all) struct ProductionImportResult {
  contract : String
  base_snapshot : @domain.EditorProject
  snapshot : @domain.EditorProject
  command_log : Array[@domain.CommandLogRecord]
  media_records : Array[@media.MediaObjectRecord]
  lineage : Array[GeneratedTake]
  annotations : Array[TimelineAnnotation]
  review_comments : Array[ReviewComment]
  delivery_intents : Array[DeliveryIntent]
  track_roles : Array[TrackRole]
  import_digest : String
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn[T : ToJson] canonical_digest(value : T) -> String {
  "sha256:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(value.to_json().stringify())),
  )
}

///|
fn role_kind(role : String) -> String raise {
  match role {
    "video" => "video"
    "dialogue" | "voice" | "music" | "SFX" => "audio"
    "subtitle" | "title" | "effect" | "AI-label" => "overlay"
    _ => fail("unsupported production role")
  }
}

///|
fn canonical_roles() -> Array[String] {
  [
    "video", "dialogue", "voice", "music", "SFX", "subtitle", "title", "effect",
    "AI-label",
  ]
}

///|
fn role_track(role_map : Array[TrackRole], role : String) -> String raise {
  for binding in role_map {
    if binding.role == role {
      return binding.track_id
    }
  }
  fail("production track role is not bound")
}

///|
fn take_by_id(
  takes : Array[GeneratedTake],
  take_id : String,
) -> GeneratedTake raise {
  for take in takes {
    if take.take_id == take_id {
      return take
    }
  }
  fail("production take is missing")
}

///|
fn payload_by_id(
  payloads : Array[TakePayload],
  take_id : String,
) -> Bytes raise {
  for payload in payloads {
    if payload.take_id == take_id {
      return payload.bytes
    }
  }
  fail("production take bytes are missing")
}

///|
fn media_ref_for_take(
  used_ids : Array[String],
  media_refs : Array[@domain.MediaRef],
  take_id : String,
) -> @domain.MediaRef raise {
  for index, value in used_ids {
    if value == take_id {
      return media_refs[index]
    }
  }
  fail("production take media declaration is missing")
}

///|
fn has_identity(
  graph : Array[@domain.ProductionIdentity],
  identity : @domain.ProductionIdentity,
) -> Bool {
  graph.any(item => item == identity)
}

///|
fn default_audio_bus() -> @domain.AudioBus {
  {
    bus_id: "bus-master",
    kind: "master",
    output_bus_id: None,
    gain_db: 0.0,
    pan: 0.0,
    muted: false,
    solo: false,
    automation: { gain_db: [], pan: [] },
    bus_digest: "builtin:bus-master-v1",
  }
}

///|
fn fresh_editor_project(
  project : ProductionProjectBinding,
  intent : ProductionIntent,
  media_refs : Array[@domain.MediaRef],
  artifacts : Array[@domain.AigcArtifact],
  intent_refs : Array[@domain.IntentRef],
) -> @domain.EditorProject raise {
  let tracks : Array[@domain.Track] = []
  for order, role in canonical_roles() {
    let kind = role_kind(role)
    tracks.push({
      track_id: role_track(intent.track_role_map, role),
      kind,
      order,
      clips: [],
      mix: if kind == "audio" {
        Some({ volume_db: 0.0, pan: 0.0, muted: false })
      } else {
        None
      },
    })
  }
  {
    contract: "mooncast.editor-project.v1",
    project_id: project.project_id,
    revision: 0,
    identity_graph: project.identities,
    media_refs,
    artifacts,
    intent_refs,
    timeline: {
      contract: "mooncast.editor-timeline.v1",
      timeline_id: "timeline:" + project.project_id,
      revision: 0,
      timebase: { ticks_per_second: intent.ticks_per_second },
      output: {
        preset: "horizontal-1080p",
        orientation: "horizontal",
        width: 1920,
        height: 1080,
        fps: { numerator: 24, denominator: 1 },
        background: "#000000",
      },
      tracks,
      transitions: [],
      audio_buses: [default_audio_bus()],
      delivery_audio: {
        target_lufs: -14.0,
        true_peak_limit_dbtp: -1.0,
        limiter_enabled: true,
        delivery_audio_digest: "builtin:delivery-audio-v1",
      },
    },
  }
}

///|
fn validate_review_comment(
  comment : ReviewComment,
  timeline_duration_ticks : Int,
  current_round : Int,
) -> Unit raise {
  guard !comment.comment_id.is_blank() &&
    !comment.text.is_blank() &&
    comment.text.length() <= 4096 else {
    fail("invalid review comment")
  }
  guard comment.range.start_tick >= 0 &&
    comment.range.duration_ticks > 0 &&
    comment.range.start_tick + comment.range.duration_ticks <=
    timeline_duration_ticks else {
    fail("review comment is outside timeline")
  }
  guard comment.revision_round >= 0 &&
    comment.revision_round <= 2 &&
    comment.revision_round <= current_round else {
    fail("invalid review revision round")
  }
}

///|
/// Public validator used by workspace and transport adapters.
pub fn validate_review_comments(
  comments : Array[ReviewComment],
  timeline_duration_ticks : Int,
  current_round : Int,
) -> Unit raise {
  let ids : Array[String] = []
  for comment in comments {
    guard !ids.contains(comment.comment_id) else {
      fail("duplicate review comment")
    }
    validate_review_comment(comment, timeline_duration_ticks, current_round)
    ids.push(comment.comment_id)
  }
}

///|
fn validate_annotations(
  items : Array[TimelineAnnotation],
  timeline_duration_ticks : Int,
) -> Unit raise {
  let ids : Array[String] = []
  for item in items {
    guard !item.annotation_id.is_blank() && !ids.contains(item.annotation_id) else {
      fail("invalid production annotation")
    }
    guard item.kind == "continuity" || item.kind == "QC" else {
      fail("invalid production annotation kind")
    }
    guard item.range.start_tick >= 0 &&
      item.range.duration_ticks > 0 &&
      item.range.start_tick + item.range.duration_ticks <=
      timeline_duration_ticks else {
      fail("production annotation is outside timeline")
    }
    ids.push(item.annotation_id)
  }
}

///|
fn validate_delivery_intents(items : Array[DeliveryIntent]) -> Unit raise {
  guard items.length() == 2 else {
    fail("horizontal and vertical delivery intents are required")
  }
  let ids : Array[String] = []
  let orientations : Array[String] = []
  for item in items {
    guard !item.delivery_id.is_blank() &&
      !ids.contains(item.delivery_id) &&
      !orientations.contains(item.orientation) else {
      fail("duplicate delivery intent")
    }
    guard item.width > 0 && item.height > 0 else {
      fail("invalid delivery dimensions")
    }
    guard (item.orientation == "horizontal" && item.width > item.height) ||
      (item.orientation == "vertical" && item.height > item.width) else {
      fail("delivery orientation does not match dimensions")
    }
    ids.push(item.delivery_id)
    orientations.push(item.orientation)
  }
  guard orientations.contains("horizontal") && orientations.contains("vertical") else {
    fail("horizontal and vertical delivery intents are required")
  }
}

///|
/// Validates, registers and deterministically projects production media onto the editor timeline.
/// All provider/file IO remains outside this function; the supplied bytes are the sole source.
pub async fn import_production_materialized(
  project : ProductionProjectBinding,
  takes : Array[GeneratedTake],
  intent : ProductionIntent,
  payloads : Array[TakePayload],
  registry : @media.MediaRegistry,
  existing_snapshot : @domain.EditorProject?,
  actor_id : String,
) -> ProductionImportResult {
  guard project.contract == "mooncast.production-project.v2" ||
    project.contract == "production-project.v2" else {
    fail("unsupported production project contract")
  }
  guard intent.contract == "mooncast.editor-production-intent.v1" else {
    fail("unsupported production intent contract")
  }
  guard project.project_id == intent.project_id &&
    project.revision == intent.expected_production_revision else {
    fail("stale production revision")
  }
  let current_editor_revision = match existing_snapshot {
    Some(value) => value.revision
    None => 0
  }
  guard current_editor_revision == intent.expected_editor_revision else {
    fail("stale editor revision")
  }
  guard intent.ticks_per_second > 0 &&
    intent.max_client_revision_rounds <= 2 &&
    intent.current_client_revision_rounds >= 0 &&
    intent.current_client_revision_rounds <= intent.max_client_revision_rounds else {
    fail("invalid production intent limits")
  }
  guard intent.budget_ceiling.currency == "CNY" else {
    fail("production import budget must use CNY")
  }

  let roles = canonical_roles()
  guard intent.track_role_map.length() == roles.length() else {
    fail("nine canonical production tracks are required")
  }
  let track_ids : Array[String] = []
  for role in roles {
    let track_id = role_track(intent.track_role_map, role)
    guard !track_id.is_blank() && !track_ids.contains(track_id) else {
      fail("track role map must be unique")
    }
    track_ids.push(track_id)
  }
  let take_ids : Array[String] = []
  for take in takes {
    guard take.contract == "mooncast.editor-generated-take.v1" &&
      take.project_id == project.project_id else {
      fail("production take identity mismatch")
    }
    guard !take.take_id.is_blank() && !take_ids.contains(take.take_id) else {
      fail("duplicate production take")
    }
    take_ids.push(take.take_id)
    guard roles.contains(take.role) &&
      take.duration_ticks > 0 &&
      take.content_sha256.has_prefix("sha256:") &&
      take.content_sha256.length() == 71 &&
      take.prompt_digest.has_prefix("sha256:") &&
      take.prompt_digest.length() == 71 else {
      fail("invalid production take")
    }
    let identity : @domain.ProductionIdentity = {
      project_id: take.project_id,
      episode_id: take.episode_id,
      scene_id: take.scene_id,
      shot_id: take.shot_id,
      asset_id: take.asset_id,
    }
    guard has_identity(project.identities, identity) else {
      fail("production take is outside the bound graph")
    }
    guard take.rights.status == "cleared" &&
      !take.rights.refs.is_empty() &&
      take.qc.status == "passed" else {
      fail("take lacks rights or passed QC")
    }
    guard take.cost.currency == "CNY" &&
      (@string.parse_double(take.cost.amount) catch { _ => -1.0 }) >= 0.0 else {
      fail("invalid take cost")
    }
    let bytes = payload_by_id(payloads, take.take_id)
    let digest = "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    guard digest == take.content_sha256 else {
      fail("production take digest mismatch")
    }
  }
  let selected_ids : Array[String] = []
  let selected_keys : Array[String] = []
  for choice in intent.take_selections {
    let take = take_by_id(takes, choice.take_id)
    let key = choice.shot_id + "\u{0000}" + take.role
    guard take.shot_id == choice.shot_id &&
      !selected_ids.contains(choice.take_id) &&
      !selected_keys.contains(key) else {
      fail("invalid or conflicting take selection")
    }
    selected_ids.push(choice.take_id)
    selected_keys.push(key)
  }
  let placements = intent.placements.copy()
  placements.sort_by((left, right) => {
    let by_start = left.start_tick.compare(right.start_tick)
    if by_start != 0 {
      by_start
    } else {
      let by_role = left.role.compare(right.role)
      if by_role != 0 {
        by_role
      } else {
        left.placement_id.compare(right.placement_id)
      }
    }
  })
  let used_ids = selected_ids.copy()
  let placement_ids : Array[String] = []
  let intent_refs : Array[@domain.IntentRef] = []
  let mut timeline_end = 0
  for placement in placements {
    guard !placement.placement_id.is_blank() &&
      !placement_ids.contains(placement.placement_id) &&
      placement.start_tick >= 0 &&
      placement.duration_ticks > 0 else {
      fail("invalid production placement")
    }
    let take = take_by_id(takes, placement.take_id)
    guard placement.role == take.role &&
      placement.source_in_tick >= 0 &&
      placement.source_in_tick + placement.duration_ticks <= take.duration_ticks else {
      fail("production placement does not match take")
    }
    let chosen = intent.take_selections.filter(choice => {
      choice.shot_id == take.shot_id
    })
    guard chosen.is_empty() ||
      chosen.any(choice => choice.take_id == take.take_id) else {
      fail("placement uses an unselected variant")
    }
    placement_ids.push(placement.placement_id)
    if !used_ids.contains(placement.take_id) {
      used_ids.push(placement.take_id)
    }
    let intent_reference = if placement.intent_ref.is_blank() {
      "moonwiki:intent:" + placement.placement_id
    } else {
      placement.intent_ref
    }
    if !intent_refs.any(item => item.intent_ref == intent_reference) {
      intent_refs.push({ intent_ref: intent_reference })
    }
    timeline_end = Int::max(
      timeline_end,
      placement.start_tick + placement.duration_ticks,
    )
  }
  used_ids.sort()
  validate_review_comments(
    intent.review_comments,
    timeline_end,
    intent.current_client_revision_rounds,
  )
  validate_annotations(intent.annotations, timeline_end)
  validate_delivery_intents(intent.delivery_intents)
  let total_cost = used_ids.fold(init=0.0, (total, take_id) => {
    total +
    (@string.parse_double(take_by_id(takes, take_id).cost.amount) catch {
      _ => fail("invalid take cost")
    })
  })
  let project_limit = @string.parse_double(project.maximum_cost_cny) catch {
    _ => fail("invalid project budget")
  }
  let intent_limit = @string.parse_double(intent.budget_ceiling.amount) catch {
    _ => fail("invalid intent budget")
  }
  guard total_cost >= 0.0 &&
    total_cost <= project_limit &&
    total_cost <= intent_limit else {
    fail("production import budget exceeded")
  }

  let records : Array[@media.MediaObjectRecord] = []
  let media_refs : Array[@domain.MediaRef] = []
  let artifacts : Array[@domain.AigcArtifact] = []
  for take_id in used_ids {
    let take = take_by_id(takes, take_id)
    let bytes = payload_by_id(payloads, take_id)
    let digest = "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    guard digest == take.content_sha256 else {
      fail("production take digest mismatch")
    }
    let record = registry.ingest(
      bytes,
      take.mime_type,
      Some(
        take.duration_ticks.to_double() / intent.ticks_per_second.to_double(),
      ),
      "original",
      Some(take.content_sha256),
      take.source_asset_ids,
      [take.attempt_id, take.provider_ref, take.prompt_digest],
      take.rights.refs,
      take.created_at,
    )
    records.push(record)
    let media_id = "media:" +
      @crypto.bytes_to_hex_string(
        @crypto.sha256(@utf8.encode(take_id + "\u{0000}" + record.digest)),
      )
    media_refs.push({
      contract: "mooncast.editor-media-ref.v1",
      media_ref_id: media_id,
      locator: { kind: "pack-relative", uri: record.locator },
      metadata: {
        sha256: record.digest[7:].to_owned(),
        mime_type: record.mime,
        size_bytes: record.size,
        duration_ticks: take.duration_ticks,
      },
    })
    let source_refs = take.source_asset_ids.copy()
    source_refs.append(take.rights.refs)
    artifacts.push({
      contract: "mooncast.editor-aigc-artifact.v1",
      artifact_id: "artifact:" + take_id,
      source_refs,
      output_media_ref_ids: [media_id],
      provider: take.provider_ref,
      model: take.model_ref + "@" + take.model_version,
      prompt_digest: take.prompt_digest,
      rights_state: take.rights.status,
      review_state: take.qc.status,
    })
  }
  let fresh = fresh_editor_project(
    project, intent, media_refs, artifacts, intent_refs,
  )
  let base = match existing_snapshot {
    None => fresh
    Some(existing) => {
      guard existing.contract == fresh.contract &&
        existing.project_id == fresh.project_id &&
        existing.identity_graph == fresh.identity_graph &&
        existing.media_refs == fresh.media_refs &&
        existing.artifacts == fresh.artifacts &&
        existing.intent_refs == fresh.intent_refs else {
        fail("existing editor declarations conflict with production import")
      }
      guard existing.timeline.timebase == fresh.timeline.timebase &&
        existing.timeline.tracks.map(track => {
          (track.track_id, track.kind, track.order)
        }) ==
        fresh.timeline.tracks.map(track => {
          (track.track_id, track.kind, track.order)
        }) else {
        fail("existing editor timeline conflicts with production import")
      }
      existing
    }
  }
  let mut session = @domain.EditorSession::new(base)
  for index, placement in placements {
    let already_present = session.snapshot.timeline.tracks.any(track => {
      track.clips.any(clip => clip.clip_id == placement.placement_id)
    })
    if !already_present {
      let take = take_by_id(takes, placement.take_id)
      let media_ref = media_ref_for_take(
        used_ids,
        media_refs,
        placement.take_id,
      )
      let intent_ref = if placement.intent_ref.is_blank() {
        "moonwiki:intent:" + placement.placement_id
      } else {
        placement.intent_ref
      }
      let clip : @domain.Clip = {
        clip_id: placement.placement_id,
        media_ref_id: media_ref.media_ref_id,
        identity: {
          project_id: take.project_id,
          episode_id: take.episode_id,
          scene_id: take.scene_id,
          shot_id: take.shot_id,
          asset_id: take.asset_id,
        },
        intent: { intent_ref, },
        artifact_id: Some("artifact:" + take.take_id),
        start_tick: placement.start_tick,
        duration_ticks: placement.duration_ticks,
        source_in_tick: placement.source_in_tick,
        source_out_tick: placement.source_in_tick + placement.duration_ticks,
        settings: @domain.default_clip_settings(),
        keyframes: @domain.empty_keyframes(),
        effects: [],
        effect_stack_digest: "sha256:" +
        @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(""))),
        audio_bus_id: if role_kind(placement.role) == "audio" {
          Some("bus-master")
        } else {
          None
        },
      }
      let command : @domain.EditCommand = {
        contract: "mooncast.editor-edit-command.v1",
        command_id: "mc3a:" + project.project_id + ":" + (index + 1).to_string(),
        expected_revision: session.snapshot.revision,
        actor: { actor_id, provenance: "mooncast:mc3a" },
        operation: @domain.Add(
          track_id=role_track(intent.track_role_map, placement.role),
          clip~,
        ),
      }
      session = session.dispatch(command)
    }
  }
  let immutable = Json::object({
    "contract": "mooncast.editor-production-import.v1".to_json(),
    "project_id": project.project_id.to_json(),
    "production_revision": project.revision.to_json(),
    "ticks_per_second": intent.ticks_per_second.to_json(),
    "take_ids": used_ids.to_json(),
    "take_selections": intent.take_selections.to_json(),
    "placements": placements.to_json(),
    "track_role_map": intent.track_role_map.to_json(),
    "annotations": intent.annotations.to_json(),
    "review_comments": intent.review_comments.to_json(),
    "delivery_intents": intent.delivery_intents.to_json(),
    "publication_authority": false.to_json(),
    "provider_authority": false.to_json(),
  })
  {
    contract: "mooncast.editor-production-import.v1",
    base_snapshot: base,
    snapshot: session.snapshot,
    command_log: session.command_log,
    media_records: records,
    lineage: used_ids.map(id => take_by_id(takes, id)),
    annotations: intent.annotations,
    review_comments: intent.review_comments,
    delivery_intents: intent.delivery_intents,
    track_roles: intent.track_role_map,
    import_digest: canonical_digest(immutable),
    publication_authority: false,
    provider_authority: false,
  }
}

///|
pub fn import_production(
  value : ProductionImport,
) -> @domain.EditorSession raise {
  guard value.contract == "mooncast.editor-production-import.v1" else {
    fail("unsupported production import contract")
  }
  guard !value.publication_authority && !value.provider_authority else {
    fail("production import cannot grant external authority")
  }
  let commands = value.command_log.map(record => record.command)
  let session = @domain.replay(value.snapshot, commands)
  guard session.snapshot.project_id == value.snapshot.project_id else {
    fail("production import identity mismatch")
  }
  session
}

///|
pub(all) struct ExportSpec {
  width : Int
  height : Int
  fps : @domain.FrameRate
  container : String
  video_codec : String
  audio_codec : String
  subtitle_mode : String
  ai_label_mode : String
  retain_sources : Bool
  cost_ceiling : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionExportRequest {
  job_id : String
  request_id : String
  expected_editor_revision : Int
  quality : String
  range : @plan.TickRange
  max_attempts : Int
  spec : ExportSpec
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExportReceipt {
  digest : String
  size : Int
  output_ref : String
  provider_ref : String
  provider_version : String
  plan_digest : String
  spec_digest : String
  test_only : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterPromotionRequest {
  job_id : String
  expected_project_revision : Int
  actor : String
  authority_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterPromotionReceipt {
  contract : String
  master_id : String
  project_id : String
  project_revision : Int
  editor_revision : Int
  job_id : String
  digest : String
  size : Int
  video_ref : String
  subtitle_ref : String
  plan_digest : String
  actor : String
  authority_ref : String
  promoted_at : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Creates an exact promotion receipt only when the export and authority anchors match.
pub fn promote_master(
  project_id : String,
  current_project_revision : Int,
  editor_revision : Int,
  request : MasterPromotionRequest,
  export_receipt : ExportReceipt,
  master_id : String,
  subtitle_ref : String,
  promoted_at : String,
) -> MasterPromotionReceipt raise {
  guard request.expected_project_revision == current_project_revision else {
    fail("project revision conflict during master promotion")
  }
  guard !request.actor.is_blank() && !request.authority_ref.is_blank() else {
    fail("named promotion authority is required")
  }
  guard request.job_id != "" && export_receipt.digest.has_prefix("sha256:") else {
    fail("completed editor export receipt is required")
  }
  {
    contract: "mooncast.editor-master-promotion.v1",
    master_id,
    project_id,
    project_revision: current_project_revision,
    editor_revision,
    job_id: request.job_id,
    digest: export_receipt.digest,
    size: export_receipt.size,
    video_ref: export_receipt.output_ref,
    subtitle_ref,
    plan_digest: export_receipt.plan_digest,
    actor: request.actor,
    authority_ref: request.authority_ref,
    promoted_at,
    publication_authority: false,
  }
}
