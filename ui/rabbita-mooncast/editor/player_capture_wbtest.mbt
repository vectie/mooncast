///|
extern "js" fn capture_fixture_install() -> Unit =
  #|() => {
  #| const f={saved:{document:globalThis.document,AudioContext:globalThis.AudioContext,state:globalThis.__mooncastPlayerAudio},events:{}};
  #| f.video={paused:false,seeking:false,currentTime:0,addEventListener:(name,fn)=>f.events[name]=fn};
  #| globalThis.document={getElementById:()=>f.video};delete globalThis.__mooncastPlayerAudio;
  #| globalThis.AudioContext=class{constructor(){this.sampleRate=16000;this.destination={};}resume(){return Promise.resolve();}createMediaElementSource(){return {connect(){}};}createGain(){return {gain:{value:1},connect(){}};}createScriptProcessor(){return f.processor={connect(){}};}};
  #| globalThis.__mooncastCaptureFixture=f;
  #| }

///|
extern "js" fn capture_fixture_feed(samples : Int) -> Unit =
  #|n => {const f=globalThis.__mooncastCaptureFixture;f.video.currentTime+=n/16000;f.processor.onaudioprocess({inputBuffer:{getChannelData:()=>new Float32Array(n).fill(.2)}});}

///|
extern "js" fn capture_fixture_seek() -> Unit =
  #|() => globalThis.__mooncastCaptureFixture.events.seeking()

///|
extern "js" fn capture_fixture_restore() -> Unit =
  #|() => {const f=globalThis.__mooncastCaptureFixture;globalThis.document=f.saved.document;globalThis.AudioContext=f.saved.AudioContext;globalThis.__mooncastPlayerAudio=f.saved.state;delete globalThis.__mooncastCaptureFixture;}

///|
test "playback capture uses bounded WAV windows retains only latest queued audio and clears on seek" {
  capture_fixture_install()
  defer capture_fixture_restore()
  player_audio_resume()
  assert_eq(player_audio_poll(1, true), "")
  capture_fixture_feed(64000)
  capture_fixture_feed(64000)
  assert_eq(player_audio_poll(1, false), "")
  let raw = player_audio_poll(1, true)
  let chunk = @json.parse(raw)
  guard chunk is { "audio": String(audio), "key": String(key), .. } else { fail("Missing WAV") }
  assert_true(audio.has_prefix("UklGR"))
  assert_true(audio.length() < 180000)
  assert_eq(key, "1:8:8")
  assert_eq(player_audio_poll(1, true), "")
  capture_fixture_feed(64000)
  capture_fixture_seek()
  assert_eq(player_audio_poll(1, true), "{\"reset\":true}")
  assert_eq(player_audio_poll(2, true), "")
  player_audio_stop()
  capture_fixture_feed(64000)
  assert_eq(player_audio_poll(2, true), "")
}
