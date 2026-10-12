///|
pub(all) struct Section {
  marker_id : String?
  title : String
  start_ms : Int
  end_ms : Int
  cue_numbers : Array[Int]
  continuing_cue_numbers : Array[Int]
} derive(Eq, ToJson)

///|
pub(all) struct Transcript {
  title : String
  captions : @captions.CaptionDraft
  chapters : @chapters.Draft
  sections : Array[Section]
} derive(Eq, ToJson)

///|
fn milliseconds(ticks : Int, rate : Int) -> Int raise {
  let scaled = ticks.to_int64() * 1000L
  guard scaled % rate.to_int64() == 0L else {
    fail("chapter boundaries must be exact whole milliseconds")
  }
  let result = scaled / rate.to_int64()
  guard result <= 7200000L else { fail("chapter duration exceeds two hours") }
  result.to_int()
}

///|
/// Join operator-selected drafts on the same output clock. Duration equality
/// is not proof of media identity. Each cue is owned by exactly one section.
pub fn compose(
  captions : @captions.CaptionDraft,
  chapters : @chapters.Draft,
  title : String,
) -> Transcript raise {
  captions.validate()
  chapters.validate()
  guard !title.is_blank() &&
    title.length() <= 200 &&
    !title.iter().any(c => c < ' ' || c == '\u{7f}') else {
    fail("title must be a nonblank single line of at most 200 characters")
  }
  let duration = milliseconds(
    chapters.duration_ticks,
    chapters.ticks_per_second,
  )
  guard duration == captions.duration_ms else {
    fail("caption and chapter durations must match exactly")
  }
  let sections : Array[Section] = []
  let starts = chapters.markers.map(m => {
    milliseconds(m.start_tick, chapters.ticks_per_second)
  })
  if starts[0] > 0 {
    sections.push({
      marker_id: None,
      title: "Before first chapter",
      start_ms: 0,
      end_ms: starts[0],
      cue_numbers: [],
      continuing_cue_numbers: [],
    })
  }
  for i, marker in chapters.markers {
    sections.push({
      marker_id: Some(marker.marker_id),
      title: marker.title,
      start_ms: starts[i],
      end_ms: starts.get(i + 1).unwrap_or(duration),
      cue_numbers: [],
      continuing_cue_numbers: [],
    })
  }
  let mut references = 0
  for i, cue in captions.cues {
    for section in sections {
      if cue.start_ms >= section.start_ms && cue.start_ms < section.end_ms {
        section.cue_numbers.push(i + 1)
      } else if cue.start_ms < section.start_ms && cue.end_ms > section.start_ms {
        section.continuing_cue_numbers.push(i + 1)
        references += 1
        guard references <= 20000 else {
          fail("more than 20000 cross-chapter cue references")
        }
      }
    }
  }
  { title, captions, chapters, sections, }
}

///|
fn escape_html(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
fn pad(value : Int, width : Int) -> String {
  let text = value.to_string()
  "0".repeat(width - text.length()) + text
}

///|
fn time(ms : Int) -> String {
  pad(ms / 3600000, 2) +
  ":" +
  pad(ms / 60000 % 60, 2) +
  ":" +
  pad(ms / 1000 % 60, 2) +
  "." +
  pad(ms % 1000, 3)
}

///|
/// Plain text retains every original cue's words and line breaks exactly once.
pub fn Transcript::plain_text(self : Transcript) -> String {
  let out = StringBuilder::new()
  out.write_string(
    self.title +
    "\n\nLocal transcript; review against the intended media. No acceptance or delivery status is inferred.\n",
  )
  for section in self.sections {
    out.write_string(
      "\n" +
      section.title +
      " [" +
      time(section.start_ms) +
      "–" +
      time(section.end_ms) +
      "]\n",
    )
    for number in section.continuing_cue_numbers {
      out.write_string("Continues from cue " + number.to_string() + " above.\n")
    }
    if section.cue_numbers.is_empty() {
      out.write_string("No cues begin in this chapter.\n")
    }
    for number in section.cue_numbers {
      let cue = self.captions.cues[number - 1]
      out.write_string(
        "\nCue " +
        number.to_string() +
        " [" +
        time(cue.start_ms) +
        "–" +
        time(cue.end_ms) +
        "]\n" +
        cue.text +
        "\n",
      )
    }
  }
  out.to_string()
}

///|
/// Standalone semantic HTML, without scripts, remote assets or media requests.
pub fn Transcript::html(self : Transcript) -> String {
  let out = StringBuilder::new()
  out.write_string(
    "<!doctype html>\n<html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>" +
    escape_html(self.title) +
    "</title><style>body{max-width:56rem;margin:2rem auto;padding:0 1rem;font:1.1rem/1.6 system-ui}a{color:#0645ad}:focus{outline:3px solid #a40}.words{white-space:pre-wrap}section{margin-top:2rem}.timing{font-size:.9em}li{margin:.4rem 0}@media print{nav{display:none}}</style></head><body>\n<a href=\"#transcript\">Skip chapter navigation</a><header><h1>" +
    escape_html(self.title) +
    "</h1><p>Local transcript; review against the intended media. No acceptance or delivery status is inferred.</p></header>\n<nav aria-label=\"Chapters\"><h2>Chapters</h2><ol>\n",
  )
  for i, section in self.sections {
    out.write_string(
      "<li><a href=\"#chapter-" +
      (i + 1).to_string() +
      "\">" +
      escape_html(section.title) +
      "</a> (" +
      time(section.start_ms) +
      ")</li>\n",
    )
  }
  out.write_string("</ol></nav><main id=\"transcript\">\n")
  for i, section in self.sections {
    out.write_string(
      "<section aria-labelledby=\"chapter-" +
      (i + 1).to_string() +
      "\"><h2 id=\"chapter-" +
      (i + 1).to_string() +
      "\">" +
      escape_html(section.title) +
      "</h2><p class=\"timing\">" +
      time(section.start_ms) +
      "–" +
      time(section.end_ms) +
      "</p>\n",
    )
    for number in section.continuing_cue_numbers {
      out.write_string(
        "<p>Continues from <a href=\"#cue-" +
        number.to_string() +
        "\">cue " +
        number.to_string() +
        " above</a>.</p>\n",
      )
    }
    if section.cue_numbers.is_empty() {
      out.write_string("<p>No cues begin in this chapter.</p>\n")
    }
    for number in section.cue_numbers {
      let cue = self.captions.cues[number - 1]
      out.write_string(
        "<div id=\"cue-" +
        number.to_string() +
        "\"><p class=\"timing\">Cue " +
        number.to_string() +
        " · " +
        time(cue.start_ms) +
        "–" +
        time(cue.end_ms) +
        "</p><p class=\"words\">" +
        escape_html(cue.text) +
        "</p></div>\n",
      )
    }
    out.write_string("</section>\n")
  }
  out.write_string("</main></body></html>\n")
  out.to_string()
}
