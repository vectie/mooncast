///|
fn clock(ms : Int, separator : String) -> String {
  fn pad(value : Int, width : Int) -> String {
    let mut text = value.to_string()
    while text.length() < width {
      text = "0" + text
    }
    text
  }
  pad(ms / 3600000, 2) +
  ":" +
  pad(ms / 60000 % 60, 2) +
  ":" +
  pad(ms / 1000 % 60, 2) +
  separator +
  pad(ms % 1000, 3)
}

///|
/// Export numbered plain SRT cues with exact millisecond boundaries.
pub fn CaptionDraft::srt(self : CaptionDraft) -> String raise {
  self.validate()
  let content = self.cues
    .mapi((index, cue) => {
      (index + 1).to_string() +
      "\n" +
      clock(cue.start_ms, ",") +
      " --> " +
      clock(cue.end_ms, ",") +
      "\n" +
      cue.text +
      "\n"
    })
    .join("\n")
  bounded_output(content)
}

///|
/// Export UTF-8 WebVTT suitable for an HTML video track. Ampersands are escaped
/// so literal entity-shaped text is displayed unchanged by WebVTT players.
pub fn CaptionDraft::vtt(self : CaptionDraft) -> String raise {
  self.validate()
  let content = "WEBVTT\n\n" +
    self.cues
    .mapi((index, cue) => {
      (index + 1).to_string() +
      "\n" +
      clock(cue.start_ms, ".") +
      " --> " +
      clock(cue.end_ms, ".") +
      "\n" +
      cue.text.replace_all(old="&", new="&amp;") +
      "\n"
    })
    .join("\n")
  bounded_output(content)
}

///|
fn bounded_output(content : String) -> String raise {
  guard @utf8.encode(content).length() <= 2097152 else {
    fail("caption export exceeds 2 MiB; shorten the text or divide the draft")
  }
  content
}
