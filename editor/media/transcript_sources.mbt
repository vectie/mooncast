///|
// Whisper JSON uses seconds; Whisper's headered TSV uses integer milliseconds.
// Audacity's headerless label table uses seconds. The header selects the unit,
// never the magnitude, so a 1000-second label cannot become a one-second cue.
fn transcript_cue(
  number : Int,
  start_ms : Double,
  end_ms : Double,
  text : String,
  duration_ticks : Int,
  ticks_per_second : Int,
) -> @domain.SubtitleCue raise {
  guard duration_ticks > 0 && ticks_per_second > 0 else {
    fail("transcript timeline bounds are invalid")
  }
  let ceiling = duration_ticks.to_double() *
    1000.0 /
    ticks_per_second.to_double()
  guard start_ms >= 0.0 && end_ms > start_ms && end_ms <= ceiling else {
    fail(
      "transcript cue " + number.to_string() + " is outside the media duration",
    )
  }
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .filter(line => !line.is_blank())
    .map(line => line.trim().to_owned())
    .collect()
    .join("\n")
  guard !normalized.is_blank() &&
    normalized.length() <= 2000 &&
    !normalized.contains("<") &&
    !normalized.contains(">") &&
    !normalized.contains("\u{0000}") else {
    fail(
      "transcript cue " +
      number.to_string() +
      " requires plain, nonempty caption text",
    )
  }
  let start_wide = start_ms * ticks_per_second.to_double() / 1000.0 + 0.5
  let end_wide = end_ms * ticks_per_second.to_double() / 1000.0 + 0.5
  guard start_wide < 2147483648.0 && end_wide < 2147483648.0 else {
    fail("transcript timing exceeds the supported timeline")
  }
  let start_tick = start_wide.to_int()
  let end_tick = end_wide.to_int()
  guard end_tick > start_tick && end_tick <= duration_ticks else {
    fail("transcript cue is shorter than one timeline tick")
  }
  {
    cue_id: "cue-" + number.to_string(),
    start_tick,
    end_tick,
    text: normalized,
  }
}

///|
fn transcript_result(
  cues : Array[@domain.SubtitleCue],
  parser_version : String,
) -> SubtitleParseResult raise {
  guard !cues.is_empty() && cues.length() <= 5000 else {
    fail("transcript cue count must be between 1 and 5000")
  }
  for index in 1..<cues.length() {
    guard cues[index].start_tick >= cues[index - 1].start_tick else {
      fail("transcript cues must be ordered by start time")
    }
  }
  {
    parser_version,
    cues,
    cue_digest: "sha256:" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(cues.to_json().stringify())),
    ),
  }
}

///|
fn parse_whisper_json(
  text : String,
  duration_ticks : Int,
  ticks_per_second : Int,
) -> SubtitleParseResult raise {
  let value = @json.parse(text)
  guard value is { "segments": Array(segments), .. } else {
    fail("Whisper JSON must contain a segments array with start, end and text")
  }
  guard segments.length() <= 5000 else { fail("transcript exceeds 5000 cues") }
  let cues : Array[@domain.SubtitleCue] = []
  for index, segment in segments {
    guard segment
      is {
        "start": Number(start),
        "end": Number(end),
        "text": String(caption),
        ..
      } else {
      fail(
        "Whisper segment " +
        (index + 1).to_string() +
        " requires numeric start/end and text",
      )
    }
    cues.push(
      transcript_cue(
        index + 1,
        start * 1000.0,
        end * 1000.0,
        caption,
        duration_ticks,
        ticks_per_second,
      ),
    )
  }
  transcript_result(cues, "mooncast-whisper-json-parser@1.0.0")
}

///|
fn parse_transcript_table(
  text : String,
  duration_ticks : Int,
  ticks_per_second : Int,
) -> SubtitleParseResult raise {
  let lines = text.split("\n").filter(line => !line.is_blank()).collect()
  guard !lines.is_empty() else { fail("transcript table is empty") }
  let whisper = lines[0].trim() == "start\tend\ttext"
  let cues : Array[@domain.SubtitleCue] = []
  for index, line in lines {
    if index == 0 && whisper {
      continue
    }
    guard line.split_once("\t") is Some((start, rest)) &&
      rest.split_once("\t") is Some((end, caption)) else {
      fail(
        "transcript row " +
        (index + 1).to_string() +
        " requires start, end and text separated by tabs",
      )
    }
    let start_ms = if whisper {
      @string.parse_int64(start.trim()).to_double()
    } else {
      @string.parse_double(start.trim()) * 1000.0
    }
    let end_ms = if whisper {
      @string.parse_int64(end.trim()).to_double()
    } else {
      @string.parse_double(end.trim()) * 1000.0
    }
    guard cues.length() < 5000 else { fail("transcript exceeds 5000 cues") }
    cues.push(
      transcript_cue(
        cues.length() + 1,
        start_ms,
        end_ms,
        caption.to_owned(),
        duration_ticks,
        ticks_per_second,
      ),
    )
  }
  transcript_result(
    cues,
    if whisper {
      "mooncast-whisper-tsv-parser@1.0.0"
    } else {
      "mooncast-audacity-label-parser@1.0.0"
    },
  )
}
