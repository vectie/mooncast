///|
fn header() -> String {
  "[Script Info]\nScriptType: v4.00+\nWrapStyle: 0\nTimer: 100.0000\n" +
  "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
}

///|
fn read(events : String) -> @ass.Import raise {
  @ass.import_plain(@utf8.encode(header() + events), "sample.ass", 10000)
}

///|
fn rejected(text : String) -> Unit raise {
  guard (try? @ass.import_plain(@utf8.encode(text), "invalid.ass", 10000))
    is Err(_) else {
    fail("expected a rejected ASS file")
  }
}

///|
test "ASS imports exact centisecond timing, commas, Unicode and plain text escapes" {
  let input = "\u{feff}" +
    header().replace_all(old="\n", new="\r\n") +
    "Comment: ignored production note\r\n" +
    "Dialogue: 0,0:00:00.25,0:00:02.75,Default,Ada,0,0,0,,{\\i1}Hello, 世界 🌙{\\i0}\\NSecond\\hline\\nsoft\r\n"
  let result = @ass.import_plain(@utf8.encode(input), "styled.ass", 10000)
  assert_eq(result.draft.cues, [
    {
      start_ms: 250,
      end_ms: 2750,
      text: "Hello, 世界 🌙\nSecond\u{00a0}line soft",
    },
  ])
  assert_eq(result.override_cues, 1)
  assert_eq(result.comment_events, 1)
  assert_eq(result.script_type, "v4.00+")
  assert_true(!result.reordered)
  assert_eq(result.draft.source_file, "styled.ass")
}

///|
test "out-of-order and overlapping events sort by start with stable equal starts" {
  let result = read(
    "Dialogue: 2,0:00:04.00,0:00:06.00,Default,,0,0,0,,Later\n" +
    "Dialogue: 0,0:00:01.00,0:00:05.00,Default,,0,0,0,Banner;1;0;10,First\n" +
    "Dialogue: 1,0:00:01.00,0:00:03.00,Default,,0,0,0,,Second\n",
  )
  assert_eq(result.draft.cues.map(c => c.text), ["First", "Second", "Later"])
  assert_true(result.reordered)
  assert_eq(result.source_lines, [8, 9, 7])
  assert_eq(result.effect_cues, 1)
  assert_eq(result.draft.cues[0].end_ms, 5000)
}

///|
test "SSA and named format columns map into the same editable caption model" {
  let source = "[Script Info]\nScriptType: v4.00\n[V4 Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n" +
    "[Events]\nFormat: Marked, End, Start, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n" +
    "Dialogue: Marked=0,0:00:02.50,0:00:00.50,Default,,0,0,0,,SSA caption\n"
  let result = @ass.import_plain(@utf8.encode(source), "legacy.ssa", 10000)
  assert_eq(result.script_type, "v4.00")
  assert_eq(result.draft.cues[0], {
    start_ms: 500,
    end_ms: 2500,
    text: "SSA caption",
  })
  let corrected = result.draft.set_cue(1, 600, 2600, "Corrected 🌙")
  let reopened = @captions.import_draft(
    @utf8.encode(corrected.srt()),
    "application/x-subrip",
    "reopen.srt",
    10000,
  )
  assert_eq(reopened.cues, corrected.cues)
  let vtt = @captions.import_draft(
    @utf8.encode(corrected.vtt()),
    "text/vtt",
    "reopen.vtt",
    10000,
  )
  assert_eq(vtt.cues, corrected.cues)
  assert_eq(result.draft.cues[0].text, "SSA caption")
}

///|
test "soft line breaks respect script wrap and explicit wrap resets; karaoke becomes full text" {
  let result = read(
    "Dialogue: 0,0:00:00.00,0:00:03.00,Default,,0,0,0,,{\\q2\\k20}A\\nB{\\r}C\\nD{comment}\\N{\\pos(10,20)\\p0}E\n",
  )
  assert_eq(result.draft.cues[0].text, "A\nBC D\nE")
  let wrap2 = (header() +
  "Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,A\\nB").replace_all(
    old="WrapStyle: 0",
    new="WrapStyle: 2",
  )
  assert_eq(
    @ass.import_plain(@utf8.encode(wrap2), "wrap.ass", 10000).draft.cues[0].text,
    "A\nB",
  )
}

///|
test "drawing, malformed blocks and unsupported visible text cannot become misleading captions" {
  for
    text in [
      "{\\p1}m 0 0 l 10 10{\\p0}", "{\\p-1}drawing", "{\\p2}vector", "A{unclosed",
      "A}", "{{nested}}A", "{comment}", "A\\N\\NB", "<tag>",
    ] {
    rejected(
      header() + "Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,," + text,
    )
  }
  rejected(header() + "Picture: 0,0:00:00.00,0:00:01.00,missing.bmp")
  rejected(header() + "[Fonts]\nfontname: attached.ttf\n")
}

///|
test "bad clocks, timing scaling, missing format and wrong script type fail the entire import" {
  for
    clock in [
      "0:00:00.001", "0:60:00.00", "0:00:60.00", "-1:00:00.00", "0:0:00.00", "NaN",
    ] {
    rejected(
      header() + "Dialogue: 0," + clock + ",0:00:01.00,Default,,0,0,0,,A",
    )
  }
  let good = header() + "Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,A"
  rejected(good.replace_all(old="Timer: 100.0000", new="Timer: 99.0"))
  rejected(good.replace_all(old="v4.00+", new="v3.00"))
  rejected(good.replace_all(old="Format: Layer,", new="Format: Marked,"))
  rejected(good.replace_all(old="0:00:01.00", new="0:00:11.00"))
  rejected(good.replace_all(old="0:00:01.00", new="0:00:00.00"))
  rejected(
    "[Script Info]\nScriptType: v4.00+\n[Events]\nDialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,A",
  )
  rejected(good + "\n[Events]\n")
}
