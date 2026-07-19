///|
struct EditorCatalogRecord {
  summary : EditorProjectSummary
} derive(ToJson, FromJson)

///|
fn editor_catalog_key(project_id : String) -> String {
  "editor-catalog-" + sha256_text(project_id) + ".json"
}

///|
fn editor_intake_key(project_id : String, intake_id : String) -> String {
  "editor-intake-" + sha256_text(project_id + ":" + intake_id) + ".json"
}

///|
fn editor_binding_key(project_id : String, intake_id : String) -> String {
  "editor-binding-" +
  sha256_text(project_id) +
  "-" +
  sha256_text(intake_id) +
  ".json"
}

///|
fn editor_take_key(project_id : String, take_id : String) -> String {
  "editor-take-" +
  sha256_text(project_id) +
  "-" +
  sha256_text(take_id) +
  ".json"
}

///|
fn editor_comment_key(project_id : String, comment_id : String) -> String {
  "editor-comment-" +
  sha256_text(project_id) +
  "-" +
  sha256_text(comment_id) +
  ".json"
}

///|
fn editor_job_key(project_id : String, job_id : String) -> String {
  "editor-job-" + sha256_text(project_id + ":" + job_id) + ".json"
}

///|
fn editor_analysis_key(digest : String) -> String {
  "editor-analysis-" + sha256_text(digest) + ".json"
}

///|
fn editor_promotion_key(project_id : String, master_id : String) -> String {
  "editor-promotion-" + sha256_text(project_id + ":" + master_id) + ".json"
}

///|
fn editor_latest_promotion_key(project_id : String) -> String {
  "editor-latest-promotion-" + sha256_text(project_id) + ".json"
}

///|
fn editor_production_source_key(project_id : String) -> String {
  "editor-production-source-" + sha256_text(project_id) + ".json"
}

///|
fn editor_render_key(project_id : String, job_id : String) -> String {
  "render-" + sha256_text(project_id + ":" + job_id) + ".mp4"
}

///|
fn editor_subtitle_key(project_id : String, job_id : String) -> String {
  "render-" + sha256_text(project_id + ":" + job_id) + ".srt"
}

///|
fn editor_provenance_key(project_id : String, job_id : String) -> String {
  "render-" + sha256_text(project_id + ":" + job_id) + ".provenance.json"
}

///|
fn normalized_digest(value : String) -> String {
  if value.has_prefix("sha256:") {
    value
  } else {
    "sha256:" + value
  }
}

///|
fn production_source_binding(
  snapshot : @kernel.ProjectSnapshot,
) -> @editor_integration.ProductionSourceBinding raise {
  guard snapshot.graph.episodes.get(0) is Some(episode) else {
    fail("production source requires an episode")
  }
  let g4_receipts = snapshot.gate_receipts.filter(receipt => {
    receipt.gate.to_string() == "G4"
  })
  guard !g4_receipts.is_empty() else {
    fail("production source requires a G4 receipt")
  }
  let g4 = g4_receipts[g4_receipts.length() - 1]
  let provisional : @editor_integration.ProductionSourceBinding = {
    contract: "mooncast.editor-production-source-binding.v1",
    project_id: snapshot.graph.project_id,
    episode_id: episode.episode_id,
    production_revision: snapshot.revision,
    production_digest: "sha256:" + sha256_text(snapshot.to_json().stringify()),
    g4_evidence_digest: normalized_digest(g4.evidence_digest),
    g4_receipt_digest: "sha256:" + sha256_text(g4.to_json().stringify()),
    g4_snapshot_revision: g4.snapshot_revision,
    provenance_ref: "/api/v2/projects/" + snapshot.graph.project_id,
    binding_digest: "",
    publication_authority: false,
    provider_authority: false,
  }
  {
    ..provisional,
    binding_digest: "sha256:" + sha256_text(provisional.to_json().stringify()),
  }
}

///|
fn production_source_evidence_valid(
  snapshot : @kernel.ProjectSnapshot,
  source : @editor_integration.ProductionSourceBinding,
) -> Bool {
  let unsigned = { ..source, binding_digest: "" }
  source.contract == "mooncast.editor-production-source-binding.v1" &&
  source.project_id == snapshot.graph.project_id &&
  snapshot.graph.episodes.any(episode => episode.episode_id == source.episode_id) &&
  source.production_revision > 0 &&
  source.production_revision <= snapshot.revision &&
  normalized_digest(source.binding_digest) ==
  normalized_digest("sha256:" + sha256_text(unsigned.to_json().stringify())) &&
  snapshot.gate_receipts.any(receipt => {
    receipt.gate.to_string() == "G4" &&
    receipt.snapshot_revision == source.g4_snapshot_revision &&
    normalized_digest(receipt.evidence_digest) ==
    normalized_digest(source.g4_evidence_digest) &&
    normalized_digest("sha256:" + sha256_text(receipt.to_json().stringify())) ==
    normalized_digest(source.g4_receipt_digest)
  }) &&
  !source.publication_authority &&
  !source.provider_authority
}

///|
async fn StudioService::editor_production_source(
  self : StudioService,
  project_id : String,
) -> @editor_integration.ProductionSourceBinding? {
  let stored : @editor_integration.ProductionSourceBinding? = load_value(
    self.store,
    editor_production_source_key(project_id),
  )
  match stored {
    Some(value) => Some(value)
    None => {
      let canonical = self.get_project(project_id) catch {
        NotFound(entity=_, id=_) => return None
        _ => return None
      }
      guard canonical.snapshot.gate_receipts.any(receipt => {
        receipt.gate.to_string() == "G4"
      }) else {
        return None
      }
      let value = production_source_binding(canonical.snapshot)
      save_value(self.store, editor_production_source_key(project_id), value)
      Some(value)
    }
  }
}

///|
fn timeline_duration(project : @editor_domain.EditorProject) -> Int {
  let mut duration = 0
  for track in project.timeline.tracks {
    for clip in track.clips {
      duration = Int::max(duration, clip.start_tick + clip.duration_ticks)
    }
  }
  duration
}

///|
fn generated_subtitle_timestamp(milliseconds : Int) -> String {
  fn pad(value : Int, width : Int) -> String {
    let mut result = value.to_string()
    while result.length() < width {
      result = "0" + result
    }
    result
  }
  let hours = milliseconds / 3600000
  let after_hours = milliseconds % 3600000
  let minutes = after_hours / 60000
  let after_minutes = after_hours % 60000
  let seconds = after_minutes / 1000
  let millis = after_minutes % 1000
  pad(hours, 2) +
  ":" +
  pad(minutes, 2) +
  ":" +
  pad(seconds, 2) +
  "," +
  pad(millis, 3)
}

///|
fn approved_shot_caption(
  storyboard : Json,
  shot_id : String,
  fallback : String,
) -> String {
  guard json_member(storyboard, "scenes") is Some(Array(scenes)) else {
    return fallback
  }
  for scene in scenes {
    if json_member(scene, "shots") is Some(Array(shots)) {
      for shot in shots {
        if json_member(shot, "shot_id") == Some(shot_id.to_json()) &&
          json_member(shot, "description") is Some(String(description)) &&
          !description.is_blank() {
          return description
        }
      }
    }
  }
  fallback
}

///|
fn approved_project_subtitles(
  snapshot : @kernel.ProjectSnapshot,
) -> (Bytes, String, String) raise {
  guard @creative.current_artifact(
      snapshot.creative_artifacts,
      @creative.Script,
    )
    is Some(script) &&
    @creative.current_artifact(
      snapshot.creative_artifacts,
      @creative.Storyboard,
    )
    is Some(storyboard) &&
    @creative.exact_approval(Some(script), snapshot.creative_decisions) &&
    @creative.exact_approval(Some(storyboard), snapshot.creative_decisions) else {
    fail("approved script and storyboard are required for editor subtitles")
  }
  let script_json = @json.parse(script.content)
  let storyboard_json = @json.parse(storyboard.content)
  let script_text = match json_member(script_json, "text") {
    Some(String(value)) if !value.is_blank() => value
    _ => snapshot.graph.title
  }
  let lines : Array[String] = []
  let mut cursor_ms = 0
  let mut cue_number = 1
  for episode in snapshot.graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        let end_ms = cursor_ms + shot.duration_ms
        let fallback = scene.title + " — " + script_text
        let caption = approved_shot_caption(
            storyboard_json,
            shot.shot_id,
            fallback,
          )
          .replace_all(old="<", new="")
          .replace_all(old=">", new="")
          .trim()
          .to_owned()
        guard !caption.is_blank() else {
          fail("approved shot subtitle text is empty")
        }
        lines.append([
          cue_number.to_string(),
          generated_subtitle_timestamp(cursor_ms) +
          " --> " +
          generated_subtitle_timestamp(end_ms),
          caption,
          "",
        ])
        cursor_ms = end_ms
        cue_number = cue_number + 1
      }
    }
  }
  guard cursor_ms == snapshot.graph.target_duration_seconds * 1000 &&
    cue_number > 1 else {
    fail("approved subtitle timing does not cover the canonical episode")
  }
  (
    @utf8.encode(lines.join("\n")),
    script.reference.digest,
    storyboard.reference.digest,
  )
}

///|
async fn StudioService::materialize_approved_subtitles(
  self : StudioService,
  snapshot : @kernel.ProjectSnapshot,
  project : @editor_domain.EditorProject,
) -> @editor_media.CompletedIntake {
  guard project.identity_graph.get(0) is Some(identity) else {
    fail("canonical production has no subtitle identity")
  }
  let duration_ticks = timeline_duration(project)
  guard duration_ticks > 0 else {
    fail("canonical production duration is empty")
  }
  let (bytes, script_digest, storyboard_digest) = approved_project_subtitles(
    snapshot,
  )
  let sha256 = "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
  let prepared = @editor_media.prepare_intake(
    project,
    project.revision,
    "approved-project-subtitles-v1-r" + project.revision.to_string(),
    "subtitle",
    "approved-project-subtitles.srt",
    "application/x-subrip",
    bytes.length(),
    sha256,
    duration_ticks,
    identity,
    {
      confirmed: true,
      rights_ref: "mooncast:approved-creative:" + script_digest,
      owner: snapshot.graph.project_id,
      basis: "approved-script-and-storyboard",
      territory: "contracted-delivery-territories",
      channels: ["master", "review"],
    },
    { kind: "original", source_id: script_digest + ":" + storyboard_digest },
    "mooncast-production-import",
    now_string(),
  )
  let completed = @editor_media.complete_intake(
    self.editor_media,
    prepared.request,
    bytes,
    project.timeline.timebase.ticks_per_second,
    prepared.intake_id,
    "media:" +
    sha256_text(project.project_id + ":approved-project-subtitles:" + sha256),
    "sha256:" + sha256_text(prepared.request.to_json().stringify()),
  )
  save_value(
    self.store,
    editor_intake_key(project.project_id, prepared.intake_id),
    prepared.request,
  )
  save_value(
    self.store,
    editor_binding_key(project.project_id, prepared.intake_id),
    completed.binding,
  )
  completed
}

///|
fn approved_subtitle_clip(
  project : @editor_domain.EditorProject,
  completed : @editor_media.CompletedIntake,
) -> @editor_domain.Clip raise {
  guard project.identity_graph.get(0) is Some(identity) else {
    fail("canonical production has no subtitle identity")
  }
  let duration_ticks = timeline_duration(project)
  {
    clip_id: "clip-approved-project-subtitles",
    media_ref_id: completed.media_ref.media_ref_id,
    identity,
    intent: { intent_ref: "mooncast:approved-script-subtitles" },
    artifact_id: None,
    start_tick: 0,
    duration_ticks,
    source_in_tick: 0,
    source_out_tick: duration_ticks,
    settings: @editor_domain.default_clip_settings(),
    keyframes: @editor_domain.empty_keyframes(),
    effects: [],
    effect_stack_digest: "sha256:" +
    sha256_text("approved-project-subtitles-v1"),
    audio_bus_id: None,
  }
}

///|
fn empty_editor_track(
  id : String,
  kind : String,
  order : Int,
) -> @editor_domain.Track {
  {
    track_id: id,
    kind,
    order,
    mix: if kind == "audio" {
      Some({ volume_db: 0.0, pan: 0.0, muted: false })
    } else {
      None
    },
    clips: [],
  }
}

///|
fn empty_editor_bus(
  id : String,
  kind : String,
  output : String?,
) -> @editor_domain.AudioBus {
  {
    bus_id: id,
    kind,
    output_bus_id: output,
    gain_db: 0.0,
    pan: 0.0,
    muted: false,
    solo: false,
    automation: { gain_db: [], pan: [] },
    bus_digest: "sha256:" + sha256_text(id + ":editor-bus-v1"),
  }
}

///|
fn editor_from_production_graph(
  graph : @project.ProjectGraph,
) -> @editor_domain.EditorProject {
  let identities : Array[@editor_domain.ProductionIdentity] = []
  for episode in graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        identities.push({
          project_id: graph.project_id,
          episode_id: episode.episode_id,
          scene_id: scene.scene_id,
          shot_id: shot.shot_id,
          asset_id: shot.source_asset_ids
          .get(0)
          .unwrap_or("asset-pending:" + shot.shot_id),
        })
      }
    }
  }
  let timeline : @editor_domain.Timeline = {
    contract: "mooncast.editor-timeline.v1",
    timeline_id: "timeline-main",
    revision: 0,
    timebase: { ticks_per_second: 1000 },
    output: {
      preset: "horizontal-1080p",
      orientation: "horizontal",
      width: 1920,
      height: 1080,
      fps: { numerator: 24, denominator: 1 },
      background: "#000000",
    },
    tracks: [
      empty_editor_track("track-video", "video", 0),
      empty_editor_track("track-effect", "overlay", 1),
      empty_editor_track("track-title", "overlay", 2),
      empty_editor_track("track-subtitle", "overlay", 3),
      empty_editor_track("track-ai-label", "overlay", 4),
      empty_editor_track("track-dialogue", "audio", 5),
      empty_editor_track("track-voice", "audio", 6),
      empty_editor_track("track-music", "audio", 7),
      empty_editor_track("track-sfx", "audio", 8),
    ],
    transitions: [],
    audio_buses: [
      empty_editor_bus("bus-master", "master", None),
      empty_editor_bus("bus-dialogue", "dialogue", Some("bus-master")),
      empty_editor_bus("bus-voice", "voice", Some("bus-master")),
      empty_editor_bus("bus-music", "music", Some("bus-master")),
      empty_editor_bus("bus-sfx", "sfx", Some("bus-master")),
    ],
    delivery_audio: {
      target_lufs: -14.0,
      true_peak_limit_dbtp: -1.0,
      limiter_enabled: true,
      delivery_audio_digest: "sha256:" +
      sha256_text("broadcast-web-delivery-audio-v1"),
    },
  }
  {
    contract: "mooncast.editor-project.v1",
    project_id: graph.project_id,
    revision: 0,
    identity_graph: identities,
    media_refs: [],
    artifacts: [],
    intent_refs: [{ intent_ref: "moonwiki:project:" + graph.project_id }],
    timeline,
  }
}

///|
/// Replace the legacy opaque project placeholder only when this project was
/// created from an approved MoonWiki packet. These values are copied directly
/// from MoonWiki's exported provenance references; no fallback is synthesized.
async fn StudioService::bind_editor_moonwiki_intents(
  self : StudioService,
  project : @editor_domain.EditorProject,
) -> @editor_domain.EditorProject {
  let matches = self.needs_intake
    .list_bindings()
    .filter(value => value.project_id == project.project_id)
  if matches.is_empty() {
    return project
  }
  let binding = matches[0]
  {
    ..project,
    intent_refs: [
      { intent_ref: binding.brief_intent_ref.provenance_ref },
      { intent_ref: binding.bible_intent_ref.provenance_ref },
      { intent_ref: binding.script_intent_ref.provenance_ref },
    ],
  }
}

///|
fn latest_successful_attempt(
  snapshot : @kernel.ProjectSnapshot,
  shot_id : String,
) -> @governance.GenerationAttempt? {
  let matches = snapshot.generation_attempts.filter(attempt => {
    attempt.shot_id == shot_id && attempt.status == "succeeded"
  })
  if matches.is_empty() {
    None
  } else {
    Some(matches[matches.length() - 1])
  }
}

///|
async fn StudioService::hydrate_generated_editor_project(
  self : StudioService,
  snapshot : @kernel.ProjectSnapshot,
  base : @editor_domain.EditorProject,
) -> @editor_domain.EditorProject {
  guard snapshot.gate_receipts.any(receipt => receipt.gate.to_string() == "G4") else {
    raise Conflict(
      code="editor_production_not_approved",
      message="canonical G4 approval is required before editor import",
    )
  }
  let media_refs : Array[@editor_domain.MediaRef] = []
  let artifacts : Array[@editor_domain.AigcArtifact] = []
  let identities : Array[@editor_domain.ProductionIdentity] = []
  let clips : Array[@editor_domain.Clip] = []
  let mut cursor = 0
  for episode in snapshot.graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        guard latest_successful_attempt(snapshot, shot.shot_id) is Some(attempt) &&
          @governance.shot_passes_qc(
            shot.shot_id,
            snapshot.generation_attempts,
            snapshot.qc_findings,
            snapshot.qc_decisions,
          ) else {
          raise Conflict(
            code="editor_shot_evidence_incomplete",
            message="each imported shot requires a successful attempt and five-dimension QC",
          )
        }
        guard self.execution_application.artifact_metadata(
            attempt.output_digest,
          )
          is Some(provider_artifact) &&
          self.execution_application.artifact_bytes(attempt.output_digest)
          is Some(bytes) else {
          raise Invalid(
            code="editor_provider_media_missing",
            message="canonical generation evidence has no content-addressed provider media",
          )
        }
        let duration_seconds = shot.duration_ms.to_double() / 1000.0
        let media = self.editor_media.ingest(
          bytes,
          provider_artifact.media_type,
          Some(duration_seconds),
          "original",
          None,
          [attempt.output_digest, attempt.attempt.digest],
          [attempt.route_plan.digest, attempt.prompt_digest],
          provider_artifact.rights_refs,
          now_string(),
        )
        let media_ref_id = "media:" +
          sha256_text(
            snapshot.graph.project_id + ":" + shot.shot_id + ":" + media.digest,
          )
        let identity : @editor_domain.ProductionIdentity = {
          project_id: snapshot.graph.project_id,
          episode_id: episode.episode_id,
          scene_id: scene.scene_id,
          shot_id: shot.shot_id,
          asset_id: provider_artifact.artifact_id,
        }
        let media_ref : @editor_domain.MediaRef = {
          contract: "mooncast.editor-media-ref.v1",
          media_ref_id,
          locator: {
            kind: "registry",
            uri: "/api/editor/media/" + media.digest,
          },
          metadata: {
            sha256: if media.digest.has_prefix("sha256:") {
              media.digest[7:].to_owned()
            } else {
              media.digest
            },
            mime_type: media.mime,
            size_bytes: media.size,
            duration_ticks: shot.duration_ms,
          },
        }
        let route = snapshot.routing_plan.bind(plan => {
          plan.routes
          .iter()
          .find_first(item => item.route_id == attempt.route_id)
        })
        let artifact_id = "aigc-" +
          shot.shot_id +
          "-v" +
          attempt.attempt.version.to_string()
        media_refs.push(media_ref)
        identities.push(identity)
        artifacts.push({
          contract: "mooncast.editor-aigc-artifact.v1",
          artifact_id,
          source_refs: [attempt.attempt.digest, attempt.route_plan.digest],
          output_media_ref_ids: [media_ref_id],
          provider: route.map(item => item.provider).unwrap_or("provider"),
          model: route.map(item => item.model).unwrap_or("unknown"),
          prompt_digest: attempt.prompt_digest,
          rights_state: "cleared",
          review_state: "passed",
        })
        clips.push({
          clip_id: "clip-generated-" + shot.shot_id,
          media_ref_id,
          identity,
          intent: { intent_ref: "mooncast:approved-shot:" + shot.shot_id },
          artifact_id: Some(artifact_id),
          start_tick: cursor,
          duration_ticks: shot.duration_ms,
          source_in_tick: 0,
          source_out_tick: shot.duration_ms,
          settings: @editor_domain.default_clip_settings(),
          keyframes: @editor_domain.empty_keyframes(),
          effects: [],
          effect_stack_digest: "sha256:" + sha256_text("empty-effect-stack-v1"),
          audio_bus_id: None,
        })
        cursor = cursor + shot.duration_ms
      }
    }
  }
  guard cursor > 0 else { fail("canonical production duration is empty") }
  let tracks = base.timeline.tracks.copy()
  let mut video_index = -1
  let mut subtitle_index = -1
  for index, track in tracks {
    if track.track_id == "track-video" {
      video_index = index
    }
    if track.track_id == "track-subtitle" {
      subtitle_index = index
    }
  }
  guard video_index >= 0 && subtitle_index >= 0 else {
    fail("canonical video or subtitle track is missing")
  }
  tracks[video_index] = { ..tracks[video_index], clips, }
  let video_project : @editor_domain.EditorProject = {
    ..base,
    identity_graph: identities,
    media_refs,
    artifacts,
    timeline: { ..base.timeline, tracks, },
  }
  let completed_subtitles = self.materialize_approved_subtitles(
    snapshot, video_project,
  )
  media_refs.push(completed_subtitles.media_ref)
  let subtitle_clip = approved_subtitle_clip(video_project, completed_subtitles)
  tracks[subtitle_index] = { ..tracks[subtitle_index], clips: [subtitle_clip] }
  {
    ..base,
    identity_graph: identities,
    media_refs,
    artifacts,
    timeline: { ..base.timeline, tracks, },
  }
}

///|
async fn StudioService::ensure_approved_editor_subtitles(
  self : StudioService,
  snapshot : @kernel.ProjectSnapshot,
  current : EditorOpenView,
) -> EditorOpenView {
  let already_present = current.snapshot.timeline.tracks.any(track => {
    track.track_id == "track-subtitle" &&
    track.clips.any(clip => clip.clip_id == "clip-approved-project-subtitles")
  })
  if already_present {
    return current
  }
  let completed = self.materialize_approved_subtitles(
    snapshot,
    current.snapshot,
  )
  guard self.editor_repository.load_snapshot(current.project_id) is Some(stored) else {
    raise NotFound(entity="editor_project", id=current.project_id)
  }
  let base_refs = stored.base_snapshot.media_refs.map(reference => {
    let sha256 = reference.metadata.sha256
    if sha256.has_prefix("sha256:") {
      {
        ..reference,
        metadata: { ..reference.metadata, sha256: sha256[7:].to_owned() },
      }
    } else {
      reference
    }
  })
  if !base_refs.any(value => {
      value.media_ref_id == completed.media_ref.media_ref_id
    }) {
    base_refs.push(completed.media_ref)
  }
  let base = { ..stored.base_snapshot, media_refs: base_refs }
  let session = @editor_domain.replay(
    base,
    stored.command_log.map(record => record.command),
  )
  let clip = approved_subtitle_clip(session.snapshot, completed)
  let updated = session.dispatch({
    contract: "mooncast.editor-edit-command.v1",
    command_id: "approved-project-subtitles-r" +
    session.snapshot.revision.to_string(),
    expected_revision: session.snapshot.revision,
    actor: {
      actor_id: "mooncast-production-import",
      provenance: "approved-script-and-storyboard",
    },
    operation: @editor_domain.Add(track_id="track-subtitle", clip~),
  })
  let digest = "sha256:" +
    sha256_text(
      snapshot.graph.project_id +
      ":approved-project-subtitles:" +
      completed.binding.cue_digest,
    )
  ignore(self.editor_repository.save_session(updated, digest))
  self.save_editor_catalog(updated.snapshot, now_string())
  self.get_editor_project(current.project_id)
}

///|
fn track_binding_for_role(
  project : @editor_domain.EditorProject,
  role : String,
) -> (String, String, String?) {
  let (wanted_id, wanted_kind, bus) = match role {
    "voice" => ("track-voice", "audio", Some("bus-voice"))
    "music" => ("track-music", "audio", Some("bus-music"))
    "SFX" | "sfx" => ("track-sfx", "audio", Some("bus-sfx"))
    "dialogue" => ("track-dialogue", "audio", Some("bus-dialogue"))
    "subtitle" => ("track-subtitle", "overlay", None)
    "title" => ("track-title", "overlay", None)
    "logo" | "AI-label" => ("track-ai-label", "overlay", None)
    "image" | "effect" => ("track-effect", "overlay", None)
    _ => ("track-video", "video", None)
  }
  for track in project.timeline.tracks {
    if track.track_id == wanted_id {
      return (track.track_id, track.kind, bus)
    }
  }
  for track in project.timeline.tracks {
    if track.kind == wanted_kind {
      return (track.track_id, track.kind, bus)
    }
  }
  (wanted_id, wanted_kind, bus)
}

///|
async fn StudioService::save_editor_catalog(
  self : StudioService,
  project : @editor_domain.EditorProject,
  updated_at : String,
) -> Unit {
  let record : EditorCatalogRecord = {
    summary: {
      project_id: project.project_id,
      revision: project.revision,
      timeline_id: project.timeline.timeline_id,
      duration_ticks: timeline_duration(project),
      updated_at,
    },
  }
  save_value(self.store, editor_catalog_key(project.project_id), record)
}

///|
pub async fn StudioService::list_editor_projects(
  self : StudioService,
) -> Array[EditorProjectSummary] {
  let result : Array[EditorProjectSummary] = []
  for key in self.store.list_keys(prefix="editor-catalog-", suffix=".json") {
    let record : EditorCatalogRecord? = load_value(self.store, key)
    if record is Some(value) {
      result.push(value.summary)
    }
  }
  result
}

///|
async fn StudioService::editor_bindings(
  self : StudioService,
  project_id : String,
) -> Array[@editor_domain.LocalMediaBinding] {
  let result : Array[@editor_domain.LocalMediaBinding] = []
  let prefix = "editor-binding-" + sha256_text(project_id) + "-"
  for key in self.store.list_keys(prefix~, suffix=".json") {
    let binding : @editor_domain.LocalMediaBinding? = load_value(
      self.store,
      key,
    )
    if binding is Some(value) {
      result.push(value)
    }
  }
  result
}

///|
async fn StudioService::editor_takes(
  self : StudioService,
  project_id : String,
) -> Array[EditorTakeRecord] {
  let result : Array[EditorTakeRecord] = []
  let prefix = "editor-take-" + sha256_text(project_id) + "-"
  for key in self.store.list_keys(prefix~, suffix=".json") {
    let take : EditorTakeRecord? = load_value(self.store, key)
    if take is Some(value) {
      result.push(value)
    }
  }
  result
}

///|
async fn StudioService::editor_review_comments(
  self : StudioService,
  project_id : String,
) -> Array[@editor_integration.ReviewComment] {
  let result : Array[@editor_integration.ReviewComment] = []
  let prefix = "editor-comment-" + sha256_text(project_id) + "-"
  for key in self.store.list_keys(prefix~, suffix=".json") {
    let comment : @editor_integration.ReviewComment? = load_value(
      self.store,
      key,
    )
    if comment is Some(value) {
      result.push(value)
    }
  }
  result
}

///|
fn promotion_is_newer(
  candidate : @editor_integration.MasterPromotionReceipt,
  current : @editor_integration.MasterPromotionReceipt,
) -> Bool {
  let time_order = candidate.promoted_at.lexical_compare(current.promoted_at)
  if time_order != 0 {
    time_order > 0
  } else if candidate.project_revision != current.project_revision {
    candidate.project_revision > current.project_revision
  } else if candidate.editor_revision != current.editor_revision {
    candidate.editor_revision > current.editor_revision
  } else {
    candidate.master_id.lexical_compare(current.master_id) > 0
  }
}

///|
async fn StudioService::latest_editor_promotion(
  self : StudioService,
  project_id : String,
) -> @editor_integration.MasterPromotionReceipt? {
  let indexed : @editor_integration.MasterPromotionReceipt? = load_value(
    self.store,
    editor_latest_promotion_key(project_id),
  )
  let mut latest = match indexed {
    Some(receipt) if receipt.project_id == project_id => Some(receipt)
    _ => None
  }
  // Older installations have only immutable per-master receipts. Scanning is
  // the migration-free fallback; new promotions also maintain the direct
  // project projection above.
  for key in self.store.list_keys(prefix="editor-promotion-", suffix=".json") {
    let stored : @editor_integration.MasterPromotionReceipt? = load_value(
      self.store,
      key,
    )
    match stored {
      Some(receipt) if receipt.project_id == project_id =>
        match latest {
          Some(current) if !promotion_is_newer(receipt, current) => ()
          _ => latest = Some(receipt)
        }
      _ => ()
    }
  }
  latest
}

///|
pub async fn StudioService::get_editor_project(
  self : StudioService,
  project_id : String,
) -> EditorOpenView {
  guard self.editor_repository.load_snapshot(project_id) is Some(record) else {
    raise NotFound(entity="editor_project", id=project_id)
  }
  {
    project_id,
    revision: record.current_snapshot.revision,
    snapshot: record.current_snapshot,
    command_log: record.command_log,
    media_bindings: self.editor_bindings(project_id),
    takes: self.editor_takes(project_id),
    review_comments: self.editor_review_comments(project_id),
    production_source: self.editor_production_source(project_id),
    master_promotion: self.latest_editor_promotion(project_id),
    publication_authority: false,
    provider_authority: false,
  }
}

///|
pub async fn StudioService::record_editor_review_comment(
  self : StudioService,
  project_id : String,
  request : EditorReviewCommentRequest,
) -> @editor_integration.ReviewComment {
  self.with_mutation_lock(() => {
    let editor = self.get_editor_project(project_id)
    guard editor.revision == request.expected_revision else {
      raise Conflict(
        code="editor_revision_conflict",
        message="review comment must bind the current editor revision",
      )
    }
    let input = request.comment
    let duration = timeline_duration(editor.snapshot)
    guard (
        input.kind == "continuity" ||
        input.kind == "qc" ||
        input.kind == "review"
      ) &&
      input.start_tick >= 0 &&
      input.end_tick > input.start_tick &&
      input.end_tick <= duration &&
      !input.text.is_blank() &&
      input.revision_round >= 0 &&
      input.revision_round <= 2 else {
      raise Invalid(
        code="editor_review_comment_invalid",
        message="review comment range, kind, text, or revision round is invalid",
      )
    }
    let comment : @editor_integration.ReviewComment = {
      comment_id: input.comment_id,
      range: {
        start_tick: input.start_tick,
        duration_ticks: input.end_tick - input.start_tick,
      },
      text: input.text,
      revision_round: input.revision_round,
    }
    let key = editor_comment_key(project_id, input.comment_id)
    let existing : @editor_integration.ReviewComment? = load_value(
      self.store,
      key,
    )
    match existing {
      Some(value) => {
        guard value == comment else {
          raise Conflict(
            code="editor_review_comment_conflict",
            message="comment id already binds another review comment",
          )
        }
        value
      }
      None => {
        save_value(self.store, key, comment)
        comment
      }
    }
  })
}

///|
pub async fn StudioService::create_editor_project(
  self : StudioService,
  request : EditorCreateRequest,
) -> EditorOpenView {
  self.with_mutation_lock(() => {
    let project = request.project
    guard project.contract == "mooncast.editor-project.v1" &&
      project.timeline.contract == "mooncast.editor-timeline.v1" else {
      raise Invalid(
        code="editor_project_contract_invalid",
        message="editor project contracts are invalid",
      )
    }
    guard project.revision == project.timeline.revision else {
      raise Invalid(
        code="editor_revision_invalid",
        message="project and timeline revisions must match",
      )
    }
    if self.editor_repository.load_snapshot(project.project_id)
      is Some(existing) {
      guard existing.current_snapshot == project else {
        raise Conflict(
          code="editor_project_exists",
          message="editor project id already binds another snapshot",
        )
      }
      return self.get_editor_project(project.project_id)
    }
    ignore(
      @editor_http.create_project(
        self.editor_repository,
        project,
        request.content_digest,
      ),
    )
    self.save_editor_catalog(project, request.recorded_at)
    self.get_editor_project(project.project_id)
  })
}

///|
pub async fn StudioService::import_editor_production(
  self : StudioService,
  request : EditorProductionImportRequest,
) -> EditorOpenView {
  self.with_mutation_lock(() => {
    let production = request.production
    let project_id = production.snapshot.project_id
    let session = @editor_integration.import_production(production)
    match self.editor_repository.load_snapshot(project_id) {
      Some(existing) => {
        guard request.expected_editor_revision ==
          Some(existing.current_snapshot.revision) else {
          raise Conflict(
            code="editor_revision_conflict",
            message="production refresh requires the current editor revision",
          )
        }
      }
      None => ()
    }
    ignore(self.editor_repository.save_session(session, request.content_digest))
    self.save_editor_catalog(session.snapshot, request.recorded_at)
    for take in production.lineage {
      let digest = normalized_digest(take.content_sha256)
      let record : EditorTakeRecord = {
        take_id: take.take_id,
        project_id,
        media_ref_id: "media:" + sha256_text(take.take_id + ":" + digest),
        media_digest: digest,
        mime_type: take.mime_type,
        role: take.role,
        source_url: "/api/editor/projects/" +
        project_id +
        "/takes/" +
        take.take_id +
        "/source",
        thumbnail_url: "/api/editor/projects/" +
        project_id +
        "/takes/" +
        take.take_id +
        "/thumbnail",
        analysis_url: "/api/editor/projects/" +
        project_id +
        "/takes/" +
        take.take_id +
        "/analysis",
        proxy_state: "pending",
        identity: {
          project_id: take.project_id,
          episode_id: take.episode_id,
          scene_id: take.scene_id,
          shot_id: take.shot_id,
          asset_id: take.asset_id,
        },
        approved: false,
        already_placed: false,
        track_id: "",
        track_kind: "",
        add_clip_template: None,
      }
      save_value(self.store, editor_take_key(project_id, take.take_id), record)
    }
    self.get_editor_project(project_id)
  })
}

///|
pub async fn StudioService::import_editor_from_canonical_project(
  self : StudioService,
  project_id : String,
) -> EditorOpenView {
  self.with_mutation_lock(() => {
    match self.editor_repository.load_snapshot(project_id) {
      Some(_) => {
        let canonical = self.get_project(project_id)
        self.ensure_approved_editor_subtitles(
          canonical.snapshot,
          self.get_editor_project(project_id),
        )
      }
      None => {
        let canonical = self.get_project(project_id)
        let base = self.bind_editor_moonwiki_intents(
          editor_from_production_graph(canonical.snapshot.graph),
        )
        let editor = self.hydrate_generated_editor_project(
          canonical.snapshot,
          base,
        )
        let digest = "sha256:" +
          sha256_text(canonical.snapshot.to_json().stringify())
        ignore(
          @editor_http.create_project(self.editor_repository, editor, digest),
        )
        self.save_editor_catalog(editor, now_string())
        for clip in editor.timeline.tracks[0].clips {
          guard editor.media_refs
            .iter()
            .find_first(reference => reference.media_ref_id == clip.media_ref_id)
            is Some(reference) else {
            continue
          }
          let take_id = "take-generated-" + clip.identity.shot_id
          let take : EditorTakeRecord = {
            take_id,
            project_id,
            media_ref_id: reference.media_ref_id,
            media_digest: reference.metadata.sha256,
            mime_type: reference.metadata.mime_type,
            role: "video",
            source_url: "/api/editor/projects/" +
            project_id +
            "/takes/" +
            take_id +
            "/source",
            thumbnail_url: "/api/editor/projects/" +
            project_id +
            "/takes/" +
            take_id +
            "/thumbnail",
            analysis_url: "/api/editor/projects/" +
            project_id +
            "/takes/" +
            take_id +
            "/analysis",
            proxy_state: "pending",
            identity: clip.identity,
            approved: true,
            already_placed: true,
            track_id: "track-video",
            track_kind: "video",
            add_clip_template: None,
          }
          save_value(self.store, editor_take_key(project_id, take_id), take)
        }
        self.get_editor_project(project_id)
      }
    }
  })
}

///|
pub async fn StudioService::dispatch_editor_command(
  self : StudioService,
  project_id : String,
  command : @editor_domain.EditCommand,
  content_digest : String,
) -> EditorOpenView {
  self.with_mutation_lock(() => {
    guard command.expected_revision >= 0 else {
      raise Invalid(
        code="editor_revision_invalid",
        message="expected editor revision must be non-negative",
      )
    }
    let current = self.get_editor_project(project_id)
    for record in current.command_log {
      if record.command.command_id == command.command_id {
        guard record.command == command else {
          raise Conflict(
            code="editor_command_id_reused",
            message="command id already binds another editor command",
          )
        }
        return current
      }
    }
    guard command.expected_revision == current.revision else {
      raise Conflict(
        code="editor_revision_conflict",
        message="expected editor revision does not match",
      )
    }
    ignore(
      @editor_http.dispatch_project_command(
        self.editor_repository,
        project_id,
        command,
        content_digest,
      ) catch {
        _ =>
          raise Invalid(
            code="editor_command_rejected",
            message="editor command was rejected",
          )
      },
    )
    let view = self.get_editor_project(project_id)
    self.save_editor_catalog(view.snapshot, now_string())
    view
  })
}

///|
pub async fn StudioService::prepare_editor_intake(
  self : StudioService,
  project_id : String,
  input : EditorPrepareIntakeRequest,
) -> EditorPreparedIntake {
  self.with_mutation_lock(() => {
    let view = self.get_editor_project(project_id)
    guard view.revision == input.expected_editor_revision else {
      raise Conflict(
        code="editor_revision_conflict",
        message="timeline changed before media intake",
      )
    }
    let intake_id = "intake-" +
      sha256_text(project_id + ":" + input.idempotency_key)[:20].to_owned()
    let provisional : @editor_media.IntakeRequest = {
      contract: "mooncast.editor-local-media-intake.v1",
      project_id,
      expected_editor_revision: input.expected_editor_revision,
      idempotency_key: input.idempotency_key,
      role: input.role,
      file_name: input.file_name,
      mime_type: input.mime_type,
      size_bytes: input.size_bytes,
      sha256: normalized_digest(input.sha256),
      duration_ticks: input.duration_ticks,
      identity: input.identity,
      rights: input.rights,
      source: input.source,
      created_by: input.created_by,
      created_at: now_string(),
      request_digest: "",
    }
    let intake = {
      ..provisional,
      request_digest: "sha256:" + sha256_text(provisional.to_json().stringify()),
    }
    let key = editor_intake_key(project_id, intake_id)
    let existing : @editor_media.IntakeRequest? = load_value(self.store, key)
    match existing {
      Some(value) => {
        guard value == intake else {
          raise Conflict(
            code="editor_intake_idempotency_conflict",
            message="idempotency key already binds another intake",
          )
        }
      }
      None => save_value(self.store, key, intake)
    }
    {
      intake,
      intake_id,
      upload_url: "/api/editor/projects/" +
      project_id +
      "/media-intakes/" +
      intake_id +
      "/content",
      status: "awaiting-content",
      publication_authority: false,
      provider_authority: false,
    }
  })
}

///|
pub async fn StudioService::complete_editor_intake(
  self : StudioService,
  project_id : String,
  intake_id : String,
  content : Bytes,
) -> @editor_media.CompletedIntake {
  self.with_mutation_lock(() => {
    let key = editor_intake_key(project_id, intake_id)
    let intake : @editor_media.IntakeRequest? = load_value(self.store, key)
    guard intake is Some(request) else {
      raise NotFound(entity="editor_intake", id=intake_id)
    }
    let view = self.get_editor_project(project_id)
    guard view.revision == request.expected_editor_revision else {
      raise Conflict(
        code="editor_revision_conflict",
        message="timeline changed after intake preparation",
      )
    }
    let media_ref_id = "media:" + sha256_text(intake_id + ":" + request.sha256)
    let receipt_digest = "sha256:" + sha256_text(request.to_json().stringify())
    let completed = @editor_http.complete_media_intake_raw(
      self.editor_media,
      request,
      content,
      view.snapshot.timeline.timebase.ticks_per_second,
      intake_id,
      media_ref_id,
      receipt_digest,
    )
    save_value(
      self.store,
      editor_binding_key(project_id, intake_id),
      completed.binding,
    )
    let stored = self.editor_repository.load_snapshot(project_id).unwrap()
    let base_refs = stored.base_snapshot.media_refs.filter(value => {
      value.media_ref_id != media_ref_id
    })
    base_refs.push(completed.media_ref)
    let base = { ..stored.base_snapshot, media_refs: base_refs }
    let session = @editor_domain.replay(
      base,
      stored.command_log.map(entry => entry.command),
    )
    ignore(self.editor_repository.save_session(session, receipt_digest))
    let take_id = "take-" + intake_id
    let (track_id, track_kind, audio_bus_id) = track_binding_for_role(
      session.snapshot,
      request.role,
    )
    let clip : @editor_domain.Clip = {
      clip_id: "clip-" + intake_id,
      media_ref_id,
      identity: request.identity,
      intent: { intent_ref: "mooncast:editor-role:" + request.role },
      artifact_id: None,
      start_tick: 0,
      duration_ticks: request.duration_ticks,
      source_in_tick: 0,
      source_out_tick: request.duration_ticks,
      settings: @editor_domain.default_clip_settings(),
      keyframes: @editor_domain.empty_keyframes(),
      effects: [],
      effect_stack_digest: "sha256:" + sha256_text("empty-effect-stack-v1"),
      audio_bus_id,
    }
    let take : EditorTakeRecord = {
      take_id,
      project_id,
      media_ref_id,
      media_digest: completed.media_record.digest,
      mime_type: completed.media_record.mime,
      role: request.role,
      source_url: "/api/editor/projects/" +
      project_id +
      "/takes/" +
      take_id +
      "/source",
      thumbnail_url: "/api/editor/projects/" +
      project_id +
      "/takes/" +
      take_id +
      "/thumbnail",
      analysis_url: "/api/editor/projects/" +
      project_id +
      "/takes/" +
      take_id +
      "/analysis",
      proxy_state: "pending",
      identity: request.identity,
      approved: true,
      already_placed: false,
      track_id,
      track_kind,
      add_clip_template: Some({ track_id, clip }),
    }
    save_value(self.store, editor_take_key(project_id, take_id), take)
    self.save_editor_catalog(session.snapshot, now_string())
    completed
  })
}

///|
async fn StudioService::find_editor_take(
  self : StudioService,
  project_id : String,
  take_id : String,
) -> EditorTakeRecord {
  let take : EditorTakeRecord? = load_value(
    self.store,
    editor_take_key(project_id, take_id),
  )
  match take {
    Some(value) => value
    None => raise NotFound(entity="editor_take", id=take_id)
  }
}

///|
fn pcm_waveform(bytes : Bytes) -> Array[Int] {
  let samples = bytes.length() / 2
  if samples <= 0 {
    return []
  }
  let bins = Int::min(256, samples)
  let peaks : Array[Int] = []
  for bin in 0..<bins {
    let begin = bin * samples / bins
    let finish = Int::max(begin + 1, (bin + 1) * samples / bins)
    let mut peak = 0
    for index in begin..<finish {
      let raw = bytes[index * 2].to_int() | (bytes[index * 2 + 1].to_int() << 8)
      let signed = if raw >= 32768 { raw - 65536 } else { raw }
      let magnitude = if signed < 0 { -signed } else { signed }
      peak = Int::max(peak, magnitude)
    }
    peaks.push(peak)
  }
  peaks
}

///|
async fn StudioService::materialize_media(
  self : StudioService,
  digest : String,
  suffix : String,
) -> String {
  let canonical = normalized_digest(digest)
  guard self.editor_media.bytes(canonical) is Some(content) else {
    raise NotFound(entity="editor_media", id=canonical)
  }
  let key = "source-" + sha256_text(canonical) + suffix
  ignore(self.editor_render_files.put_blob(key, content))
  self.editor_render_files.owned_path(key)
}

///|
pub async fn StudioService::analyze_editor_media(
  self : StudioService,
  digest : String,
) -> EditorMediaAnalysisView {
  let canonical = normalized_digest(digest)
  let stored : EditorMediaAnalysisView? = load_value(
    self.store,
    editor_analysis_key(canonical),
  )
  if stored is Some(value) {
    return value
  }
  guard self.editor_media.get(canonical) is Some(media) else {
    raise NotFound(entity="editor_media", id=canonical)
  }
  let source_path = self.materialize_media(canonical, ".source")
  let analysis_id = @runtime.new_id(prefix="analysis")
  let analysis_digest = "sha256:" + sha256_text(canonical + ":ffprobe-json-v1")
  let base = @editor_media.probe(
    bundled_ffprobe,
    source_path,
    canonical,
    media.size,
    media.mime,
    analysis_id,
    analysis_digest,
  )
  let waveform_process = @process.run_capture({
    executable: bundled_ffmpeg,
    arguments: [
      "-hide_banner", "-nostdin", "-v", "error", "-i", source_path, "-vn", "-ac",
      "1", "-ar", "100", "-f", "s16le", "pipe:1",
    ],
    working_directory: None,
    timeout_ms: 120000,
    max_output_bytes: 4194304,
  })
  let peaks = if waveform_process.exit_code == Some(0) &&
    !waveform_process.timed_out {
    pcm_waveform(waveform_process.stdout)
  } else {
    []
  }
  let thumbnail_process = @process.run_capture({
    executable: bundled_ffmpeg,
    arguments: if base.video.state == "available" {
      [
        "-hide_banner", "-nostdin", "-v", "error", "-ss", "0", "-i", source_path,
        "-frames:v", "1", "-vf", "scale=320:-2", "-f", "image2pipe", "-vcodec", "mjpeg",
        "pipe:1",
      ]
    } else {
      [
        "-hide_banner", "-nostdin", "-v", "error", "-i", source_path, "-filter_complex",
        "showwavespic=s=640x160:colors=white", "-frames:v", "1", "-f", "image2pipe",
        "-vcodec", "mjpeg", "pipe:1",
      ]
    },
    working_directory: None,
    timeout_ms: 120000,
    max_output_bytes: 8388608,
  })
  let thumbnail_record = if thumbnail_process.exit_code == Some(0) &&
    !thumbnail_process.stdout.is_empty() {
    Some(
      self.editor_media.ingest(
        thumbnail_process.stdout,
        "image/jpeg",
        None,
        "thumbnail",
        Some(canonical),
        media.source_refs,
        [analysis_digest],
        media.rights_refs,
        now_string(),
      ),
    )
  } else {
    None
  }
  let proxy_key = "proxy-" +
    sha256_text(canonical) +
    (if base.video.state == "available" { ".mp4" } else { ".m4a" })
  ignore(self.editor_render_files.put_blob(proxy_key, b""))
  let proxy_path = self.editor_render_files.owned_path(proxy_key)
  let invocation = @editor_render.compile_proxy(
    bundled_ffmpeg,
    canonical,
    source_path,
    proxy_path,
    if base.video.state == "available" {
      "video"
    } else {
      "audio"
    },
  )
  let proxy_receipt = @editor_render.execute_proxy(invocation)
  let proxy_record = if proxy_receipt.succeeded &&
    self.editor_render_files.get_blob(proxy_key) is Some(blob) {
    Some(
      self.editor_media.ingest(
        blob.bytes,
        if base.video.state == "available" {
          "video/mp4"
        } else {
          "audio/mp4"
        },
        media.duration,
        "proxy",
        Some(canonical),
        media.source_refs,
        ["mooncast-review-source-proxy@1.0.0", analysis_digest],
        media.rights_refs,
        now_string(),
      ),
    )
  } else {
    None
  }
  let analysis = {
    ..base,
    thumbnail: match thumbnail_record {
      Some(value) =>
        {
          state: "available",
          digest: Some(value.digest),
          mime: Some(value.mime),
          width: Some(320),
          height: None,
        }
      None =>
        { state: "failed", digest: None, mime: None, width: None, height: None }
    },
    waveform: {
      state: if peaks.is_empty() {
        "unavailable"
      } else {
        "available"
      },
      peak_count: peaks.length(),
      peaks,
      digest: if peaks.is_empty() {
        None
      } else {
        Some("sha256:" + sha256_text(peaks.to_json().stringify()))
      },
    },
    source_url: Some("/api/editor/media/" + canonical),
    thumbnail_url: match thumbnail_record {
      Some(_) => Some("/api/editor/media/" + canonical + "/thumbnail")
      None => None
    },
  }
  let proxy : @editor_plan.ProxyReadiness = match proxy_record {
    Some(value) =>
      {
        source_digest: canonical,
        proxy_digest: value.digest,
        state: "available",
        cache_hit: false,
        profile: "mooncast-review-source-proxy@1.0.0",
      }
    None =>
      {
        source_digest: canonical,
        proxy_digest: "",
        state: "failed",
        cache_hit: false,
        profile: "mooncast-review-source-proxy@1.0.0",
      }
  }
  let result : EditorMediaAnalysisView = {
    analysis,
    proxy,
    publication_authority: false,
    provider_authority: false,
  }
  save_value(self.store, editor_analysis_key(canonical), result)
  result
}

///|
pub async fn StudioService::resolve_editor_media(
  self : StudioService,
  digest : String,
  prefer_proxy : Bool,
) -> (@editor_media.MediaObjectRecord, Bytes) {
  let canonical = normalized_digest(digest)
  let target = if prefer_proxy {
    let analysis : EditorMediaAnalysisView? = load_value(
      self.store,
      editor_analysis_key(canonical),
    )
    match analysis {
      Some(value) if value.proxy.state == "available" =>
        value.proxy.proxy_digest
      _ => canonical
    }
  } else {
    canonical
  }
  guard self.editor_media.get(target) is Some(record) else {
    raise NotFound(entity="editor_media", id=target)
  }
  guard self.editor_media.bytes(target) is Some(content) else {
    raise Invalid(
      code="editor_media_integrity_failed",
      message="registered editor media bytes are missing",
    )
  }
  (record, content)
}

///|
async fn StudioService::materialize_plan_media(
  self : StudioService,
  plan : @editor_plan.RenderPlan,
) -> Array[@editor_render.ResolvedMedia] {
  let result : Array[@editor_render.ResolvedMedia] = []
  let seen : Array[String] = []
  for track in plan.tracks {
    for clip in track.clips {
      if !seen.contains(clip.selected_digest) {
        let path = self.materialize_media(clip.selected_digest, ".media")
        result.push({ digest: clip.selected_digest, path })
        seen.push(clip.selected_digest)
      }
    }
  }
  result
}

///|
fn production_render_plan(
  base : @editor_plan.RenderPlan,
  request : @editor_integration.ProductionExportRequest,
) -> @editor_plan.RenderPlan raise {
  let range = request.range
  let range_end = range.start_tick + range.duration_ticks
  let base_end = base.range.start_tick + base.range.duration_ticks
  let duration_seconds = range.duration_ticks.to_double() /
    base.timebase.ticks_per_second.to_double()
  guard request.job_id == request.request_id &&
    request.quality == "original" &&
    request.max_attempts >= 1 &&
    request.max_attempts <= 10 &&
    range.start_tick >= base.range.start_tick &&
    range.duration_ticks > 0 &&
    range_end <= base_end &&
    duration_seconds >= 180.0 &&
    duration_seconds <= 480.0 else {
    fail("production export identity, range, or attempt policy is invalid")
  }
  let spec = request.spec
  let cost_ceiling = @string.parse_double(spec.cost_ceiling) catch { _ => -1.0 }
  let estimated_cost = duration_seconds *
    spec.fps.numerator.to_double() /
    spec.fps.denominator.to_double() *
    spec.width.to_double() *
    spec.height.to_double() /
    1000000000.0
  guard spec.width > 0 &&
    spec.height > 0 &&
    spec.fps.numerator > 0 &&
    spec.fps.denominator > 0 &&
    spec.container == "mp4" &&
    spec.video_codec == "h264" &&
    spec.audio_codec == "aac" &&
    spec.subtitle_mode == "embedded-and-sidecar" &&
    spec.ai_label_mode == "retain-visible" &&
    spec.retain_sources &&
    cost_ceiling >= 0.0 &&
    estimated_cost <= cost_ceiling else {
    fail(
      "production export media, subtitle, label, or provenance policy is invalid",
    )
  }
  let tracks = base.tracks.map(track => {
    let clips = track.clips.filter_map(clip => {
      let clip_end = clip.start_tick + clip.duration_ticks
      let selected_start = Int::max(clip.start_tick, range.start_tick)
      let selected_end = Int::min(clip_end, range_end)
      if selected_end <= selected_start {
        None
      } else {
        let source_in = clip.source_in_tick + selected_start - clip.start_tick
        Some({
          ..clip,
          start_tick: selected_start - range.start_tick,
          duration_ticks: selected_end - selected_start,
          source_in_tick: source_in,
          source_out_tick: source_in + selected_end - selected_start,
        })
      }
    })
    { ..track, clips, }
  })
  let transitions = base.transitions.filter_map(transition => {
    let transition_end = transition.range.start_tick +
      transition.range.duration_ticks
    if transition.range.start_tick < range.start_tick ||
      transition_end > range_end {
      None
    } else {
      Some({
        ..transition,
        cut_tick: transition.cut_tick - range.start_tick,
        range: {
          start_tick: transition.range.start_tick - range.start_tick,
          duration_ticks: transition.range.duration_ticks,
        },
      })
    }
  })
  let output = {
    ..base.output,
    preset: if spec.width > spec.height {
      "horizontal-production"
    } else {
      "vertical-production"
    },
    orientation: if spec.width > spec.height {
      "horizontal"
    } else {
      "vertical"
    },
    width: spec.width,
    height: spec.height,
    fps: spec.fps,
  }
  @editor_plan.rehash({
    ..base,
    output,
    range: { start_tick: 0, duration_ticks: range.duration_ticks },
    tracks,
    transitions,
  })
}

///|
async fn verified_editor_output(
  path : String,
  digest : String,
  size : Int,
  plan : @editor_plan.RenderPlan,
  spec : @editor_integration.ExportSpec,
) -> @editor_render.OutputInspection? {
  try
    @editor_render.inspect_render_output(bundled_ffprobe, path, digest, size, {
      project_id: plan.project_id,
      plan_digest: plan.plan_digest,
      duration_seconds: plan.range.duration_ticks.to_double() /
      plan.timebase.ticks_per_second.to_double(),
      width: spec.width,
      height: spec.height,
      fps: spec.fps,
      container: spec.container,
      video_codec: spec.video_codec,
      audio_codec: spec.audio_codec,
      audio_required: true,
      subtitle_required: true,
    })
  catch {
    _ => None
  } noraise {
    inspection => Some(inspection)
  }
}

///|
async fn StudioService::run_editor_job(
  self : StudioService,
  project_id : String,
  job_id : String,
  kind : String,
  request_digest : String,
  quality : String,
  expected_revision : Int,
  export_request : @editor_integration.ProductionExportRequest?,
  retry_job : @editor_jobs.EditorJob?,
) -> EditorJobView {
  let existing : EditorJobView? = load_value(
    self.store,
    editor_job_key(project_id, job_id),
  )
  match (existing, retry_job) {
    (Some(value), None) => {
      guard value.job.request_digest == request_digest else {
        raise Conflict(
          code="editor_job_idempotency_conflict",
          message="job id already binds another request",
        )
      }
      return value
    }
    (Some(value), Some(previous)) => {
      guard value.job == previous && previous.request_digest == request_digest else {
        raise Conflict(
          code="editor_job_retry_conflict",
          message="retry must bind the persisted failed job",
        )
      }
    }
    (None, Some(_)) =>
      raise Conflict(
        code="editor_job_retry_missing",
        message="retry cannot recreate a missing job",
      )
    (None, None) => ()
  }
  let editor = self.get_editor_project(project_id)
  guard editor.revision == expected_revision else {
    raise Conflict(
      code="editor_revision_conflict",
      message="render request does not bind the current editor revision",
    )
  }
  let frozen_plan = @editor_http.freeze_render_plan(
    self.editor_repository,
    project_id,
    editor.media_bindings,
    quality,
  )
  let plan = match export_request {
    Some(request) => production_render_plan(frozen_plan, request)
    None => frozen_plan
  }
  let created_at = now_string()
  let base_queued = @editor_jobs.EditorJob::queued(
    job_id,
    project_id,
    kind,
    plan.plan_digest,
    request_digest,
    created_at,
  )
  let queued = match retry_job {
    Some(previous) => previous.retry(created_at)
    None =>
      match export_request {
        Some(request) =>
          {
            ..base_queued,
            maximum_retries: Int::max(0, request.max_attempts - 1),
          }
        None => base_queued
      }
  }
  let running = queued.start(created_at)
  let output_key = editor_render_key(project_id, job_id)
  let subtitle_key = editor_subtitle_key(project_id, job_id)
  let provenance_key = editor_provenance_key(project_id, job_id)
  ignore(self.editor_render_files.remove(output_key))
  ignore(self.editor_render_files.remove(subtitle_key))
  ignore(self.editor_render_files.remove(provenance_key))
  let output_path = self.editor_render_files.prepare_owned_path(output_key)
  let (job, render_receipt, export_receipt) = if !plan.ready {
    let failed = running.fail(
      "render-plan-not-ready",
      plan.findings.map(value => value.code).join(","),
      now_string(),
    )
    (failed, None, None)
  } else {
    let media = self.materialize_plan_media(plan)
    let invocation = match export_request {
      Some(request) =>
        @editor_render.compile_with_encoding(
          bundled_ffmpeg,
          plan,
          media,
          output_path,
          @editor_render.delivery_encoding(
            request.spec.container,
            request.spec.video_codec,
            request.spec.audio_codec,
          ),
        )
      None => @editor_render.compile(bundled_ffmpeg, plan, media, output_path)
    }
    let receipt = @editor_render.execute(invocation)
    let output_blob = if receipt.succeeded {
      self.editor_render_files.get_blob(output_key)
    } else {
      None
    }
    if receipt.succeeded && output_blob is Some(blob) && !blob.bytes.is_empty() {
      let digest = "sha256:" + blob.sha256
      let output_ref = if kind == "export" {
        "/api/editor/projects/" + project_id + "/exports/" + job_id + "/media"
      } else {
        "/api/editor/projects/" + project_id + "/jobs/" + job_id + "/media"
      }
      match export_request {
        Some(request) => {
          let sidecar = @editor_render.subtitle_sidecar(plan)
          let inspection = verified_editor_output(
            output_path,
            digest,
            blob.bytes.length(),
            plan,
            request.spec,
          )
          if sidecar.cue_count > 0 &&
            !sidecar.content.is_blank() &&
            inspection is Some(verified) &&
            verified.passed {
            let subtitle_blob = self.editor_render_files.put_blob(
              subtitle_key,
              @utf8.encode(sidecar.content),
            )
            guard !subtitle_blob.bytes.is_empty() else {
              fail("production subtitle sidecar is empty")
            }
            let provenance = Json::object({
              "contract": "mooncast.editor-export-provenance.v1".to_json(),
              "project_id": project_id.to_json(),
              "job_id": job_id.to_json(),
              "request": request.to_json(),
              "plan_digest": plan.plan_digest.to_json(),
              "output_digest": digest.to_json(),
              "output_size": blob.bytes.length().to_json(),
              "subtitle_digest": ("sha256:" + subtitle_blob.sha256).to_json(),
              "subtitle_url": ("/api/editor/projects/" +
              project_id +
              "/exports/" +
              job_id +
              "/subtitles").to_json(),
              "ai_label": "AI GENERATED".to_json(),
              "inspection": verified.to_json(),
              "publication_authority": false.to_json(),
            })
            let provenance_blob = self.editor_render_files.put_json(
              provenance_key, provenance,
            )
            guard !provenance_blob.bytes.is_empty() else {
              fail("production provenance manifest is empty")
            }
            let completed = running.succeed(digest, output_ref, now_string())
            let completed_export : @editor_integration.ExportReceipt = {
              digest,
              size: blob.bytes.length(),
              output_ref,
              provider_ref: "mooncast-native-ffmpeg",
              provider_version: "argv-port-v1-verified",
              plan_digest: plan.plan_digest,
              spec_digest: "sha256:" +
              sha256_text(request.spec.to_json().stringify()),
              test_only: false,
              publication_authority: false,
            }
            (completed, Some(receipt), Some(completed_export))
          } else {
            ignore(self.editor_render_files.remove(output_key))
            ignore(self.editor_render_files.remove(subtitle_key))
            ignore(self.editor_render_files.remove(provenance_key))
            (
              running.fail(
                "output-verification-failed",
                "ffprobe, audio, subtitle, or label verification failed",
                now_string(),
              ),
              Some(receipt),
              None,
            )
          }
        }
        None => {
          let completed = running.succeed(digest, output_ref, now_string())
          (completed, Some(receipt), None)
        }
      }
    } else {
      ignore(self.editor_render_files.remove(output_key))
      ignore(self.editor_render_files.remove(subtitle_key))
      ignore(self.editor_render_files.remove(provenance_key))
      (
        running.fail("render-failed", receipt.stderr_tail, now_string()),
        Some(receipt),
        None,
      )
    }
  }
  let view : EditorJobView = {
    job,
    render_plan: plan,
    render_receipt,
    export_receipt,
    export_spec: export_request.map(request => request.spec),
    export_request,
    media_url: if job.state == "succeeded" {
      Some(job.output_ref)
    } else {
      None
    },
    publication_authority: false,
  }
  save_value(self.store, editor_job_key(project_id, job_id), view)
  view
}

///|
pub async fn StudioService::create_editor_preview(
  self : StudioService,
  project_id : String,
  request : EditorPreviewCreateRequest,
) -> EditorJobView {
  let job_id = request.job_id.unwrap_or(
    "preview-" +
    sha256_text(project_id + ":" + request.idempotency_key)[:20].to_owned(),
  )
  let digest = "sha256:" + sha256_text(request.to_json().stringify())
  self.with_mutation_lock(() => {
    self.run_editor_job(
      project_id,
      job_id,
      "preview",
      digest,
      request.quality,
      request.expected_editor_revision,
      None,
      None,
    )
  })
}

///|
pub async fn StudioService::create_editor_export(
  self : StudioService,
  project_id : String,
  request : EditorExportCreateRequest,
) -> EditorJobView {
  guard request.idempotency_key == request.export_request.request_id else {
    raise Invalid(
      code="editor_export_idempotency_invalid",
      message="idempotency_key must equal export.request_id",
    )
  }
  let digest = "sha256:" + sha256_text(request.to_json().stringify())
  self.with_mutation_lock(() => {
    self.run_editor_job(
      project_id,
      request.export_request.job_id,
      "export",
      digest,
      request.export_request.quality,
      request.export_request.expected_editor_revision,
      Some(request.export_request),
      None,
    )
  })
}

///|
pub async fn StudioService::get_editor_job(
  self : StudioService,
  project_id : String,
  job_id : String,
) -> EditorJobView {
  let job : EditorJobView? = load_value(
    self.store,
    editor_job_key(project_id, job_id),
  )
  match job {
    Some(value) => value
    None => raise NotFound(entity="editor_job", id=job_id)
  }
}

///|
pub async fn StudioService::retry_editor_job(
  self : StudioService,
  project_id : String,
  job_id : String,
) -> EditorJobView {
  self.with_mutation_lock(() => {
    let previous = self.get_editor_job(project_id, job_id)
    guard previous.job.state == "failed" else {
      raise Conflict(
        code="editor_job_not_retryable",
        message="only failed editor jobs can retry",
      )
    }
    guard previous.job.retry_count < previous.job.maximum_retries else {
      raise Conflict(
        code="editor_job_retry_exhausted",
        message="editor job exhausted its bounded attempt budget",
      )
    }
    guard previous.job.kind != "export" || previous.export_request is Some(_) else {
      raise Conflict(
        code="editor_export_retry_contract_missing",
        message="legacy exports without a typed request cannot be retried",
      )
    }
    self.run_editor_job(
      project_id,
      job_id,
      previous.job.kind,
      previous.job.request_digest,
      previous.render_plan.quality,
      previous.render_plan.project_revision,
      previous.export_request,
      Some(previous.job),
    )
  })
}

///|
pub async fn StudioService::resolve_editor_job_media(
  self : StudioService,
  project_id : String,
  job_id : String,
) -> Bytes {
  let job = self.get_editor_job(project_id, job_id)
  guard job.job.state == "succeeded" else {
    raise Conflict(
      code="editor_job_incomplete",
      message="editor job has no completed output",
    )
  }
  let key = editor_render_key(project_id, job_id)
  guard self.editor_render_files.get_blob(key) is Some(blob) else {
    raise Invalid(
      code="editor_job_output_missing",
      message="completed render output is missing",
    )
  }
  guard !blob.bytes.is_empty() &&
    normalized_digest(job.job.output_digest) ==
    normalized_digest("sha256:" + blob.sha256) else {
    raise Invalid(
      code="editor_job_output_integrity_failed",
      message="completed render output is empty or does not match its receipt",
    )
  }
  blob.bytes
}

///|
pub async fn StudioService::editor_export_path_for_digest(
  self : StudioService,
  project_id : String,
  output_digest : String,
) -> String {
  let wanted = normalized_digest(output_digest)
  for key in self.store.list_keys(prefix="editor-job-", suffix=".json") {
    let view : EditorJobView? = load_value(self.store, key)
    match view {
      Some(value) if value.job.project_id == project_id &&
        value.job.kind == "export" &&
        value.job.state == "succeeded" &&
        normalized_digest(value.job.output_digest) == wanted => {
        let output_key = editor_render_key(project_id, value.job.job_id)
        guard self.editor_render_files.get_blob(output_key) is Some(blob) &&
          !blob.bytes.is_empty() &&
          normalized_digest(value.job.output_digest) ==
          normalized_digest("sha256:" + blob.sha256) else {
          raise Invalid(
            code="editor_job_output_missing",
            message="completed export bytes are missing",
          )
        }
        return self.editor_render_files.owned_path(output_key)
      }
      _ => ()
    }
  }
  raise NotFound(entity="editor_export", id=output_digest)
}

///|
pub async fn StudioService::promote_editor_master(
  self : StudioService,
  project_id : String,
  job_id : String,
  envelope : EditorMasterPromotionEnvelope,
) -> @editor_integration.MasterPromotionReceipt {
  let receipt = self.with_mutation_lock(() => {
    let canonical = self.get_project(project_id)
    let editor = self.get_editor_project(project_id)
    let job = self.get_editor_job(project_id, job_id)
    guard self.editor_production_source(project_id) is Some(stored_source) &&
      stored_source == envelope.production_source &&
      production_source_binding(canonical.snapshot) == stored_source else {
      raise Conflict(
        code="editor_production_source_stale",
        message="promotion requires the exact current imported production source and G4 receipt",
      )
    }
    guard job.export_receipt is Some(completed_export) &&
      job.job.state == "succeeded" else {
      raise Conflict(
        code="editor_export_incomplete",
        message="only a completed export can become a master",
      )
    }
    guard self.editor_render_files.get_blob(
        editor_subtitle_key(project_id, job_id),
      )
      is Some(subtitle_blob) &&
      !subtitle_blob.bytes.is_empty() &&
      self.editor_render_files.get_blob(
        editor_provenance_key(project_id, job_id),
      )
      is Some(provenance_blob) &&
      !provenance_blob.bytes.is_empty() else {
      raise Conflict(
        code="editor_export_evidence_incomplete",
        message="verified subtitles and provenance are required for promotion",
      )
    }
    guard envelope.request.job_id == job_id else {
      raise Invalid(
        code="editor_master_job_mismatch",
        message="promotion request must bind the route job",
      )
    }
    let receipt = @editor_http.promote_master(
      project_id,
      canonical.snapshot.revision,
      editor.revision,
      envelope.request,
      completed_export,
      envelope.master_id,
      envelope.subtitle_ref,
      envelope.promoted_at,
    )
    save_value(
      self.store,
      editor_promotion_key(project_id, envelope.master_id),
      receipt,
    )
    save_value(self.store, editor_latest_promotion_key(project_id), receipt)
    receipt
  })
  let current = self.get_project(project_id)
  let already_registered = current.snapshot.master
    .map(master => {
      normalized_digest(master.video_digest) ==
      normalized_digest(receipt.digest)
    })
    .unwrap_or(false)
  if !already_registered {
    ignore(
      self.record_master_feature(project_id, {
        expected_project_revision: current.snapshot.revision,
        expected_master_version: current.snapshot.master.map(master => {
          master.reference.version
        }),
        expected_master_digest: current.snapshot.master.map(master => {
          master.reference.digest
        }),
        duration_seconds: current.snapshot.graph.target_duration_seconds,
        video_digest: receipt.digest,
        audio_digest: receipt.digest,
        subtitle_digest: receipt.plan_digest,
        provenance_digest: receipt.plan_digest,
        ai_label: "ai-assisted-production",
        human_confirmed: true,
        actor: receipt.actor,
      }),
    )
  }
  receipt
}

///|
pub fn StudioService::register_route_extension(
  self : StudioService,
  extension : RouteExtension,
) -> Unit {
  self.route_extensions.push(extension)
}

///|
async fn StudioService::dispatch_route_extension(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  for extension in self.route_extensions {
    if request.path == extension.prefix ||
      request.path.has_prefix(extension.prefix + "/") {
      if (extension.handler)(request) is Some(response) {
        return Some(response)
      }
    }
  }
  None
}
