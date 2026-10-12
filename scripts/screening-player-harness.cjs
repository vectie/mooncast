'use strict';
// Execute every literal line of the actual production player. DOM/media/download
// doubles make this a focused functional check, not native or browser evidence.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../editor/screening/output.mbt'), 'utf8');
const block = source.match(/fn player_script\(\) -> String \{\n  let script =\n([\s\S]*?)\n  script\n\}/);
assert(block);
assert(block[1].split('\n').every(line => line.startsWith('    #|')));
const script = block[1].split('\n').map(line => line.slice(6)).join('\n');
const htmlSource = source.replace(/\\"/g, '"');
const ids = [...htmlSource.matchAll(/id="([a-z0-9-]+)"/g)].map(match => match[1]);
assert.equal(ids.length, new Set(ids).size);
assert(source.includes('"</script><script>\\n" + player_script()'));
const reviewIds = ['review-notes', 'review-status', 'review-text', 'review-anchor', 'review-save', 'review-filter', 'review-file', 'review-apply', 'review-import-status', 'review-merge', 'review-discard-import', 'review-merge-preview', 'review-point', 'review-range', 'review-cancel', 'review-download', 'screening-source-sha256', 'review-search', 'review-chapter', 'review-order', 'review-previous', 'review-next', 'review-navigation', 'review-brief-scope', 'review-brief-download', 'review-brief-status', 'review-revision-open', 'review-revision-panel', 'review-revision-title', 'review-revision-list', 'review-revision-status', 'review-revision-apply', 'review-revision-cancel'];
for (const id of reviewIds) assert(ids.includes(id), `production HTML has ${id}`);
assert.match(htmlSource, /<label for="review-text">/);
for (const id of ['review-search', 'review-chapter', 'review-order', 'review-brief-scope']) assert.match(htmlSource, new RegExp('<label for="' + id + '">'));
for (const id of ['review-previous', 'review-next']) assert.match(htmlSource, new RegExp('id="' + id + '"[^>]*disabled'));
assert.match(htmlSource, /id="review-navigation" role="status"/);
assert.match(htmlSource, /id="review-brief-status" role="status"/);
assert.match(htmlSource, /id="review-brief-download"[^>]*disabled/);
assert.match(htmlSource, /<textarea id="review-text"[^>]*maxlength="2000"/);
assert.match(htmlSource, /id="review-apply"[^>]*disabled/);
assert.match(htmlSource, /id="review-file"[^>]*multiple/);
for (const id of ['review-merge', 'review-discard-import']) assert.match(htmlSource, new RegExp('id="' + id + '"[^>]*disabled'));
for (const id of ['review-revision-open', 'review-revision-apply']) assert.match(htmlSource, new RegExp('id="' + id + '"[^>]*disabled'));
assert.match(htmlSource, /id="review-revision-panel"[^>]*hidden/);
assert.match(htmlSource, /id="review-revision-status" role="status"/);
assert.match(htmlSource, /Matching local IDs propose a correspondence, not reviewer identity or common history/);
assert.match(htmlSource, /Source SHA-256: <span id="screening-source-sha256">/);
assert(!/\b(?:fetch|localStorage|XMLHttpRequest)\b/.test(script));

function setup(options = {}) {
  const blobs = new Map(), revoked = [], downloads = [], created = [];
  function node(tag = 'div', attrs = {}) {
    const listeners = {}, classes = new Set();
    const el = {tag, attrs, children: [], textContent: '', value: '', hidden: false, disabled: false, files: [], dataset: {},
      classList: {toggle(k,on){if(on)classes.add(k);else classes.delete(k);}, contains:k=>classes.has(k)},
      setAttribute(k,v){attrs[k]=v;}, removeAttribute(k){delete attrs[k];},
      addEventListener(k,f){(listeners[k]??=[]).push(f);},
      async emit(k){for(const f of listeners[k]??[]) await f({target:this});},
      appendChild(child){this.children.push(child);child.parent=this;return child;},
      replaceChildren(...children){this.children=children;},
      focus(){this.focused=true;},
      querySelector(selector){const key=selector.startsWith('.')?'class':null;const value=selector.slice(1);for(const child of this.children){if(key&&child.attrs[key]===value)return child;const found=child.querySelector(selector);if(found)return found;}return null;},
      remove(){if(this.parent)this.parent.children=this.parent.children.filter(child=>child!==this);},
      click(){if(tag==='a') {if(options.downloadError)throw Error('download blocked');downloads.push({href:this.href,download:this.download,blob:blobs.get(this.href)});}else return this.emit('click');}
    };
    created.push(el); return el;
  }
  const elements = ids.map(id=>node('div',{id}));
  const get = id=>elements.find(el=>el.attrs.id===id);
  const data = {contract:'mooncast.screening-plan.v1', title:'Cut 7', duration_ms:6000, cues:[{start_ms:1000,end_ms:3000,text:'Café 🌱'}], chapters:[{start_ms:0,title:'Opening'}], ...options.data};
  get('screening-data').textContent=JSON.stringify(data);
  get('screening-source-sha256').textContent=options.sha || 'a'.repeat(64);
  get('review-filter').value='all';
  const video=get('player'); Object.assign(video,{currentTime:0,readyState:1,duration:6,paused:true,seeking:false,plays:0,load(){},play(){this.plays++;return Promise.resolve();}});
  const cueRows=data.cues.map((cue,index)=>{
    const row=node('li',{'data-cue-index':String(index)});
    const seek=node('button',{'data-seek-ms':String(cue.start_ms)});seek.dataset.seekMs=String(cue.start_ms);
    const words=node('span',{class:'words'});words.textContent=cue.text;seek.appendChild(words);row.appendChild(seek);
    const edit=node('button',{'data-caption-edit-index':String(index)});edit.dataset.captionEditIndex=String(index);edit.textContent='Edit caption '+(index+1);row.appendChild(edit);
    return row;
  });
  const editButtons=cueRows.map(row=>row.children[1]);
  const chapterButtons=data.chapters.map((chapter,index)=>{const button=node('button',{'data-chapter-index':String(index),'data-seek-ms':String(chapter.start_ms)});button.dataset.seekMs=String(chapter.start_ms);return button;});
  const query=selector=>created.filter(item=>selector.slice(1,-1) in item.attrs);
  video.tracks=[];
  if(options.nativeCaptions)video.addTextTrack=function(){const track={cues:[],addCue(cue){this.cues.push(cue);}};this.tracks.push(track);return track;};
  class Cue {constructor(start,end,text){this.startTime=start;this.endTime=end;this._text=text;}get text(){return this._text;}set text(value){if(video.rejectTextUpdate)throw Error('caption update unavailable');this._text=value;}}
  const body=node('body');
  vm.runInNewContext(script,{document:{getElementById:get,querySelectorAll:query,createElement:tag=>node(tag),body},VTTCue:options.nativeCaptions?Cue:undefined,Blob,URL:{createObjectURL(blob){const url='blob:'+blobs.size;blobs.set(url,blob);return url;},revokeObjectURL(url){revoked.push(url);}}},{timeout:1000});
  const click=id=>get(id).emit('click');
  const rows=()=>get('review-notes').children;
  const actions=index=>rows()[index].children[2].children;
  const add=async(text,time=1.234)=>{video.currentTime=time;await click('review-point');get('review-text').value=text;await click('review-save');};
  const exported=async()=>{await click('review-download');assert(downloads.length);return JSON.parse(await downloads.at(-1).blob.text());};
  const loadMany=async(values)=>{get('review-file').files=values.map((value,i)=>{const raw=JSON.stringify(value);return {name:'Reviewer '+(i+1)+'.json',size:Buffer.byteLength(raw),text:async()=>raw};});await get('review-file').emit('change');};
  const load=async(value)=>loadMany([value]);
  return {get,video,rows,actions,click,add,exported,load,loadMany,downloads,blobs,revoked,created,data,cueRows,editButtons,chapterButtons};
}

module.exports = {setup, script};
