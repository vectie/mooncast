///|
/// Read the actual native HTTP response files in transport verification. Normal
/// test runs use retained verbatim responses from the same synthetic fixture.
/// No URL or digest is rewritten to agree with the UI's expectation.
extern "js" fn cut_player_native_wire(name : String) -> String =
  #| name => {
  #|   const fs = process.getBuiltinModule("node:fs");
  #|   const variable = name === "project" ? "MOONCAST_NATIVE_PROJECT_WIRE" : "MOONCAST_NATIVE_PLAYBACK_WIRE";
  #|   const filename = name === "project" ? "promoted-master-project.native.json" : "promoted-master-playback.native.json";
  #|   return fs.readFileSync(process.env[variable] || "studio/fixtures/" + filename, "utf8");
  #| }

///|
test "actual native project and playback wire open the released player and feed seek mark preview handlers" {
  let project : ProjectProjection = @json.from_json(
    @json.parse(cut_player_native_wire("project")),
  )
  let projection : PromotedMasterPlayback = @json.from_json(
    @json.parse(cut_player_native_wire("playback")),
  )
  let initial = {
    ..initial_model(),
    tab: Delivery,
    loading: false,
    selected_project_id: project.id,
    project: Some(project),
  }
  let initial = edit_delivery_cuts(initial, AddDeliveryCut)
  let initial = edit_delivery_cuts(
    initial,
    EditDeliveryCut(1, "start", "1.250"),
  )
  let initial = edit_delivery_cuts(initial, EditDeliveryCut(1, "end", "3.750"))
  let pending = step(initial, SelectCutPlayer(1))
  let mut model = step(
    pending,
    LoadedCutPlayer(pending.cut_player_generation, Ok(projection)),
  )
  assert_true(
    model.cut_player.unwrap().projection is Some(_),
    msg="Actual unmodified native playback response must be accepted",
  )
  assert_true(
    rendered(render_cut_player(_ => @rabbita.none, model)).contains(
      projection.media_url,
    ),
  )
  install_cut_storage("ok")
  defer restore_cut_storage()
  install_cut_player_dom()
  defer restore_cut_player_dom()
  let generation = model.cut_player_generation
  let notify = (kind, seconds, duration) => {
    model = step(model, CutPlayerEvent(generation, kind, seconds, duration))
  }
  let cleanup = cut_player_dom_watch("fixture", notify)
  defer cleanup()
  assert_true(model.cut_player.unwrap().ready)
  cut_player_dom_fixture_event("seeked", 1.2345)
  cut_player_dom_command("fixture", "mark-start", 0, 0, notify)
  assert_eq(delivery_cut_drafts(model).cuts[0].start, "1.235")
  assert_eq(delivery_cut_drafts(model).cuts[0].end, "3.750")
  cut_player_dom_fixture_event("seeked", 2.501)
  cut_player_dom_command("fixture", "mark-end", 0, 0, notify)
  assert_eq(delivery_cut_drafts(model).cuts[0].end, "2.501")
  let range = cut_player_range(model, model.cut_player.unwrap()).unwrap()
  assert_eq(range, (1235, 2501))
  cut_player_dom_command("fixture", "preview", range.0, range.1, notify)
  cut_player_dom_fixture_event("timeupdate", 3.0)
  assert_true(
    @json.parse(cut_player_dom_fixture_status())
    is { "time": Number(2.501), "paused": True, .. },
  )
  assert_eq(model.command_sequence, initial.command_sequence)
  assert_false(model.busy)
  assert_true(model.delivery_builds.is_empty())
  assert_true(delivery_cut_storage_notice(model) is None)
  println("Native wire accepted unchanged: " + projection.media_url)
}
