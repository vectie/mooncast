///|
extern "js" fn delivery_transcript_native_wire(name : String) -> String =
  #| name => {
  #|   const fs=process.getBuiltinModule("node:fs");
  #|   const variable=name==="builds" ? "MOONCAST_NATIVE_DELIVERY_BUILDS" : "MOONCAST_NATIVE_DELIVERY_CAPTION";
  #|   const filename=name==="builds" ? "delivery-builds.native.json" : "delivery-caption.native.json";
  #|   return fs.readFileSync(process.env[variable] || "studio/fixtures/"+filename,"utf8");
  #| }

///|
test "native trimmed caption wire flows into compiled transcript and event bridge at output zero" {
  let wire : DeliveryListProjection = @json.from_json(
    @json.parse(delivery_transcript_native_wire("builds")),
  )
  let caption : DeliveryCaptionPreviewProjection = @json.from_json(
    @json.parse(delivery_transcript_native_wire("caption")),
  )
  let build = wire.builds
    .iter()
    .find_first(b => b.videos.unwrap_or([]).any(v => v.output_id == "later"))
    .unwrap()
  let model = {
    ..initial_model(),
    tab: Delivery,
    selected_project_id: "media-route-project",
    delivery_builds: wire.builds,
  }
  let selected = step(model, SelectDeliveryMedia(build.build_id, "later"))
  let video = selected_delivery_video(selected).unwrap()
  assert_eq(video.in_seconds, Some(2.0))
  assert_eq(video.out_seconds, Some(4.0))
  let g = selected.delivery_media_generation
  let mut ready = step(
    selected,
    LoadedDeliveryMediaCaptions(
      g,
      video.captions.unwrap().preview_url,
      Ok(caption),
    ),
  )
  assert_eq(ready.delivery_transcript.cues.length(), 1)
  assert_eq(ready.delivery_transcript.cues[0].start_ms, 0)
  assert_eq(ready.delivery_transcript.cues[0].end_ms, 2000)
  install_cut_player_dom()
  defer restore_cut_player_dom()
  delivery_dom_fixture_duration(2.0)
  let id = delivery_player_id(g)
  delivery_dom_fixture_bind(id)
  let notify = (kind, seconds, duration) => {
    ready = step(ready, DeliveryPlayerEvent(g, kind, seconds, duration))
  }
  let cleanup = delivery_player_dom_watch(id, notify)
  defer cleanup()
  cut_player_dom_fixture_event("timeupdate", 1.0)
  let effects : Array[String] = []
  let restore_network = delivery_network_trap()
  defer restore_network()
  let scheduler : &@cmd.Scheduler = DeliveryFixtureScheduler::{ effects, }
  let emit = @cmd.Emit(message => {
    ready = step(ready, message)
    @rabbita.none
  })
  let (command, unchanged) = update(emit, SeekDeliveryCue(g, 0), ready)
  assert_eq(unchanged.delivery_transcript.seconds, 1.0)
  scheduler.add(command)
  assert_eq(effects, ["after-render"])
  assert_eq(delivery_network_calls(), 0)
  assert_true(
    @json.parse(cut_player_dom_fixture_status())
    is { "time": Number(0, ..), "plays": Number(0, ..), .. },
  )
  assert_eq(ready.delivery_transcript.seconds, 1.0)
  cut_player_dom_fixture_event("seeked", 0.0)
  assert_eq(ready.delivery_transcript.seconds, 0.0)
  assert_true(
    delivery_cue_active(
      ready.delivery_transcript.cues[0],
      ready.delivery_transcript,
    ),
  )
  cut_player_dom_fixture_event("timeupdate", 2.0)
  assert_false(
    delivery_cue_active(
      ready.delivery_transcript.cues[0],
      ready.delivery_transcript,
    ),
  )
  let html = rendered(render_delivery_media(_ => @rabbita.none, ready, build))
  assert_true(html.contains("Seek 00:00:00,000"))
  assert_true(html.contains("你好 🌙 &amp;"))
  assert_true(html.contains(video.preview_url))
  assert_true(html.contains(video.captions.unwrap().download_url))
  assert_eq(ready.command_sequence, model.command_sequence)
  assert_false(ready.busy)
  assert_false(ready.operator.human_confirmed)
  println(
    "Native trimmed SRT accepted unchanged; source in=2, transcript seek=0: " +
    video.preview_url,
  )
}
