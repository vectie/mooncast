///|
/// Export native cuts without dropping visual edits, rounding frames or selecting
/// a track implicitly. Audio-only, layered, transformed and retimed edits need a
/// richer interchange format and are deliberately not flattened into CMX3600.
pub fn export_edl(
  project : @domain.EditorProject,
  mapping : ReelMap,
  title : String,
) -> String raise {
  mapping.validate()
  guard project.contract == "mooncast.editor-project.v1" &&
    project.timeline.contract == "mooncast.editor-timeline.v1" else {
    fail("expected a native editor project snapshot")
  }
  guard !title.is_empty() &&
    title.length() <= 120 &&
    title.iter().all(c => c >= ' ') else {
    fail("TITLE needs 1–120 printable characters")
  }
  let timeline = project.timeline
  guard timeline.output.fps.numerator == mapping.fps &&
    timeline.output.fps.denominator == 1 else {
    fail("map fps must match the native integer output frame rate")
  }
  guard timeline.tracks.length() == 1 &&
    timeline.tracks[0].kind == "video" &&
    timeline.transitions.is_empty() else {
    fail("EDL export requires exactly one video track and no transitions")
  }
  let track = timeline.tracks[0]
  guard track.mix is None ||
    track.mix == Some({ volume_db: 0.0, pan: 0.0, muted: false, }) else {
    fail("track mix is not representable in a video-only EDL")
  }
  guard !track.clips.is_empty() && track.clips.length() <= 999 else {
    fail("EDL export needs 1–999 clips")
  }
  let clips = track.clips.copy()
  clips.sort_by_key(clip => clip.start_tick)
  let origin = timecode_frames(mapping.record_start_timecode, mapping.fps)
  let lines : Array[String] = ["TITLE: " + title, "FCM: NON-DROP FRAME", ""]
  let mut previous_end = 0
  for index, clip in clips {
    guard clip.settings == @domain.default_clip_settings() &&
      clip.keyframes == @domain.empty_keyframes() &&
      clip.effects.is_empty() &&
      clip.audio_bus_id is None else {
      fail(
        "clip " +
        clip.clip_id +
        " has settings, keyframes, effects or audio routing that CMX3600 cannot preserve",
      )
    }
    let bindings = mapping.bindings.filter(binding => {
      binding.media_ref_id == clip.media_ref_id
    })
    guard bindings.length() == 1 else {
      fail("unmapped clip media: " + clip.media_ref_id)
    }
    let binding = bindings[0]
    let media = media_for(project, binding.media_ref_id)
    guard clip.source_in_tick >= 0 &&
      clip.source_out_tick > clip.source_in_tick &&
      clip.source_out_tick <= media.metadata.duration_ticks &&
      clip.duration_ticks == clip.source_out_tick - clip.source_in_tick else {
      fail("clip " + clip.clip_id + " has an invalid source range or a retime")
    }
    let start = ticks_to_frames(
      clip.start_tick,
      mapping.fps,
      timeline.timebase.ticks_per_second,
    )
    let duration = ticks_to_frames(
      clip.duration_ticks,
      mapping.fps,
      timeline.timebase.ticks_per_second,
    )
    guard start >= previous_end else {
      fail("video clips overlap; EDL export cannot flatten layers")
    }
    let end = checked_int(start.to_int64() + duration.to_int64())
    let source_origin = timecode_frames(
      binding.source_start_timecode,
      mapping.fps,
    )
    let source_in = ticks_to_frames(
        clip.source_in_tick,
        mapping.fps,
        timeline.timebase.ticks_per_second,
      ) +
      source_origin
    let source_out = ticks_to_frames(
        clip.source_out_tick,
        mapping.fps,
        timeline.timebase.ticks_per_second,
      ) +
      source_origin
    lines.push(
      pad(index + 1, 3) +
      "  " +
      binding.reel +
      "  V  C  " +
      frames_timecode(source_in, mapping.fps) +
      " " +
      frames_timecode(source_out, mapping.fps) +
      " " +
      frames_timecode(
        checked_int(start.to_int64() + origin.to_int64()),
        mapping.fps,
      ) +
      " " +
      frames_timecode(
        checked_int(end.to_int64() + origin.to_int64()),
        mapping.fps,
      ),
    )
    previous_end = end
  }
  lines.join("\n") + "\n"
}
