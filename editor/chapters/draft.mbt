///|
pub(all) struct Marker {
  marker_id : String
  start_tick : Int
  title : String
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct Draft {
  contract : String
  project_id : String
  project_revision : Int
  timeline_id : String
  timeline_revision : Int
  ticks_per_second : Int
  duration_ticks : Int
  markers : Array[Marker]
} derive(Eq, ToJson, FromJson)

///|
fn single_line(text : String) -> Bool {
  !text.trim().is_empty() &&
  text.length() <= 200 &&
  !text.iter().any(c => c.to_int() < 32 || c.to_int() == 127)
}

///|
pub fn Draft::validate(self : Draft) -> Unit raise {
  guard self.contract == "mooncast.chapter-draft.v1" &&
    !self.project_id.is_empty() &&
    !self.timeline_id.is_empty() &&
    self.project_revision >= 0 &&
    self.timeline_revision >= 0 &&
    self.ticks_per_second > 0 &&
    self.duration_ticks > 0 &&
    !self.markers.is_empty() &&
    self.markers.length() <= 1000 else {
    fail(
      "expected a chapter draft with source identity, positive clock/duration and 1–1000 markers",
    )
  }
  let ids : Map[String, Bool] = {}
  let mut previous = -1
  for marker in self.markers {
    guard single_line(marker.marker_id) && single_line(marker.title) else {
      fail(
        "marker ID and title must be nonblank single lines of at most 200 characters",
      )
    }
    guard !ids.contains(marker.marker_id) else {
      fail("duplicate chapter ID: " + marker.marker_id)
    }
    guard marker.start_tick > previous &&
      marker.start_tick < self.duration_ticks else {
      fail("chapter starts must be distinct, ordered and within the timeline")
    }
    ids[marker.marker_id] = true
    previous = marker.start_tick
  }
}

///|
pub fn read_draft(text : String) -> Draft raise {
  let draft : Draft = @json.from_json(@json.parse(text))
  draft.validate()
  draft
}

///|
/// Make chapter suggestions from one explicitly chosen track. Other tracks
/// contribute to the total timeline duration, but never create extra markers.
pub fn seed(project : @domain.EditorProject, track_id : String) -> Draft raise {
  let matches = project.timeline.tracks.filter(t => t.track_id == track_id)
  guard matches.length() == 1 else { fail("choose one existing track") }
  let mut duration = 0L
  for track in project.timeline.tracks {
    for clip in track.clips {
      guard clip.start_tick >= 0 && clip.duration_ticks > 0 else {
        fail("invalid clip timing")
      }
      let end = clip.start_tick.to_int64() + clip.duration_ticks.to_int64()
      if end > duration {
        duration = end
      }
    }
  }
  guard duration > 0L && duration <= 2147483647L else {
    fail("timeline duration is empty or exceeds tick range")
  }
  let markers = matches[0].clips.map(c => Marker::{
    marker_id: c.clip_id,
    start_tick: c.start_tick,
    title: c.clip_id,
  })
  markers.sort_by((a, b) => a.start_tick.compare(b.start_tick))
  let draft : Draft = {
    contract: "mooncast.chapter-draft.v1",
    project_id: project.project_id,
    project_revision: project.revision,
    timeline_id: project.timeline.timeline_id,
    timeline_revision: project.timeline.revision,
    ticks_per_second: project.timeline.timebase.ticks_per_second,
    duration_ticks: duration.to_int(),
    markers,
  }
  draft.validate()
  draft
}

///|
/// Add or replace one chapter by ID, without modifying the input draft.
pub fn Draft::put(self : Draft, marker : Marker) -> Draft raise {
  self.validate()
  let markers = self.markers.filter(m => m.marker_id != marker.marker_id)
  markers.push(marker)
  markers.sort_by((a, b) => a.start_tick.compare(b.start_tick))
  let result = { ..self, markers, }
  result.validate()
  result
}

///|
pub fn Draft::remove(self : Draft, marker_id : String) -> Draft raise {
  self.validate()
  guard self.markers.any(m => m.marker_id == marker_id) else {
    fail("unknown chapter ID: " + marker_id)
  }
  let result = {
    ..self,
    markers: self.markers.filter(m => m.marker_id != marker_id),
  }
  result.validate()
  result
}
