///|
/// A deterministic HTMLMediaElement adapter fixture. Native HTTP separately
/// verifies the retained MP4 and release assets. Cloud-browser restrictions
/// prevented real Chromium playback and pixel acceptance in this environment.
extern "js" fn install_cut_player_dom() -> Unit =
  #| () => {
  #|   globalThis.__cutDomOld = Object.fromEntries(["document","MutationObserver","requestAnimationFrame","cancelAnimationFrame"].map(k => [k,Object.getOwnPropertyDescriptor(globalThis,k)]));
  #|   const listeners = new Map(), frames = new Map(); let seq = 0;
  #|   const video = { currentTime:0, duration:4, readyState:1, error:null, paused:true, src:"verified.mp4", plays:0, loads:0,
  #|     addEventListener(name, fn) { listeners.set(name, fn); }, removeEventListener(name) { listeners.delete(name); },
  #|     pause() { this.paused = true; }, play() { this.paused = false; this.plays++; return Promise.resolve(); },
  #|     load() { this.loads++; }, removeAttribute(name) { if(name === "src") this.src = ""; } };
  #|   globalThis.__cutDom = {video,listeners,frames};
  #|   Object.defineProperty(globalThis,"document",{configurable:true,value:{documentElement:{},getElementById:id=>id === "fixture" ? video : null}});
  #|   Object.defineProperty(globalThis,"MutationObserver",{configurable:true,value:class {observe(){} disconnect(){}}});
  #|   Object.defineProperty(globalThis,"requestAnimationFrame",{configurable:true,value:fn=>{frames.set(++seq,fn);return seq;}});
  #|   Object.defineProperty(globalThis,"cancelAnimationFrame",{configurable:true,value:id=>frames.delete(id)});
  #| }

///|
extern "js" fn cut_player_dom_fixture_event(
  name : String,
  seconds : Double,
) -> Unit =
  #| (name, seconds) => { const d=globalThis.__cutDom; d.video.currentTime=seconds; d.listeners.get(name)?.(); }

///|
extern "js" fn cut_player_dom_fixture_status() -> String =
  #| () => { const d=globalThis.__cutDom; return JSON.stringify({time:d.video.currentTime,paused:d.video.paused,plays:d.video.plays,loads:d.video.loads,src:d.video.src,listeners:d.listeners.size,frames:d.frames.size}); }

///|
extern "js" fn restore_cut_player_dom() -> Unit =
  #| () => { for(const [k,v] of Object.entries(globalThis.__cutDomOld)) { if(v) Object.defineProperty(globalThis,k,v); else delete globalThis[k]; } delete globalThis.__cutDom; delete globalThis.__cutDomOld; }

///|
test "DOM range starts at in point pauses exactly at out point and close releases all resources" {
  install_cut_player_dom()
  defer restore_cut_player_dom()
  let events : Array[(String, Double, Double)] = []
  let notify = (kind, seconds, duration) => {
    events.push((kind, seconds, duration))
  }
  let cleanup = cut_player_dom_watch("fixture", notify)
  assert_eq(events[0], ("metadata", 0.0, 4.0))
  cut_player_dom_command("fixture", "preview", 1250, 2501, notify)
  assert_true(
    @json.parse(cut_player_dom_fixture_status())
    is { "time": Number(1.25), "paused": False, "plays": Number(1), .. },
  )
  cut_player_dom_fixture_event("timeupdate", 2.7)
  assert_true(
    @json.parse(cut_player_dom_fixture_status())
    is { "time": Number(2.501), "paused": True, "frames": Number(0), .. },
  )
  cut_player_dom_command("fixture", "mark-start", 0, 0, notify)
  assert_eq(events.last(), Some(("mark-start", 2.501, 4.0)))
  cleanup()
  assert_true(
    @json.parse(cut_player_dom_fixture_status())
    is {
      "paused": True,
      "loads": Number(1),
      "src": String(""),
      "listeners": Number(0),
      "frames": Number(0),
      ..
    },
  )
  let count = events.length()
  cut_player_dom_fixture_event("timeupdate", 3.0)
  cut_player_dom_command("fixture", "mark-end", 0, 0, notify)
  assert_eq(events.length(), count)
  cleanup()
}
