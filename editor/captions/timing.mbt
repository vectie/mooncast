///|
/// Move all cues equally. No cue is clipped or dropped if a boundary is exceeded.
pub fn CaptionDraft::shift(
  self : CaptionDraft,
  delta_ms : Int,
) -> CaptionDraft raise {
  self.validate()
  guard delta_ms >= -7200000 && delta_ms <= 7200000 else {
    fail("caption offset must be within two hours")
  }
  let updated = {
    ..self,
    cues: self.cues.map(cue => {
      ..cue,
      start_ms: cue.start_ms + delta_ms,
      end_ms: cue.end_ms + delta_ms,
    }),
  }
  updated.validate()
  updated
}

///|
/// Fit a linear clock from two observed synchronization points. Both anchors
/// and all resulting cues must fit the media duration. Milliseconds round to
/// nearest, with exact half milliseconds rounded upward. Gaps and overlaps
/// retain the same linear mapping. This does not detect spoken words.
pub fn CaptionDraft::sync(
  self : CaptionDraft,
  source_first_ms : Int,
  target_first_ms : Int,
  source_last_ms : Int,
  target_last_ms : Int,
) -> CaptionDraft raise {
  self.validate()
  guard source_first_ms >= 0 &&
    source_last_ms > source_first_ms &&
    source_last_ms <= self.duration_ms &&
    target_first_ms >= 0 &&
    target_last_ms > target_first_ms &&
    target_last_ms <= self.duration_ms else {
    fail(
      "sync needs two increasing source and target points inside duration_ms",
    )
  }
  let source_span = (source_last_ms - source_first_ms).to_int64()
  let target_span = (target_last_ms - target_first_ms).to_int64()
  fn map_time(value : Int) -> Int raise {
    let numerator = target_first_ms.to_int64() * source_span +
      (value - source_first_ms).to_int64() * target_span
    guard numerator >= 0L &&
      numerator <= self.duration_ms.to_int64() * source_span else {
      fail("synchronized cue falls outside duration_ms; no cues were clipped")
    }
    ((numerator + source_span / 2L) / source_span).to_int()
  }
  let cues : Array[Caption] = []
  for cue in self.cues {
    cues.push({
      ..cue,
      start_ms: map_time(cue.start_ms),
      end_ms: map_time(cue.end_ms),
    })
  }
  let updated = { ..self, cues, }
  updated.validate()
  updated
}
