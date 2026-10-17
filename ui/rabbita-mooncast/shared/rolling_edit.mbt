///|
/// One atomic group trim: the outer boundaries and all asset references stay put.
pub(all) struct RollCutPlan {
  payload : Json
  boundary_tick : Int
} derive(ToJson)

///|
pub fn roll_frame_ticks(timeline : Timeline) -> Result[Int, String] {
  let fps = timeline.output
    .bind(output => output.fps)
    .unwrap_or({ numerator: 24, denominator: 1, })
  let numerator = timeline.timebase.ticks_per_second.to_int64() *
    fps.denominator.to_int64()
  guard fps.numerator > 0 && fps.denominator > 0 && numerator > 0L else {
    Err("The output frame rate and timeline timebase must be positive.")
  }
  // Quantize one output frame to the nearest representable timeline tick.
  let ticks = (numerator + fps.numerator.to_int64() / 2L) /
    fps.numerator.to_int64()
  guard ticks > 0L && ticks <= 2147483647L else {
    Err("Frame duration exceeds the supported tick range.")
  }
  Ok(ticks.to_int())
}

///|
fn roll_has_animation(clip : Clip) -> Bool {
  if !clip.effects.unwrap_or([]).is_empty() {
    return true
  }
  match clip.keyframes {
    None | Some(Null) => false
    Some(Object(fields)) =>
      fields
      .values()
      .any(value => {
        match value {
          Array(points) => !points.is_empty()
          _ => true
        }
      })
    _ => true
  }
}

///|
pub fn plan_roll_cut(
  timeline : Timeline,
  selected_ids : Array[String],
  source_durations : Map[String, Int],
  delta_ticks : Int,
) -> Result[RollCutPlan, String] {
  guard selected_ids.length() == 2 && selected_ids[0] != selected_ids[1] else {
    Err(
      "Select exactly two adjacent clips on the same track to roll their cut.",
    )
  }
  let selected_tracks = timeline.tracks.filter(track => {
    track.clips.any(clip => selected_ids.contains(clip.clip_id))
  })
  guard selected_tracks.length() == 1 else {
    Err("Rolling needs two clips on the same track.")
  }
  let track = selected_tracks[0]
  guard track.kind == "video" || track.kind == "audio" else {
    Err("Rolling supports video and audio tracks only.")
  }
  let selected = track.clips.filter(clip => selected_ids.contains(clip.clip_id))
  guard selected.length() == 2 else {
    Err("The selected clips are no longer in this timeline.")
  }
  let (left, right) = if selected[0].start_tick < selected[1].start_tick {
    (selected[0], selected[1])
  } else {
    (selected[1], selected[0])
  }
  guard left.start_tick.to_int64() + left.duration_ticks.to_int64() ==
    right.start_tick.to_int64() else {
    Err("The selected clips must share a cut with no gap or overlap.")
  }
  guard delta_ticks != 0 else { Err("Choose a nonzero roll amount.") }
  guard !timeline.transitions.any(transition => {
    selected_ids.contains(transition.from_clip_id) ||
    selected_ids.contains(transition.to_clip_id)
  }) else {
    Err("Remove transitions touching these clips before rolling their cut.")
  }
  for clip in selected {
    guard clip.duration_ticks > 0 &&
      clip.source_in_tick >= 0 &&
      clip.start_tick >= 0 &&
      clip.source_out_tick.to_int64() - clip.source_in_tick.to_int64() ==
      clip.duration_ticks.to_int64() &&
      !roll_has_animation(clip) else {
      return Err(
        "Rolling requires constant-speed clips without effects or keyframes.",
      )
    }
    guard source_durations.get(clip.media_ref_id) is Some(limit) &&
      limit > 0 &&
      clip.source_out_tick <= limit else {
      return Err(
        "Reload source media metadata before rolling; source handles are unknown or invalid.",
      )
    }
  }
  let delta = delta_ticks.to_int64()
  let left_out = left.source_out_tick.to_int64() + delta
  let right_in = right.source_in_tick.to_int64() + delta
  let boundary = right.start_tick.to_int64() + delta
  guard left_out > left.source_in_tick.to_int64() &&
    left_out <= source_durations[left.media_ref_id].to_int64() &&
    right_in >= 0L &&
    right_in < right.source_out_tick.to_int64() &&
    boundary >= 0L &&
    boundary <= 2147483647L else {
    Err("Not enough source handles, or the roll would empty a clip.")
  }
  Ok({
    boundary_tick: boundary.to_int(),
    payload: {
      "trims": [
        {
          "clip_id": left.clip_id,
          "source_in_tick": left.source_in_tick,
          "source_out_tick": left_out.to_int(),
          "start_tick": left.start_tick,
        },
        {
          "clip_id": right.clip_id,
          "source_in_tick": right_in.to_int(),
          "source_out_tick": right.source_out_tick,
          "start_tick": boundary.to_int(),
        },
      ],
    },
  })
}
