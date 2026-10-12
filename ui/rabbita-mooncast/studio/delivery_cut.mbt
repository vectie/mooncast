///|
priv struct DeliveryCutSelection {
  cut_id : String
  channel : String
  source_variant : String
  start_ms : Int
  end_ms : Int
} derive(Eq, Debug)

///|
priv struct DeliveryCutDraft {
  key : Int
  selected : Bool
  cut_id : String
  channel : String
  source_variant : String
  start : String
  end : String
} derive(Eq, Debug, ToJson, FromJson)

///|
priv struct DeliveryCutDraftSet {
  master_sha256 : String
  cuts : Array[DeliveryCutDraft]
} derive(Eq, Debug, ToJson, FromJson)

///|
fn delivery_cut_drafts(model : Model) -> DeliveryCutDraftSet {
  model.delivery_cut_drafts
  .get(model.selected_project_id)
  .unwrap_or({ master_sha256: "", cuts: [], })
}

///|
fn delivery_cut_name_valid(name : String) -> Bool {
  name.length() > 0 &&
  name.length() <= 80 &&
  name[0] is ('a'..='z' | 'A'..='Z' | '0'..='9') &&
  name
  .iter()
  .all(c => c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '_' | '-')) &&
  !["master", "horizontal-1080p", "vertical-1080p"].contains(name.to_lower())
}

///|
fn edit_delivery_cuts(model : Model, msg : Msg) -> Model {
  guard model.project is Some(project) &&
    project.id == model.selected_project_id &&
    !model.busy else {
    return model
  }
  let current = delivery_cut_drafts(model)
  let master_sha256 = project.master.map(master => master.sha256).unwrap_or("")
  let mut next = current
  match msg {
    AddDeliveryCut => {
      if current.cuts.length() >= 12 {
        return {
          ..model,
          error: Some("A delivery draft can contain at most 12 cuts."),
        }
      }
      let mut key = 1
      while current.cuts.any(cut => cut.key == key) {
        key += 1
      }
      let mut name_number = 1
      while current.cuts.any(cut => {
              cut.cut_id.to_lower() == "cut-\{name_number}"
            }) {
        name_number += 1
      }
      next = {
        master_sha256: if current.cuts.is_empty() {
          master_sha256
        } else {
          current.master_sha256
        },
        cuts: current.cuts +
        [
          {
            key,
            selected: true,
            cut_id: "cut-\{name_number}",
            channel: "review-only",
            source_variant: "master",
            start: "",
            end: "",
          },
        ],
      }
    }
    EditDeliveryCut(key, field, value) => {
      // Bound retained incomplete input as well as completed selections.
      if value.length() > 512 {
        return model
      }
      next = {
        ..current,
        cuts: current.cuts.map(cut => {
          if cut.key != key {
            cut
          } else {
            match field {
              "name" => { ..cut, cut_id: value, }
              "channel" => { ..cut, channel: value, }
              "source" => { ..cut, source_variant: value, }
              "start" => { ..cut, start: value, }
              "end" => { ..cut, end: value, }
              _ => cut
            }
          }
        }),
      }
    }
    ToggleDeliveryCut(key) =>
      next = {
        ..current,
        cuts: current.cuts.map(cut => {
          if cut.key == key {
            { ..cut, selected: !cut.selected, }
          } else {
            cut
          }
        }),
      }
    RemoveDeliveryCut(key) =>
      next = { ..current, cuts: current.cuts.filter(cut => cut.key != key), }
    RebindDeliveryCuts => next = { ..current, master_sha256, }
    _ => return model
  }
  let drafts = model.delivery_cut_drafts.copy()
  drafts[project.id] = next
  { ..model, delivery_cut_drafts: drafts, error: None, }
}

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
) -> Result[Array[DeliveryCutSelection], String] {
  if project.id != model.selected_project_id {
    return Err("Wait for the selected project to load.")
  }
  let draft = delivery_cut_drafts(model)
  if draft.cuts.length() > 12 {
    return Err("A delivery draft can contain at most 12 cuts.")
  }
  let selected = draft.cuts.filter(cut => cut.selected)
  if selected.is_empty() {
    return Ok([])
  }
  let master = match project.master {
    Some(master) if master.media.duration_seconds > 0 => master
    _ =>
      return Err(
        "A promoted master with a known duration is required for a cut.",
      )
  }
  if draft.master_sha256 != master.sha256 {
    return Err(
      "The promoted master changed. Review the ranges, then choose Use current master before building.",
    )
  }
  let cuts : Array[DeliveryCutSelection] = []
  let names : Array[String] = []
  for cut in selected {
    let name = cut.cut_id.trim().to_owned()
    if !delivery_cut_name_valid(name) {
      return Err(
        "Each cut needs a unique 1–80 character name starting with a letter or digit; use letters, digits, dot, hyphen or underscore. Master and variant names are reserved.",
      )
    }
    let folded = name.to_lower()
    if names.contains(folded) {
      return Err("Selected cut names must be unique, including letter case.")
    }
    names.push(folded)
    let channel = cut.channel.trim().to_owned()
    if channel == "" || channel.length() > 120 {
      return Err("Cut \{name}: enter a channel of 1–120 characters.")
    }
    if !["master", "horizontal-1080p", "vertical-1080p"].contains(
        cut.source_variant,
      ) {
      return Err(
        "Cut \{name}: select master, horizontal-1080p or vertical-1080p as the source.",
      )
    }
    match
      delivery_cut_range(cut.start, cut.end, master.media.duration_seconds) {
      Ok((start_ms, end_ms)) =>
        cuts.push({
          cut_id: name,
          channel,
          source_variant: cut.source_variant,
          start_ms,
          end_ms,
        })
      Err(message) => return Err("Cut \{name}: \{message}")
    }
  }
  Ok(cuts)
}

///|
fn delivery_cut_range(
  start : String,
  end : String,
  duration : Int,
) -> Result[(Int, Int), String] {
  let start = start.trim().to_owned()
  let end = end.trim().to_owned()
  if start == "" || end == "" {
    return Err("Enter both cut start and end, or deselect this cut.")
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
      if end_ms.to_double() / 1000.0 > duration.to_double() {
        return Err("Cut end exceeds the promoted master duration.")
      }
      Ok((start_ms, end_ms))
    }
    _ =>
      Err(
        "Use finite non-negative decimal seconds with at most 3 decimal places.",
      )
  }
}

///|
fn delivery_profile(
  cuts : Array[DeliveryCutSelection],
  covers? : Array[DeliveryCoverSelection] = [],
) -> Json {
  let cuts : Array[Json] = cuts.map(cut => {
    "cut_id": cut.cut_id,
    "channel": cut.channel,
    "source_variant": cut.source_variant,
    "in_seconds": cut.start_ms.to_double() / 1000.0,
    "out_seconds": cut.end_ms.to_double() / 1000.0,
  })
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
    "covers": covers
    .map(cover => {
      (
        {
          "cover_id": cover.cover_id,
          "source_variant": cover.source_variant,
          "timestamp_seconds": cover.timestamp_ms.to_double() / 1000.0,
          "format": cover.format,
        } : Json)
    })
    .to_json(),
    "include_subtitles": true,
    "include_metadata": true,
    "include_provenance_rights_ai_manifest": true,
  }
}
