///|
pub(all) struct SidecarCue {
  start_tick : Int
  end_tick : Int
  text : String
  source_clip_id : String
  evidence_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SubtitleSidecar {
  contract : String
  project_id : String
  timeline_id : String
  plan_digest : String
  format : String
  content : String
  cue_count : Int
  digest : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn pad_left(value : Int, width : Int) -> String {
  let mut output = value.to_string()
  while output.length() < width {
    output = "0" + output
  }
  output
}

///|
fn srt_time(milliseconds : Int) -> String {
  let hours = milliseconds / 3600000
  let after_hours = milliseconds % 3600000
  let minutes = after_hours / 60000
  let after_minutes = after_hours % 60000
  let seconds = after_minutes / 1000
  let millis = after_minutes % 1000
  pad_left(hours, 2) +
  ":" +
  pad_left(minutes, 2) +
  ":" +
  pad_left(seconds, 2) +
  "," +
  pad_left(millis, 3)
}

///|
/// Produces the deterministic sidecar from rights-attested local subtitle cues.
pub fn subtitle_sidecar(plan : @plan.RenderPlan) -> SubtitleSidecar {
  let cues : Array[SidecarCue] = []
  let range_end = plan.range.start_tick + plan.range.duration_ticks
  for track in plan.tracks {
    for clip in track.clips {
      if clip.local_media is Some(binding) && binding.role == "subtitle" {
        for cue in binding.cues {
          let source_start = Int::max(cue.start_tick, clip.source_in_tick)
          let source_end = Int::min(cue.end_tick, clip.source_out_tick)
          let timeline_start = clip.start_tick +
            source_start -
            clip.source_in_tick
          let timeline_end = clip.start_tick + source_end - clip.source_in_tick
          let start = Int::max(plan.range.start_tick, timeline_start)
          let end_tick = Int::min(range_end, timeline_end)
          if end_tick > start {
            cues.push({
              start_tick: start - plan.range.start_tick,
              end_tick: end_tick - plan.range.start_tick,
              text: cue.text,
              source_clip_id: clip.clip_id,
              evidence_digest: binding.cue_digest +
              ":" +
              binding.intake_receipt_digest,
            })
          }
        }
      }
    }
  }
  cues.sort_by((left, right) => {
    let by_start = left.start_tick.compare(right.start_tick)
    if by_start != 0 {
      by_start
    } else {
      left.text.compare(right.text)
    }
  })
  let lines : Array[String] = []
  for index, cue in cues {
    let start_ms = cue.start_tick * 1000 / plan.timebase.ticks_per_second
    let end_ms = cue.end_tick * 1000 / plan.timebase.ticks_per_second
    lines.append([
      (index + 1).to_string(),
      srt_time(start_ms) + " --> " + srt_time(end_ms),
      cue.text,
      "",
    ])
  }
  let content = lines.join("\n")
  {
    contract: "mooncast.editor-subtitle-sidecar.v1",
    project_id: plan.project_id,
    timeline_id: plan.timeline_id,
    plan_digest: plan.plan_digest,
    format: "srt",
    content,
    cue_count: cues.length(),
    digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(content))),
    publication_authority: false,
  }
}
