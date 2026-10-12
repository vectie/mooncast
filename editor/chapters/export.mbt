///|
fn end_tick(draft : Draft, index : Int) -> Int {
  if index + 1 < draft.markers.length() {
    draft.markers[index + 1].start_tick
  } else {
    draft.duration_ticks
  }
}

///|
fn metadata_title(title : String) -> String {
  title
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="=", new="\\=")
  .replace_all(old=";", new="\\;")
  .replace_all(old="#", new="\\#")
}

///|
/// FFmpeg chapter metadata preserves the source timeline's exact tick clock.
pub fn Draft::ffmetadata(self : Draft) -> String raise {
  self.validate()
  let out = StringBuilder::new()
  out.write_string(";FFMETADATA1\n")
  for index, marker in self.markers {
    guard !marker.title.has_suffix("\\") else {
      fail(
        "FFmetadata cannot safely represent a title ending in a backslash; revise: " +
        marker.marker_id,
      )
    }
    let end = end_tick(self, index)
    out.write_string(
      "[CHAPTER]\nTIMEBASE=1/\{self.ticks_per_second}\nSTART=\{marker.start_tick}\nEND=\{end}\ntitle=",
    )
    out.write_string(metadata_title(marker.title))
    out.write_char('\n')
  }
  out.to_string()
}

///|
fn padded(value : Int64, width : Int) -> String {
  let text = value.to_string()
  "0".repeat(if width > text.length() { width - text.length() } else { 0 }) +
  text
}

///|
fn timestamp(ms : Int64) -> String {
  padded(ms / 3600000L, 2) +
  ":" +
  padded(ms / 60000L % 60L, 2) +
  ":" +
  padded(ms / 1000L % 60L, 2) +
  "." +
  padded(ms % 1000L, 3)
}

///|
/// Chapter WebVTT uses shared floor-to-millisecond boundaries. Intervals
/// that collapse below its precision are rejected rather than dropped.
pub fn Draft::webvtt(self : Draft) -> String raise {
  self.validate()
  let out = StringBuilder::new()
  out.write_string("WEBVTT\n\n")
  for index, marker in self.markers {
    let start = marker.start_tick.to_int64() *
      1000L /
      self.ticks_per_second.to_int64()
    let end = end_tick(self, index).to_int64() *
      1000L /
      self.ticks_per_second.to_int64()
    guard end > start else {
      fail(
        "chapter is shorter than WebVTT millisecond precision: " +
        marker.marker_id,
      )
    }
    let title = marker.title
      .replace_all(old="&", new="&amp;")
      .replace_all(old="<", new="&lt;")
      .replace_all(old=">", new="&gt;")
    out.write_string("\{index + 1}\n")
    out.write_string(
      timestamp(start) + " --> " + timestamp(end) + "\n" + title + "\n\n",
    )
  }
  out.to_string()
}
