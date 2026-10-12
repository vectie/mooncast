///|
/// Carry source chapter intervals through reordered/repeated, contiguous cuts.
/// Exact source/project clock conversion is required at each surviving boundary.
/// Marker-only drafts cannot represent internal unchaptered gaps, so those cuts
/// are refused instead of silently extending another chapter's title into them.
pub fn conform(
  project : @domain.EditorProject,
  sources : Array[SourceChapters],
) -> ConformedChapters raise {
  let timeline = project.timeline
  guard project.contract == "mooncast.editor-project.v1" &&
    timeline.contract == "mooncast.editor-timeline.v1" &&
    timeline.tracks.length() == 1 &&
    timeline.tracks[0].kind == "video" &&
    timeline.transitions.is_empty() else {
    fail(
      "chapter conform requires a native project with one video track and no transitions",
    )
  }
  let tps = timeline.timebase.ticks_per_second.to_int64()
  guard tps > 0L else { fail("timeline clock must be positive") }
  let clips = timeline.tracks[0].clips.copy()
  guard !clips.is_empty() && clips.length() <= 999 else {
    fail("chapter conform needs 1–999 clips")
  }
  clips.sort_by_key(clip => clip.start_tick)
  guard !sources.is_empty() && sources.length() <= 64 else {
    fail("chapter conform needs 1–64 source bindings")
  }
  let bindings : Map[String, SourceChapters] = {}
  for source in sources {
    guard !source.media_ref_id.is_blank() &&
      !bindings.contains(source.media_ref_id) &&
      clips.any(c => c.media_ref_id == source.media_ref_id) else {
      fail("duplicate, blank or unused chapter binding: " + source.media_ref_id)
    }
    source.draft.validate()
    let media = project.media_refs.filter(m => {
      m.media_ref_id == source.media_ref_id
    })
    guard media.length() == 1 &&
      media[0].metadata.mime_type.has_prefix("video/") &&
      media[0].metadata.duration_ticks > 0 else {
      fail(
        "expected one video reference with known duration: " +
        source.media_ref_id,
      )
    }
    let duration = media[0].metadata.duration_ticks.to_int64()
    guard duration <= 7200L * tps &&
      source.draft.duration_ticks.to_int64() * tps ==
      duration * source.draft.ticks_per_second.to_int64() else {
      fail(
        "source chapter duration must match media exactly and fit two hours: " +
        source.media_ref_id,
      )
    }
    bindings[source.media_ref_id] = source
  }
  let markers : Array[@chapters.Marker] = []
  let origins : Array[ChapterOrigin] = []
  let ids : Map[String, Bool] = {}
  let mut previous_end = 0L
  for clip in clips {
    guard !clip.clip_id.is_blank() && !ids.contains(clip.clip_id) else {
      fail("clip IDs must be nonblank and unique")
    }
    ids[clip.clip_id] = true
    let start = clip.start_tick.to_int64()
    let end = start + clip.duration_ticks.to_int64()
    guard start == previous_end &&
      clip.duration_ticks > 0 &&
      end <= 2147483647L &&
      end <= 7200L * tps else {
      fail(
        "chapter conform requires contiguous clips from zero within two hours and signed tick range",
      )
    }
    guard clip.source_in_tick >= 0 &&
      clip.source_out_tick > clip.source_in_tick &&
      clip.source_out_tick.to_int64() - clip.source_in_tick.to_int64() ==
      clip.duration_ticks.to_int64() &&
      !clip.effects.any(effect => {
        effect.enabled &&
        (
          effect.kind == "speed-ramp" ||
          !effect.parameters.speed_points.is_empty()
        )
      }) else {
      fail("source ranges must play at normal speed: " + clip.clip_id)
    }
    guard bindings.get(clip.media_ref_id) is Some(source) else {
      fail("missing source chapter binding: " + clip.media_ref_id)
    }
    let draft = source.draft
    let source_tps = draft.ticks_per_second.to_int64()
    let source_in = clip.source_in_tick.to_int64() * source_tps
    let source_out = clip.source_out_tick.to_int64() * source_tps
    guard source_out <= draft.duration_ticks.to_int64() * tps else {
      fail("clip exceeds source chapter/media duration: " + clip.clip_id)
    }
    guard source_in >= draft.markers[0].start_tick.to_int64() * tps else {
      fail(
        "selected source interval starts before its first chapter: " +
        clip.clip_id,
      )
    }
    for index, marker in draft.markers {
      let source_end = if index + 1 < draft.markers.length() {
        draft.markers[index + 1].start_tick
      } else {
        draft.duration_ticks
      }
      let chapter_in = marker.start_tick.to_int64() * tps
      let chapter_out = source_end.to_int64() * tps
      let kept_in = Int64::max(source_in, chapter_in)
      let kept_out = Int64::min(source_out, chapter_out)
      if kept_in >= kept_out {
        continue
      }
      guard kept_in % source_tps == 0L && kept_out % source_tps == 0L else {
        fail(
          "surviving chapter boundary is not exact in the timeline clock: " +
          marker.marker_id,
        )
      }
      guard markers.length() < 1000 else {
        fail("conformed cut exceeds 1000 chapter markers")
      }
      let output_start = start +
        kept_in / source_tps -
        clip.source_in_tick.to_int64()
      let output_end = start +
        kept_out / source_tps -
        clip.source_in_tick.to_int64()
      let marker_id = "conformed." + (markers.length() + 1).to_string()
      markers.push({
        marker_id,
        start_tick: output_start.to_int(),
        title: marker.title,
      })
      origins.push({
        output_marker_id: marker_id,
        clip_id: clip.clip_id,
        media_ref_id: clip.media_ref_id,
        source_marker_id: marker.marker_id,
        source_start_tick: marker.start_tick,
        source_end_tick: source_end,
        source_ticks_per_second: draft.ticks_per_second,
        output_start_tick: output_start.to_int(),
        output_end_tick: output_end.to_int(),
        clipped_at_start: kept_in != chapter_in,
        clipped_at_end: kept_out != chapter_out,
      })
    }
    previous_end = end
  }
  let draft : @chapters.Draft = {
    contract: "mooncast.chapter-draft.v1",
    project_id: project.project_id,
    project_revision: project.revision,
    timeline_id: timeline.timeline_id,
    timeline_revision: timeline.revision,
    ticks_per_second: timeline.timebase.ticks_per_second,
    duration_ticks: previous_end.to_int(),
    markers,
  }
  draft.validate()
  let uses : Array[ChapterUse] = []
  for source in sources {
    for marker in source.draft.markers {
      uses.push({
        media_ref_id: source.media_ref_id,
        source_marker_id: marker.marker_id,
        output_marker_ids: origins
        .filter(o => {
          o.media_ref_id == source.media_ref_id &&
          o.source_marker_id == marker.marker_id
        })
        .map(o => o.output_marker_id),
      })
    }
  }
  {
    contract: "mooncast.chapter-conform.v1",
    draft,
    origins,
    source_uses: uses,
  }
}
