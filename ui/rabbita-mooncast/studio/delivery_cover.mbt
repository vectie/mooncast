///|
priv struct DeliveryCoverSelection {
  cover_id : String
  source_variant : String
  timestamp_ms : Int
  format : String
} derive(Eq, Debug)

///|
priv struct DeliveryCoverDraft {
  key : Int
  selected : Bool
  cover_id : String
  source_variant : String
  timestamp : String
  format : String
} derive(Eq, Debug, ToJson, FromJson)

///|
priv struct DeliveryCoverDraftSet {
  master_sha256 : String
  covers : Array[DeliveryCoverDraft]
} derive(Eq, Debug, ToJson, FromJson)

///|
fn delivery_cover_drafts(model : Model) -> DeliveryCoverDraftSet {
  model.delivery_cover_drafts
  .get(model.selected_project_id)
  .unwrap_or({ master_sha256: "", covers: [], })
}

///|
fn edit_delivery_covers(model : Model, msg : Msg) -> Model {
  guard model.project is Some(project) &&
    project.id == model.selected_project_id &&
    !model.busy else {
    return model
  }
  let current = delivery_cover_drafts(model)
  let master_sha256 = project.master.map(master => master.sha256).unwrap_or("")
  let mut next = current
  match msg {
    AddDeliveryCover => {
      if current.covers.length() >= 8 {
        return {
          ..model,
          error: Some("A delivery draft can contain at most 8 covers."),
        }
      }
      let mut key = 1
      while current.covers.any(cover => cover.key == key) {
        key += 1
      }
      let mut number = 1
      while current.covers.any(cover => {
              cover.cover_id.to_lower() == "cover-\{number}"
            }) ||
            delivery_cut_drafts(model).cuts.any(cut => {
              cut.cut_id.to_lower() == "cover-\{number}"
            }) {
        number += 1
      }
      next = {
        master_sha256: if current.covers.is_empty() {
          master_sha256
        } else {
          current.master_sha256
        },
        covers: current.covers +
        [
          {
            key,
            selected: true,
            cover_id: "cover-\{number}",
            source_variant: "master",
            timestamp: "0",
            format: "png",
          },
        ],
      }
    }
    EditDeliveryCover(key, field, value) => {
      if value.length() > 512 {
        return model
      }
      next = {
        ..current,
        covers: current.covers.map(cover => {
          if cover.key != key {
            cover
          } else {
            match field {
              "name" => { ..cover, cover_id: value, }
              "source" => { ..cover, source_variant: value, }
              "timestamp" => { ..cover, timestamp: value, }
              "format" => { ..cover, format: value, }
              _ => cover
            }
          }
        }),
      }
    }
    ToggleDeliveryCover(key) =>
      next = {
        ..current,
        covers: current.covers.map(cover => {
          if cover.key == key {
            { ..cover, selected: !cover.selected, }
          } else {
            cover
          }
        }),
      }
    RemoveDeliveryCover(key) =>
      next = {
        ..current,
        covers: current.covers.filter(cover => cover.key != key),
      }
    RebindDeliveryCovers => next = { ..current, master_sha256, }
    _ => return model
  }
  let drafts = model.delivery_cover_drafts.copy()
  drafts[project.id] = next
  { ..model, delivery_cover_drafts: drafts, error: None, }
}

///|
fn delivery_cover_selection(
  model : Model,
  project : ProjectProjection,
) -> Result[Array[DeliveryCoverSelection], String] {
  if project.id != model.selected_project_id {
    return Err("Wait for the selected project to load.")
  }
  let draft = delivery_cover_drafts(model)
  if draft.covers.length() > 8 {
    return Err("A delivery draft can contain at most 8 covers.")
  }
  let selected = draft.covers.filter(cover => cover.selected)
  if selected.is_empty() {
    return Ok([])
  }
  let master = match project.master {
    Some(master) if master.media.duration_seconds > 0 => master
    _ =>
      return Err(
        "A promoted master with a known duration is required for a cover.",
      )
  }
  if draft.master_sha256 != master.sha256 {
    return Err(
      "The promoted master changed. Check cover timestamps, then choose Use current master for covers.",
    )
  }
  let names = delivery_cut_drafts(model).cuts
    .filter(cut => cut.selected)
    .map(cut => cut.cut_id.trim().to_owned().to_lower())
  let covers : Array[DeliveryCoverSelection] = []
  for cover in selected {
    let name = cover.cover_id.trim().to_owned()
    if !delivery_cut_name_valid(name) {
      return Err(
        "Each cover needs a unique 1–80 character name starting with a letter or digit; use letters, digits, dot, hyphen or underscore. Master and variant names are reserved.",
      )
    }
    if names.contains(name.to_lower()) {
      return Err(
        "Selected cover and cut names must be unique, including letter case.",
      )
    }
    names.push(name.to_lower())
    if !["master", "horizontal-1080p", "vertical-1080p"].contains(
        cover.source_variant,
      ) {
      return Err(
        "Cover \{name}: choose master, horizontal-1080p or vertical-1080p.",
      )
    }
    if !["jpg", "png"].contains(cover.format) {
      return Err("Cover \{name}: choose JPG or PNG.")
    }
    let timestamp_ms = match delivery_cut_milliseconds(cover.timestamp) {
      Some(value) => value
      None =>
        return Err(
          "Cover \{name}: enter non-negative seconds with at most 3 decimal places.",
        )
    }
    if timestamp_ms.to_double() / 1000.0 >=
      master.media.duration_seconds.to_double() {
      return Err(
        "Cover \{name}: timestamp must be before the end of the promoted master.",
      )
    }
    covers.push({
      cover_id: name,
      source_variant: cover.source_variant,
      timestamp_ms,
      format: cover.format,
    })
  }
  Ok(covers)
}
