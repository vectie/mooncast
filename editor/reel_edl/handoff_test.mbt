///|
fn recipe() -> @render.ReelRecipe {
  {
    contract: "mooncast.multi-source-reel-recipe.v1",
    canvas: { width: 320, height: 180, fit: "letterbox", },
    sources: [
      { id: "zebra", media: "zebra footage.mp4", transcript: "z.srt", },
      { id: "alpha", media: "alpha.mp4", transcript: "a.srt", },
    ],
    choices: [
      { source_id: "zebra", selection: "3,1-2", },
      { source_id: "alpha", selection: "2", },
      { source_id: "zebra", selection: "3", },
    ],
  }
}

///|
fn cues() -> Array[@domain.SubtitleCue] {
  [
    { cue_id: "one", start_tick: 0, end_tick: 1000, text: "First 🌙", },
    { cue_id: "two", start_tick: 1500, end_tick: 2000, text: "Second", },
    { cue_id: "three", start_tick: 3000, end_tick: 4000, text: "Third", },
  ]
}

///|
test "ordered repeated multi-source cuts preserve internal gaps and parse in the existing EDL reader" {
  let input = recipe()
  let transcript = cues()
  let before = (input.to_json(), transcript.to_json())
  let result = @reel_edl.export_reel_edl(
    input,
    [transcript, transcript],
    24,
    "exact",
  )
  assert_eq(result.sources.map(s => s.source_id), ["alpha", "zebra"])
  assert_eq(result.sources.map(s => s.reel), ["SRC00001", "SRC00002"])
  let parsed = @edl.parse_edl(result.edl, 24)
  assert_eq(parsed.cuts.map(c => c.reel), [
    "SRC00002", "SRC00002", "SRC00001", "SRC00002",
  ])
  assert_eq(parsed.cuts.map(c => c.source_in_frame), [72, 0, 36, 72])
  assert_eq(parsed.cuts.map(c => c.source_out_frame), [96, 48, 48, 96])
  assert_eq(parsed.cuts.map(c => c.record_in_frame), [
    86400, 86424, 86472, 86484,
  ])
  assert_eq(result.duration_frames, 108)
  assert_eq(result.excerpts.map(e => (e.first_cue, e.last_cue)), [
    (3, 3),
    (1, 2),
    (2, 2),
    (3, 3),
  ])
  assert_false(result.excerpts.any(e => e.rounded))
  assert_true(result.edl.contains("* FROM CLIP NAME: zebra footage.mp4"))
  assert_eq((input.to_json(), transcript.to_json()), before)
}

///|
test "source-to-reel mapping is stable when source array is reordered" {
  let input = recipe()
  let swapped = { ..input, sources: [input.sources[1], input.sources[0]], }
  let first = @reel_edl.export_reel_edl(input, [cues(), cues()], 30, "exact")
  let second = @reel_edl.export_reel_edl(swapped, [cues(), cues()], 30, "exact")
  assert_eq(first, second)
}

///|
test "cover explicitly rounds source bounds outwards and accumulates record durations" {
  let input = recipe()
  let one = {
    ..input,
    sources: [input.sources[0]],
    choices: [{ source_id: "zebra", selection: "1,1,1", }],
  }
  let transcript : Array[@domain.SubtitleCue] = [
    { cue_id: "fraction", start_tick: 17, end_tick: 1051, text: "Words", },
  ]
  assert_true(
    (try? @reel_edl.export_reel_edl(one, [transcript], 24, "exact")) is Err(_),
  )
  let result = @reel_edl.export_reel_edl(one, [transcript], 24, "cover")
  assert_eq(result.excerpts.map(e => e.cut.source_in_frame), [0, 0, 0])
  assert_eq(result.excerpts.map(e => e.cut.source_out_frame), [26, 26, 26])
  assert_eq(result.excerpts.map(e => e.cut.record_in_frame), [
    86400, 86426, 86452,
  ])
  assert_eq(result.duration_frames, 78)
  assert_true(
    result.excerpts.all(e => {
      e.rounded && e.source_start_ms == 17 && e.source_end_ms == 1051
    }),
  )
  for fps in [1, 24, 25, 30, 50, 60] {
    let plan = @reel_edl.export_reel_edl(one, [transcript], fps, "cover")
    for e in plan.excerpts {
      assert_true(e.cut.source_in_frame * 1000 <= e.source_start_ms * fps)
      assert_true(e.cut.source_out_frame * 1000 >= e.source_end_ms * fps)
      assert_true(e.source_start_ms * fps - e.cut.source_in_frame * 1000 < 1000)
      assert_true(e.cut.source_out_frame * 1000 - e.source_end_ms * fps < 1000)
    }
    assert_eq(@edl.parse_edl(plan.edl, fps).cuts, plan.excerpts.map(e => e.cut))
  }
}

///|
test "exact frame boundaries work at 25fps and unsupported rates and policies fail" {
  let input = recipe()
  let one = {
    ..input,
    sources: [input.sources[0]],
    choices: [{ source_id: "zebra", selection: "1", }],
  }
  let transcript : Array[@domain.SubtitleCue] = [
    { cue_id: "aligned", start_tick: 40, end_tick: 1040, text: "Words", },
  ]
  let result = @reel_edl.export_reel_edl(one, [transcript], 25, "exact")
  assert_eq(result.excerpts[0].cut.source_in_frame, 1)
  assert_eq(result.excerpts[0].cut.source_out_frame, 26)
  assert_false(result.excerpts[0].rounded)
  for fps in [-1, 0, 61, 2147483647] {
    assert_true(
      (try? @reel_edl.export_reel_edl(one, [transcript], fps, "cover"))
      is Err(_),
    )
  }
  assert_true(
    (try? @reel_edl.export_reel_edl(one, [transcript], 25, "nearest")) is Err(_),
  )
}

///|
test "two-hour bound applies after frame covering without integer overflow" {
  let input = recipe()
  let one = {
    ..input,
    sources: [input.sources[0]],
    choices: [{ source_id: "zebra", selection: "1", }],
  }
  let long : Array[@domain.SubtitleCue] = [
    { cue_id: "long", start_tick: 0, end_tick: 7200000, text: "Long", },
  ]
  assert_eq(
    @reel_edl.export_reel_edl(one, [long], 60, "exact").duration_frames,
    432000,
  )
  let twice = { ..one, choices: [{ source_id: "zebra", selection: "1,1", }], }
  let fraction : Array[@domain.SubtitleCue] = [
    { cue_id: "fraction", start_tick: 1, end_tick: 3600001, text: "Long", },
  ]
  assert_true(
    (try? @reel_edl.export_reel_edl(twice, [fraction], 24, "cover")) is Err(_),
  )
}

///|
test "missing source cues invalid ranges and unsafe source comments retain recipe validation" {
  let input = recipe()
  assert_true(
    (try? @reel_edl.export_reel_edl(input, [cues()], 24, "exact")) is Err(_),
  )
  let bad = {
    ..input,
    choices: [
      { source_id: "zebra", selection: "3-1", },
      { source_id: "alpha", selection: "1", },
    ],
  }
  assert_true(
    (try? @reel_edl.export_reel_edl(bad, [cues(), cues()], 24, "cover"))
    is Err(_),
  )
  let unsafe_source = { ..input.sources[0], media: "footage\nFCM: DROP FRAME", }
  assert_true(
    (try? @reel_edl.export_reel_edl(
      { ..input, sources: [unsafe_source, input.sources[1]], },
      [cues(), cues()],
      24,
      "cover",
    ))
    is Err(_),
  )
}

///|
test "ASCII reel ordering handles unequal lengths mixed case and prefixes" {
  let ids = ["z", "Alpha", "A", "Alpha2", "a", "_", "9", "-x"]
  let sources = ids.map(id => @render.ReelSource::{
    id,
    media: id + ".mp4",
    transcript: id + ".srt",
  })
  let input = {
    ..recipe(),
    sources,
    choices: ids.map(id => @render.ReelChoice::{
      source_id: id,
      selection: "1",
    }),
  }
  let transcripts = ids.map(_ => cues())
  let plan = @reel_edl.export_reel_edl(input, transcripts, 24, "exact")
  assert_eq(plan.sources.map(s => s.source_id), [
    "-x", "9", "A", "Alpha", "Alpha2", "_", "a", "z",
  ])
  assert_eq(plan.excerpts.map(e => e.cut.reel), [
    "SRC00008", "SRC00004", "SRC00003", "SRC00005", "SRC00007", "SRC00006", "SRC00002",
    "SRC00001",
  ])
  let reversed = {
    ..input,
    sources: ids
    .rev()
    .map(id => @render.ReelSource::{
      id,
      media: id + ".mp4",
      transcript: id + ".srt",
    }),
  }
  assert_eq(@reel_edl.export_reel_edl(reversed, transcripts, 24, "exact"), plan)
  assert_eq(@edl.parse_edl(plan.edl, 24).cuts, plan.excerpts.map(e => e.cut))
}
