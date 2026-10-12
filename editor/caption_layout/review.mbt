///|
pub(all) struct CueReview {
  cue : Int
  start_ms : Int
  end_ms : Int
  characters : Int
  line_count : Int
  longest_line : Int
  chars_per_second_milli : Int
  issues : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct Review {
  profile : Profile
  cue_count : Int
  flagged_cues : Int
  cues : Array[CueReview]
} derive(Debug, Eq, ToJson)

///|
/// Mechanical editorial feedback only. Thresholds never approve delivery.
/// Counts Unicode scalars, including spaces, with each newline counted as a
/// space for reading speed. Grapheme/display-cell widths are not measured.
pub fn review(
  draft : @captions.CaptionDraft,
  profile : Profile,
) -> Review raise {
  draft.validate()
  profile.validate()
  let cues : Array[CueReview] = []
  let mut previous_end = -1
  let mut flagged = 0
  for i, cue in draft.cues {
    let lengths = cue.text
      .split("\n")
      .map(line => line.to_owned().char_length())
      .to_array()
    let longest = lengths.fold(init=0, (a, b) => Int::max(a, b))
    let characters = cue.text.replace_all(old="\n", new=" ").char_length()
    let duration = cue.end_ms - cue.start_ms
    let issues : Array[String] = []
    if longest > profile.max_line_chars {
      issues.push("long_line")
    }
    if lengths.length() > profile.max_lines {
      issues.push("too_many_lines")
    }
    if duration < profile.min_duration_ms {
      issues.push("short_duration")
    }
    if characters.to_int64() * 1000L >
      profile.max_chars_per_second.to_int64() * duration.to_int64() {
      issues.push("fast_reading")
    }
    if previous_end > cue.start_ms ||
      (i + 1 < draft.cues.length() && draft.cues[i + 1].start_ms < cue.end_ms) {
      issues.push("overlap")
    }
    previous_end = Int::max(previous_end, cue.end_ms)
    if !issues.is_empty() {
      flagged += 1
    }
    cues.push({
      cue: i + 1,
      start_ms: cue.start_ms,
      end_ms: cue.end_ms,
      characters,
      line_count: lengths.length(),
      longest_line: longest,
      chars_per_second_milli: ((
        characters.to_int64() * 1000000L + duration.to_int64() - 1L
      ) /
      duration.to_int64()).to_int(),
      issues,
    })
  }
  { profile, cue_count: cues.length(), flagged_cues: flagged, cues, }
}

///|
/// Portable TSV with json:-prefixed, JSON-quoted caption text. Newlines/tabs are
/// escaped and the fixed prefix keeps user text from leading spreadsheet cells.
pub fn tsv(draft : @captions.CaptionDraft, profile : Profile) -> String raise {
  let feedback = review(draft, profile)
  "cue\tstart_ms\tend_ms\tcharacters\tlines\tlongest_line\tcps_milli\tissues\ttext_json\n" +
  feedback.cues
  .mapi((i, cue) => {
    [
      cue.cue.to_string(),
      cue.start_ms.to_string(),
      cue.end_ms.to_string(),
      cue.characters.to_string(),
      cue.line_count.to_string(),
      cue.longest_line.to_string(),
      cue.chars_per_second_milli.to_string(),
      cue.issues.join(","),
      "json:" + draft.cues[i].text.to_json().stringify(),
    ].join("\t")
  })
  .join("\n") +
  "\n"
}
