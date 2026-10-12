///|
fn tokens(line : String) -> Array[String] {
  line
  .replace_all(old="\t", new=" ")
  .split(" ")
  .filter(token => !token.is_empty())
  .map(token => token.to_owned())
  .to_array()
}

///|
/// Bounded CMX3600: one V channel, C edits, NON-DROP FRAME, 1–999 events.
/// Descriptive comments are ignored. Every other directive is rejected.
pub fn parse_edl(input : String, fps : Int) -> EditList raise {
  valid_fps(fps)
  guard input.length() <= 2097152 else { fail("EDL exceeds 2 MiB") }
  let mut title = "MoonCast cut"
  let mut has_title = false
  let mut has_fcm = false
  let cuts : Array[Cut] = []
  let events : Map[Int, Bool] = Map([])
  for index, raw in input.split("\n").to_array() {
    let line = raw.trim().to_owned()
    if line.is_empty() {
      continue
    }
    let label = "EDL line " + (index + 1).to_string() + ": "
    if line.has_prefix("TITLE:") {
      guard !has_title && cuts.is_empty() else {
        fail(label + "duplicate or late TITLE")
      }
      title = line.strip_prefix("TITLE:").unwrap().trim().to_owned()
      guard !title.is_empty() &&
        title.length() <= 120 &&
        title.iter().all(c => c >= ' ') else {
        fail(label + "TITLE needs 1–120 printable characters")
      }
      has_title = true
      continue
    }
    if line.has_prefix("FCM:") {
      guard !has_fcm &&
        cuts.is_empty() &&
        tokens(line) == ["FCM:", "NON-DROP", "FRAME"] else {
        fail(
          label +
          "expected one FCM: NON-DROP FRAME before the events; drop-frame is unsupported",
        )
      }
      has_fcm = true
      continue
    }
    if line.has_prefix("* FROM CLIP NAME:") ||
      line.has_prefix("* SOURCE FILE:") ||
      line.has_prefix("* COMMENT:") {
      continue
    }
    guard has_fcm else {
      fail(label + "FCM: NON-DROP FRAME is required before events")
    }
    let fields = tokens(line)
    guard fields.length() == 8 && fields[2] == "V" && fields[3] == "C" else {
      fail(
        label +
        "only V cuts are supported; transitions, audio, retimes and unknown directives are unsupported",
      )
    }
    guard fields[0].length() == 3 &&
      fields[0].iter().all(c => c >= '0' && c <= '9') else {
      fail(label + "event number must be three decimal digits (001–999)")
    }
    let event_number = @string.parse_int(fields[0], base=10)
    guard event_number > 0 && !events.contains(event_number) else {
      fail(label + "duplicate or zero event number")
    }
    guard valid_reel(fields[1]) else {
      fail(
        label +
        "unsupported reel; BL/black events are represented as record gaps",
      )
    }
    let cut : Cut = {
      event_number,
      reel: fields[1],
      source_in_frame: timecode_frames(fields[4], fps),
      source_out_frame: timecode_frames(fields[5], fps),
      record_in_frame: timecode_frames(fields[6], fps),
      record_out_frame: timecode_frames(fields[7], fps),
    }
    guard cut.source_out_frame > cut.source_in_frame &&
      cut.record_out_frame > cut.record_in_frame else {
      fail(
        label +
        "in/out ranges must be positive; midnight rollover is unsupported",
      )
    }
    guard cut.source_out_frame - cut.source_in_frame ==
      cut.record_out_frame - cut.record_in_frame else {
      fail(
        label + "source and record durations differ; retimes are unsupported",
      )
    }
    if cuts.last() is Some(previous) {
      guard cut.record_in_frame >= previous.record_out_frame else {
        fail(label + "record events overlap or are out of order")
      }
    }
    events[event_number] = true
    cuts.push(cut)
    guard cuts.length() <= 999 else { fail("EDL has more than 999 events") }
  }
  guard has_fcm && !cuts.is_empty() else {
    fail("EDL needs FCM: NON-DROP FRAME and at least one video cut")
  }
  { title, fps, cuts, }
}
