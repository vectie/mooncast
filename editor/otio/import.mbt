///|
fn reel(index : Int) -> String {
  let s = (index + 1).to_string()
  "R" +
  (if s.length() == 1 { "00" } else if s.length() == 2 { "0" } else { "" }) +
  s
}

///|
/// Import picture through the established exact EDL adapter and retain an optional
/// synchronized soundtrack as a separate ordinary audio track. EDL is picture-only.
/// OTIO URL tokens only choose explicit existing-media bindings.
/// Global timeline origin is retained in the catalog; native time starts at zero.
pub fn import_timeline(
  project : @domain.EditorProject,
  input : String,
  mapping : MediaMap,
) -> ImportedTimeline raise {
  let mapping = read_media_map(mapping.to_json().stringify())
  let catalog = catalog_timeline(input, mapping.fps)
  for binding in mapping.bindings {
    if !catalog.items.any(item => {
        item.kind == "clip" && item.target_url == binding.target_url
      }) {
      fail("OTIO unused media binding: " + binding.target_url)
    }
  }
  let bindings : Array[@edl.ReelBinding] = []
  for i, binding in mapping.bindings {
    if !catalog.items.any(item => {
        item.track_kind == "Video" && item.target_url == binding.target_url
      }) {
      continue
    }
    bindings.push({
      reel: reel(i),
      media_ref_id: binding.media_ref_id,
      template_clip_id: binding.template_clip_id,
      source_start_timecode: "00:00:00:00",
    })
  }
  let edl_mapping : @edl.ReelMap = {
    contract: "mooncast.edl-reel-map.v1",
    fps: mapping.fps,
    record_start_timecode: "00:00:00:00",
    draft_timeline_id: mapping.draft_timeline_id,
    bindings,
  }
  let lines : Array[String] = [
    "TITLE: OTIO picture-only projection", "FCM: NON-DROP FRAME",
  ]
  let mut event = 0
  for item in catalog.items {
    if item.kind == "gap" || item.track_kind != "Video" {
      continue
    }
    let indexes = [
      for i, b in mapping.bindings if b.target_url == item.target_url => i
    ]
    if indexes.length() != 1 {
      fail("OTIO unmapped exact target_url token: " + item.target_url)
    }
    let index = indexes[0]
    let binding = mapping.bindings[index]
    if item.source_start_frame < binding.source_start_frame {
      fail("OTIO clip starts before the explicit mapped source origin")
    }
    if item.available_start_frame is Some(a) && a != binding.source_start_frame {
      fail("OTIO available_range start differs from mapped source origin")
    }
    let start = item.source_start_frame - binding.source_start_frame
    if start.to_int64() + item.duration_frames.to_int64() >=
      (86400 * mapping.fps).to_int64() {
      fail("OTIO source-relative range must fit within one EDL day")
    }
    event += 1
    let number = event.to_string()
    let number = (if event < 10 {
        "00"
      } else if event < 100 {
        "0"
      } else {
        ""
      }) +
      number
    lines.push(
      number +
      " " +
      reel(index) +
      " V C " +
      @edl.frames_timecode(start, mapping.fps) +
      " " +
      @edl.frames_timecode(start + item.duration_frames, mapping.fps) +
      " " +
      @edl.frames_timecode(item.start_frame, mapping.fps) +
      " " +
      @edl.frames_timecode(item.start_frame + item.duration_frames, mapping.fps),
    )
  }
  let normalized_edl = lines.join("\n") + "\n"
  let imported = @edl.import_edl(project, normalized_edl, edl_mapping)
  let audio_clips : Array[@domain.Clip] = []
  let audio_preview : Array[AudioCutPreview] = []
  let timebase = imported.project.timeline.timebase.ticks_per_second
  let ticks_per_frame = timebase / mapping.fps
  let mut previous_end = 0
  for item in catalog.items {
    if item.track_kind != "Audio" || item.kind != "clip" {
      continue
    }
    let matches = mapping.bindings.filter(binding => {
      binding.target_url == item.target_url
    })
    guard matches.length() == 1 else {
      fail("OTIO unmapped exact audio target_url token: " + item.target_url)
    }
    let binding = matches[0]
    if item.source_start_frame < binding.source_start_frame ||
      (
        item.available_start_frame is Some(start) &&
        start != binding.source_start_frame
      ) {
      fail("OTIO audio source range must fit its explicit mapped source origin")
    }
    let source_in_frame = item.source_start_frame - binding.source_start_frame
    let source_out_frame = source_in_frame + item.duration_frames
    if source_out_frame >= 86400 * mapping.fps {
      fail("OTIO audio source-relative range must fit within one day")
    }
    let media = imported.project.media_refs.filter(media => {
      media.media_ref_id == binding.media_ref_id
    })
    guard media.length() == 1 &&
      media[0].metadata.mime_type.has_prefix("audio/") &&
      media[0].metadata.duration_ticks > 0 else {
      fail(
        "OTIO Audio track must map to one audio media reference with known positive duration",
      )
    }
    let template = audio_template(project, binding)
    let source_in_tick = audio_tick(source_in_frame, ticks_per_frame)
    let source_out_tick = audio_tick(source_out_frame, ticks_per_frame)
    if source_out_tick > media[0].metadata.duration_ticks {
      fail("OTIO audio clip exceeds mapped media duration")
    }
    let end_frame = item.start_frame + item.duration_frames
    audio_tick(end_frame, ticks_per_frame) |> ignore
    let clip_id = "otio.audio." + (audio_clips.length() + 1).to_string()
    audio_clips.push({
      clip_id,
      media_ref_id: binding.media_ref_id,
      identity: template.identity,
      intent: template.intent,
      artifact_id: template.artifact_id,
      start_tick: audio_tick(item.start_frame, ticks_per_frame),
      duration_ticks: source_out_tick - source_in_tick,
      source_in_tick,
      source_out_tick,
      settings: @domain.default_clip_settings(),
      keyframes: @domain.empty_keyframes(),
      effects: [],
      effect_stack_digest: "",
      audio_bus_id: None,
    })
    audio_preview.push({
      clip_id,
      media_ref_id: binding.media_ref_id,
      source_in_frame,
      source_out_frame,
      start_frame: item.start_frame,
      end_frame,
      gap_before_frames: item.start_frame - previous_end,
    })
    previous_end = end_frame
  }
  let tracks = imported.project.timeline.tracks.copy()
  if !audio_clips.is_empty() {
    tracks.push({
      track_id: "otio.audio",
      kind: "audio",
      order: 1,
      mix: Some({ volume_db: 0.0, pan: 0.0, muted: false, }),
      clips: audio_clips,
    })
  }
  let result = {
    ..imported.project,
    timeline: { ..imported.project.timeline, tracks, },
  }
  {
    project: result,
    catalog,
    preview: imported.preview,
    audio_preview,
    edl_mapping,
    normalized_edl,
  }
}

///|
fn audio_tick(frame : Int, ticks_per_frame : Int) -> Int raise {
  let value = frame.to_int64() * ticks_per_frame.to_int64()
  guard value >= 0L && value <= 2147483647L else {
    fail("OTIO audio ticks exceed the native integer clock")
  }
  value.to_int()
}

///|
fn audio_template(
  project : @domain.EditorProject,
  binding : MediaBinding,
) -> @domain.Clip raise {
  let matches : Array[@domain.Clip] = []
  for track in project.timeline.tracks {
    for clip in track.clips {
      if clip.clip_id == binding.template_clip_id {
        matches.push(clip)
      }
    }
  }
  guard matches.length() == 1 && matches[0].media_ref_id == binding.media_ref_id else {
    fail(
      "OTIO audio template must identify one existing clip using the mapped media",
    )
  }
  let clip = matches[0]
  guard clip.identity.project_id == project.project_id &&
    project.identity_graph.contains(clip.identity) &&
    project.intent_refs.contains(clip.intent) else {
    fail("OTIO audio template must retain existing project identity and intent")
  }
  if clip.artifact_id is Some(id) {
    guard project.artifacts.any(artifact => {
      artifact.artifact_id == id &&
      artifact.output_media_ref_ids.contains(binding.media_ref_id)
    }) else {
      fail("OTIO audio template artifact does not identify the mapped media")
    }
  }
  clip
}
