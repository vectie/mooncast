///|
pub(all) struct Excerpt {
  cue_number : Int
  start_ms : Int
  end_ms : Int
  text : String
} derive(Eq, ToJson)

///|
pub(all) struct Card {
  number : Int
  title : String
  start_ms : Int
  end_ms : Int
  requested_ms : Int
  image : String
  excerpts : Array[Excerpt]
} derive(Eq, ToJson)

///|
pub(all) struct Sheet {
  contract : String
  title : String
  mode : String
  duration_ms : Int
  has_captions : Bool
  cards : Array[Card]
} derive(Eq, ToJson)

///|
fn validate_duration(duration_ms : Int) -> Unit raise {
  guard duration_ms > 0 && duration_ms <= 7200000 else {
    fail("video must last 1 millisecond to two hours")
  }
}

///|
fn milliseconds(ticks : Int, rate : Int) -> Int raise {
  let scaled = ticks.to_int64() * 1000L
  guard scaled % rate.to_int64() == 0L && scaled / rate.to_int64() <= 7200000L else {
    fail("chapter times must be exact whole milliseconds within two hours")
  }
  (scaled / rate.to_int64()).to_int()
}

///|
fn compose(
  duration_ms : Int,
  title : String,
  mode : String,
  starts : Array[Int],
  titles : Array[String],
  captions : @captions.CaptionDraft?,
) -> Sheet raise {
  validate_duration(duration_ms)
  guard !title.is_blank() &&
    title.length() <= 200 &&
    title.iter().all(c => c >= ' ' && c != '\u{7f}') else {
    fail("title must be a nonblank single line of at most 200 characters")
  }
  guard starts.length() >= 1 && starts.length() <= 120 else {
    fail(
      "a review sheet must contain 1–120 cards, including any opening section",
    )
  }
  if captions is Some(draft) {
    draft.validate()
    guard (draft.duration_ms - duration_ms).abs() <= 50 else {
      fail("caption and video durations differ by more than 50 ms")
    }
  }
  let cards : Array[Card] = []
  let mut quoted_chars = 0
  let mut cue_references = 0
  for i, start_ms in starts {
    let end_ms = starts.get(i + 1).unwrap_or(duration_ms)
    guard start_ms >= 0 && end_ms > start_ms && end_ms <= duration_ms else {
      fail("sample intervals must be ordered, distinct and within the video")
    }
    let excerpts : Array[Excerpt] = []
    if captions is Some(draft) {
      for j, cue in draft.cues {
        if cue.start_ms < end_ms && cue.end_ms > start_ms {
          quoted_chars += cue.text.length()
          cue_references += 1
          guard quoted_chars <= 1000000 && cue_references <= 20000 else {
            fail(
              "caption excerpts exceed 1000000 characters or 20000 references; use fewer cards",
            )
          }
          excerpts.push({
            cue_number: j + 1,
            start_ms: cue.start_ms,
            end_ms: cue.end_ms,
            text: cue.text,
          })
        }
      }
    }
    cards.push({
      number: i + 1,
      title: titles[i],
      start_ms,
      end_ms,
      requested_ms: start_ms + (end_ms - start_ms) / 2,
      image: "frames/frame-" + (i + 1).to_string() + ".png",
      excerpts,
    })
  }
  {
    contract: "mooncast.review-sheet-plan.v1",
    title,
    mode,
    duration_ms,
    has_captions: captions is Some(_),
    cards,
  }
}

///|
/// Evenly partition the video and request the midpoint of each half-open interval.
/// Midpoints avoid empty frames at an exact end boundary. This is sampling,
/// not shot detection; transitions or brief shots may be missed.
pub fn uniform(
  duration_ms : Int,
  count : Int,
  title : String,
  captions? : @captions.CaptionDraft,
) -> Sheet raise {
  validate_duration(duration_ms)
  guard count >= 1 && count <= 120 && count <= duration_ms else {
    fail(
      "choose 1–120 samples, no more than the video's millisecond duration",
    )
  }
  let starts = Array::makei(count, i => {
    (i.to_int64() * duration_ms.to_int64() / count.to_int64()).to_int()
  })
  let titles = Array::makei(count, i => "Sample " + (i + 1).to_string())
  compose(duration_ms, title, "uniform", starts, titles, captions)
}

///|
/// Sample each selected chapter's midpoint, including any uncovered opening.
/// Matching clocks do not prove media identity: the operator chooses the drafts.
pub fn by_chapters(
  duration_ms : Int,
  chapters : @chapters.Draft,
  title : String,
  captions? : @captions.CaptionDraft,
) -> Sheet raise {
  validate_duration(duration_ms)
  chapters.validate()
  guard (milliseconds(chapters.duration_ticks, chapters.ticks_per_second) -
    duration_ms).abs() <=
    50 else {
    fail("chapter and video durations differ by more than 50 ms")
  }
  let starts : Array[Int] = []
  let titles : Array[String] = []
  if chapters.markers[0].start_tick > 0 {
    starts.push(0)
    titles.push("Before first chapter")
  }
  for marker in chapters.markers {
    starts.push(milliseconds(marker.start_tick, chapters.ticks_per_second))
    titles.push(marker.title)
  }
  compose(duration_ms, title, "chapters", starts, titles, captions)
}
