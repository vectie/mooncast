///|
extern "js" fn delivery_cover_storage_read(key : String) -> String =
  #| key => {
  #|   try {
  #|     if (!globalThis.localStorage) return JSON.stringify({error:"Browser storage is unavailable; covers remain only in this tab."});
  #|     const value = globalThis.localStorage.getItem(key);
  #|     return JSON.stringify(value === null ? {missing:true} : {value});
  #|   } catch (_) { return JSON.stringify({error:"Saved covers could not be read. Existing bytes will not be replaced; edits remain only in this tab."}); }
  #| }

///|
extern "js" fn delivery_cover_storage_write(
  key : String,
  value : String,
) -> String =
  #| (key, value) => {
  #|   try {
  #|     if (!globalThis.localStorage) return "Browser storage is unavailable; covers remain only in this tab.";
  #|     globalThis.localStorage.setItem(key, value);
  #|     if (globalThis.localStorage.getItem(key) !== value) return "Saved covers could not be verified. Keep this tab open and retry saving.";
  #|     return "";
  #|   } catch (_) { return "Cover autosave failed. Edits remain in this tab; retry saving before closing it."; }
  #| }

///|
fn delivery_cover_storage_key(project_id : String) -> String {
  "mooncast.delivery-covers.v1:" + project_id
}

///|
fn delivery_cover_storage_notice(model : Model) -> String? {
  model.delivery_cover_storage_notices.get(model.selected_project_id)
}

///|
fn set_delivery_cover_storage_notice(
  model : Model,
  project_id : String,
  notice : String?,
) -> Model {
  let notices = model.delivery_cover_storage_notices.copy()
  match notice {
    Some(message) => notices[project_id] = message
    None => notices.remove(project_id)
  }
  { ..model, delivery_cover_storage_notices: notices, }
}

///|
fn encode_delivery_cover_draft(
  project_id : String,
  draft : DeliveryCoverDraftSet,
) -> String {
  (
    {
      "contract": "mooncast.delivery-cover-draft.v1",
      "project_id": project_id,
      "draft": ToJson::to_json(draft),
    } : Json).stringify()
}

///|
fn decode_delivery_cover_draft(
  project_id : String,
  raw : String,
) -> Result[DeliveryCoverDraftSet, String] {
  // Include worst-case JSON escaping of all bounded incomplete input fields.
  if raw.length() > 262144 {
    return Err("Saved cover draft is too large.")
  }
  let parsed = @json.parse(raw) catch {
    _ => return Err("Saved cover draft is unreadable.")
  }
  guard parsed
    is {
      "contract": "mooncast.delivery-cover-draft.v1",
      "project_id": String(id),
      "draft": draft,
      ..
    } &&
    id == project_id else {
    return Err("Saved cover draft belongs to another project or version.")
  }
  let draft : DeliveryCoverDraftSet = @json.from_json(draft) catch {
    _ => return Err("Saved cover draft has invalid fields.")
  }
  if draft.covers.length() > 8 || draft.master_sha256.length() > 512 {
    return Err("Saved cover draft exceeds its bounds.")
  }
  let keys : Array[Int] = []
  for cover in draft.covers {
    if cover.key < 1 ||
      cover.key > 1000000 ||
      keys.contains(cover.key) ||
      [cover.cover_id, cover.source_variant, cover.timestamp, cover.format].any(value => {
          value.length() > 512
        },
      ) {
      return Err(
        "Saved cover draft has invalid row identities or oversized fields.",
      )
    }
    keys.push(cover.key)
  }
  Ok(draft)
}

///|
fn restore_delivery_cover_drafts(
  model : Model,
  project_id : String,
  reply : String,
) -> Model {
  let parsed = @json.parse(reply) catch { _ => Json::null() }
  let result = match parsed {
    { "missing": True, .. } => Ok({ master_sha256: "", covers: [], })
    { "value": String(value), .. } =>
      decode_delivery_cover_draft(project_id, value)
    { "error": String(message), .. } => Err(message)
    _ => Err("Saved covers could not be read.")
  }
  let drafts = model.delivery_cover_drafts.copy()
  match result {
    Ok(draft) => {
      drafts[project_id] = draft
      set_delivery_cover_storage_notice(
        { ..model, delivery_cover_drafts: drafts, },
        project_id,
        None,
      )
    }
    Err(message) => {
      drafts[project_id] = { master_sha256: "", covers: [], }
      set_delivery_cover_storage_notice(
        {
          ..model,
          delivery_cover_drafts: drafts,
          delivery_cover_storage_blocked: model.delivery_cover_storage_blocked +
          [project_id],
        },
        project_id,
        Some(
          message +
          " Autosave is paused for this project to preserve the saved draft. Keep this tab open.",
        ),
      )
    }
  }
}

///|
fn load_delivery_cover_drafts(model : Model, project_id : String) -> Model {
  if project_id == "" || model.delivery_cover_drafts.contains(project_id) {
    return model
  }
  restore_delivery_cover_drafts(
    model,
    project_id,
    delivery_cover_storage_read(delivery_cover_storage_key(project_id)),
  )
}

///|
fn save_delivery_cover_drafts(model : Model) -> Model {
  let project_id = model.selected_project_id
  if project_id == "" || model.busy {
    return model
  }
  if model.delivery_cover_storage_blocked.contains(project_id) {
    return set_delivery_cover_storage_notice(
      model,
      project_id,
      Some(
        "Autosave is paused for this project because its saved draft could not be read. Existing saved bytes are preserved; keep this tab open.",
      ),
    )
  }
  guard model.delivery_cover_drafts.get(project_id) is Some(draft) else {
    return model
  }
  let error = delivery_cover_storage_write(
    delivery_cover_storage_key(project_id),
    encode_delivery_cover_draft(project_id, draft),
  )
  set_delivery_cover_storage_notice(
    model,
    project_id,
    if error == "" {
      None
    } else {
      Some(error)
    },
  )
}
