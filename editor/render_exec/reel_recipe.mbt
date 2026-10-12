///|
pub(all) struct ReelSource {
  id : String
  media : String
  transcript : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReelChoice {
  source_id : String
  selection : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReelCanvas {
  width : Int
  height : Int
  fit : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReelRecipe {
  contract : String
  canvas : ReelCanvas
  sources : Array[ReelSource]
  choices : Array[ReelChoice]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SourceExcerpt {
  source_id : String
  source_index : Int
  first_cue : Int
  last_cue : Int
  source_start_ms : Int
  source_end_ms : Int
  output_start_frame : Int
  output_frames : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MultiSourceReel {
  contract : String
  canvas : ReelCanvas
  excerpts : Array[SourceExcerpt]
  cues : Array[@domain.SubtitleCue]
  duration_frames : Int
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn recipe_keys(value : Json, expected : Array[String]) -> Unit raise {
  guard value is Object(fields) &&
    fields.length() == expected.length() &&
    expected.all(key => fields.contains(key)) else {
    fail("recipe contains missing or unsupported fields")
  }
}

///|
/// Strict versioned recipe; paths are resolved by the local host.
pub fn parse_reel_recipe(text : String) -> ReelRecipe raise {
  guard text.length() <= 1048576 else { fail("recipe exceeds 1 MiB") }
  let value = @json.parse(text)
  recipe_keys(value, ["contract", "canvas", "sources", "choices"])
  guard value
    is {
      "canvas": canvas,
      "sources": Array(sources),
      "choices": Array(choices),
      ..
    } else {
    fail("invalid recipe structure")
  }
  recipe_keys(canvas, ["width", "height", "fit"])
  for source in sources {
    recipe_keys(source, ["id", "media", "transcript"])
  }
  for choice in choices {
    recipe_keys(choice, ["source_id", "selection"])
  }
  let recipe : ReelRecipe = @json.from_json(value)
  validate_reel_recipe(recipe)
  recipe
}

///|
pub fn validate_reel_recipe(recipe : ReelRecipe) -> Unit raise {
  guard recipe.contract == "mooncast.multi-source-reel-recipe.v1" else {
    fail("unsupported multi-source reel recipe contract")
  }
  let c = recipe.canvas
  guard c.fit == "letterbox" &&
    c.width >= 32 &&
    c.width <= 1920 &&
    c.height >= 32 &&
    c.height <= 1080 &&
    c.width % 2 == 0 &&
    c.height % 2 == 0 else {
    fail(
      "canvas requires even 32..1920 x 32..1080 dimensions and letterbox fit",
    )
  }
  guard recipe.sources.length() >= 1 &&
    recipe.sources.length() <= 8 &&
    recipe.choices.length() >= 1 &&
    recipe.choices.length() <= 100 else {
    fail("recipe requires 1..8 sources and 1..100 choices")
  }
  let ids : Map[String, Bool] = {}
  for source in recipe.sources {
    guard !source.id.is_empty() &&
      source.id.length() <= 64 &&
      source.id
      .iter()
      .all(c => c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_' | '-')) &&
      !ids.contains(source.id) else {
      fail("source IDs must be unique ASCII identifiers")
    }
    ids[source.id] = true
    for path in [source.media, source.transcript] {
      guard !path.is_empty() &&
        path.length() <= 4096 &&
        !path.contains(":") &&
        !path.iter().any(c => c < ' ') else {
        fail("source paths must be bounded local file paths")
      }
    }
    guard recipe.choices.any(choice => choice.source_id == source.id) else {
      fail("every declared source must be selected")
    }
  }
  for choice in recipe.choices {
    guard ids.contains(choice.source_id) && choice.selection.length() <= 4096 else {
      fail("choice refers to an unknown source or oversized selection")
    }
  }
}

///|
/// Hard cuts are rounded up individually to whole 30 fps frames. Captions keep
/// their source-relative milliseconds; the <=33 ms tail is held video/silence.
pub fn multi_source_reel(
  recipe : ReelRecipe,
  transcripts : Array[Array[@domain.SubtitleCue]],
) -> MultiSourceReel raise {
  validate_reel_recipe(recipe)
  guard transcripts.length() == recipe.sources.length() else {
    fail("missing source transcript")
  }
  let excerpts : Array[SourceExcerpt] = []
  let cues : Array[@domain.SubtitleCue] = []
  let mut cursor = 0
  for choice in recipe.choices {
    let index = recipe.sources.search_by(s => s.id == choice.source_id).unwrap()
    let selected = transcript_reel(transcripts[index], choice.selection)
    for excerpt in selected.excerpts {
      guard excerpts.length() < 100 else {
        fail("at most 100 excerpts per reel")
      }
      let frames = (
          (excerpt.source_end_ms - excerpt.source_start_ms) * 30 + 999
        ) /
        1000
      guard cursor <= 216000 - frames else { fail("reel exceeds two hours") }
      excerpts.push({
        source_id: choice.source_id,
        source_index: index,
        first_cue: excerpt.first_cue,
        last_cue: excerpt.last_cue,
        source_start_ms: excerpt.source_start_ms,
        source_end_ms: excerpt.source_end_ms,
        output_start_frame: cursor,
        output_frames: frames,
      })
      for i in (excerpt.first_cue - 1)..<excerpt.last_cue {
        guard cues.length() < 5000 else {
          fail("reel exceeds 5000 output captions")
        }
        let cue = transcripts[index][i]
        let start = cursor * 1000 / 30 +
          cue.start_tick -
          excerpt.source_start_ms
        guard cues.last() is None || cues.last().unwrap().end_tick <= start else {
          fail("selected captions overlap; refine the selected ranges")
        }
        cues.push({
          cue_id: "reel-" + (cues.length() + 1).to_string(),
          start_tick: start,
          end_tick: cursor * 1000 / 30 + cue.end_tick - excerpt.source_start_ms,
          text: cue.text,
        })
      }
      cursor += frames
    }
  }
  {
    contract: "mooncast.multi-source-reel.v1",
    canvas: recipe.canvas,
    excerpts,
    cues,
    duration_frames: cursor,
    publication_authority: false,
  }
}

///|
pub fn MultiSourceReel::srt(self : MultiSourceReel) -> String {
  TranscriptReel::{
    contract: "mooncast.transcript-reel.v1",
    excerpts: [],
    cues: self.cues,
    duration_ms: self.duration_frames * 1000 / 30,
    publication_authority: false,
  }.srt()
}
