///|
/// A stable link to the one-based cue number in the input draft.
pub(all) struct CueOrigin {
  output_cue : Int
  source_cue : Int
  page : Int
  page_count : Int
  estimated_timing : Bool
} derive(Debug, Eq, ToJson)

///|
pub(all) struct Layout {
  draft : @captions.CaptionDraft
  origins : Array[CueOrigin]
} derive(Debug, Eq, ToJson)

///|
priv struct Page {
  cue : @captions.Caption
  source_cue : Int
  page : Int
  page_count : Int
}

///|
/// Greedy, Unicode-scalar-count wrapping at ASCII spaces and existing newlines.
/// Normalize those separators only. Never split a word or alter punctuation.
fn wrap(text : String, width : Int, cue_number : Int) -> Array[String] raise {
  let words = text
    .replace_all(old="\n", new=" ")
    .split(" ")
    .filter(word => !word.is_empty())
    .map(word => word.to_owned())
    .to_array()
  let lines : Array[String] = []
  let mut line = ""
  let mut length = 0
  for word in words {
    let size = word.char_length()
    guard size <= width else {
      fail(
        "cue " +
        cue_number.to_string() +
        ": an unbreakable word exceeds max_line_chars; edit it or choose a wider profile",
      )
    }
    if length > 0 && length + 1 + size > width {
      lines.push(line)
      line = word
      length = size
    } else if length == 0 {
      line = word
      length = size
    } else {
      line += " " + word
      length += 1 + size
    }
  }
  if length > 0 {
    lines.push(line)
  }
  guard !lines.is_empty() else { fail("caption has no wrappable words") }
  lines
}

///|
/// Rewrap into a new draft, preserving every cue's exact timing and order.
/// max_lines is advisory in this mode; use paginate to create smaller screens.
pub fn reflow(
  draft : @captions.CaptionDraft,
  profile : Profile,
) -> Layout raise {
  draft.validate()
  profile.validate()
  let cues = draft.cues.mapi((i, cue) => {
    ..cue,
    text: wrap(cue.text, profile.max_line_chars, i + 1).join("\n"),
  })
  let result = { ..draft, cues, }
  result.validate()
  {
    draft: result,
    origins: cues.mapi((i, _) => {
      output_cue: i + 1,
      source_cue: i + 1,
      page: 1,
      page_count: 1,
      estimated_timing: false,
    }),
  }
}

///|
/// Explicitly split each wrapped cue into pages of at most max_lines lines.
/// Allocate its original interval by each page's Unicode-scalar text length,
/// counting linebreaks as spaces. Cumulative divisions floor to milliseconds;
/// the final page ends exactly at the original end. This is not word alignment.
/// Reject the entire transformation if any page is below min_duration_ms.
pub fn paginate(
  draft : @captions.CaptionDraft,
  profile : Profile,
) -> Layout raise {
  draft.validate()
  profile.validate()
  let pages : Array[Page] = []
  for i, source in draft.cues {
    let lines = wrap(source.text, profile.max_line_chars, i + 1)
    let texts : Array[String] = []
    for start = 0; start < lines.length(); start = start + profile.max_lines {
      texts.push(
        lines[start:Int::min(start + profile.max_lines, lines.length())]
        .to_array()
        .join("\n"),
      )
    }
    guard pages.length() + texts.length() <= 5000 else {
      fail("pagination exceeds the draft limit of 5000 cues")
    }
    let weights = texts.map(text => {
      text.replace_all(old="\n", new=" ").char_length()
    })
    let total = weights.fold(init=0, (sum, weight) => sum + weight)
    let duration = (source.end_ms - source.start_ms).to_int64()
    let mut accumulated = 0
    let mut start = source.start_ms
    for j, text in texts {
      accumulated += weights[j]
      let end = source.start_ms +
        (duration * accumulated.to_int64() / total.to_int64()).to_int()
      guard end - start >= profile.min_duration_ms else {
        fail(
          "cue " +
          (i + 1).to_string() +
          ", page " +
          (j + 1).to_string() +
          ": allocated duration is below min_duration_ms; use reflow, edit timing, or explicitly lower the profile minimum",
        )
      }
      pages.push({
        cue: { start_ms: start, end_ms: end, text, },
        source_cue: i + 1,
        page: j + 1,
        page_count: texts.length(),
      })
      start = end
    }
  }
  // A long cue may overlap another speaker. Keep every page in start order,
  // including deterministic tie-breaking by original cue and page number.
  pages.sort_by((a, b) => {
    let time = a.cue.start_ms - b.cue.start_ms
    if time != 0 {
      time
    } else {
      let source = a.source_cue - b.source_cue
      if source != 0 {
        source
      } else {
        a.page - b.page
      }
    }
  })
  let result = { ..draft, cues: pages.map(page => page.cue), }
  result.validate()
  {
    draft: result,
    origins: pages.mapi((i, page) => {
      output_cue: i + 1,
      source_cue: page.source_cue,
      page: page.page,
      page_count: page.page_count,
      estimated_timing: page.page_count > 1,
    }),
  }
}
