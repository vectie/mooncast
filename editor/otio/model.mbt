///|
/// Explicitly bind an OTIO URL token to media already present in a project.
/// The token is never opened or resolved as a path. source_start_frame is the
/// OTIO source coordinate of the first frame in that existing media file.
pub(all) struct MediaBinding {
  target_url : String
  media_ref_id : String
  template_clip_id : String
  source_start_frame : Int
} derive(Eq, ToJson, @json.FromJson)

///|
pub extend MediaBinding with Eq::{equal, not_equal}

///|
pub extend MediaBinding with ToJson::{to_json}

///|
pub extend MediaBinding with @json.FromJson::{from_json}

///|
pub(all) struct MediaMap {
  contract : String
  fps : Int
  draft_timeline_id : String
  bindings : Array[MediaBinding]
} derive(Eq, ToJson, @json.FromJson)

///|
pub extend MediaMap with Eq::{equal, not_equal}

///|
pub extend MediaMap with ToJson::{to_json}

///|
pub extend MediaMap with @json.FromJson::{from_json}

///|
pub(all) struct TimelineItem {
  track_kind : String
  kind : String
  name : String
  target_url : String
  source_start_frame : Int
  duration_frames : Int
  start_frame : Int
  available_start_frame : Int?
  available_duration_frames : Int?
} derive(Eq, ToJson)

///|
pub extend TimelineItem with Eq::{equal, not_equal}

///|
pub extend TimelineItem with ToJson::{to_json}

///|
pub(all) struct TimelineCatalog {
  contract : String
  name : String
  fps : Int
  global_start_frame : Int?
  duration_frames : Int
  video_duration_frames : Int
  audio_duration_frames : Int?
  items : Array[TimelineItem]
} derive(Eq, ToJson)

///|
pub extend TimelineCatalog with Eq::{equal, not_equal}

///|
pub extend TimelineCatalog with ToJson::{to_json}

///|
pub(all) struct ImportedTimeline {
  project : @domain.EditorProject
  catalog : TimelineCatalog
  preview : @edl.DraftPreview
  audio_preview : Array[AudioCutPreview]
  edl_mapping : @edl.ReelMap
  normalized_edl : String
} derive(ToJson)

///|
pub extend ImportedTimeline with ToJson::{to_json}

///|
pub(all) struct AudioCutPreview {
  clip_id : String
  media_ref_id : String
  source_in_frame : Int
  source_out_frame : Int
  start_frame : Int
  end_frame : Int
  gap_before_frames : Int
} derive(Eq, ToJson)

///|
pub extend AudioCutPreview with ToJson::{to_json}

///|
pub extend AudioCutPreview with Eq::{equal, not_equal}

///|
pub fn read_media_map(text : String) -> MediaMap raise {
  let raw = parse_exact_json(text)
  let fields = object(raw, "media map", [
    "contract", "fps", "draft_timeline_id", "bindings",
  ])
  number(required(fields, "fps"), "map fps") |> ignore
  for raw_binding in array(required(fields, "bindings"), "map bindings") {
    let b = object(raw_binding, "media binding", [
      "target_url", "media_ref_id", "template_clip_id", "source_start_frame",
    ])
    number(required(b, "source_start_frame"), "source origin") |> ignore
  }
  let map : MediaMap = @json.from_json(raw)
  if map.contract != "mooncast.otio-media-map.v1" ||
    map.fps < 1 ||
    map.fps > 60 ||
    map.draft_timeline_id.trim().is_empty() ||
    map.bindings.is_empty() ||
    map.bindings.length() > 999 {
    fail(
      "OTIO map requires its v1 contract, integer 1–60 fps, draft timeline ID and 1–999 bindings",
    )
  }
  let urls : Map[String, Bool] = Map([])
  let media : Map[String, Bool] = Map([])
  for binding in map.bindings {
    if binding.target_url.is_empty() ||
      binding.source_start_frame < 0 ||
      binding.media_ref_id.trim().is_empty() ||
      binding.template_clip_id.trim().is_empty() ||
      urls.contains(binding.target_url) ||
      media.contains(binding.media_ref_id) {
      fail(
        "OTIO bindings require unique exact URL tokens and media IDs, existing template IDs and nonnegative source origins",
      )
    }
    urls[binding.target_url] = true
    media[binding.media_ref_id] = true
  }
  map
}
