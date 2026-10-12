///|
test "Whisper JSON preserves multilingual segment timing and discards no caption rows" {
  let parsed = @media.parse_subtitles(
    @utf8.encode(
      "{\"language\":\"en\",\"segments\":[{\"id\":0,\"start\":0.25,\"end\":1.5,\"text\":\" Hello, world! \"},{\"start\":2.125,\"end\":4.75,\"text\":\"你好 🌙\\nSecond line\",\"words\":[]}]}",
    ),
    "application/json",
    5000,
    1000,
  )
  assert_eq(parsed.parser_version, "mooncast-whisper-json-parser@1.0.0")
  assert_eq(parsed.cues.length(), 2)
  assert_eq(parsed.cues[0].start_tick, 250)
  assert_eq(parsed.cues[1].end_tick, 4750)
  assert_eq(parsed.cues[1].text, "你好 🌙\nSecond line")
  assert_true(parsed.cue_digest.has_prefix("sha256:"))
}

///|
test "Whisper header selects milliseconds while Audacity labels use seconds" {
  let whisper = @media.parse_subtitles(
    @utf8.encode(
      "\u{FEFF}start\tend\ttext\r\n250\t1500\tHello\r\n2125\t4750\t世界\r\n",
    ),
    "text/tab-separated-values",
    5000,
    1000,
  )
  let audacity = @media.parse_subtitles(
    @utf8.encode("0.250000\t1.500000\tHello\n2.125000\t4.750000\t世界\n"),
    "text/plain",
    5000,
    1000,
  )
  assert_eq(whisper.cues, audacity.cues)
  assert_eq(whisper.cue_digest, audacity.cue_digest)
  assert_eq(whisper.parser_version, "mooncast-whisper-tsv-parser@1.0.0")
  assert_eq(audacity.parser_version, "mooncast-audacity-label-parser@1.0.0")
  let long_label = @media.parse_subtitles(
    b"1000\t1001\tLate chapter", "text/tab-separated-values", 1002000, 1000,
  )
  assert_eq(long_label.cues[0].start_tick, 1000000)
}

///|
test "transcript timing supports nonmillisecond timeline clocks" {
  let parsed = @media.parse_subtitles(
    b"start\tend\ttext\n250\t1500\tQuarter second", "text/tab-separated-values",
    480000, 48000,
  )
  assert_eq(parsed.cues[0].start_tick, 12000)
  assert_eq(parsed.cues[0].end_tick, 72000)
}

///|
test "malformed transcript rows never create partial caption imports" {
  for
    (mime, payload) in [
      ("application/json", "{\"text\":\"untimed transcript\"}"),
      (
        "application/json", "{\"segments\":[{\"start\":0,\"end\":1,\"text\":\"Good\"},{\"start\":2,\"text\":\"Missing end\"}]}",
      ),
      (
        "application/json", "{\"segments\":[{\"start\":0,\"end\":6,\"text\":\"Too long\"}]}",
      ),
      ("text/tab-separated-values", "0\t0\tPoint label"),
      (
        "text/tab-separated-values", "start\tend\ttext\n0.5\t1000\tNot integer milliseconds",
      ),
      ("text/tab-separated-values", "0\t1\tGood\nmissing fields"),
      ("text/tab-separated-values", "2\t3\tLater\n0\t1\tEarlier"),
      ("text/tab-separated-values", "0\t1\t<style>unsafe</style>"),
      ("text/tab-separated-values", "0\t1\tRegion\n\\\t100\t200"),
    ] {
    try @media.parse_subtitles(@utf8.encode(payload), mime, 5000, 1000) catch {
      _ => ()
    } noraise {
      _ => fail("invalid transcript unexpectedly accepted: " + payload)
    }
  }
}

///|
test "existing SRT and VTT subtitle sources remain accepted" {
  let srt = @media.parse_subtitles(
    b"1\n00:00:00,250 --> 00:00:01,500\nHello\n", "application/x-subrip", 5000, 1000,
  )
  let vtt = @media.parse_subtitles(
    b"WEBVTT\n\n00:00.250 --> 00:01.500\nHello\n", "text/vtt", 5000, 1000,
  )
  assert_eq(srt.cues, vtt.cues)
  assert_eq(srt.parser_version, "mooncast-plain-subtitle-parser@1.0.0")
}
