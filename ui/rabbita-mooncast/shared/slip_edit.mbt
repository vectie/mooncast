///|
/// Shift the source window without changing the occupied timeline interval.
pub fn plan_slip_clip(
  timeline : Timeline,
  selected_ids : Array[String],
  source_durations : Map[String, Int],
  offset_frames : Int,
) -> Result[Json, String] {
  guard selected_ids.length() == 1 else {
    Err("Select exactly one clip to slip its source window.")
  }
  guard offset_frames != 0 else { Err("Choose a nonzero signed frame offset.") }
  let tracks = timeline.tracks.filter(track => {
    track.clips.any(clip => clip.clip_id == selected_ids[0])
  })
  guard tracks.length() == 1 else { Err("The selected clip is missing or ambiguous.") }
  let track = tracks[0]
  guard track.kind == "video" || track.kind == "audio" else {
    Err("Slip supports video and audio clips only.")
  }
  let clips = track.clips.filter(clip => clip.clip_id == selected_ids[0])
  guard clips.length() == 1 else { Err("The selected clip is ambiguous.") }
  let clip = clips[0]
  guard clip.effect_stack_digest.unwrap_or("") == "" &&
    !(clip.settings is Some(settings) &&
      (settings.transition is Some(_) || settings.effect is Some(_) ||
        settings.overlay is Some(_) || settings.color is Some(_))) else {
    Err("Remove legacy transition/effect settings and reconcile the effect stack before slipping.")
  }
  guard !timeline.transitions.any(t => {
    t.from_clip_id == clip.clip_id || t.to_clip_id == clip.clip_id
  }) else { Err("Remove transitions touching this clip before slipping.") }
  guard clip.duration_ticks > 0 && clip.start_tick >= 0 &&
    clip.source_in_tick >= 0 &&
    clip.start_tick.to_int64() + clip.duration_ticks.to_int64() <= 2147483647L &&
    clip.source_out_tick.to_int64() - clip.source_in_tick.to_int64() ==
      clip.duration_ticks.to_int64() && !roll_has_animation(clip) else {
    Err("Slip requires a valid constant-speed clip without effects or keyframes.")
  }
  guard source_durations.get(clip.media_ref_id) is Some(limit) &&
    limit > 0 && clip.source_out_tick <= limit else {
    Err("Reload source metadata; source handles are unknown or invalid.")
  }
  let step = match roll_frame_ticks(timeline) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let delta = step.to_int64() * offset_frames.to_int64()
  let source_in = clip.source_in_tick.to_int64() + delta
  let source_out = clip.source_out_tick.to_int64() + delta
  guard source_in >= 0L && source_out <= limit.to_int64() &&
    source_out <= 2147483647L else {
    Err("Not enough source handles for this signed frame offset.")
  }
  Ok({
    "clip_id": clip.clip_id,
    "source_in_tick": source_in.to_int(),
    "source_out_tick": source_out.to_int(),
    "start_tick": clip.start_tick,
  })
}
