///|
priv struct PlayerCaptions {
  enabled : Bool
  target : String
  generation : Int32
  pending : String
  text : String
  translation : String
  error : String
}

///|
fn PlayerCaptions::new() -> PlayerCaptions {
  {
    enabled: false,
    target: "off",
    generation: 0,
    pending: "",
    text: "",
    translation: "",
    error: "",
  }
}

///|
fn PlayerCaptions::invalidate(self : PlayerCaptions) -> PlayerCaptions {
  {
    ..self,
    generation: self.generation + 1,
    text: "",
    translation: "",
    error: "",
  }
}

// Browser audio I/O only. Routing, requests, generation guards and UI state stay in MoonBit.
// One bounded four-second window and one latest pending window, never a full-file decode.

///|
extern "js" fn player_audio_resume() -> Unit =
  #|() => { try { const AC = globalThis.AudioContext || globalThis.webkitAudioContext; if (!AC) return; const s = globalThis.__mooncastPlayerAudio ||= {ctx:new AC(),nodes:new WeakMap()}; s.ctx.resume().catch(()=>{}); } catch (_) {} }

///|
extern "js" fn player_audio_stop() -> Unit =
  #|() => { const s=globalThis.__mooncastPlayerAudio; if(s){s.active=false;s.queue=null;s.samples=[];s.count=0;} }

///|
extern "js" fn player_audio_poll(
  generation : Int32,
  take_chunk : Bool,
) -> String =
  #|(generation,take) => {
  #| const s=globalThis.__mooncastPlayerAudio, v=document.getElementById('standalone-video');
  #| if(!s || !v) return JSON.stringify({error:'Audio capture is unavailable. Open media, then retry captions.'});
  #| const reset=()=>{s.samples=[];s.count=0;s.queue=null;s.start=v.currentTime;};
  #| if(s.video && s.video!==v){const old=s.nodes.get(s.video);if(old){old.source.disconnect();old.processor.disconnect();old.mute.disconnect();s.nodes.delete(s.video);}}
  #| if(s.video!==v || s.generation!==generation){s.active=true;s.video=v;s.generation=generation;s.reset=false;reset();}
  #| try {
  #|  if(!s.nodes.has(v)){
  #|   const source=s.ctx.createMediaElementSource(v), processor=s.ctx.createScriptProcessor(4096,1,1), mute=s.ctx.createGain(); mute.gain.value=0;
  #|   source.connect(s.ctx.destination); source.connect(processor);processor.connect(mute);mute.connect(s.ctx.destination);
  #|   const flush=()=>{if(s.count<1600)return; const data=new Float32Array(s.count);let n=0;for(const a of s.samples){data.set(a,n);n+=a.length;}
  #|    const length=Math.min(64000,Math.floor(data.length*16000/s.ctx.sampleRate)), wav=new Uint8Array(44+length*2), d=new DataView(wav.buffer);
  #|    const str=(p,t)=>{for(let i=0;i<t.length;i++)wav[p+i]=t.charCodeAt(i);};str(0,'RIFF');d.setUint32(4,wav.length-8,true);str(8,'WAVEfmt ');d.setUint32(16,16,true);d.setUint16(20,1,true);d.setUint16(22,1,true);d.setUint32(24,16000,true);d.setUint32(28,32000,true);d.setUint16(32,2,true);d.setUint16(34,16,true);str(36,'data');d.setUint32(40,length*2,true);
  #|    let energy=0;for(let i=0;i<length;i++){const x=data[Math.min(data.length-1,Math.floor(i*s.ctx.sampleRate/16000))];energy+=x*x;d.setInt16(44+i*2,Math.max(-32768,Math.min(32767,Math.round(x*32767))),true);}
  #|    if(energy/Math.max(1,length)>0.000001){let raw='';for(let i=0;i<wav.length;i+=8192)raw+=String.fromCharCode(...wav.subarray(i,i+8192));s.queue={audio:btoa(raw),key:generation+':'+s.start+':'+v.currentTime};}
  #|    s.samples=[];s.count=0;s.start=v.currentTime;};
  #|   processor.onaudioprocess=e=>{if(!s.active||s.video!==v||v.paused||v.seeking)return;const a=new Float32Array(e.inputBuffer.getChannelData(0));if(!s.count)s.start=v.currentTime;s.samples.push(a);s.count+=a.length;if(s.count>=s.ctx.sampleRate*4)flush();};
  #|   v.addEventListener('seeking',()=>{if(s.video===v){reset();s.reset=true;}});v.addEventListener('ratechange',()=>{if(s.video===v){reset();s.reset=true;}});
  #|   v.addEventListener('pause',()=>{if(s.active&&s.video===v)flush();});v.addEventListener('ended',()=>{if(s.active&&s.video===v)flush();});s.nodes.set(v,{source,processor,mute});
  #|  }
  #| }catch(e){return JSON.stringify({error:'This media cannot provide playback audio for captions: '+e.message});}
  #| if(s.reset){s.reset=false;return JSON.stringify({reset:true});}
  #| if(take&&s.queue){const q=s.queue;s.queue=null;return JSON.stringify(q);}return '';
  #| }

///|
fn player_caption_controls(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  has_media : Bool,
) -> @rabbita.Html {
  let state = model.player_captions
  @html.div(class="player-caption-controls", [
    @html.button(
      disabled=!has_media,
      attrs=@html.Attrs::build().aria_pressed(state.enabled.to_string()),
      on_click=dispatch(TogglePlayerCaptions),
      if state.enabled {
        "Stop captions"
      } else if state.error != "" {
        "Retry captions"
      } else {
        "Live captions"
      },
    ),
    @html.label(
      class="player-setting",
      attrs=@html.Attrs::build().for_("player-caption-target"),
      [
        @html.span("Translate to"),
        @html.select(
          id="player-caption-target",
          on_change=dispatch.map(value => SetPlayerTranslation(value)),
          [
            ("off", "Off"),
            ("en", "English"),
            ("zh", "中文"),
            ("ja", "日本語"),
            ("ko", "한국어"),
            ("fr", "Français"),
            ("de", "Deutsch"),
            ("es", "Español"),
            ("ru", "Русский"),
            ("ar", "العربية"),
          ].map(item => {
            @html.option(value=item.0, selected=state.target == item.0, item.1)
          }),
        ),
      ],
    ),
    if state.enabled {
      @html.span(
        attrs=@html.Attrs::build().role("status"),
        if state.pending != "" {
          "Transcribing locally…"
        } else {
          "Listening during playback…"
        },
      )
    } else {
      @html.nothing
    },
    @html.details([
      @html.summary("Local model details"),
      @html.p(
        "Qwen ASR · Index Translate. Audio stays on this computer. Captions follow playback in four-second chunks with processing delay; they are not saved or exported.",
      ),
    ]),
  ])
}

///|
fn player_caption_output(model : Model) -> @rabbita.Html {
  let state = model.player_captions
  @html.div(class="player-caption-output", [
    if state.enabled && state.text != "" {
      @html.div(
        class="player-caption-text",
        attrs=@html.Attrs::build().aria_live("polite"),
        [
          @html.p(state.text),
          if state.translation != "" {
            @html.p(class="player-caption-translation", state.translation)
          } else {
            @html.nothing
          },
        ],
      )
    } else {
      @html.nothing
    },
  ])
}

///|
fn player_caption_reply(
  state : PlayerCaptions,
  generation : Int32,
  key : String,
  result : Result[Json, Error],
) -> PlayerCaptions {
  guard key == state.pending && key != "" else { return state }
  let next = { ..state, pending: "", }
  guard state.enabled && generation == state.generation else { return next }
  match result {
    Ok({ "text": String(text), "translation": String(translation), .. }) =>
      { ..next, text, translation, }
    Ok({ "error": String(error), .. }) => { ..next, enabled: false, error, }
    _ =>
      {
        ..next,
        enabled: false,
        error: "Local captions unavailable. Check Qwen ASR (18731) and Index Translate (18732), then retry.",
      }
  }
}
