///|
fn object(
  value : Json,
  label : String,
  allowed : Array[String],
) -> Map[String, Json] raise {
  guard value is Object(fields) else {
    fail("OTIO " + label + " must be an object")
  }
  for key, _ in fields {
    if !allowed.contains(key) {
      fail("OTIO unsupported " + label + " field: " + key)
    }
  }
  fields
}

///|
fn required(fields : Map[String, Json], key : String) -> Json raise {
  guard fields.get(key) is Some(value) else { fail("OTIO missing " + key) }
  value
}

///|
fn text(value : Json, label : String) -> String raise {
  guard value is String(value) else {
    fail("OTIO " + label + " must be a string")
  }
  value
}

///|
fn schema(fields : Map[String, Json], expected : String) -> Unit raise {
  if text(required(fields, "OTIO_SCHEMA"), "schema") != expected {
    fail("OTIO expected schema " + expected)
  }
}

///|
fn number(value : Json, label : String) -> Int raise {
  guard value is Number(_) &&
    exact_integer(value.stringify()) is Some(n) &&
    n >= 0L &&
    n <= 2147483647L else {
    fail("OTIO " + label + " requires a nonnegative whole frame integer")
  }
  n.to_int()
}

///|
fn time(value : Json, fps : Int) -> Int raise {
  let fields = object(value, "time", ["OTIO_SCHEMA", "value", "rate"])
  schema(fields, "RationalTime.1")
  if number(required(fields, "rate"), "rate") != fps {
    fail("OTIO all time values must use the explicitly selected integer fps")
  }
  number(required(fields, "value"), "frame")
}

///|
fn range(value : Json, fps : Int) -> (Int, Int) raise {
  let fields = object(value, "range", ["OTIO_SCHEMA", "start_time", "duration"])
  schema(fields, "TimeRange.1")
  let start = time(required(fields, "start_time"), fps)
  let duration = time(required(fields, "duration"), fps)
  if duration == 0 || start.to_int64() + duration.to_int64() > 2147483647L {
    fail("OTIO range must be nonempty and fit the frame integer clock")
  }
  (start, duration)
}

///|
fn array(value : Json, label : String) -> Array[Json] raise {
  guard value is Array(values) else {
    fail("OTIO " + label + " must be an array")
  }
  values
}

///|
fn named(fields : Map[String, Json]) -> String raise {
  match fields.get("name") {
    Some(value) => text(value, "name")
    None => ""
  }
}

///|
fn common(fields : Map[String, Json], container : Bool) -> Unit raise {
  named(fields) |> ignore
  if fields.get("metadata") is Some(value) {
    guard value is Object(_) else { fail("OTIO metadata must be an object") }
  }
  for key in ["effects", "markers"] {
    if fields.get(key) is Some(value) {
      if !array(value, key).is_empty() {
        fail("OTIO " + key + " are unsupported, not discarded")
      }
    }
  }
  if fields.get("enabled") is Some(value) && value != Json::boolean(true) {
    fail("OTIO disabled items are unsupported")
  }
  if fields.get("color") is Some(value) && !(value is Null) {
    fail("OTIO item colors are unsupported")
  }
  if container && fields.get("source_range") is Some(value) && !(value is Null) {
    fail("OTIO trimmed containers are unsupported")
  }
}

///|
fn item_fields(
  value : Json,
  additions : Array[String],
) -> Map[String, Json] raise {
  object(
    value,
    "item",
    [
      "OTIO_SCHEMA", "name", "metadata", "source_range", "effects", "markers", "enabled",
      "color",
    ] +
    additions,
  )
}

///|
fn reference(value : Json, fps : Int) -> (String, Int?, Int?) raise {
  let fields = object(value, "external reference", [
    "OTIO_SCHEMA", "name", "metadata", "target_url", "available_range", "available_image_bounds",
  ])
  schema(fields, "ExternalReference.1")
  common(fields, false)
  if fields.get("available_image_bounds") is Some(value) && !(value is Null) {
    fail("OTIO image bounds are unsupported")
  }
  let url = text(required(fields, "target_url"), "target_url")
  if url.is_empty() {
    fail("OTIO external reference URL token is empty")
  }
  match fields.get("available_range") {
    None | Some(Null) => (url, None, None)
    Some(value) => {
      let (start, duration) = range(value, fps)
      (url, Some(start), Some(duration))
    }
  }
}

///|
/// Inspect a bounded cuts-only OTIO file without opening any referenced media.
/// Items retain track order and within-track order, including leading/internal gaps.
/// One Video and optionally one Audio track share the same explicit frame clock.
pub fn catalog_timeline(input : String, fps : Int) -> TimelineCatalog raise {
  if fps < 1 || fps > 60 || @utf8.encode(input).length() > 4194304 {
    fail("OTIO requires integer 1–60 fps and at most 4 MiB UTF-8 JSON")
  }
  let root = object(parse_exact_json(input), "timeline", [
    "OTIO_SCHEMA", "name", "metadata", "global_start_time", "tracks",
  ])
  schema(root, "Timeline.1")
  common(root, false)
  let global_start_frame = match root.get("global_start_time") {
    None | Some(Null) => None
    Some(value) => Some(time(value, fps))
  }
  let stack = item_fields(required(root, "tracks"), ["children"])
  schema(stack, "Stack.1")
  common(stack, true)
  let tracks = array(required(stack, "children"), "tracks")
  if tracks.length() < 1 || tracks.length() > 2 {
    fail("OTIO requires one Video track and at most one optional Audio track")
  }
  let items : Array[TimelineItem] = []
  let mut video_duration = None
  let mut audio_duration = None
  for value in tracks {
    let track = item_fields(value, ["children", "kind"])
    schema(track, "Track.1")
    let kind = text(required(track, "kind"), "kind")
    if (kind == "Video" && video_duration is Some(_)) ||
      (kind == "Audio" && audio_duration is Some(_)) ||
      (kind != "Video" && kind != "Audio") {
      fail(
        "OTIO supports one Video and optionally one Audio track; duplicate kinds and layers are refused",
      )
    }
    let (track_items, duration) = catalog_track(value, fps, kind)
    for item in track_items {
      items.push(item)
    }
    if kind == "Video" {
      video_duration = Some(duration)
    } else {
      audio_duration = Some(duration)
    }
  }
  guard video_duration is Some(video_duration_frames) else {
    fail("OTIO requires one Video track; audio-only timelines are unsupported")
  }
  if items.length() > 1999 ||
    items.filter(item => item.kind == "clip").length() > 999 {
    fail(
      "OTIO supports at most 999 clips and 1999 total clips/gaps across both tracks",
    )
  }
  {
    contract: "mooncast.otio-catalog.v2",
    name: named(root),
    fps,
    global_start_frame,
    duration_frames: match audio_duration {
      Some(duration) => Int::max(video_duration_frames, duration)
      None => video_duration_frames
    },
    video_duration_frames,
    audio_duration_frames: audio_duration,
    items,
  }
}

///|
fn catalog_track(
  value : Json,
  fps : Int,
  track_kind : String,
) -> (Array[TimelineItem], Int) raise {
  let track = item_fields(value, ["children", "kind"])
  schema(track, "Track.1")
  common(track, true)
  let children = array(required(track, "children"), "track children")
  if children.is_empty() || children.length() > 1999 {
    fail("OTIO requires 1–1999 cuts/gaps")
  }
  let items : Array[TimelineItem] = []
  let mut cursor = 0
  let mut cuts = 0
  for child in children {
    let fields = item_fields(child, [
      "media_reference", "media_references", "active_media_reference_key",
    ])
    common(fields, false)
    let kind = text(required(fields, "OTIO_SCHEMA"), "item schema")
    let (start, duration) = range(required(fields, "source_range"), fps)
    if cursor.to_int64() + duration.to_int64() >= (86400 * fps).to_int64() {
      fail("OTIO timeline must fit within one 24-hour EDL interchange day")
    }
    let (url, available_start, available_duration) = match kind {
      "Gap.1" => {
        if start != 0 ||
          fields.contains("media_reference") ||
          fields.contains("media_references") ||
          fields.contains("active_media_reference_key") {
          fail("OTIO gap requires zero source start and no media fields")
        }
        ("", None, None)
      }
      "Clip.1" => {
        if fields.contains("media_references") ||
          fields.contains("active_media_reference_key") {
          fail("OTIO Clip.1 cannot carry Clip.2 media fields")
        }
        reference(required(fields, "media_reference"), fps)
      }
      "Clip.2" => {
        if fields.contains("media_reference") {
          fail("OTIO Clip.2 cannot carry a Clip.1 media reference")
        }
        guard required(fields, "media_references") is Object(refs) else {
          fail("OTIO media_references must be an object")
        }
        let active = text(
          required(fields, "active_media_reference_key"),
          "active media key",
        )
        if refs.length() != 1 {
          fail("OTIO alternate media references are unsupported")
        }
        reference(required(refs, active), fps)
      }
      _ => fail("OTIO unsupported item schema: " + kind)
    }
    if kind != "Gap.1" {
      cuts += 1
      if cuts > 999 {
        fail("OTIO supports at most 999 clips")
      }
      if available_start is Some(a) &&
        available_duration is Some(d) &&
        (
          start < a ||
          start.to_int64() + duration.to_int64() > a.to_int64() + d.to_int64()
        ) {
        fail("OTIO clip range exceeds its declared available_range")
      }
    }
    items.push({
      track_kind,
      kind: if kind == "Gap.1" {
        "gap"
      } else {
        "clip"
      },
      name: named(fields),
      target_url: url,
      source_start_frame: start,
      duration_frames: duration,
      start_frame: cursor,
      available_start_frame: available_start,
      available_duration_frames: available_duration,
    })
    cursor += duration
  }
  if cuts == 0 || items[items.length() - 1].kind == "gap" {
    fail(
      "OTIO needs a final clip: a native timeline cannot retain an explicit trailing gap",
    )
  }
  (items, cursor)
}
