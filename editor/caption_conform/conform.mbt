///|
/// Carry source captions through a single nonoverlapping video cut. Intersections
/// are computed in an exact integer clock before rounding starts up and ends down
/// to milliseconds, so captions cannot leak into gaps or another shot. Cue text
/// is kept intact even when its time range is clipped; the editor reviews words.
pub fn conform(
  project : @domain.EditorProject,
  sources : Array[SourceCaptions],
) -> ConformedCaptions raise {
  let timeline = project.timeline
  guard project.contract == "mooncast.editor-project.v1" &&
    timeline.contract == "mooncast.editor-timeline.v1" else {
    fail("expected a native editor project snapshot")
  }
  guard timeline.tracks.length() == 1 &&
    timeline.tracks[0].kind == "video" &&
    timeline.transitions.is_empty() else {
    fail("caption conform requires one video track with no transitions")
  }
  let tps = timeline.timebase.ticks_per_second.to_int64()
  guard tps > 0L else { fail("timeline ticks_per_second must be positive") }
  let clips = timeline.tracks[0].clips.copy()
  guard !clips.is_empty() && clips.length() <= 999 else {
    fail("caption conform needs 1–999 video clips")
  }
  clips.sort_by_key(clip => clip.start_tick)
  let bindings : Map[String, SourceCaptions] = Map([])
  let silent : Array[String] = []
  guard !sources.is_empty() && sources.length() <= 64 else {
    fail("caption conform needs 1–64 source bindings")
  }
  for source in sources {
    guard !bindings.contains(source.media_ref_id) &&
      clips.any(c => c.media_ref_id == source.media_ref_id) else {
      fail("duplicate or unused caption binding: " + source.media_ref_id)
    }
    let duration = media_duration_ms(project, source.media_ref_id)
    if source.draft is Some(draft) {
      draft.validate()
      guard draft.cues.all(cue => cue.end_ms <= duration) else {
        fail("source captions extend beyond media: " + source.media_ref_id)
      }
    } else {
      silent.push(source.media_ref_id)
    }
    bindings[source.media_ref_id] = source
  }
  let cues : Array[@captions.Caption] = []
  let origins : Array[CueOrigin] = []
  let ids : Map[String, Bool] = Map([])
  let mut previous_end = 0L
  for clip in clips {
    guard !clip.clip_id.is_blank() && !ids.contains(clip.clip_id) else {
      fail("clip IDs must be nonempty and unique")
    }
    ids[clip.clip_id] = true
    let start = clip.start_tick.to_int64()
    let end = start + clip.duration_ticks.to_int64()
    guard start >= previous_end &&
      clip.duration_ticks > 0 &&
      end * 1000L <= 7200000L * tps else {
      fail(
        "clips must not overlap and must fit a two-hour timeline: " +
        clip.clip_id,
      )
    }
    guard clip.source_in_tick >= 0 &&
      clip.source_out_tick > clip.source_in_tick &&
      clip.duration_ticks == clip.source_out_tick - clip.source_in_tick &&
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
      fail(
        "missing caption binding; supply a transcript or explicit silence: " +
        clip.media_ref_id,
      )
    }
    // media_duration_ms already established an unambiguous media reference.
    let media = project.media_refs.filter(m => {
        m.media_ref_id == clip.media_ref_id
      })[0]
    guard clip.source_out_tick <= media.metadata.duration_ticks else {
      fail("clip exceeds source media duration: " + clip.clip_id)
    }
    previous_end = end
    if source.draft is Some(draft) {
      let source_in = clip.source_in_tick.to_int64() * 1000L
      let source_out = clip.source_out_tick.to_int64() * 1000L
      for index, cue in draft.cues {
        let cue_in = cue.start_ms.to_int64() * tps
        let cue_out = cue.end_ms.to_int64() * tps
        let kept_in = Int64::max(source_in, cue_in)
        let kept_out = Int64::min(source_out, cue_out)
        if kept_in >= kept_out {
          continue
        }
        let record_in = start * 1000L + kept_in - source_in
        let record_out = start * 1000L + kept_out - source_in
        let start_ms = ((record_in + tps - 1L) / tps).to_int()
        let end_ms = (record_out / tps).to_int()
        guard end_ms > start_ms else {
          fail(
            "caption intersection is shorter than a representable millisecond: " +
            clip.clip_id +
            " cue " +
            (index + 1).to_string(),
          )
        }
        guard cues.length() < 5000 else {
          fail("conformed cut exceeds 5000 cues")
        }
        cues.push({ start_ms, end_ms, text: cue.text, })
        origins.push({
          output_cue: cues.length(),
          clip_id: clip.clip_id,
          media_ref_id: clip.media_ref_id,
          source_file: draft.source_file,
          source_cue: index + 1,
          source_start_ms: cue.start_ms,
          source_end_ms: cue.end_ms,
          clipped_at_cut: kept_in != cue_in || kept_out != cue_out,
          rounded_inward: record_in % tps != 0L || record_out % tps != 0L,
        })
      }
    }
  }
  guard !cues.is_empty() else {
    fail("no captions intersect this cut; no caption draft can be exported")
  }
  let draft : @captions.CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file: "timeline:" + timeline.timeline_id,
    duration_ms: ((previous_end * 1000L + tps - 1L) / tps).to_int(),
    cues,
  }
  draft.validate()
  {
    contract: "mooncast.caption-conform.v1",
    project_id: project.project_id,
    project_revision: project.revision,
    timeline_id: timeline.timeline_id,
    timeline_revision: timeline.revision,
    ticks_per_second: timeline.timebase.ticks_per_second,
    silent_media_ref_ids: silent,
    draft,
    origins,
  }
}
