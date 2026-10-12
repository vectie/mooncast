///|
/// Plain-caption import. The original ASS/SSA remains necessary for styling.
pub(all) struct Import {
  draft : @captions.CaptionDraft
  script_type : String
  comment_events : Int
  override_cues : Int
  effect_cues : Int
  reordered : Bool
  source_lines : Array[Int]
} derive(Debug, ToJson)

///|
fn decimal(text : String) -> Int raise {
  guard !text.is_empty() && text.iter().all(c => c >= '0' && c <= '9') else {
    fail("expected an unsigned decimal integer")
  }
  @string.parse_int(text)
}

///|
fn timestamp(text : String) -> Int raise {
  let parts = text
    .trim()
    .to_string()
    .split(":")
    .map(p => p.to_string())
    .to_array()
  guard parts.length() == 3 &&
    parts[0].length() >= 1 &&
    parts[0].length() <= 2 &&
    parts[1].length() == 2 &&
    parts[2].length() == 5 &&
    parts[2][2] == '.' else {
    fail("ASS time must be H:MM:SS.cc (centiseconds)")
  }
  let hours = decimal(parts[0])
  let minutes = decimal(parts[1])
  let seconds = decimal(parts[2][:2].to_string())
  let fraction = decimal(parts[2][3:].to_string())
  guard hours <= 2 && minutes < 60 && seconds < 60 else {
    fail("ASS timestamp is outside the supported two-hour clock")
  }
  ((hours * 60 + minutes) * 60 + seconds) * 1000 + fraction * 10
}

///|
// Split only metadata commas. A comma in the final Text field is literal.
fn event_fields(text : String) -> Array[String] raise {
  let parts = text.split(",").map(p => p.to_string()).to_array()
  guard parts.length() >= 10 else { fail("Dialogue needs ten event fields") }
  let result = parts[:9].map(p => p.trim().to_string())
  result.push(parts[9:].join(","))
  result
}

///|
/// Read a UTF-8 ASS v4.00+ or SSA v4.00 file into a plain editable draft.
/// Times are exact centiseconds, reordered stably by start when necessary.
/// Style, layers, placement, karaoke and comments are not caption semantics.
pub fn import_plain(
  bytes : Bytes,
  source_file : String,
  duration_ms : Int,
) -> Import raise {
  guard bytes.length() > 0 && bytes.length() <= 2097152 else {
    fail("ASS/SSA input must be 1 byte to 2 MiB")
  }
  let text = @utf8.decode(bytes).replace_all(old="\r\n", new="\n")
  guard !text.contains("\r") && !text.contains("\u{0000}") else {
    fail("bare carriage return or NUL in ASS/SSA file")
  }
  let mut section = ""
  let mut script_type = ""
  let mut wrap_style = 0
  let mut seen_events = false
  let mut columns : Array[String] = []
  let mut comment_events = 0
  let mut override_cues = 0
  let mut effect_cues = 0
  let entries : Array[(Int, @captions.Caption)] = []
  for i, raw in text.split("\n").to_array() {
    let raw = if i == 0 && raw.has_prefix("\u{feff}") { raw[1:] } else { raw }
    let line = raw.trim().to_string()
    if line.is_empty() || line.has_prefix(";") {
      continue
    }
    if line.has_prefix("[") {
      guard line.has_suffix("]") else { fail("malformed ASS section header") }
      section = line.to_lower()
      guard section == "[script info]" ||
        section == "[v4+ styles]" ||
        section == "[v4 styles]" ||
        section == "[events]" ||
        section == "[aegisub project garbage]" else {
        fail("unsupported ASS section (attachments are not imported): " + line)
      }
      if section == "[events]" {
        guard !seen_events && !script_type.is_empty() else {
          fail("exactly one Events section must follow ScriptType")
        }
        seen_events = true
      }
      continue
    }
    let split = raw.split(":").map(p => p.to_string()).to_array()
    guard split.length() >= 2 else { fail("expected an ASS key: value line") }
    let directive = split[0].trim().to_string().to_lower()
    // ASS uses one separator space after the colon. Retain text field spaces.
    let value = split[1:].join(":")
    if section == "[script info]" {
      if directive == "scripttype" {
        guard script_type.is_empty() && !seen_events else {
          fail("duplicate or late ScriptType")
        }
        script_type = value.trim().to_string().to_lower()
        guard script_type == "v4.00+" || script_type == "v4.00" else {
          fail("supported ScriptType values are v4.00+ and v4.00")
        }
      } else if directive == "timer" {
        guard @string.parse_double(value.trim()) == 100.0 else {
          fail(
            "non-100 ASS/SSA Timer scaling is unsupported; retime the source first",
          )
        }
      } else if directive == "wrapstyle" {
        guard !seen_events else { fail("WrapStyle must precede Events") }
        wrap_style = decimal(value.trim().to_string())
        guard wrap_style <= 3 else { fail("WrapStyle must be 0, 1, 2 or 3") }
      }
      continue
    }
    if section != "[events]" {
      guard !section.is_empty() else {
        fail("ASS content must start in a section")
      }
      continue
    }
    if directive == "format" {
      guard columns.is_empty() else {
        fail("only one Events Format is supported")
      }
      columns = value
        .split(",")
        .map(p => p.trim().to_string().to_lower())
        .to_array()
      let first = if script_type == "v4.00+" { "layer" } else { "marked" }
      let required = [
        first, "start", "end", "style", "name", "marginl", "marginr", "marginv",
        "effect", "text",
      ]
      guard columns.length() == 10 &&
        columns[9] == "text" &&
        required.all(name => columns.filter(c => c == name).length() == 1) else {
        fail("Events Format needs the ten standard fields with Text last")
      }
      continue
    }
    if directive == "comment" {
      comment_events += 1
      continue
    }
    guard directive == "dialogue" && columns.length() == 10 else {
      fail("Events supports only Format, Dialogue and Comment")
    }
    guard entries.length() < 5000 else {
      fail("ASS import supports at most 5000 Dialogue events")
    }
    let fields = event_fields(value)
    let values : Map[String, String] = Map([])
    for index, name in columns {
      values[name] = fields[index]
    }
    let (plain, overridden) = plain_text(values["text"], wrap_style)
    if overridden {
      override_cues += 1
    }
    if !values["effect"].is_empty() {
      effect_cues += 1
    }
    let cue : @captions.Caption = {
      start_ms: timestamp(values["start"]),
      end_ms: timestamp(values["end"]),
      text: plain,
    }
    // Per-cue validation retains the source line in a useful error message.
    let single : @captions.CaptionDraft = {
      contract: "mooncast.caption-draft.v1",
      source_file,
      duration_ms,
      cues: [cue],
    }
    single.validate() catch {
      error =>
        fail("ASS line " + (i + 1).to_string() + ": " + error.to_string())
    }
    entries.push((i + 1, cue))
  }
  guard seen_events && !columns.is_empty() && !entries.is_empty() else {
    fail("ASS/SSA needs ScriptType, Events Format and at least one Dialogue")
  }
  let original = entries.map(entry => entry.0)
  entries.sort_by((a, b) => {
    let order = a.1.start_ms.compare(b.1.start_ms)
    if order == 0 {
      a.0.compare(b.0)
    } else {
      order
    }
  })
  let source_lines = entries.map(entry => entry.0)
  let draft : @captions.CaptionDraft = {
    contract: "mooncast.caption-draft.v1",
    source_file,
    duration_ms,
    cues: entries.map(entry => entry.1),
  }
  draft.validate()
  {
    draft,
    script_type,
    comment_events,
    override_cues,
    effect_cues,
    reordered: original != source_lines,
    source_lines,
  }
}
