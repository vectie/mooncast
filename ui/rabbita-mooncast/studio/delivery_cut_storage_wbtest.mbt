///|
extern "js" fn install_cut_storage(mode : String) -> Unit =
  #| mode => {
  #|   globalThis.__cutOldStorage = Object.getOwnPropertyDescriptor(globalThis,"localStorage");
  #|   globalThis.__cutValues = new Map(); globalThis.__cutMode = mode;
  #|   Object.defineProperty(globalThis,"localStorage",{configurable:true,value:{
  #|     getItem(key) { if(globalThis.__cutMode === "read-error") throw new Error("blocked"); return globalThis.__cutValues.get(key) ?? null; },
  #|     setItem(key,value) { if(globalThis.__cutMode === "write-error") throw new Error("quota"); globalThis.__cutValues.set(key,value); }
  #|   }});
  #| }

///|
extern "js" fn restore_cut_storage() -> Unit =
  #| () => { if(globalThis.__cutOldStorage) Object.defineProperty(globalThis,"localStorage",globalThis.__cutOldStorage); else delete globalThis.localStorage; }

///|
extern "js" fn cut_storage_mode(mode : String) -> Unit = "mode => { globalThis.__cutMode = mode; }"

///|
test "cut field limits and worst-case escaped drafts remain bounded and round trippable" {
  let model = cut_fixture_model("1", "3")
  for (field, length) in [("name", 80), ("channel", 120)] {
    let valid = edit_delivery_cuts(
      model,
      EditDeliveryCut(1, field, Array::make(length, "a").join("")),
    )
    assert_true(delivery_cut_selection(valid, valid.project.unwrap()) is Ok(_))
    let invalid = edit_delivery_cuts(
      model,
      EditDeliveryCut(1, field, Array::make(length + 1, "a").join("")),
    )
    assert_true(
      delivery_cut_selection(invalid, invalid.project.unwrap()) is Err(_),
    )
  }
  let escaped = Array::make(512, "\u{0001}").join("")
  let row = delivery_cut_drafts(model).cuts[0]
  let draft = {
    master_sha256: "sha256:master-file",
    cuts: Array::makei(12, i => {
      ..row,
      key: i + 1,
      selected: false,
      cut_id: escaped,
      channel: escaped,
      source_variant: escaped,
      start: escaped,
      end: escaped,
    }),
  }
  let encoded = encode_delivery_cut_draft(model.selected_project_id, draft)
  assert_true(encoded.length() > 65536)
  assert_eq(
    decode_delivery_cut_draft(model.selected_project_id, encoded),
    Ok(draft),
  )
}

///|
test "cut draft codec retains incomplete excluded rows exact strings and master identity" {
  let model = edit_delivery_cuts(
    cut_fixture_model("12.250", "42.750"),
    AddDeliveryCut,
  )
  let model = edit_delivery_cuts(model, ToggleDeliveryCut(2))
  let draft = delivery_cut_drafts(model)
  let encoded = encode_delivery_cut_draft(model.selected_project_id, draft)
  assert_eq(
    decode_delivery_cut_draft(model.selected_project_id, encoded),
    Ok(draft),
  )
  assert_true(decode_delivery_cut_draft("other-project", encoded) is Err(_))
  assert_true(
    decode_delivery_cut_draft(model.selected_project_id, "not JSON") is Err(_),
  )
  let duplicate = { ..draft, cuts: [draft.cuts[0], draft.cuts[0]], }
  assert_true(
    decode_delivery_cut_draft(
      model.selected_project_id,
      encode_delivery_cut_draft(model.selected_project_id, duplicate),
    )
    is Err(_),
  )
  let too_many = { ..draft, cuts: Array::make(13, draft.cuts[0]), }
  assert_true(
    decode_delivery_cut_draft(
      model.selected_project_id,
      encode_delivery_cut_draft(model.selected_project_id, too_many),
    )
    is Err(_),
  )
}

///|
test "browser storage round trip reload and independent project keys retain named cuts" {
  install_cut_storage("ok")
  let model = save_delivery_cut_drafts(cut_fixture_model("12.250", "42.750"))
  assert_eq(delivery_cut_storage_notice(model), None)
  let loaded = load_delivery_cut_drafts(
    initial_model(),
    model.selected_project_id,
  )
  assert_eq(
    loaded.delivery_cut_drafts.get(model.selected_project_id),
    model.delivery_cut_drafts.get(model.selected_project_id),
  )
  let loaded = load_delivery_cut_drafts(loaded, "other-project")
  assert_eq(
    loaded.delivery_cut_drafts.get("other-project").unwrap().cuts.length(),
    0,
  )
  let reloaded = {
    ..loaded,
    project: model.project,
    selected_project_id: model.selected_project_id,
  }
  assert_eq(
    delivery_cut_selection(reloaded, model.project.unwrap()),
    delivery_cut_selection(model, model.project.unwrap()),
  )
  restore_cut_storage()
}

///|
test "maximum accepted row key remains round trippable after adding another cut" {
  let model = cut_fixture_model("1", "3")
  let draft = delivery_cut_drafts(model)
  let draft = { ..draft, cuts: [{ ..draft.cuts[0], key: 1000000, }], }
  let restored = restore_delivery_cut_drafts(
    model,
    model.selected_project_id,
    (
      { "value": encode_delivery_cut_draft(model.selected_project_id, draft) } :
      Json).stringify(),
  )
  let added = edit_delivery_cuts(restored, AddDeliveryCut)
  let current = delivery_cut_drafts(added)
  assert_eq(current.cuts.length(), 2)
  assert_eq(current.cuts[1].key, 1)
  assert_eq(
    decode_delivery_cut_draft(
      model.selected_project_id,
      encode_delivery_cut_draft(model.selected_project_id, current),
    ),
    Ok(current),
  )
}

///|
test "quota failure preserves in-memory edits and successful retry stores latest values" {
  install_cut_storage("write-error")
  let model = save_delivery_cut_drafts(cut_fixture_model("1", "3"))
  assert_true(delivery_cut_storage_notice(model) is Some(_))
  let edited = edit_delivery_cuts(
    model,
    EditDeliveryCut(1, "name", "latest-teaser"),
  )
  cut_storage_mode("ok")
  let saved = save_delivery_cut_drafts(edited)
  assert_eq(delivery_cut_storage_notice(saved), None)
  let restored = load_delivery_cut_drafts(
    initial_model(),
    saved.selected_project_id,
  )
  assert_eq(
    restored.delivery_cut_drafts.get(saved.selected_project_id).unwrap().cuts[0].cut_id,
    "latest-teaser",
  )
  restore_cut_storage()
}

///|
test "read errors and malformed saved drafts never overwrite existing bytes" {
  install_cut_storage("ok")
  let model = cut_fixture_model("1", "3")
  let key = delivery_cut_storage_key(model.selected_project_id)
  assert_eq(delivery_cut_storage_write(key, "unreadable original bytes"), "")
  let restored = load_delivery_cut_drafts(
    initial_model(),
    model.selected_project_id,
  )
  assert_true(
    restored.delivery_cut_storage_blocked.contains(model.selected_project_id),
  )
  let editable = {
    ..restored,
    project: model.project,
    selected_project_id: model.selected_project_id,
  }
  let edited = save_delivery_cut_drafts(
    edit_delivery_cuts(editable, AddDeliveryCut),
  )
  assert_eq(delivery_cut_drafts(edited).cuts.length(), 1)
  let different = load_delivery_cut_drafts(edited, "different-project")
  let different = { ..different, selected_project_id: "different-project", }
  assert_eq(delivery_cut_storage_notice(different), None)
  let returned = {
    ..different,
    selected_project_id: model.selected_project_id,
  }
  assert_true(delivery_cut_storage_notice(returned) is Some(_))
  assert_true(
    delivery_cut_storage_read(key).contains("unreadable original bytes"),
  )
  cut_storage_mode("read-error")
  let blocked = load_delivery_cut_drafts(
    initial_model(),
    model.selected_project_id,
  )
  assert_true(
    blocked.delivery_cut_storage_blocked.contains(model.selected_project_id),
  )
  restore_cut_storage()
}
