'use strict';
// Execute exactly the JavaScript emitted in index.html. This is a DOM/API test
// double, not a real browser or an accessibility/codec conformance claim.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
function setup(nativeCaptions) {
  const elements = input.nodes.map(node => {
    const attrs = {...node.attrs}, listeners = {}, classes = new Set();
    return {tag: node.tag, attrs, dataset: Object.fromEntries(Object.entries(attrs).filter(([key])=>key.startsWith('data-')).map(([key,value])=>[key.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase()),value])), hidden: 'hidden' in attrs, textContent:'',value:'',children:[],
      replaceChildren(...children){this.children=children;},appendChild(child){this.children.push(child);return child;},focus(){},
      classList:{toggle(name,on){if(on)classes.add(name);else classes.delete(name);},contains:name=>classes.has(name)},
      setAttribute(key,value){attrs[key]=value;},removeAttribute(key){delete attrs[key];},
      addEventListener(event,fn){(listeners[event]??=[]).push(fn);},emit(event){for(const fn of listeners[event]??[])fn({target:this});}};
  });
  const get=id=>elements.find(el=>el.attrs.id===id);
  const query=selector=>elements.filter(el=>selector.slice(1,-1) in el.attrs);
  get('screening-data').textContent=JSON.stringify(input.data);
  const video=get('player');Object.assign(video,{currentTime:0,readyState:0,duration:NaN,paused:true,playbackRate:1,loads:0,plays:0,load(){this.loads++},play(){this.plays++},tracks:[]});
  if(nativeCaptions)video.addTextTrack=function(){const track={cues:[],mode:'disabled',addCue(cue){this.cues.push(cue)}};this.tracks.push(track);return track;};
  const context={document:{getElementById:get,querySelectorAll:query,createElement:tag=>({tag,children:[],addEventListener(){},appendChild(child){this.children.push(child);return child;}})},VTTCue:nativeCaptions?class {constructor(startTime,endTime,text){Object.assign(this,{startTime,endTime,text})}}:undefined};
  vm.runInNewContext(input.script,context,{timeout:1000});
  return {get,query,video};
}
for(const nativeCaptions of [true,false]){
  const {get,query,video}=setup(nativeCaptions);
  const cues=query('[data-cue-index]'),chapters=query('[data-chapter-index]'),seeks=query('[data-seek-ms]'),nudges=query('[data-nudge-ms]');
  assert.equal(video.plays,0);
  if(cues.length){
    seeks[0].emit('click');assert.equal(video.currentTime,0);assert.match(get('playback-status').textContent,/Loading video/);
    seeks.at(-1).emit('click');video.readyState=1;video.duration=6;video.emit('loadedmetadata');assert.equal(video.currentTime,4);assert.equal(video.plays,0);
    video.currentTime=1.6;video.emit('timeupdate');assert(cues[0].classList.contains('current'));assert(cues[1].classList.contains('current'));assert(!cues[2].classList.contains('current'));
    assert.equal(chapters[0].attrs['aria-current'],'true');
    video.currentTime=2.5;video.emit('seeked');assert(!cues[0].classList.contains('current'));assert(cues[1].classList.contains('current'));
    const search=get('search');search.value='CAFÉ';search.emit('input');assert.equal(cues.filter(c=>!c.hidden).length,1);assert.equal(get('search-count').textContent,'1 of 3 cues');
    search.value='does not exist';search.emit('input');assert(cues.every(c=>c.hidden));
    search.value='';search.emit('input');assert(cues.every(c=>!c.hidden));
    chapters[1].emit('click');assert.equal(video.currentTime,3.001);assert.equal(chapters[1].attrs['aria-current'],'true');assert(!('aria-current' in chapters[0].attrs));
    const toggle=get('captions-toggle');toggle.emit('click');assert.equal(toggle.attrs['aria-pressed'],'false');assert.equal(toggle.textContent,'Captions off');
    toggle.emit('click');assert.equal(toggle.attrs['aria-pressed'],'true');
    video.currentTime=1.6;video.emit('timeupdate');
    if(nativeCaptions){assert.equal(video.tracks[0].cues.length,3);assert.equal(video.tracks[0].cues[0].text,'Café &amp;amp; 🌱\nSecond line');assert.equal(video.tracks[0].mode,'showing');assert(get('caption-fallback').hidden);}
    else {assert(!get('caption-fallback').hidden);assert.match(get('caption-fallback').textContent,/Another speaker/);}
    video.currentTime=3.5;video.emit('timeupdate');assert(get('caption-fallback').hidden);
  }else{assert(get('captions-toggle').hidden);assert.equal(video.tracks.length,0);video.readyState=1;video.duration=6;}
  video.currentTime=0;nudges[0].emit('click');assert.equal(video.currentTime,0);
  video.currentTime=5;nudges[1].emit('click');assert.equal(video.currentTime,6);
  get('speed').value='1.5';get('speed').emit('change');assert.equal(video.playbackRate,1.5);
  video.emit('error');assert.match(get('playback-status').textContent,/could not play/);assert.equal(video.plays,0);
}
console.log(JSON.stringify({passed:true,native_and_fallback_captions:true,seek_latest_before_metadata:true,overlap_and_half_open_boundaries:true,unicode_search:true,search_clear_and_empty:true,chapter_navigation:true,speed_and_clamped_nudges:true,playback_error:true,no_autoplay:true}));
