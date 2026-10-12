'use strict';
// Exact production #| JavaScript, with DOM/media API doubles. No MoonBit build,
// native HTML export, codec, real playback, or graphical-browser claim.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const source = fs.readFileSync(path.join(__dirname, '../editor/screening/output.mbt'), 'utf8');
const block = source.match(/fn player_script\(\) -> String \{\n  let script =\n([\s\S]*?)\n  script\n\}/);
assert(block, 'production player_script boundary');
const lines = block[1].split('\n');
assert(lines.every(line => line.startsWith('    #|')), 'no ignored/interpolated lines');
const script = lines.map(line => line.slice(6)).join('\n');
assert(source.includes('"</script><script>\\n" + player_script()'), 'HTML calls this exact function');
const htmlSource = source.replace(/\\"/g, '"');
const ids = ['player', 'screening-data', 'playback-status', 'search', 'search-count', 'captions-toggle', 'caption-fallback', 'speed', 'range-status', 'range-repeat', 'range-start', 'range-end', 'range-clear'];
for (const id of ids) assert.equal([...htmlSource.matchAll(new RegExp('id="' + id + '"', 'g'))].length, 1, `one production HTML ${id}`);
for (const id of ['range-start','range-end','range-repeat','range-clear']) assert.match(htmlSource, new RegExp('<button id="'+id+'" type="button"'));
assert.match(htmlSource, /id="range-repeat"[^>]*disabled/);
assert.match(htmlSource, /id="range-status" role="status"/);
function setup(nativeCaptions = false) {
  const node = (attrs = {}) => {
    const listeners = {}, classes = new Set();
    return {attrs, dataset: Object.fromEntries(Object.entries(attrs).filter(([k])=>k.startsWith('data-')).map(([k,v])=>[k.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase()),v])), textContent:'', value:'', hidden:false, disabled:false,
      classList:{toggle(k,on){if(on)classes.add(k);else classes.delete(k);},contains:k=>classes.has(k)},
      setAttribute(k,v){attrs[k]=v;},removeAttribute(k){delete attrs[k];},
      addEventListener(k,f){(listeners[k]??=[]).push(f);},emit(k){for(const f of listeners[k]??[])f({target:this});}};
  };
  const elements = ids.map(id=>node({id}));
  const cues = [{start_ms:1000,end_ms:2500,text:'Café first'}, {start_ms:1500,end_ms:3000,text:'Second'}, {start_ms:4000,end_ms:5500,text:'Third'}];
  const chapters = [{start_ms:0,title:'Intro'},{start_ms:3001,title:'Later'}];
  const data={duration_ms:6000,cues,chapters};
  const rows=cues.map((_,i)=>node({'data-cue-index':String(i)}));
  const chapterNodes=chapters.map((c,i)=>node({'data-chapter-index':String(i),'data-seek-ms':String(c.start_ms)}));
  elements.push(...rows,...chapterNodes,...cues.map(c=>node({'data-seek-ms':String(c.start_ms)})),node({'data-nudge-ms':'-5000'}),node({'data-nudge-ms':'5000'}));
  const get=id=>elements.find(e=>e.attrs.id===id);
  const query=s=>elements.filter(e=>s.slice(1,-1) in e.attrs);
  get('screening-data').textContent=JSON.stringify(data);
  const video=get('player');
  Object.assign(video,{currentTime:0,readyState:0,duration:NaN,paused:true,seeking:false,playbackRate:1,plays:0,loads:0,load(){this.loads++},play(){this.plays++;this.paused=false;return Promise.resolve();},tracks:[]});
  if(nativeCaptions) video.addTextTrack=function(){const t={cues:[],addCue(c){this.cues.push(c)}};this.tracks.push(t);return t;};
  vm.runInNewContext(script,{document:{getElementById:get,querySelectorAll:query},VTTCue:nativeCaptions?class {constructor(start,end,text){Object.assign(this,{start,end,text})}}:undefined},{timeout:1000});
  const click=id=>get(id).emit('click');
  const range=(a,b)=>{video.currentTime=a;click('range-start');video.currentTime=b;click('range-end');};
  return {get,query,video,rows,chapterNodes,click,range};
}
(async()=>{
for(const native of [false,true]) {
  const {get,query,video,rows,chapterNodes,click,range}=setup(native);
  assert(get('range-repeat').disabled);assert.equal(video.plays,0);
  click('range-start');assert.match(get('range-status').textContent,/Load the video/);
  video.readyState=1;video.duration=6;
  click('range-end');assert.match(get('range-status').textContent,/Mark A first/);
  range(1,3);assert(!get('range-repeat').disabled);assert.equal(video.plays,0);
  click('range-repeat');assert.equal(video.currentTime,1);assert.equal(get('range-repeat').attrs['aria-pressed'],'true');assert.equal(video.plays,0);
  video.currentTime=3.2;video.emit('timeupdate');assert.equal(video.currentTime,3.2,'paused never rewinds');
  video.paused=false;video.currentTime=2.999;video.emit('timeupdate');assert.equal(video.currentTime,2.999);
  video.currentTime=3;video.emit('timeupdate');assert.equal(video.currentTime,1,'exact B rewinds');
  assert(rows[0].classList.contains('current'));assert(!rows[1].classList.contains('current'));
  video.currentTime=3.8;video.emit('timeupdate');assert.equal(video.currentTime,1,'event overshoot rewinds');
  video.seeking=true;video.currentTime=4;video.emit('timeupdate');assert.equal(video.currentTime,4);video.emit('seeking');video.seeking=false;assert.equal(get('range-repeat').attrs['aria-pressed'],'false');
  click('range-repeat');assert.equal(video.currentTime,1);click('range-repeat');video.currentTime=3.5;video.emit('timeupdate');assert.equal(video.currentTime,3.5);
  range(1,3);video.currentTime=0.5;click('range-end');assert.match(get('range-status').textContent,/previous range is unchanged/);click('range-repeat');assert.equal(video.currentTime,1);video.currentTime=3;video.emit('timeupdate');assert.equal(video.currentTime,1);
  video.currentTime=4;click('range-start');assert(get('range-repeat').disabled);assert.equal(get('range-repeat').attrs['aria-pressed'],'false');
  range(1.125,3.875);assert.match(get('range-status').textContent,/1.125 s.*3.875 s/);
  click('range-repeat');video.duration=2;video.emit('durationchange');assert(get('range-repeat').disabled);assert.equal(get('range-repeat').attrs['aria-pressed'],'false');
  video.duration=6;video.emit('durationchange');range(1,6);click('range-repeat');video.currentTime=6;video.paused=true;video.emit('ended');assert.equal(video.currentTime,1);assert.equal(video.plays,1,'explicit enabled repeat continues at media end');
  click('range-clear');assert(get('range-repeat').disabled);video.currentTime=6;video.emit('ended');assert.equal(video.plays,1);
  range(1,3);click('range-repeat');video.emit('error');assert.equal(get('range-repeat').attrs['aria-pressed'],'false');assert.match(get('playback-status').textContent,/could not play/);
  // Existing production controls still act on their real handlers.
  get('search').value='CAFÉ';get('search').emit('input');assert.equal(rows.filter(r=>!r.hidden).length,1);get('search').value='';get('search').emit('input');assert(rows.every(r=>!r.hidden));
  chapterNodes[1].emit('click');assert.equal(video.currentTime,3.001);
  get('speed').value='1.5';get('speed').emit('change');assert.equal(video.playbackRate,1.5);
  video.currentTime=1.6;video.emit('timeupdate');assert(rows[0].classList.contains('current')&&rows[1].classList.contains('current'));
  click('captions-toggle');assert.equal(get('captions-toggle').attrs['aria-pressed'],'false');click('captions-toggle');assert.equal(get('captions-toggle').attrs['aria-pressed'],'true');
  video.currentTime=0;query('[data-nudge-ms]')[0].emit('click');assert.equal(video.currentTime,0);
  range(1,6);click('range-repeat');video.play=()=>Promise.reject(Error('blocked'));video.currentTime=6;video.emit('ended');await Promise.resolve();assert.equal(get('range-repeat').attrs['aria-pressed'],'false');assert.match(get('range-status').textContent,/could not resume/);
  // An older rejected repeat attempt cannot turn off a newly selected range.
  let reject;video.play=()=>new Promise((_,r)=>reject=r);range(1,6);click('range-repeat');video.currentTime=6;video.emit('ended');click('range-clear');range(2,4);click('range-repeat');reject(Error('old'));await Promise.resolve();assert.equal(get('range-repeat').attrs['aria-pressed'],'true');
}
// A terminal timeupdate may be paused and overshoot B before ended fires.
// An explicit outside seek still cancels repeat before the same terminal events.
for (const outsideSeek of [false,true]) {
  const {get,video,click,range}=setup();video.readyState=1;video.duration=6;
  range(1,5.9);click('range-repeat');video.paused=false;video.currentTime=6;
  if(outsideSeek) video.emit('seeking');
  video.paused=true;video.emit('timeupdate');video.emit('ended');
  assert.equal(video.currentTime,outsideSeek?6:1);
  assert.equal(video.plays,outsideSeek?0:1);
  assert.equal(get('range-repeat').attrs['aria-pressed'],String(!outsideSeek));
}
// A failed media seek disables repeat and never follows it with play().
{
  const {get,video,click,range}=setup();video.readyState=1;video.duration=6;
  range(1,6);click('range-repeat');
  Object.defineProperty(video,'currentTime',{configurable:true,get:()=>6,set(){throw Error('not seekable')}});
  video.emit('ended');assert.equal(video.plays,0);assert.equal(get('range-repeat').attrs['aria-pressed'],'false');assert.match(get('playback-status').textContent,/Unable to seek/);
}
console.log(JSON.stringify({passed:true,production_script_sha256:crypto.createHash('sha256').update(script).digest('hex'),profiles:2,range_marking:true,paused_no_autoplay:true,boundary_and_overshoot:true,explicit_repeat_end:true,manual_seek_exit:true,invalid_marks_preserve_range:true,clear_and_reselection:true,duration_change:true,play_rejection_and_stale_result:true,existing_controls:true,qualification:'source-extracted production JavaScript with DOM/media doubles; MoonBit/native export/browser not run'},null,2));
})().catch(error=>{console.error(error);process.exitCode=1});
