///|
pub(all) struct Candidate {
  start_ms : Int
  score : Double
  included : Bool
  reason : String
} derive(Eq, ToJson)

///|
pub(all) struct Scene {
  number : Int
  start_ms : Int
  end_ms : Int
  title : String
} derive(Eq, ToJson)

///|
pub(all) struct Index {
  contract : String
  source_sha256 : String
  threshold : Int
  min_scene_ms : Int
  duration_ms : Int
  candidates : Array[Candidate]
  scenes : Array[Scene]
  chapters : @chapters.Draft
} derive(ToJson)

///|
/// Select cuts in chronological order with a minimum gap from the last kept
/// cut and the media end. Every suppressed candidate remains visible. A
/// no-change or short input still produces a single opening scene.
pub fn index(
  source_sha256 : String,
  duration_ms : Int,
  threshold : Int,
  min_scene_ms : Int,
  detections : Array[Detection],
) -> Index raise {
  validate_options(threshold, min_scene_ms)
  guard duration_ms > 0 &&
    duration_ms <= 1800000 &&
    detections.length() <= 10000 else {
    fail("invalid media duration or candidate count")
  }
  guard source_sha256.length() == 64 &&
    source_sha256
    .iter()
    .all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) else {
    fail("source SHA-256 must contain 64 lowercase hex characters")
  }
  let starts = [0]
  let candidates : Array[Candidate] = []
  let mut previous = -1
  let mut kept = 0
  for detection in detections {
    guard detection.start_ms >= 0 &&
      detection.start_ms >= previous &&
      detection.start_ms < duration_ms &&
      detection.score >= threshold.to_double() &&
      detection.score <= 100.0 else {
      fail("candidates must be ordered, in range and meet the chosen threshold")
    }
    previous = detection.start_ms
    let reason = if detection.start_ms - kept < min_scene_ms {
      "minimum gap from previous kept boundary"
    } else if duration_ms - detection.start_ms < min_scene_ms {
      "minimum final scene length"
    } else {
      "included visual-change boundary"
    }
    let included = reason == "included visual-change boundary"
    candidates.push({
      start_ms: detection.start_ms,
      score: detection.score,
      included,
      reason,
    })
    if included {
      starts.push(detection.start_ms)
      kept = detection.start_ms
      guard starts.length() <= 1000 else {
        fail(
          "more than 1000 scenes; increase threshold/minimum gap or split media",
        )
      }
    }
  }
  let scenes = starts.mapi((i, start_ms) => Scene::{
    number: i + 1,
    start_ms,
    end_ms: starts.get(i + 1).unwrap_or(duration_ms),
    title: "Scene " + (i + 1).to_string(),
  })
  let chapters : @chapters.Draft = {
    contract: "mooncast.chapter-draft.v1",
    project_id: "local-media:" + source_sha256,
    project_revision: 0,
    timeline_id: "scene-index:" + source_sha256,
    timeline_revision: 0,
    ticks_per_second: 1000,
    duration_ticks: duration_ms,
    markers: scenes.map(scene => {
      marker_id: "scene-" + scene.number.to_string(),
      start_tick: scene.start_ms,
      title: scene.title,
    }),
  }
  chapters.validate()
  {
    contract: "mooncast.scene-index.v1",
    source_sha256,
    threshold,
    min_scene_ms,
    duration_ms,
    candidates,
    scenes,
    chapters,
  }
}
