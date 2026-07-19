///|
fn sha256_text(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn find_media(
  project : @domain.EditorProject,
  id : String,
) -> @domain.MediaRef? {
  for value in project.media_refs {
    if value.media_ref_id == id {
      return Some(value)
    }
  }
  None
}

///|
fn find_binding(
  bindings : Array[@domain.LocalMediaBinding],
  id : String,
) -> @domain.LocalMediaBinding? {
  for value in bindings {
    if value.intake_receipt.media_ref_id == id {
      return Some(value)
    }
  }
  None
}

///|
fn find_artifact(
  project : @domain.EditorProject,
  id : String?,
) -> @domain.AigcArtifact? {
  match id {
    None => None
    Some(target) => {
      for value in project.artifacts {
        if value.artifact_id == target {
          return Some(value)
        }
      }
      None
    }
  }
}

///|
fn freeze_clip(
  project : @domain.EditorProject,
  clip : @domain.Clip,
  bindings : Array[@domain.LocalMediaBinding],
  findings : Array[PlanFinding],
) -> FrozenClip {
  let media = find_media(project, clip.media_ref_id)
  let binding = find_binding(bindings, clip.media_ref_id)
  let artifact = find_artifact(project, clip.artifact_id)
  let original_digest = match media {
    Some(value) => "sha256:" + value.metadata.sha256
    None => ""
  }
  if media is None {
    findings.push({
      code: "missing-media-ref",
      severity: "error",
      message: "clip media reference is absent",
      track_id: "",
      clip_id: clip.clip_id,
    })
  }
  if binding is None && artifact is None {
    findings.push({
      code: "missing-media-evidence",
      severity: "error",
      message: "clip has neither generated artifact nor rights-bound local media",
      track_id: "",
      clip_id: clip.clip_id,
    })
  }
  if artifact is Some(value) &&
    (value.rights_state != "cleared" || value.review_state != "passed") {
    findings.push({
      code: "generated-media-unapproved",
      severity: "error",
      message: "generated clip lacks rights or passed QC",
      track_id: "",
      clip_id: clip.clip_id,
    })
  }
  let source_refs = match artifact {
    Some(value) => value.source_refs
    None => []
  }
  let provenance_refs = match artifact {
    Some(value) => [value.prompt_digest, value.provider, value.model]
    None => []
  }
  let rights_refs = match binding {
    Some(value) => [value.rights_ref]
    None =>
      match artifact {
        Some(value) => value.source_refs
        None => []
      }
  }
  let selected_digest = match binding {
    Some(value) => value.media_digest
    None => original_digest
  }
  {
    clip_id: clip.clip_id,
    media_ref_id: clip.media_ref_id,
    identity: clip.identity,
    start_tick: clip.start_tick,
    duration_ticks: clip.duration_ticks,
    source_in_tick: clip.source_in_tick,
    source_out_tick: clip.source_out_tick,
    settings: clip.settings,
    keyframes: clip.keyframes,
    effects: clip.effects,
    effect_stack_digest: clip.effect_stack_digest,
    audio_bus_id: clip.audio_bus_id,
    original_digest,
    selected_digest,
    selection: if binding is Some(_) {
      "rights-cleared-local"
    } else if artifact is Some(_) {
      "approved-generated-original"
    } else {
      "unresolved"
    },
    original_source_refs: source_refs,
    original_provenance_refs: provenance_refs,
    original_rights_refs: rights_refs,
    selected_source_refs: source_refs,
    selected_provenance_refs: provenance_refs,
    selected_rights_refs: rights_refs,
    local_media: binding,
  }
}

///|
fn find_clip(project : @domain.EditorProject, id : String) -> @domain.Clip? {
  for track in project.timeline.tracks {
    for clip in track.clips {
      if clip.clip_id == id {
        return Some(clip)
      }
    }
  }
  None
}

///|
fn frozen_transition(
  project : @domain.EditorProject,
  value : @domain.Transition,
) -> FrozenTransition {
  let outgoing = find_clip(project, value.from_clip_id)
  let incoming = find_clip(project, value.to_clip_id)
  let cut_tick = match outgoing {
    Some(clip) => clip.start_tick + clip.duration_ticks
    None => 0
  }
  let incoming_start = match incoming {
    Some(clip) => clip.start_tick
    None => cut_tick
  }
  let relationship = if incoming_start < cut_tick {
    "layer-overlap"
  } else {
    "edit-point"
  }
  let start_tick = if value.duration_ticks == 0 {
    cut_tick
  } else if relationship == "layer-overlap" {
    incoming_start
  } else {
    Int::max(0, cut_tick - value.outgoing_handle_ticks)
  }
  {
    transition_id: value.transition_id,
    track_id: value.track_id,
    from_clip_id: value.from_clip_id,
    to_clip_id: value.to_clip_id,
    kind: value.kind,
    duration_ticks: value.duration_ticks,
    outgoing_handle_ticks: value.outgoing_handle_ticks,
    incoming_handle_ticks: value.incoming_handle_ticks,
    color: value.color,
    direction: value.direction,
    transition_digest: value.transition_digest,
    relationship,
    cut_tick,
    range: { start_tick, duration_ticks: value.duration_ticks },
  }
}

///|
fn plan_duration(project : @domain.EditorProject) -> Int {
  project.timeline.tracks.fold(init=0, (timeline_end, track) => {
    track.clips.fold(init=timeline_end, (end_tick, clip) => {
      Int::max(end_tick, clip.start_tick + clip.duration_ticks)
    })
  })
}

///|
/// Freezes an editor revision. It records problems instead of performing IO.
pub fn freeze(
  project : @domain.EditorProject,
  bindings : Array[@domain.LocalMediaBinding],
  quality : String,
) -> RenderPlan {
  let findings : Array[PlanFinding] = []
  if project.revision != project.timeline.revision {
    findings.push({
      code: "revision-mismatch",
      severity: "error",
      message: "project and timeline revisions differ",
      track_id: "",
      clip_id: "",
    })
  }
  let tracks = project.timeline.tracks.map(track => {
    let clips = track.clips.map(clip => {
      let frozen = freeze_clip(project, clip, bindings, findings)
      if frozen.selection == "unresolved" {
        findings.push({
          code: "track-media-unready",
          severity: "error",
          message: "track contains unresolved media",
          track_id: track.track_id,
          clip_id: clip.clip_id,
        })
      }
      frozen
    })
    {
      track_id: track.track_id,
      kind: track.kind,
      order: track.order,
      mix: track.mix,
      clips,
    }
  })
  let transitions = project.timeline.transitions.map(value => {
    frozen_transition(project, value)
  })
  let range = { start_tick: 0, duration_ticks: plan_duration(project) }
  if range.duration_ticks <= 0 {
    findings.push({
      code: "empty-timeline",
      severity: "error",
      message: "render range is empty",
      track_id: "",
      clip_id: "",
    })
  }
  let ready = !findings.any(value => value.severity == "error")
  let provisional : RenderPlan = {
    contract: "mooncast.editor-render-plan.v1",
    project_id: project.project_id,
    timeline_id: project.timeline.timeline_id,
    project_revision: project.revision,
    timeline_revision: project.timeline.revision,
    timebase: project.timeline.timebase,
    output: project.timeline.output,
    range,
    quality,
    tracks,
    transitions,
    audio_buses: project.timeline.audio_buses,
    delivery_audio: project.timeline.delivery_audio,
    findings,
    ready,
    publication_authority: false,
    plan_digest: "",
  }
  { ..provisional, plan_digest: sha256_text(provisional.to_json().stringify()) }
}

///|
pub fn cache_projection(
  plan : RenderPlan,
  range : TickRange,
) -> CacheKeyProjection {
  let clips : Array[CacheClipProjection] = []
  for track in plan.tracks {
    for clip in track.clips {
      let clip_end = clip.start_tick + clip.duration_ticks
      let range_end = range.start_tick + range.duration_ticks
      if clip.start_tick < range_end && clip_end > range.start_tick {
        clips.push({
          clip_id: clip.clip_id,
          selected_digest: clip.selected_digest,
          start_tick: clip.start_tick,
          duration_ticks: clip.duration_ticks,
          source_in_tick: clip.source_in_tick,
          source_out_tick: clip.source_out_tick,
          effect_stack_digest: clip.effect_stack_digest,
        })
      }
    }
  }
  let provisional : CacheKeyProjection = {
    contract: "mooncast.editor-preview-cache-key.v1",
    plan_digest: plan.plan_digest,
    project_revision: plan.project_revision,
    timeline_revision: plan.timeline_revision,
    quality: plan.quality,
    range,
    output: plan.output,
    clips,
    transition_digests: plan.transitions.map(value => value.transition_digest),
    audio_bus_digests: plan.audio_buses.map(value => value.bus_digest),
    delivery_audio_digest: plan.delivery_audio.delivery_audio_digest,
    cache_key: "",
  }
  { ..provisional, cache_key: sha256_text(provisional.to_json().stringify()) }
}

///|
pub fn rehash(value : RenderPlan) -> RenderPlan {
  let provisional = { ..value, plan_digest: "" }
  { ..provisional, plan_digest: sha256_text(provisional.to_json().stringify()) }
}
