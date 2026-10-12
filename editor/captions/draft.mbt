///|
/// A plain-text caption in the media's millisecond clock.
pub(all) struct Caption {
  start_ms : Int
  end_ms : Int
  text : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// An editable local document, not a production approval or rights receipt.
pub(all) struct CaptionDraft {
  contract : String
  source_file : String
  duration_ms : Int
  cues : Array[Caption]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Validate without sorting, clipping, discarding or normalizing the user's edits.
pub fn CaptionDraft::validate(self : CaptionDraft) -> Unit raise {
  guard self.contract == "mooncast.caption-draft.v1" else {
    fail("unsupported caption draft contract")
  }
  guard self.duration_ms > 0 && self.duration_ms <= 7200000 else {
    fail("duration_ms must be between 1 and 7200000 (two hours)")
  }
  guard !self.cues.is_empty() && self.cues.length() <= 5000 else {
    fail("a caption draft needs between 1 and 5000 cues")
  }
  let mut previous = -1
  for i, cue in self.cues {
    let label = "cue " + (i + 1).to_string() + ": "
    guard cue.start_ms >= 0 &&
      cue.end_ms > cue.start_ms &&
      cue.end_ms <= self.duration_ms else {
      fail(label + "timing must be positive and inside duration_ms")
    }
    guard cue.start_ms >= previous else {
      fail(label + "cues must remain ordered by start_ms")
    }
    guard !cue.text.is_blank() &&
      cue.text.length() <= 2000 &&
      !cue.text.contains("<") &&
      !cue.text.contains(">") else {
      fail(
        label + "use 1–2000 characters of plain text without angle brackets",
      )
    }
    guard cue.text.split("\n").all(line => !line.is_blank()) else {
      fail(
        label + "blank caption lines are not supported; use a single newline",
      )
    }
    for char in cue.text {
      guard char >= ' ' || char == '\n' else {
        fail(label + "control characters are not supported")
      }
    }
    previous = cue.start_ms
  }
}

///|
/// Import the existing bounded transcript formats at millisecond resolution.
pub fn import_draft(
  bytes : Bytes,
  mime : String,
  source_file : String,
  duration_ms : Int,
) -> CaptionDraft raise {
  guard duration_ms > 0 && duration_ms <= 7200000 else {
    fail("duration_ms must be between 1 and 7200000 (two hours)")
  }
  let parsed = @media.parse_subtitles(bytes, mime, duration_ms, 1000)
  let draft : CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file,
    duration_ms,
    cues: parsed.cues.map(cue => {
      start_ms: cue.start_tick,
      end_ms: cue.end_tick,
      // Decode only the plain WebVTT escape vocabulary, ampersand last.
      text: if mime == "text/vtt" {
        cue.text
        .replace_all(old="&nbsp;", new=" ")
        .replace_all(old="&lrm;", new="\u{200e}")
        .replace_all(old="&rlm;", new="\u{200f}")
        .replace_all(old="&lt;", new="<")
        .replace_all(old="&gt;", new=">")
        .replace_all(old="&amp;", new="&")
      } else {
        cue.text
      },
    }),
  }
  draft.validate()
  draft
}

///|
/// Open a hand-edited draft, including validation of every cue.
pub fn read_draft(text : String) -> CaptionDraft raise {
  let draft : CaptionDraft = @json.from_json(@json.parse(text))
  draft.validate()
  draft
}

///|
fn replace_range(
  draft : CaptionDraft,
  first : Int,
  last : Int,
  replacement : Array[Caption],
) -> CaptionDraft raise {
  draft.validate()
  guard first >= 1 && last >= first && last <= draft.cues.length() else {
    fail("cue numbers are one-based and must be inside the draft")
  }
  let cues : Array[Caption] = []
  cues.append(draft.cues[:first - 1])
  cues.append(replacement)
  cues.append(draft.cues[last:])
  let updated = { ..draft, cues, }
  updated.validate()
  updated
}

///|
/// Correct both text and timing of one numbered cue; input remains unchanged.
pub fn CaptionDraft::set_cue(
  self : CaptionDraft,
  number : Int,
  start_ms : Int,
  end_ms : Int,
  text : String,
) -> CaptionDraft raise {
  replace_range(self, number, number, [{ start_ms, end_ms, text, }])
}

///|
/// Divide one cue at an explicit boundary with separately corrected texts.
pub fn CaptionDraft::split_cue(
  self : CaptionDraft,
  number : Int,
  at_ms : Int,
  first_text : String,
  second_text : String,
) -> CaptionDraft raise {
  self.validate()
  guard number >= 1 && number <= self.cues.length() else {
    fail("split cue number is outside the draft")
  }
  let cue = self.cues[number - 1]
  guard at_ms > cue.start_ms && at_ms < cue.end_ms else {
    fail("split time must be strictly inside the cue")
  }
  let first_half = replace_range(self, number, number, [
    { start_ms: cue.start_ms, end_ms: at_ms, text: first_text, },
  ])
  // Other speakers can begin during the first half. Preserve those cues and
  // insert the second half at its own start time, before equal-start cues.
  let second_half : Caption = {
    start_ms: at_ms,
    end_ms: cue.end_ms,
    text: second_text,
  }
  let cues : Array[Caption] = []
  let mut inserted = false
  for existing in first_half.cues {
    if !inserted && existing.start_ms >= at_ms {
      cues.push(second_half)
      inserted = true
    }
    cues.push(existing)
  }
  if !inserted {
    cues.push(second_half)
  }
  let updated = { ..self, cues, }
  updated.validate()
  updated
}

///|
/// Merge a consecutive range, including intervening gaps, using explicit text.
pub fn CaptionDraft::merge_cues(
  self : CaptionDraft,
  first : Int,
  last : Int,
  text : String,
) -> CaptionDraft raise {
  self.validate()
  guard first >= 1 && last > first && last <= self.cues.length() else {
    fail("merge requires at least two consecutive valid cue numbers")
  }
  let mut end_ms = 0
  for index in (first - 1)..<last {
    end_ms = Int::max(end_ms, self.cues[index].end_ms)
  }
  replace_range(self, first, last, [
    { start_ms: self.cues[first - 1].start_ms, end_ms, text, },
  ])
}
