///|
/// Three trims form one history entry; the middle source window stays fixed.
pub(all) struct SlideClipPlan {
  payload : Json
  left_clip_id : String
  clip_id : String
  right_clip_id : String
  start_tick : Int
  end_tick : Int
  delta_ticks : Int
} derive(ToJson)

///|
pub fn plan_slide_clip(
  timeline : Timeline,
  selected_ids : Array[String],
  source_durations : Map[String, Int],
  offset_frames : Int,
) -> Result[SlideClipPlan, String] {
  guard selected_ids.length() == 1 && offset_frames != 0 else {
    Err("Select one middle clip and enter a nonzero signed frame offset.")
  }
  let tracks = timeline.tracks.filter(track => {
    track.clips.any(clip => clip.clip_id == selected_ids[0])
  })
  guard tracks.length() == 1 else {
    Err("The selected clip is missing or ambiguous.")
  }
  let track = tracks[0]
  guard track.kind == "video" || track.kind == "audio" else {
    Err("Slide supports one video or audio track only.")
  }
  let selected = track.clips.filter(clip => clip.clip_id == selected_ids[0])
  guard selected.length() == 1 else { Err("The selected clip is ambiguous.") }
  let middle = selected[0]
  // Validate intervals before looking for neighbors, using wider arithmetic.
  for clip in track.clips {
    guard clip.start_tick >= 0 &&
      clip.duration_ticks > 0 &&
      clip.start_tick.to_int64() + clip.duration_ticks.to_int64() <= 2147483647L else {
      return Err("Reconcile invalid track timing before sliding.")
    }
  }
  let middle_end = middle.start_tick.to_int64() +
    middle.duration_ticks.to_int64()
  let lefts = track.clips.filter(clip => {
    clip.clip_id != middle.clip_id &&
    clip.start_tick.to_int64() + clip.duration_ticks.to_int64() ==
    middle.start_tick.to_int64()
  })
  let rights = track.clips.filter(clip => {
    clip.clip_id != middle.clip_id && clip.start_tick.to_int64() == middle_end
  })
  guard lefts.length() == 1 && rights.length() == 1 else {
    Err(
      "The selected clip needs one adjacent neighbor on each side, with no gap.",
    )
  }
  let left = lefts[0]
  let right = rights[0]
  let ids = [left.clip_id, middle.clip_id, right.clip_id]
  guard left.clip_id != right.clip_id else {
    Err("Neighbor clip IDs are ambiguous.")
  }
  for id in ids {
    guard id.trim() != "" else {
      return Err("Affected clips need nonblank IDs.")
    }
    let mut count = 0
    for candidate_track in timeline.tracks {
      for clip in candidate_track.clips {
        if clip.clip_id == id {
          count += 1
        }
      }
    }
    guard count == 1 else {
      return Err("Affected clip IDs must be unique across the timeline.")
    }
  }
  let outer_end = right.start_tick.to_int64() + right.duration_ticks.to_int64()
  guard !track.clips.any(clip => {
    !ids.contains(clip.clip_id) &&
    clip.start_tick.to_int64() < outer_end &&
    clip.start_tick.to_int64() + clip.duration_ticks.to_int64() >
    left.start_tick.to_int64()
  }) else {
    Err("Another clip overlaps the three-clip slide interval.")
  }
  guard !timeline.transitions.any(t => {
    ids.contains(t.from_clip_id) || ids.contains(t.to_clip_id)
  }) else {
    Err("Remove transitions touching all three clips before sliding.")
  }
  for clip in [left, middle, right] {
    guard clip.media_ref_id.trim() != "" &&
      clip.source_in_tick >= 0 &&
      clip.source_out_tick.to_int64() - clip.source_in_tick.to_int64() ==
      clip.duration_ticks.to_int64() &&
      !roll_has_animation(clip) &&
      clip.effect_stack_digest.unwrap_or("") == "" &&
      !(clip.settings is Some(settings) &&
      (
        settings.transition is Some(_) ||
        settings.effect is Some(_) ||
        settings.overlay is Some(_) ||
        settings.color is Some(_)
      )) else {
      return Err(
        "Slide requires constant-speed clips without transitions, effects or keyframes.",
      )
    }
    guard source_durations.get(clip.media_ref_id) is Some(limit) &&
      limit > 0 &&
      clip.source_out_tick <= limit else {
      return Err(
        "Reload source metadata for all three clips; available handles are unknown or invalid.",
      )
    }
  }
  let step = match roll_frame_ticks(timeline) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let delta = step.to_int64() * offset_frames.to_int64()
  let left_out = left.source_out_tick.to_int64() + delta
  let right_in = right.source_in_tick.to_int64() + delta
  let start = middle.start_tick.to_int64() + delta
  let end = middle_end + delta
  guard delta >= -2147483648L &&
    delta <= 2147483647L &&
    left_out > left.source_in_tick.to_int64() &&
    left_out <= source_durations[left.media_ref_id].to_int64() &&
    right_in >= 0L &&
    right_in < right.source_out_tick.to_int64() &&
    start >= 0L &&
    end <= 2147483647L else {
    Err(
      "Not enough neighbor source handles, or the slide would empty a neighbor.",
    )
  }
  Ok({
    left_clip_id: left.clip_id,
    clip_id: middle.clip_id,
    right_clip_id: right.clip_id,
    start_tick: start.to_int(),
    end_tick: end.to_int(),
    delta_ticks: delta.to_int(),
    payload: {
      "trims": [
        {
          "clip_id": left.clip_id,
          "source_in_tick": left.source_in_tick,
          "source_out_tick": left_out.to_int(),
          "start_tick": left.start_tick,
        },
        {
          "clip_id": middle.clip_id,
          "source_in_tick": middle.source_in_tick,
          "source_out_tick": middle.source_out_tick,
          "start_tick": start.to_int(),
        },
        {
          "clip_id": right.clip_id,
          "source_in_tick": right_in.to_int(),
          "source_out_tick": right.source_out_tick,
          "start_tick": end.to_int(),
        },
      ],
    },
  })
}
