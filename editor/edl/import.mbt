///|
fn media_for(
  project : @domain.EditorProject,
  id : String,
) -> @domain.MediaRef raise {
  let matches = project.media_refs.filter(media => media.media_ref_id == id)
  guard matches.length() == 1 else {
    fail("expected one existing media reference: " + id)
  }
  guard matches[0].metadata.mime_type.has_prefix("video/") &&
    matches[0].metadata.duration_ticks > 0 else {
    fail(
      "EDL reel must map to video media with a known positive duration: " + id,
    )
  }
  matches[0]
}

///|
fn template_for(
  project : @domain.EditorProject,
  binding : ReelBinding,
) -> @domain.Clip raise {
  let clips : Array[@domain.Clip] = []
  for track in project.timeline.tracks {
    for clip in track.clips {
      if clip.clip_id == binding.template_clip_id {
        clips.push(clip)
      }
    }
  }
  guard clips.length() == 1 && clips[0].media_ref_id == binding.media_ref_id else {
    fail(
      "template_clip_id must identify one existing clip using the mapped media: " +
      binding.reel,
    )
  }
  let clip = clips[0]
  guard clip.identity.project_id == project.project_id &&
    project.identity_graph.contains(clip.identity) &&
    project.intent_refs.contains(clip.intent) else {
    fail(
      "mapped template must retain an existing project identity and intent: " +
      binding.reel,
    )
  }
  if clip.artifact_id is Some(id) {
    guard project.artifacts.any(artifact => {
      artifact.artifact_id == id &&
      artifact.output_media_ref_ids.contains(binding.media_ref_id)
    }) else {
      fail(
        "mapped template artifact does not identify the mapped media: " +
        binding.reel,
      )
    }
  }
  clip
}

///|
/// Build a separate video-only native draft, retaining media and production lineage.
/// The timebase is raised to its LCM with fps so every frame remains exact; media
/// duration ticks are scaled by the same integer factor. No source project mutates.
pub fn import_edl(
  project : @domain.EditorProject,
  input : String,
  mapping : ReelMap,
) -> ImportedCut raise {
  mapping.validate()
  guard project.contract == "mooncast.editor-project.v1" &&
    project.timeline.contract == "mooncast.editor-timeline.v1" else {
    fail("expected a native editor project snapshot")
  }
  let list = parse_edl(input, mapping.fps)
  let origin = timecode_frames(mapping.record_start_timecode, mapping.fps)
  let timebase = exact_timebase(
    project.timeline.timebase.ticks_per_second,
    mapping.fps,
  )
  let factor = timebase / project.timeline.timebase.ticks_per_second
  let media_refs = project.media_refs.map(media => {
    ..media,
    metadata: {
      ..media.metadata,
      duration_ticks: checked_int(
        media.metadata.duration_ticks.to_int64() * factor.to_int64(),
      ),
    },
  })
  let clips : Array[@domain.Clip] = []
  let previews : Array[CutPreview] = []
  let mut end_frame = 0
  let mut gap_frames = 0
  for cut in list.cuts {
    let bindings = mapping.bindings.filter(binding => binding.reel == cut.reel)
    guard bindings.length() == 1 else { fail("unmapped reel: " + cut.reel) }
    let binding = bindings[0]
    let media = media_for(project, binding.media_ref_id)
    let template = template_for(project, binding)
    let source_origin = timecode_frames(
      binding.source_start_timecode,
      mapping.fps,
    )
    let source_in_frame = cut.source_in_frame - source_origin
    let source_out_frame = cut.source_out_frame - source_origin
    let start_frame = cut.record_in_frame - origin
    let next_end_frame = cut.record_out_frame - origin
    guard source_in_frame >= 0 && start_frame >= 0 else {
      fail(
        "event " +
        cut.event_number.to_string() +
        " starts before the mapped source or record origin",
      )
    }
    let source_in_tick = frames_to_ticks(source_in_frame, mapping.fps, timebase)
    let source_out_tick = frames_to_ticks(
      source_out_frame,
      mapping.fps,
      timebase,
    )
    guard source_out_tick.to_int64() <=
      media.metadata.duration_ticks.to_int64() * factor.to_int64() else {
      fail(
        "event " +
        cut.event_number.to_string() +
        " exceeds mapped media duration: " +
        cut.reel,
      )
    }
    let clip_id = "edl." + pad(cut.event_number, 3)
    clips.push({
      clip_id,
      media_ref_id: media.media_ref_id,
      identity: template.identity,
      intent: template.intent,
      artifact_id: template.artifact_id,
      start_tick: frames_to_ticks(start_frame, mapping.fps, timebase),
      duration_ticks: source_out_tick - source_in_tick,
      source_in_tick,
      source_out_tick,
      settings: @domain.default_clip_settings(),
      keyframes: @domain.empty_keyframes(),
      effects: [],
      effect_stack_digest: "",
      audio_bus_id: None,
    })
    // Validate the complete end as well, not just start and duration separately.
    ignore(frames_to_ticks(next_end_frame, mapping.fps, timebase))
    let gap_before_frames = start_frame - end_frame
    gap_frames = gap_frames + gap_before_frames
    previews.push({
      event_number: cut.event_number,
      reel: cut.reel,
      media_ref_id: media.media_ref_id,
      clip_id,
      source_in_frame,
      source_out_frame,
      start_frame,
      end_frame: next_end_frame,
      gap_before_frames,
    })
    end_frame = next_end_frame
  }
  let timeline : @domain.Timeline = {
    ..project.timeline,
    timeline_id: mapping.draft_timeline_id,
    revision: 0,
    timebase: { ticks_per_second: timebase, },
    output: {
      ..project.timeline.output,
      fps: { numerator: mapping.fps, denominator: 1, },
    },
    tracks: [
      { track_id: "edl.video", kind: "video", order: 0, mix: None, clips, },
    ],
    transitions: [],
    audio_buses: [],
  }
  {
    project: { ..project, revision: 0, media_refs, timeline, },
    preview: {
      contract: "mooncast.edl-preview.v1",
      title: list.title,
      source_project_id: project.project_id,
      source_revision: project.revision,
      source_timeline_id: project.timeline.timeline_id,
      fps: mapping.fps,
      record_start_timecode: mapping.record_start_timecode,
      ticks_per_second: timebase,
      duration_frames: end_frame,
      gap_frames,
      cuts: previews,
    },
  }
}
