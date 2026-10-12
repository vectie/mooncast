///|
fn metadata_number(text : String) -> Int64 raise {
  guard !text.is_empty() && text.iter().all(c => c >= '0' && c <= '9') else {
    fail("chapter timing must be an unsigned decimal integer")
  }
  @string.parse_int64(text)
}

///|
fn gcd(a : Int64, b : Int64) -> Int64 {
  for a = a, b = b; b != 0L; {
    continue b, a % b
  } nobreak {
    a
  }
}

///|
fn metadata_tick(value : String, timebase : String, clock : Int) -> Int raise {
  let parts = timebase.split("/").to_array()
  guard parts.length() == 2 else { fail("expected rational chapter TIMEBASE") }
  let factors = [
    metadata_number(value),
    metadata_number(parts[0].to_string()),
    clock.to_int64(),
  ]
  let mut denominator = metadata_number(parts[1].to_string())
  guard factors[1] > 0L && denominator > 0L else {
    fail("TIMEBASE must be positive")
  }
  for i in 0..<factors.length() {
    let divisor = gcd(factors[i], denominator)
    factors[i] = factors[i] / divisor
    denominator = denominator / divisor
  }
  guard denominator == 1L else {
    fail("chapter boundary does not land on an exact timeline tick")
  }
  let mut result = 1L
  for factor in factors {
    guard factor == 0L || result <= 2147483647L / factor else {
      fail("chapter tick exceeds timeline range")
    }
    result = result * factor
  }
  result.to_int()
}

///|
fn metadata_unescape(text : String) -> String raise {
  let out = StringBuilder::new()
  let mut escaped = false
  for c in text {
    if escaped {
      guard c == '\\' || c == '=' || c == ';' || c == '#' else {
        fail("unsupported FFmetadata escape")
      }
      out.write_char(c)
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else {
      guard c != ';' && c != '#' && c != '=' else {
        fail("FFmetadata special characters must be escaped")
      }
      out.write_char(c)
    }
  }
  guard !escaped else { fail("multiline FFmetadata values are not supported") }
  out.to_string()
}

///|
/// Replace chapter markers from a bounded FFmetadata sidecar. The caller
/// explicitly selects the draft whose identity, clock and duration apply.
/// Only exactly representable contiguous chapters ending at duration survive.
pub fn Draft::import_ffmetadata(self : Draft, text : String) -> Draft raise {
  self.validate()
  guard text.length() <= 2097152 else {
    fail("chapter metadata exceeds 2 MiB text limit")
  }
  let lines = text.split("\n").to_array()
  guard lines.length() > 0 &&
    lines[0].to_string().trim_end(chars="\r") == ";FFMETADATA1" else {
    fail("expected ;FFMETADATA1 header")
  }
  let sections : Array[Map[String, String]] = []
  for i in 1..<lines.length() {
    let line = lines[i].to_string().trim_end(chars="\r").to_string()
    if line.trim().is_empty() || line.has_prefix(";") || line.has_prefix("#") {
      continue
    }
    if line == "[CHAPTER]" {
      guard sections.length() < 1000 else {
        fail("at most 1000 chapters are supported")
      }
      sections.push({})
      continue
    }
    guard !line.has_prefix("[") else {
      fail("only CHAPTER sections are supported")
    }
    let parts = line.split("=").to_array()
    guard parts.length() >= 2 else { fail("expected FFmetadata key=value") }
    let key = parts[0].to_string()
    let value = parts[1:].map(p => p.to_string()).join("=")
    if sections.is_empty() {
      continue
    } // Container tags do not describe chapters.
    guard key == "TIMEBASE" || key == "START" || key == "END" || key == "title" else {
      fail("unsupported chapter field: " + key)
    }
    let section = sections[sections.length() - 1]
    guard !section.contains(key) else {
      fail("duplicate chapter field: " + key)
    }
    section[key] = value
  }
  guard !sections.is_empty() else { fail("metadata has no chapters") }
  let markers : Array[Marker] = []
  let mut previous_end = -1
  for i, section in sections {
    guard section.get("TIMEBASE") is Some(timebase) &&
      section.get("START") is Some(start) &&
      section.get("END") is Some(end) &&
      section.get("title") is Some(title) else {
      fail("chapter requires TIMEBASE, START, END and title")
    }
    let start_tick = metadata_tick(start, timebase, self.ticks_per_second)
    let end_tick = metadata_tick(end, timebase, self.ticks_per_second)
    guard end_tick > start_tick && end_tick <= self.duration_ticks else {
      fail("chapter interval is outside the selected timeline")
    }
    guard i == 0 || start_tick == previous_end else {
      fail(
        "chapter gaps, overlaps and reordering cannot be represented by markers",
      )
    }
    markers.push({
      marker_id: "imported.\{i + 1}",
      start_tick,
      title: metadata_unescape(title),
    })
    previous_end = end_tick
  }
  guard previous_end == self.duration_ticks else {
    fail("last chapter must end at selected timeline duration")
  }
  let result = { ..self, markers, }
  result.validate()
  result
}
