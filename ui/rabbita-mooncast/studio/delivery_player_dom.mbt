///|
/// Read-only completed-output media bridge. Generation-scoped DOM ownership
/// prevents detached media, timeout and seek callbacks from reaching a new output.
extern "js" fn delivery_player_dom_watch(
  id : String,
  notify : (String, Double, Double) -> Unit,
) -> () -> Unit =
  #| (id, notify) => {
  #|   if (typeof document === "undefined") return () => {};
  #|   let video = null, observer = null, timer = null;
  #|   const handlers = [], state = {active:true, pending:null, seekTimer:null};
  #|   const send = kind => { if (state.active && video) notify(kind, video.currentTime, video.duration); };
  #|   state.send = send;
  #|   state.cancel = () => { clearTimeout(state.seekTimer); state.seekTimer=null; state.pending=null; };
  #|   const attach = () => {
  #|     if (!state.active || video) return;
  #|     const node = document.getElementById(id); if (!node) return;
  #|     video=node; video.__mooncastDeliveryPlayback=state;
  #|     if (observer) { observer.disconnect(); observer=null; }
  #|     const on = (name, fn) => { video.addEventListener(name, fn); handlers.push([name,fn]); };
  #|     const metadata = () => {
  #|       if (video.readyState>=1 && Number.isFinite(video.duration) && video.duration>0) { clearTimeout(timer); send("metadata"); }
  #|       else send("unavailable");
  #|     };
  #|     on("loadedmetadata",metadata); on("durationchange",()=>{if(video.readyState>=1)metadata();});
  #|     on("timeupdate",()=>{if(state.pending===null)send("time");}); on("ended",()=>send("time"));
  #|     on("seeked",()=>{
  #|       const target=state.pending; state.cancel();
  #|       if(target!==null && Math.abs(video.currentTime-target)>0.05) send("seek-error");
  #|       else send("seeked");
  #|     });
  #|     on("error",()=>{clearTimeout(timer);state.cancel();send("error");});
  #|     timer=setTimeout(()=>{if(state.active && video.readyState<1)send("unavailable");},8000);
  #|     if(video.error) send("error"); else if(video.readyState>=1) metadata();
  #|   };
  #|   observer=new MutationObserver(attach); observer.observe(document.documentElement,{childList:true,subtree:true}); attach();
  #|   return ()=>{
  #|     if(!state.active)return; state.active=false; state.cancel(); clearTimeout(timer);
  #|     if(observer)observer.disconnect();
  #|     if(video){for(const [name,fn] of handlers)video.removeEventListener(name,fn);video.pause();delete video.__mooncastDeliveryPlayback;video.removeAttribute("src");video.load();}
  #|   };
  #| }

///|
extern "js" fn delivery_player_dom_seek(
  id : String,
  target_ms : Int,
  notify : (String, Double, Double) -> Unit,
) -> Unit =
  #| (id, targetMs, notify) => {
  #|   if(typeof document==="undefined")return;
  #|   const video=document.getElementById(id), state=video && video.__mooncastDeliveryPlayback;
  #|   if(!state || !state.active)return;
  #|   if(video.error || video.readyState<1 || !Number.isFinite(video.duration) || video.duration<=0){state.send("unavailable");return;}
  #|   if(!Number.isInteger(targetMs) || targetMs<0 || targetMs/1000>=video.duration)return;
  #|   state.cancel(); const target=targetMs/1000;
  #|   try {
  #|     if(video.currentTime===target){state.send("seeked");return;}
  #|     state.pending=target;
  #|     state.seekTimer=setTimeout(()=>{if(state.active && state.pending===target){state.cancel();state.send("seek-error");}},4000);
  #|     video.currentTime=target;
  #|   } catch(_){state.cancel();if(state.active)notify("seek-error",video.currentTime,video.duration);}
  #| }
