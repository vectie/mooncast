///|
fn example_cues() -> Array[@domain.SubtitleCue] {
  [
    {
      cue_id: "a",
      start_tick: 500,
      end_tick: 1500,
      text: "Introduce the garden.",
    },
    {
      cue_id: "b",
      start_tick: 2000,
      end_tick: 3000,
      text: "Explain the seedlings.",
    },
    {
      cue_id: "c",
      start_tick: 4000,
      end_tick: 5000,
      text: "Harvest 🌱\nThanks for watching.",
    },
  ]
}

///|
test "reel reorders excerpts and preserves silence inside a selected range" {
  let reel = transcript_reel(example_cues(), "3, 1-2")
  assert_eq(reel.duration_ms, 3500)
  assert_eq(reel.excerpts[0].source_start_ms, 4000)
  assert_eq(reel.excerpts[1].output_start_ms, 1000)
  assert_eq(reel.cues[0].text, "Harvest 🌱\nThanks for watching.")
  assert_eq(reel.cues[1].start_tick, 1000)
  assert_eq(reel.cues[2].start_tick, 2500)
  assert_true(reel.srt().contains("00:00:02,500 --> 00:00:03,500"))
  assert_eq(reel.publication_authority, false)
}

///|
test "reel intentional repetition gets new caption positions" {
  let reel = transcript_reel(example_cues(), "2,2")
  assert_eq(reel.duration_ms, 2000)
  assert_eq(reel.cues[1].start_tick, 1000)
  assert_true(reel.cues[0].cue_id != reel.cues[1].cue_id)
}

///|
test "reel invalid selections are rejected" {
  for selection in ["", "0", "4", "3-1", "1-2-3"] {
    assert_true((try? transcript_reel(example_cues(), selection)) is Err(_))
  }
}
