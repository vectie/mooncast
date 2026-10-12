///|
/// Parse exactly HH:MM:SS:FF, NDF, within one 24-hour day.
pub fn timecode_frames(value : String, fps : Int) -> Int raise {
  valid_fps(fps)
  guard value.length() == 11 &&
    value[2] == ':' &&
    value[5] == ':' &&
    value[8] == ':' else {
    fail("expected non-drop-frame HH:MM:SS:FF: " + value)
  }
  let digits : Array[Int] = []
  for i = 0; i < value.length(); i = i + 1 {
    if i != 2 && i != 5 && i != 8 {
      guard value[i] >= '0' && value[i] <= '9' else {
        fail("timecode contains a non-decimal digit: " + value)
      }
      digits.push(value[i].to_int() - 48)
    }
  }
  let h = digits[0] * 10 + digits[1]
  let m = digits[2] * 10 + digits[3]
  let s = digits[4] * 10 + digits[5]
  let f = digits[6] * 10 + digits[7]
  guard h < 24 && m < 60 && s < 60 && f < fps else {
    fail("timecode component is outside its frame-rate range: " + value)
  }
  ((h * 60 + m) * 60 + s) * fps + f
}

///|
fn pad(value : Int, width : Int) -> String {
  let text = value.to_string()
  "0".repeat(width - text.length()) + text
}

///|
pub fn frames_timecode(frame : Int, fps : Int) -> String raise {
  valid_fps(fps)
  guard frame >= 0 && frame < 86400 * fps else {
    fail("timecode must fit within one 24-hour day; rollover is unsupported")
  }
  let seconds = frame / fps
  pad(seconds / 3600, 2) +
  ":" +
  pad(seconds / 60 % 60, 2) +
  ":" +
  pad(seconds % 60, 2) +
  ":" +
  pad(frame % fps, 2)
}

///|
fn frames_to_ticks(frames : Int, fps : Int, timebase : Int) -> Int raise {
  let numerator = frames.to_int64() * timebase.to_int64()
  guard numerator % fps.to_int64() == 0L else {
    fail("frame boundary is not representable at this native timebase")
  }
  checked_int(numerator / fps.to_int64())
}

///|
fn ticks_to_frames(ticks : Int, fps : Int, timebase : Int) -> Int raise {
  guard timebase > 0 && ticks >= 0 else {
    fail("invalid native tick or timebase")
  }
  let numerator = ticks.to_int64() * fps.to_int64()
  guard numerator % timebase.to_int64() == 0L else {
    fail("native cut is not frame-aligned; EDL export does not round edits")
  }
  checked_int(numerator / timebase.to_int64())
}

///|
fn exact_timebase(timebase : Int, fps : Int) -> Int raise {
  guard timebase > 0 else { fail("project timebase must be positive") }
  let mut a = timebase
  let mut b = fps
  while b != 0 {
    let remainder = a % b
    a = b
    b = remainder
  }
  checked_int((timebase / a).to_int64() * fps.to_int64())
}
