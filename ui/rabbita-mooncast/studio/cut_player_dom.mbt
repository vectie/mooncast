///|
/// A scoped HTML media adapter. It owns no network client and cannot create a
/// delivery build. Rabbita unloads it when the generation, row or project ends.
extern "js" fn cut_player_dom_watch(
  id : String,
  notify : (String, Double, Double) -> Unit,
) -> () -> Unit =
  #| (id, notify) => {
  #|   if (typeof document === "undefined") return () => {};
  #|   let active = true, video = null, observer = null, timer = null, frame = null;
  #|   const handlers = [];
  #|   const state = { active: true, end: null, serial: 0 };
  #|   const send = kind => { if (active && video) notify(kind, video.currentTime, video.duration); };
  #|   const stopRange = () => {
  #|     state.end = null; state.serial++;
  #|     if (frame !== null) cancelAnimationFrame(frame);
  #|     frame = null;
  #|   };
  #|   const checkEnd = () => {
  #|     if (!active || !video || state.end === null) return;
  #|     if (video.currentTime >= state.end) {
  #|       const end = state.end; stopRange(); video.pause();
  #|       if (video.currentTime !== end) video.currentTime = end;
  #|       send("time");
  #|     }
  #|   };
  #|   const tick = () => {
  #|     frame = null; checkEnd();
  #|     if (active && state.end !== null) frame = requestAnimationFrame(tick);
  #|   };
  #|   state.stop = stopRange;
  #|   state.start = end => { stopRange(); state.end = end; frame = requestAnimationFrame(tick); };
  #|   const attach = () => {
  #|     if (!active || video) return;
  #|     const node = document.getElementById(id);
  #|     if (!node) return;
  #|     video = node; video.__mooncastCutPlayback = state;
  #|     if (observer) { observer.disconnect(); observer = null; }
  #|     const on = (name, handler) => { video.addEventListener(name, handler); handlers.push([name, handler]); };
  #|     const metadata = () => {
  #|       if (Number.isFinite(video.duration) && video.duration > 0 && video.readyState >= 1) {
  #|         clearTimeout(timer); timer = null; send("metadata");
  #|       } else { stopRange(); video.pause(); send("unavailable"); }
  #|     };
  #|     on("loadedmetadata", metadata);
  #|     on("durationchange", () => { if (video.readyState >= 1) metadata(); });
  #|     on("timeupdate", () => { checkEnd(); send("time"); });
  #|     on("seeked", () => { checkEnd(); send("time"); });
  #|     on("pause", () => { if (video.paused) stopRange(); });
  #|     on("ended", () => { stopRange(); send("time"); });
  #|     on("error", () => { clearTimeout(timer); stopRange(); video.pause(); send("error"); });
  #|     timer = setTimeout(() => { if (active && video.readyState < 1) { stopRange(); video.pause(); send("unavailable"); } }, 8000);
  #|     if (video.error) send("error");
  #|     else if (video.readyState >= 1) metadata();
  #|   };
  #|   observer = new MutationObserver(attach);
  #|   observer.observe(document.documentElement, {childList:true, subtree:true});
  #|   attach();
  #|   return () => {
  #|     if (!active) return;
  #|     active = false; state.active = false; stopRange(); clearTimeout(timer);
  #|     if (observer) observer.disconnect();
  #|     if (video) {
  #|       for (const [name, handler] of handlers) video.removeEventListener(name, handler);
  #|       video.pause(); delete video.__mooncastCutPlayback;
  #|       video.removeAttribute("src"); video.load();
  #|     }
  #|   };
  #| }

///|
extern "js" fn cut_player_dom_command(
  id : String,
  action : String,
  start_ms : Int,
  end_ms : Int,
  notify : (String, Double, Double) -> Unit,
) -> Unit =
  #| (id, action, startMs, endMs, notify) => {
  #|   if (typeof document === "undefined") return;
  #|   const video = document.getElementById(id);
  #|   const state = video && video.__mooncastCutPlayback;
  #|   if (!state || !state.active) return;
  #|   state.stop();
  #|   if (action === "stop") { video.pause(); return; }
  #|   if (video.error || video.readyState < 1 || !Number.isFinite(video.duration) || video.duration <= 0) {
  #|     video.pause(); notify("unavailable", video.currentTime, video.duration); return;
  #|   }
  #|   if (action === "mark-start" || action === "mark-end") {
  #|     video.pause(); notify(action, video.currentTime, video.duration); return;
  #|   }
  #|   if (action !== "preview" || startMs < 0 || endMs <= startMs || endMs - startMs > 180000 || endMs / 1000 > video.duration) return;
  #|   const serial = state.serial;
  #|   try {
  #|     video.pause(); video.currentTime = startMs / 1000;
  #|     state.start(endMs / 1000);
  #|     const playSerial = state.serial;
  #|     const result = video.play();
  #|     if (result && result.catch) result.catch(() => {
  #|       if (state.active && state.serial === playSerial) {
  #|         state.stop(); video.pause(); notify("play-error", video.currentTime, video.duration);
  #|       }
  #|     });
  #|   } catch (_) {
  #|     if (state.active && state.serial >= serial) {
  #|       state.stop(); video.pause(); notify("play-error", video.currentTime, video.duration);
  #|     }
  #|   }
  #| }
