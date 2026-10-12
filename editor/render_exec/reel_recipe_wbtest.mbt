///|
fn recipe_example() -> ReelRecipe {
  {
    contract: "mooncast.multi-source-reel-recipe.v1",
    canvas: { width: 320, height: 180, fit: "letterbox", },
    sources: [
      { id: "garden", media: "garden.mp4", transcript: "garden.json", },
      { id: "studio", media: "studio.mkv", transcript: "studio.srt", },
    ],
    choices: [
      { source_id: "studio", selection: "3", },
      { source_id: "garden", selection: "1-2", },
      { source_id: "studio", selection: "3", },
    ],
  }
}

///|
test "multi-source recipe preserves interleaving repetition gaps and source identity" {
  let recipe = recipe_example()
  let source = example_cues()
  let before = source.to_json().stringify()
  let reel = multi_source_reel(recipe, [source, source])
  assert_eq(reel.excerpts.map(e => e.source_id), ["studio", "garden", "studio"])
  assert_eq(reel.excerpts.map(e => e.source_index), [1, 0, 1])
  assert_eq(reel.excerpts.map(e => e.output_start_frame), [0, 30, 105])
  assert_eq(reel.duration_frames, 135)
  assert_eq(reel.cues.map(c => c.start_tick), [0, 1000, 2500, 3500])
  assert_eq(reel.cues[3].text, source[2].text)
  assert_true(reel.srt().contains("00:00:03,500 --> 00:00:04,500"))
  assert_eq(source.to_json().stringify(), before)
  assert_false(reel.publication_authority)
  assert_eq(parse_reel_recipe(recipe.to_json().stringify()), recipe)
}

///|
test "multi-source frame rounding is cumulative without audio drift" {
  let recipe = {
    ..recipe_example(),
    sources: [recipe_example().sources[0]],
    choices: [{ source_id: "garden", selection: "1,1,1", }],
  }
  let cue : @domain.SubtitleCue = {
    cue_id: "x",
    start_tick: 17,
    end_tick: 51,
    text: "tiny",
  }
  let reel = multi_source_reel(recipe, [[cue]])
  assert_eq(reel.excerpts.map(e => e.output_frames), [2, 2, 2])
  assert_eq(reel.cues.map(c => c.start_tick), [0, 66, 133])
  assert_eq(reel.cues.map(c => c.end_tick), [34, 100, 167])
  assert_eq(reel.duration_frames, 6)
}

///|
test "multi-source recipe rejects invalid schema canvas source IDs paths and choices" {
  let good = recipe_example()
  for
    recipe in [
      { ..good, contract: "v2", },
      { ..good, canvas: { ..good.canvas, width: 31, }, },
      { ..good, canvas: { ..good.canvas, width: 1922, }, },
      { ..good, canvas: { ..good.canvas, height: 1082, }, },
      { ..good, canvas: { ..good.canvas, fit: "crop", }, },
      { ..good, sources: [], },
      { ..good, sources: [good.sources[0], good.sources[0]], },
      {
        ..good,
        sources: [{ ..good.sources[0], id: "bad id", }, good.sources[1]],
      },
      {
        ..good,
        sources: [
          { ..good.sources[0], media: "https://example.org/a.mp4", },
          good.sources[1],
        ],
      },
      {
        ..good,
        sources: [
          { ..good.sources[0], transcript: "bad\npath", },
          good.sources[1],
        ],
      },
      { ..good, choices: [], },
      { ..good, choices: [{ source_id: "missing", selection: "1", }], },
      { ..good, choices: [{ source_id: "garden", selection: "1", }], },
    ] {
    assert_true((try? validate_reel_recipe(recipe)) is Err(_))
  }
  let json = good.to_json().stringify()
  assert_true(
    (try? parse_reel_recipe(
      json.replace_all(
        old="\"letterbox\"",
        new="\"letterbox\",\"ignored\":true",
      ),
    ))
    is Err(_),
  )
  assert_true((try? parse_reel_recipe("[]")) is Err(_))
  assert_true((try? parse_reel_recipe("{")) is Err(_))
}

///|
test "multi-source recipe selection refusal and bounded output" {
  let base = { ..recipe_example(), sources: [recipe_example().sources[0]], }
  for selection in ["", "0", "4", "3-1", "1-2-3"] {
    let recipe = { ..base, choices: [{ source_id: "garden", selection, }], }
    assert_true((try? multi_source_reel(recipe, [example_cues()])) is Err(_))
  }
  let many = Array::make(101, "1").join(",")
  assert_true(
    (try? multi_source_reel(
      { ..base, choices: [{ source_id: "garden", selection: many, }], },
      [example_cues()],
    ))
    is Err(_),
  )
  assert_true(
    (try? multi_source_reel(recipe_example(), [example_cues()])) is Err(_),
  )
  let long : @domain.SubtitleCue = {
    cue_id: "long",
    start_tick: 0,
    end_tick: 7200000,
    text: "long",
  }
  assert_true(
    (try? multi_source_reel(
      { ..base, choices: [{ source_id: "garden", selection: "1,1", }], },
      [[long]],
    ))
    is Err(_),
  )
  let tiny = { ..long, end_tick: 33, }
  assert_true(
    (try? multi_source_reel(
      { ..base, choices: [{ source_id: "garden", selection: "1", }], },
      [[tiny]],
    ))
    is Err(_),
  )
}

///|
test "multi-source selected overlapping captions are refused rather than silently lost" {
  let recipe = {
    ..recipe_example(),
    sources: [recipe_example().sources[0]],
    choices: [{ source_id: "garden", selection: "1-2", }],
  }
  let first : @domain.SubtitleCue = {
    cue_id: "a",
    start_tick: 0,
    end_tick: 1500,
    text: "a",
  }
  let second : @domain.SubtitleCue = {
    cue_id: "b",
    start_tick: 1000,
    end_tick: 2000,
    text: "b",
  }
  assert_true((try? multi_source_reel(recipe, [[first, second]])) is Err(_))
}

///|
test "multi-source source choice and caption caps are enforced" {
  let good = recipe_example()
  let nine = Array::makei(9, i => ReelSource::{
    id: "source" + i.to_string(),
    media: "a.mp4",
    transcript: "a.srt",
  })
  let all = nine.map(s => ReelChoice::{ source_id: s.id, selection: "1", })
  assert_true(
    (try? validate_reel_recipe({ ..good, sources: nine, choices: all, }))
    is Err(_),
  )
  assert_true(
    (try? validate_reel_recipe({
      ..good,
      choices: Array::make(101, good.choices[0]),
    }))
    is Err(_),
  )
  let base = {
    ..good,
    sources: [good.sources[0]],
    choices: [{ source_id: "garden", selection: "1-3000,1-3000", }],
  }
  let cues = Array::makei(3000, i => @domain.SubtitleCue::{
    cue_id: i.to_string(),
    start_tick: i * 40,
    end_tick: i * 40 + 34,
    text: "bounded caption",
  })
  assert_true((try? multi_source_reel(base, [cues])) is Err(_))
}
