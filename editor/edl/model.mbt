///|
/// Source timecodes are relative to the explicit first-frame timecode of the media.
/// The template contributes production identity, intent and artifact lineage only.
pub(all) struct ReelBinding {
  reel : String
  media_ref_id : String
  template_clip_id : String
  source_start_timecode : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReelMap {
  contract : String
  fps : Int
  record_start_timecode : String
  draft_timeline_id : String
  bindings : Array[ReelBinding]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Half-open frame intervals; no floating point, inclusive out point or retiming.
pub(all) struct Cut {
  event_number : Int
  reel : String
  source_in_frame : Int
  source_out_frame : Int
  record_in_frame : Int
  record_out_frame : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditList {
  title : String
  fps : Int
  cuts : Array[Cut]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CutPreview {
  event_number : Int
  reel : String
  media_ref_id : String
  clip_id : String
  source_in_frame : Int
  source_out_frame : Int
  start_frame : Int
  end_frame : Int
  gap_before_frames : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DraftPreview {
  contract : String
  title : String
  source_project_id : String
  source_revision : Int
  source_timeline_id : String
  fps : Int
  record_start_timecode : String
  ticks_per_second : Int
  duration_frames : Int
  gap_frames : Int
  cuts : Array[CutPreview]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ImportedCut {
  project : @domain.EditorProject
  preview : DraftPreview
} derive(Debug, Eq, ToJson)

///|
fn checked_int(value : Int64) -> Int raise {
  guard value >= 0L && value <= 2147483647L else {
    fail("time exceeds the native timeline's nonnegative 32-bit tick range")
  }
  value.to_int()
}

///|
fn valid_fps(fps : Int) -> Unit raise {
  guard fps >= 1 && fps <= 60 else {
    fail(
      "fps must be an explicit integer between 1 and 60; fractional/drop-frame rates are unsupported",
    )
  }
}

///|
fn valid_reel(reel : String) -> Bool {
  !reel.is_empty() &&
  reel.length() <= 8 &&
  reel != "BL" &&
  reel.iter().all(c => c is ('A'..='Z' | '0'..='9' | '_'))
}

///|
pub fn read_reel_map(input : String) -> ReelMap raise {
  let mapping : ReelMap = @json.from_json(@json.parse(input))
  mapping.validate()
  mapping
}

///|
pub fn ReelMap::validate(self : ReelMap) -> Unit raise {
  guard self.contract == "mooncast.edl-reel-map.v1" else {
    fail("unsupported EDL reel map contract")
  }
  valid_fps(self.fps)
  ignore(timecode_frames(self.record_start_timecode, self.fps))
  guard !self.draft_timeline_id.is_blank() else {
    fail("draft_timeline_id is required")
  }
  guard !self.bindings.is_empty() && self.bindings.length() <= 999 else {
    fail("the reel map needs 1–999 bindings")
  }
  let reels : Map[String, Bool] = Map([])
  let media : Map[String, Bool] = Map([])
  for binding in self.bindings {
    guard valid_reel(binding.reel) else {
      fail(
        "reels need 1–8 uppercase letters, digits or underscores; BL is reserved",
      )
    }
    guard !binding.media_ref_id.is_blank() &&
      !binding.template_clip_id.is_blank() else {
      fail("each reel needs an existing media_ref_id and template_clip_id")
    }
    guard !reels.contains(binding.reel) && !media.contains(binding.media_ref_id) else {
      fail("reel names and media_ref_ids must each be unique in the map")
    }
    reels[binding.reel] = true
    media[binding.media_ref_id] = true
    ignore(timecode_frames(binding.source_start_timecode, self.fps))
  }
}
