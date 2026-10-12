///|
extern "js" fn delivery_network_trap() -> () -> Unit =
  #| () => {
  #|   const old=globalThis.fetch;globalThis.__deliveryNetworkCalls=0;
  #|   globalThis.fetch=()=>{globalThis.__deliveryNetworkCalls++;throw new Error("Network forbidden during caption navigation");};
  #|   return ()=>{globalThis.fetch=old;delete globalThis.__deliveryNetworkCalls;};
  #| }

///|
extern "js" fn delivery_network_calls() -> Int =
  #| () => globalThis.__deliveryNetworkCalls

///|
struct DeliveryFixtureScheduler {
  effects : Array[String]
}

///|
impl @cmd.Scheduler for DeliveryFixtureScheduler with fn run_effect(
  self,
  kind,
  action,
) {
  self.effects.push(
    match kind {
      AfterRender => "after-render"
      Immediately => "immediately"
    },
  )
  action(self)
}

///|
impl @cmd.Scheduler for DeliveryFixtureScheduler with fn queue_message(
  _self,
  _id,
  send,
) {
  send()
}

///|
impl @cmd.Scheduler for DeliveryFixtureScheduler with fn drain_message(_self) {
  ()
}

///|
impl @cmd.Scheduler for DeliveryFixtureScheduler with fn hooks(_self) {
  { url_request: None, url_changed: None, }
}

///|
extern "js" fn delivery_dom_fixture_bind(id : String) -> Unit =
  #| id => { document.getElementById = key => key===id ? globalThis.__cutDom.video : null; }

///|
extern "js" fn delivery_dom_fixture_duration(seconds : Double) -> Unit =
  #| seconds => { globalThis.__cutDom.video.duration=seconds; }

///|
extern "js" fn delivery_dom_fixture_mode(mode : String) -> Unit =
  #| mode => {
  #|   const d=globalThis.__cutDom;
  #|   if(mode==="unavailable"){d.video.readyState=0;d.video.duration=NaN;return;}
  #|   if(mode==="ready"){d.video.readyState=1;d.video.duration=4;return;}
  #|   if(mode==="throw"){let time=d.video.currentTime;Object.defineProperty(d.video,"currentTime",{configurable:true,get:()=>time,set:()=>{throw new Error("seek failed")}});return;}
  #|   if(mode==="reset"){Object.defineProperty(d.video,"currentTime",{configurable:true,writable:true,value:0});return;}
  #|   if(mode==="retain"){globalThis.__deliveryStaleCallback=d.listeners.get("timeupdate");return;}
  #|   if(mode==="stale"){globalThis.__deliveryStaleCallback?.();delete globalThis.__deliveryStaleCallback;}
  #| }

///|
test "completed-output event bridge seeks zero and cue times without playing, survives failed seeks and releases stale callbacks" {
  install_cut_player_dom()
  defer restore_cut_player_dom()
  let mut model = transcript_fixture_model()
  let g = model.delivery_media_generation
  let notify = (kind, seconds, duration) => {
    model = step(model, DeliveryPlayerEvent(g, kind, seconds, duration))
  }
  let cleanup = delivery_player_dom_watch("fixture", notify)
  assert_true(model.delivery_transcript.ready)
  delivery_player_dom_seek("fixture", 3000, notify)
  cut_player_dom_fixture_event("seeked", 3.0)
  assert_eq(model.delivery_transcript.seconds, 3.0)
  delivery_player_dom_seek("fixture", 0, notify)
  cut_player_dom_fixture_event("seeked", 0.0)
  assert_eq(model.delivery_transcript.seconds, 0.0)
  assert_true(
    @json.parse(cut_player_dom_fixture_status())
    is { "time": Number(0, ..), "plays": Number(0, ..), .. },
  )
  delivery_dom_fixture_mode("throw")
  delivery_player_dom_seek("fixture", 1000, notify)
  assert_true(model.delivery_transcript.media_error is Some(_))
  assert_eq(model.delivery_transcript.seconds, 0.0)
  delivery_dom_fixture_mode("reset")
  delivery_player_dom_seek("fixture", 1000, notify)
  cut_player_dom_fixture_event("seeked", 1.0)
  assert_eq(model.delivery_transcript.media_error, None)
  delivery_player_dom_seek("fixture", 3000, notify)
  cut_player_dom_fixture_event("seeked", 2.0)
  assert_true(model.delivery_transcript.media_error is Some(_))
  delivery_dom_fixture_mode("retain")
  cleanup()
  let seconds = model.delivery_transcript.seconds
  delivery_dom_fixture_mode("stale")
  delivery_player_dom_seek("fixture", 3000, notify)
  assert_eq(model.delivery_transcript.seconds, seconds)
  assert_true(
    @json.parse(cut_player_dom_fixture_status())
    is {
      "listeners": Number(0, ..),
      "src": String(""),
      "loads": Number(1, ..),
      ..
    },
  )
  cleanup()
  assert_false(model.busy)
}

///|
test "metadata-unavailable completed video disables navigation until explicit fresh selection" {
  install_cut_player_dom()
  defer restore_cut_player_dom()
  delivery_dom_fixture_mode("unavailable")
  let mut model = transcript_fixture_model()
  let g = model.delivery_media_generation
  let notify = (kind, seconds, duration) => {
    model = step(model, DeliveryPlayerEvent(g, kind, seconds, duration))
  }
  let cleanup = delivery_player_dom_watch("fixture", notify)
  defer cleanup()
  delivery_player_dom_seek("fixture", 0, notify)
  assert_false(model.delivery_transcript.ready)
  assert_true(model.delivery_transcript.media_error is Some(_))
  delivery_dom_fixture_mode("ready")
  cut_player_dom_fixture_event("loadedmetadata", 0.0)
  assert_false(model.delivery_transcript.ready)
  let retried = step(model, RetryDeliveryMedia)
  assert_eq(retried.delivery_transcript.media_error, None)
}
