///|
pub(all) struct SubtitleParseResult {
  parser_version : String
  cues : Array[@domain.SubtitleCue]
  cue_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct VisualInspection {
  inspector_version : String
  width : Int
  height : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
fn parse_timestamp(value : String) -> Int raise {
  let normalized = value.trim().replace_all(old=",", new=".")
  guard normalized.split_once(".") is Some((clock, millis_text)) else {
    fail("subtitle timestamp requires milliseconds")
  }
  let parts = Array::from_iter(clock.split(":").map(item => item.to_owned()))
  guard parts.length() == 2 || parts.length() == 3 else {
    fail("unsupported subtitle timestamp")
  }
  let millis = @string.parse_int(millis_text) catch {
    _ => fail("invalid subtitle milliseconds")
  }
  let seconds = @string.parse_int(parts[parts.length() - 1]) catch {
    _ => fail("invalid subtitle seconds")
  }
  let minutes = @string.parse_int(parts[parts.length() - 2]) catch {
    _ => fail("invalid subtitle minutes")
  }
  let hours = if parts.length() == 3 {
    @string.parse_int(parts[0]) catch {
      _ => fail("invalid subtitle hours")
    }
  } else {
    0
  }
  guard minutes <= 59 && seconds <= 59 && millis >= 0 && millis <= 999 else {
    fail("subtitle timestamp is out of range")
  }
  ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis
}

///|
fn parse_cue(
  block : Array[String],
  cue_number : Int,
  duration_ticks : Int,
  ticks_per_second : Int,
) -> @domain.SubtitleCue? raise {
  let mut timing_index = -1
  for index, line in block {
    if index < 2 && line.contains("-->") {
      timing_index = index
    }
  }
  if timing_index < 0 {
    return None
  }
  guard block[timing_index].split_once("-->") is Some((left, right_raw)) else {
    fail("invalid subtitle timing")
  }
  let right_parts = Array::from_iter(
    right_raw.trim().split(" ").map(value => value.to_owned()),
  )
  guard !right_parts.is_empty() else { fail("invalid subtitle end time") }
  let start_ms = parse_timestamp(left.to_owned())
  let end_ms = parse_timestamp(right_parts[0])
  guard end_ms > start_ms else {
    fail("subtitle cue must have positive duration")
  }
  let text_lines : Array[String] = []
  for index in (timing_index + 1)..<block.length() {
    if !block[index].is_blank() {
      text_lines.push(block[index].trim().to_owned())
    }
  }
  let text = text_lines.join("\n")
  guard !text.is_blank() &&
    text.length() <= 2000 &&
    !text.contains("<") &&
    !text.contains(">") else {
    fail("subtitle cue text is empty or unsafe")
  }
  let start_tick = start_ms * ticks_per_second / 1000
  let end_tick = end_ms * ticks_per_second / 1000
  guard end_tick <= duration_ticks else {
    fail("subtitle cue exceeds media duration")
  }
  Some({ cue_id: "cue-" + cue_number.to_string(), start_tick, end_tick, text })
}

///|
pub fn parse_subtitles(
  bytes : Bytes,
  mime : String,
  duration_ticks : Int,
  ticks_per_second : Int,
) -> SubtitleParseResult raise {
  guard bytes.length() > 0 && bytes.length() <= 2097152 else {
    fail("subtitle bytes exceed the bounded intake")
  }
  let text = @utf8.decode(bytes)
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  guard mime == "text/plain" ||
    mime == "text/vtt" ||
    mime == "application/x-subrip" else {
    fail("unsupported subtitle MIME type")
  }
  let lines = Array::from_iter(text.split("\n").map(value => value.to_owned()))
  let cues : Array[@domain.SubtitleCue] = []
  let block : Array[String] = []
  for line in lines {
    if line.is_blank() {
      if !block.is_empty() {
        if parse_cue(block, cues.length() + 1, duration_ticks, ticks_per_second)
          is Some(cue) {
          cues.push(cue)
        }
        block.clear()
      }
    } else if !(mime == "text/vtt" && line.trim() == "WEBVTT") {
      block.push(line)
    }
  }
  if !block.is_empty() {
    if parse_cue(block, cues.length() + 1, duration_ticks, ticks_per_second)
      is Some(cue) {
      cues.push(cue)
    }
  }
  guard !cues.is_empty() && cues.length() <= 5000 else {
    fail("subtitle cue count is invalid")
  }
  for index in 1..<cues.length() {
    guard cues[index].start_tick >= cues[index - 1].start_tick else {
      fail("subtitle cues must be ordered")
    }
  }
  let digest = "sha256:" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(cues.to_json().stringify())),
    )
  {
    parser_version: "mooncast-plain-subtitle-parser@1.0.0",
    cues,
    cue_digest: digest,
  }
}

///|
fn be16(bytes : Bytes, offset : Int) -> Int {
  (bytes[offset].to_int() << 8) | bytes[offset + 1].to_int()
}

///|
fn be32(bytes : Bytes, offset : Int) -> Int {
  (bytes[offset].to_int() << 24) |
  (bytes[offset + 1].to_int() << 16) |
  (bytes[offset + 2].to_int() << 8) |
  bytes[offset + 3].to_int()
}

///|
fn le24(bytes : Bytes, offset : Int) -> Int {
  bytes[offset].to_int() |
  (bytes[offset + 1].to_int() << 8) |
  (bytes[offset + 2].to_int() << 16)
}

///|
pub fn inspect_visual(bytes : Bytes, mime : String) -> VisualInspection raise {
  let (width, height) = match mime {
    "image/png" => {
      guard bytes.length() >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 else {
        fail("invalid PNG header")
      }
      (be32(bytes, 16), be32(bytes, 20))
    }
    "image/webp" => {
      guard bytes.length() >= 30 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[12] == 0x56 &&
        bytes[13] == 0x50 &&
        bytes[14] == 0x38 &&
        bytes[15] == 0x58 else {
        fail("only bounded VP8X WebP is supported")
      }
      (le24(bytes, 24) + 1, le24(bytes, 27) + 1)
    }
    "image/jpeg" => {
      guard bytes.length() >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8 else {
        fail("invalid JPEG header")
      }
      let mut offset = 2
      let mut found_width = 0
      let mut found_height = 0
      while offset + 8 < bytes.length() && found_width == 0 {
        guard bytes[offset] == 0xff else { fail("invalid JPEG segment") }
        let marker = bytes[offset + 1].to_int()
        offset += 2
        if marker == 0xd8 ||
          marker == 0xd9 ||
          (marker >= 0xd0 && marker <= 0xd7) {
          continue
        }
        let length = be16(bytes, offset)
        guard length >= 2 && offset + length <= bytes.length() else {
          fail("invalid JPEG segment length")
        }
        if marker == 0xc0 ||
          marker == 0xc1 ||
          marker == 0xc2 ||
          marker == 0xc3 ||
          marker == 0xc5 ||
          marker == 0xc6 ||
          marker == 0xc7 ||
          marker == 0xc9 ||
          marker == 0xca ||
          marker == 0xcb ||
          marker == 0xcd ||
          marker == 0xce ||
          marker == 0xcf {
          found_height = be16(bytes, offset + 3)
          found_width = be16(bytes, offset + 5)
        }
        offset += length
      }
      guard found_width > 0 else { fail("JPEG frame header is absent") }
      (found_width, found_height)
    }
    _ => fail("unsupported visual MIME type")
  }
  guard width > 0 &&
    height > 0 &&
    width <= 16384 &&
    height <= 16384 &&
    width * height <= 33554432 else {
    fail("image dimensions exceed editor limits")
  }
  { inspector_version: "mooncast-raster-header-inspector@1.0.0", width, height }
}

///|
pub fn binding_with_subtitles(
  binding : @domain.LocalMediaBinding,
  parsed : SubtitleParseResult,
) -> @domain.LocalMediaBinding {
  {
    ..binding,
    parser_version: parsed.parser_version,
    cues: parsed.cues,
    cue_digest: parsed.cue_digest,
  }
}

///|
pub fn binding_with_visual(
  binding : @domain.LocalMediaBinding,
  inspected : VisualInspection,
) -> @domain.LocalMediaBinding {
  {
    ..binding,
    inspector_version: inspected.inspector_version,
    width: inspected.width,
    height: inspected.height,
  }
}

///|
pub fn waveform_peaks(
  raw_pcm_s16le : Bytes,
  count? : Int = 96,
) -> Array[Int] raise {
  guard count > 0 && count <= 192 else {
    fail("waveform peak count is invalid")
  }
  let samples = raw_pcm_s16le.length() / 2
  if samples == 0 {
    return []
  }
  let peaks : Array[Int] = []
  for bucket in 0..<count {
    let start = bucket * samples / count
    let end = Int::max(start + 1, (bucket + 1) * samples / count)
    let mut peak = 0
    for index in start..<Int::min(end, samples) {
      let unsigned = raw_pcm_s16le[index * 2].to_int() |
        (raw_pcm_s16le[index * 2 + 1].to_int() << 8)
      let signed = if unsigned >= 32768 { unsigned - 65536 } else { unsigned }
      let magnitude = signed.abs()
      if magnitude > peak {
        peak = magnitude
      }
    }
    peaks.push(Int::min(1000, peak * 1000 / 32768))
  }
  peaks
}

///|
pub fn waveform_svg(peaks : Array[Int], digest : String) -> Bytes {
  let bars : Array[String] = []
  for index, peak in peaks {
    let height = Int::max(1, peak * 60 / 1000)
    let y = 32 - height / 2
    bars.push(
      "<rect x='" +
      (index * 3).to_string() +
      "' y='" +
      y.to_string() +
      "' width='2' height='" +
      height.to_string() +
      "'/>",
    )
  }
  @utf8.encode(
    "<svg xmlns='http://www.w3.org/2000/svg' width='" +
    (peaks.length() * 3).to_string() +
    "' height='64' viewBox='0 0 " +
    (peaks.length() * 3).to_string() +
    " 64' data-source='" +
    digest +
    "'><g fill='#78a6ff'>" +
    bars.join("") +
    "</g></svg>",
  )
}
