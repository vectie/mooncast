///|
/// One half-open display interval, with one-based input cue references.
pub(all) struct Segment {
  start_ms : Int
  end_ms : Int
  primary_cue : Int?
  secondary_cue : Int?
} derive(Eq, ToJson)

///|
/// Coverage measures time, not translation completeness or correctness.
pub(all) struct Coverage {
  shared_ms : Int
  primary_only_ms : Int
  secondary_only_ms : Int
  uncaptioned_ms : Int
} derive(Eq, ToJson)

///|
pub(all) struct Composition {
  contract : String
  primary_source_file : String
  secondary_source_file : String
  primary_cue_count : Int
  secondary_cue_count : Int
  coverage : Coverage
  segments : Array[Segment]
  draft : @captions.CaptionDraft
} derive(ToJson)

///|
fn validate_track(draft : @captions.CaptionDraft, name : String) -> Unit raise {
  draft.validate()
  let mut previous_end = 0
  for i, cue in draft.cues {
    guard cue.start_ms >= previous_end else {
      fail(
        name +
        " cue " +
        (i + 1).to_string() +
        " overlaps the preceding cue; merge or retime that input before composing",
      )
    }
    previous_end = cue.end_ms
  }
}

///|
/// Stack independently timed captions in primary-then-secondary order.
/// Every input boundary is retained; nothing is extended across a gap.
pub fn compose(
  primary : @captions.CaptionDraft,
  secondary : @captions.CaptionDraft,
) -> Composition raise {
  validate_track(primary, "primary")
  validate_track(secondary, "secondary")
  guard primary.duration_ms == secondary.duration_ms else {
    fail(
      "both drafts must describe the same duration_ms; synchronize and review them first",
    )
  }
  let boundaries = [0, primary.duration_ms]
  for track in [primary, secondary] {
    for cue in track.cues {
      boundaries.push(cue.start_ms)
      boundaries.push(cue.end_ms)
    }
  }
  boundaries.sort()
  let segments : Array[Segment] = []
  let cues : Array[@captions.Caption] = []
  let mut p = 0
  let mut s = 0
  let mut shared = 0
  let mut primary_only = 0
  let mut secondary_only = 0
  let mut uncaptioned = 0
  for i in 0..<(boundaries.length() - 1) {
    let start_ms = boundaries[i]
    let end_ms = boundaries[i + 1]
    if start_ms == end_ms {
      continue
    }
    while p < primary.cues.length() && primary.cues[p].end_ms <= start_ms {
      p += 1
    }
    while s < secondary.cues.length() && secondary.cues[s].end_ms <= start_ms {
      s += 1
    }
    let primary_cue = if p < primary.cues.length() &&
      primary.cues[p].start_ms <= start_ms {
      Some(p + 1)
    } else {
      None
    }
    let secondary_cue = if s < secondary.cues.length() &&
      secondary.cues[s].start_ms <= start_ms {
      Some(s + 1)
    } else {
      None
    }
    let duration = end_ms - start_ms
    let text = match (primary_cue, secondary_cue) {
      (Some(_), Some(_)) => {
        shared += duration
        primary.cues[p].text + "\n" + secondary.cues[s].text
      }
      (Some(_), None) => {
        primary_only += duration
        primary.cues[p].text
      }
      (None, Some(_)) => {
        secondary_only += duration
        secondary.cues[s].text
      }
      (None, None) => {
        uncaptioned += duration
        continue
      }
    }
    guard cues.length() < 5000 else {
      fail(
        "composition exceeds 5000 display intervals; shorten or simplify the input drafts",
      )
    }
    cues.push({ start_ms, end_ms, text, })
    segments.push({ start_ms, end_ms, primary_cue, secondary_cue, })
  }
  let draft : @captions.CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file: "Bilingual composition; see composition.json for both input identities",
    duration_ms: primary.duration_ms,
    cues,
  }
  // The ordinary editor limits, including 2000 characters per combined cue,
  // apply before any output can be used or written.
  draft.validate()
  {
    contract: "mooncast.bilingual-composition.v1",
    primary_source_file: primary.source_file,
    secondary_source_file: secondary.source_file,
    primary_cue_count: primary.cues.length(),
    secondary_cue_count: secondary.cues.length(),
    coverage: {
      shared_ms: shared,
      primary_only_ms: primary_only,
      secondary_only_ms: secondary_only,
      uncaptioned_ms: uncaptioned,
    },
    segments,
    draft,
  }
}
