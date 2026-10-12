///|
extern "js" fn delivery_cut_storage_read(key : String) -> String =
  #| key => {
  #|   try {
  #|     if (!globalThis.localStorage) return JSON.stringify({error:"Browser storage is unavailable; cuts remain only in this tab."});
  #|     const value = globalThis.localStorage.getItem(key);
  #|     return JSON.stringify(value === null ? {missing:true} : {value});
  #|   } catch (_) { return JSON.stringify({error:"Saved cuts could not be read. Existing bytes will not be replaced; edits remain only in this tab."}); }
  #| }

///|
extern "js" fn delivery_cut_storage_write(
  key : String,
  value : String,
) -> String =
  #| (key, value) => {
  #|   try {
  #|     if (!globalThis.localStorage) return "Browser storage is unavailable; cuts remain only in this tab.";
  #|     globalThis.localStorage.setItem(key, value);
  #|     if (globalThis.localStorage.getItem(key) !== value) return "Saved cuts could not be verified. Keep this tab open and retry saving.";
  #|     return "";
  #|   } catch (_) { return "Cut autosave failed. Edits remain in this tab; retry saving before closing it."; }
  #| }

///|
fn delivery_cut_storage_key(project_id : String) -> String {
  "mooncast.delivery-cuts.v1:" + project_id
}

///|
fn delivery_cut_storage_notice(model : Model) -> String? {
  model.delivery_cut_storage_notices.get(model.selected_project_id)
}

///|
fn set_delivery_cut_storage_notice(
  model : Model,
  project_id : String,
  notice : String?,
) -> Model {
  let notices = model.delivery_cut_storage_notices.copy()
  match notice {
    Some(message) => notices[project_id] = message
    None => notices.remove(project_id)
  }
  { ..model, delivery_cut_storage_notices: notices, }
}

///|
fn encode_delivery_cut_draft(
  project_id : String,
  draft : DeliveryCutDraftSet,
) -> String {
  (
    {
      "contract": "mooncast.delivery-cut-draft.v1",
      "project_id": project_id,
      "draft": ToJson::to_json(draft),
    } : Json).stringify()
}

///|
fn decode_delivery_cut_draft(
  project_id : String,
  raw : String,
) -> Result[DeliveryCutDraftSet, String] {
  // Include worst-case JSON escaping of all bounded incomplete input fields.
  if raw.length() > 262144 {
    return Err("Saved cut draft is too large.")
  }
  let parsed = @json.parse(raw) catch {
    _ => return Err("Saved cut draft is unreadable.")
  }
  guard parsed
    is {
      "contract": "mooncast.delivery-cut-draft.v1",
      "project_id": String(id),
      "draft": draft,
      ..
    } &&
    id == project_id else {
    return Err("Saved cut draft belongs to another project or version.")
  }
  let draft : DeliveryCutDraftSet = @json.from_json(draft) catch {
    _ => return Err("Saved cut draft has invalid fields.")
  }
  if draft.cuts.length() > 12 || draft.master_sha256.length() > 512 {
    return Err("Saved cut draft exceeds its bounds.")
  }
  let keys : Array[Int] = []
  for cut in draft.cuts {
    if cut.key < 1 ||
      cut.key > 1000000 ||
      keys.contains(cut.key) ||
      [cut.cut_id, cut.channel, cut.source_variant, cut.start, cut.end].any(value => {
        value.length() > 512
      }) {
      return Err(
        "Saved cut draft has invalid row identities or oversized fields.",
      )
    }
    keys.push(cut.key)
  }
  Ok(draft)
}

///|
fn restore_delivery_cut_drafts(
  model : Model,
  project_id : String,
  reply : String,
) -> Model {
  let parsed = @json.parse(reply) catch { _ => Json::null() }
  let result = match parsed {
    { "missing": True, .. } => Ok({ master_sha256: "", cuts: [], })
    { "value": String(value), .. } =>
      decode_delivery_cut_draft(project_id, value)
    { "error": String(message), .. } => Err(message)
    _ => Err("Saved cuts could not be read.")
  }
  let drafts = model.delivery_cut_drafts.copy()
  match result {
    Ok(draft) => {
      drafts[project_id] = draft
      set_delivery_cut_storage_notice(
        { ..model, delivery_cut_drafts: drafts, },
        project_id,
        None,
      )
    }
    Err(message) => {
      drafts[project_id] = { master_sha256: "", cuts: [], }
      set_delivery_cut_storage_notice(
        {
          ..model,
          delivery_cut_drafts: drafts,
          delivery_cut_storage_blocked: model.delivery_cut_storage_blocked +
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
fn load_delivery_cut_drafts(model : Model, project_id : String) -> Model {
  if project_id == "" || model.delivery_cut_drafts.contains(project_id) {
    return model
  }
  restore_delivery_cut_drafts(
    model,
    project_id,
    delivery_cut_storage_read(delivery_cut_storage_key(project_id)),
  )
}

///|
fn save_delivery_cut_drafts(model : Model) -> Model {
  let project_id = model.selected_project_id
  if project_id == "" || model.busy {
    return model
  }
  if model.delivery_cut_storage_blocked.contains(project_id) {
    return set_delivery_cut_storage_notice(
      model,
      project_id,
      Some(
        "Autosave is paused for this project because its saved draft could not be read. Existing saved bytes are preserved; keep this tab open.",
      ),
    )
  }
  guard model.delivery_cut_drafts.get(project_id) is Some(draft) else {
    return model
  }
  let error = delivery_cut_storage_write(
    delivery_cut_storage_key(project_id),
    encode_delivery_cut_draft(project_id, draft),
  )
  set_delivery_cut_storage_notice(
    model,
    project_id,
    if error == "" {
      None
    } else {
      Some(error)
    },
  )
}
