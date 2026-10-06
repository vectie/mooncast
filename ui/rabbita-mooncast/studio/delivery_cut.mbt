///|
priv struct DeliveryCutSelection {
  start_ms : Int
  end_ms : Int
} derive(Eq, Debug)

///|
/// Parse decimal seconds directly into milliseconds without floating-point
/// rounding. Reject exponent notation, non-finite values and sub-ms precision.
fn delivery_cut_milliseconds(value : String) -> Int? {
  let parts = value.trim().to_owned().split(".").to_array()
  if parts.length() < 1 || parts.length() > 2 {
    return None
  }
  let whole = parts[0].to_owned()
  if whole == "" ||
    whole.length() > 7 ||
    !whole.iter().all(c => c >= '0' && c <= '9') {
    return None
  }
  let seconds = @string.parse_int(whole) catch { _ => return None }
  let fraction = if parts.length() == 2 {
    let digits = parts[1].to_owned()
    if digits == "" ||
      digits.length() > 3 ||
      !digits.iter().all(c => c >= '0' && c <= '9') {
      return None
    }
    let number = @string.parse_int(digits) catch { _ => return None }
    number *
    (if digits.length() == 1 {
      100
    } else if digits.length() == 2 {
      10
    } else {
      1
    })
  } else {
    0
  }
  if seconds > 2147483 || (seconds == 2147483 && fraction > 647) {
    return None
  }
  Some(seconds * 1000 + fraction)
}

///|
fn delivery_cut_selection(
  model : Model,
  project : ProjectProjection,
) -> Result[DeliveryCutSelection?, String] {
  let start = model.delivery_cut_start.trim().to_owned()
  let end = model.delivery_cut_end.trim().to_owned()
  if start == "" && end == "" {
    return Ok(None)
  }
  if start == "" || end == "" {
    return Err("Enter both cut start and end, or leave both blank for no cut.")
  }
  match (delivery_cut_milliseconds(start), delivery_cut_milliseconds(end)) {
    (Some(start_ms), Some(end_ms)) => {
      if end_ms <= start_ms {
        return Err(
          "Cut end must be after start; start must be zero or positive.",
        )
      }
      if end_ms - start_ms > 180000 {
        return Err("A selected cut can be at most 180 seconds long.")
      }
      match project.master {
        Some(master) if master.media.duration_seconds > 0 =>
          if end_ms.to_double() / 1000.0 >
            master.media.duration_seconds.to_double() {
            return Err("Cut end exceeds the promoted master duration.")
          }
        _ =>
          return Err(
            "A promoted master with a known duration is required for a cut.",
          )
      }
      Ok(Some({ start_ms, end_ms, }))
    }
    _ =>
      Err(
        "Use finite non-negative decimal seconds with at most 3 decimal places.",
      )
  }
}

///|
fn delivery_profile(cut : DeliveryCutSelection?) -> Json {
  let cuts : Array[Json] = match cut {
    None => []
    Some(cut) =>
      [
        {
          "cut_id": "selected-cut",
          "channel": "review-only",
          "source_variant": "master",
          "in_seconds": cut.start_ms.to_double() / 1000.0,
          "out_seconds": cut.end_ms.to_double() / 1000.0,
        },
      ]
  }
  {
    "contract": "mooncast.delivery-build-profile.v1",
    "version": 1,
    "include_source_master": true,
    "variants": [
      {
        "variant_id": "horizontal-1080p",
        "orientation": "horizontal",
        "width": 1920,
        "height": 1080,
        "policy": "scale",
      },
      {
        "variant_id": "vertical-1080p",
        "orientation": "vertical",
        "width": 1080,
        "height": 1920,
        "policy": "crop",
      },
    ],
    "cuts": cuts.to_json(),
    "covers": [],
    "include_subtitles": true,
    "include_metadata": true,
    "include_provenance_rights_ai_manifest": true,
  }
}
