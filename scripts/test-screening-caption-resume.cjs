'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {setup} = require('./screening-player-harness.cjs');
const fixture = options => setup({...options,data:{cues:[{start_ms:0,end_ms:1000,text:'First 🌙'},{start_ms:1200,end_ms:4000,text:'Second'}]}});
async function draft(app) { await app.click('caption-download-json'); return JSON.parse(await app.downloads.at(-1).blob.text()); }
async function load(app,value) {const text=typeof value==='string'?value:JSON.stringify(value);app.get('caption-resume-file').files=[{size:Buffer.byteLength(text),text:async()=>text}];await app.get('caption-resume-file').emit('change');}
const words=app=>app.cueRows.map(row=>row.querySelector('.words').textContent);
test('downloaded correction can be reopened, previewed, applied and continued without rewriting supplied context',async()=>{
 const original=fixture();await original.editButtons[0].emit('click');original.get('caption-edit-text').value='Resumed & literal 🌖';original.get('caption-edit-start').value='200';original.get('caption-edit-end').value='1100';await original.click('caption-preview');await original.click('caption-edit-save');const saved=await draft(original);
 const app=fixture({nativeCaptions:true});await app.editButtons[0].emit('click');await load(app,saved);assert.deepEqual(words(app),['First 🌙','Second']);assert.equal(app.get('caption-resume-list').children.length,1);assert.match(app.get('caption-resume-list').children[0].textContent,/Resumed & literal/);
 await app.click('caption-resume-apply');assert.deepEqual(words(app),['Resumed & literal 🌖','Second']);assert.equal(app.get('caption-edit-text').value,saved.cues[0].text);assert.equal(app.get('caption-edit-start').value,'200');assert.equal(app.video.tracks[0].cues[0].startTime,.2);assert.equal(app.video.tracks[0].cues[0].text,'Resumed &amp; literal 🌖');assert.equal(app.cueRows[0].children[0].dataset.seekMs,'200');assert.deepEqual((await draft(app)).cues,saved.cues);assert.equal(app.data.cues[0].text,'First 🌙');
 app.get('caption-edit-text').value='Continue editing';await app.click('caption-edit-save');assert.equal((await draft(app)).cues[0].text,'Continue editing');
});
test('wrong identity, duration, schema, cue counts and malformed cues reject whole draft',async()=>{
 const app=fixture();const base=await draft(app);
 const invalid=[null,[],{...base,source_file:'other'}, {...base,duration_ms:6001},{...base,contract:'other'},{...base,cues:[]},{...base,cues:[base.cues[0],{...base.cues[1],text:'<script>'}]},{...base,cues:[{...base.cues[0],start_ms:-1},base.cues[1]]},{...base,cues:[base.cues[0],{...base.cues[1],end_ms:9000}]},{...base,cues:[{...base.cues[0],start_ms:1400,end_ms:1600},base.cues[1]]},{...base,cues:[base.cues[0],{...base.cues[1],text:5}]},'{bad'];
 for(const value of invalid){await load(app,value);assert.equal(app.get('caption-resume-apply').disabled,true);await app.click('caption-resume-apply');assert.deepEqual(words(app),['First 🌙','Second']);assert.match(app.get('caption-resume-status').textContent,/Could not reopen/);}
});
test('dirty edits and stale previews cannot overwrite current captions',async()=>{
 const app=fixture(),saved=await draft(app);saved.cues[0].text='Incoming';await load(app,saved);await app.editButtons[1].emit('click');app.get('caption-edit-text').value='New local';await app.click('caption-edit-save');await app.click('caption-resume-apply');assert.deepEqual(words(app),['First 🌙','New local']);assert.match(app.get('caption-resume-status').textContent,/changed after preview/);
 await load(app,saved);app.get('caption-edit-text').value='Unsaved';await app.click('caption-resume-apply');assert.equal(app.get('caption-edit-text').value,'Unsaved');assert.deepEqual(words(app),['First 🌙','New local']);await load(app,saved);assert.match(app.get('caption-resume-status').textContent,/Apply or cancel/);
});
test('late reads are ignored after cancel or newer file; interrupted read leaves applied draft intact',async()=>{
 const app=fixture(),saved=await draft(app);saved.cues[0].text='Late';let resolve;
 app.get('caption-resume-file').files=[{size:100,text:()=>new Promise(r=>{resolve=r;})}];const pending=app.get('caption-resume-file').emit('change');await app.click('caption-resume-cancel');resolve(JSON.stringify(saved));await pending;assert.equal(app.get('caption-resume-apply').disabled,true);assert.match(app.get('caption-resume-status').textContent,/dismissed/);
 app.get('caption-resume-file').files=[{size:100,text:()=>new Promise(r=>{resolve=r;})}];const old=app.get('caption-resume-file').emit('change');const newest={...saved,cues:saved.cues.map(c=>({...c,text:'New file'}))};await load(app,newest);resolve(JSON.stringify(saved));await old;await app.click('caption-resume-apply');assert.deepEqual(words(app),['New file','New file']);
 app.get('caption-resume-file').files=[{size:100,text:async()=>{throw Error('read interrupted')}}];await app.get('caption-resume-file').emit('change');assert.match(app.get('caption-resume-status').textContent,/read interrupted/);assert.deepEqual(words(app),['New file','New file']);
});
test('no-op and size limits; file reading racing applied changes is refused',async()=>{
 const app=fixture(),saved=await draft(app);await load(app,saved);assert.equal(app.get('caption-resume-apply').disabled,true);assert.match(app.get('caption-resume-status').textContent,/0 of 2/);
 app.get('caption-resume-file').files=[{size:16777217,text:async()=>{throw Error('must not read')}}];await app.get('caption-resume-file').emit('change');assert.match(app.get('caption-resume-status').textContent,/16 MiB/);
 let resolve;app.get('caption-resume-file').files=[{size:100,text:()=>new Promise(r=>{resolve=r;})}];const pending=app.get('caption-resume-file').emit('change');await app.editButtons[0].emit('click');app.get('caption-edit-text').value='Local';await app.click('caption-edit-save');resolve(JSON.stringify(saved));await pending;assert.match(app.get('caption-resume-status').textContent,/changed during file reading/);assert.deepEqual(words(app),['Local','Second']);
});
