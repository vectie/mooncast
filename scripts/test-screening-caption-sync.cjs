'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {setup} = require('./screening-player-harness.cjs');
const cues = [{start_ms:500,end_ms:1500,text:'First 🌙'}, {start_ms:1000,end_ms:2500,text:'Overlapping voice'}, {start_ms:4000,end_ms:5000,text:'Closing'}];
const fixture = options => setup({data:{cues},...options});
const set = (app,name,value) => {app.get('caption-clock-'+name).value=String(value);};
async function draft(app) { await app.click('caption-download-json'); return JSON.parse(await app.downloads.at(-1).blob.text()); }
async function preview(app) { await app.click('caption-clock-preview'); }
async function apply(app) { await app.click('caption-clock-apply'); }

test('offset previews then changes every cue and its player presentation, preserving words and overlap',async()=>{
  const app=fixture({nativeCaptions:true}); app.video.currentTime=2; app.video.paused=false;
  set(app,'offset',250); await preview(app);
  assert.equal(app.get('caption-clock-list').children.length,3);
  assert.deepEqual((await draft(app)).cues,cues);
  await apply(app); const expected=cues.map(c=>({...c,start_ms:c.start_ms+250,end_ms:c.end_ms+250}));
  assert.deepEqual((await draft(app)).cues,expected);
  assert.equal(app.video.tracks[0].cues[0].startTime,.75);
  assert.equal(app.cueRows[0].querySelector('[data-seek-ms]').dataset.seekMs,'750');
  assert.equal(app.video.currentTime,2); assert.equal(app.video.paused,false); assert.equal(app.video.plays,0);
  await apply(app); assert.deepEqual((await draft(app)).cues,expected);
});

test('two captured speech targets correct drift; downloaded result reopens in existing resume workflow',async()=>{
  const app=fixture(); set(app,'mode','anchors'); set(app,'source-first',500); set(app,'source-last',4500);
  app.video.currentTime=.75; await app.click('caption-clock-capture-first');
  app.video.currentTime=5.15; await app.click('caption-clock-capture-last');
  assert.equal(app.get('caption-clock-target-first').value,'750'); assert.equal(app.get('caption-clock-target-last').value,'5150');
  await preview(app); await apply(app); const saved=await draft(app);
  assert.deepEqual(saved.cues,cues.map(c=>({...c,start_ms:750+(c.start_ms-500)*1.1,end_ms:750+(c.end_ms-500)*1.1})));
  const reopened=fixture(), raw=JSON.stringify(saved); reopened.get('caption-resume-file').files=[{size:Buffer.byteLength(raw),text:async()=>raw}];
  await reopened.get('caption-resume-file').emit('change'); await reopened.click('caption-resume-apply');
  assert.deepEqual((await draft(reopened)).cues,saved.cues);
});

test('clock math matches native Int64 formula including half-up, odd span and bounded large products',async()=>{
  // Independent BigInt implementation of editor/captions/timing.mbt integer mapping.
  for(const [duration,source,target,anchors] of [
    [6000,1,2,[0,0,2,3]], [6000,1,5,[0,0,3,4]],
    [7200000,1000000,6000000,[0,0,7000000,7100000]]
  ]) {
    const sourceCues=[{start_ms:source,end_ms:target,text:'Exact clock'}];
    const app=setup({data:{duration_ms:duration,cues:sourceCues}}); set(app,'mode','anchors');
    ['source-first','target-first','source-last','target-last'].forEach((key,i)=>set(app,key,anchors[i]));
    await preview(app); await apply(app);
    const [s1,t1,s2,t2]=anchors.map(BigInt), span=s2-s1;
    const expected=x=>Number((t1*span+(BigInt(x)-s1)*(t2-t1)+span/2n)/span);
    assert.deepEqual((await draft(app)).cues,[{start_ms:expected(source),end_ms:expected(target),text:'Exact clock'}]);
  }
});

test('out-of-range mapping and collapsed cue keep all current captions; cancel keeps draft',async()=>{
  const app=fixture(); set(app,'offset',-501); await preview(app); assert.match(app.get('caption-clock-status').textContent,/outside/);
  await apply(app); assert.deepEqual((await draft(app)).cues,cues);
  set(app,'mode','anchors'); ['source-first','target-first','source-last','target-last'].forEach((key,i)=>set(app,key,[0,0,6000,1][i]));
  await preview(app); assert.match(app.get('caption-clock-status').textContent,/shorter than/); await apply(app); assert.deepEqual((await draft(app)).cues,cues);
  set(app,'mode','offset'); set(app,'offset',100); await preview(app); await app.click('caption-clock-cancel'); await apply(app); assert.deepEqual((await draft(app)).cues,cues);
});

test('current editing and subsequent edits require a fresh track proposal',async()=>{
  const app=fixture(); await app.editButtons[0].emit('click'); app.get('caption-edit-text').value='Changed'; await app.get('caption-edit-text').emit('input');
  set(app,'offset',100); await preview(app); assert.match(app.get('caption-clock-status').textContent,/single-caption/);
  await app.click('caption-edit-save'); await preview(app);
  app.get('caption-edit-text').value='Later'; await app.get('caption-edit-text').emit('input'); await app.click('caption-edit-save');
  await apply(app); assert.match(app.get('caption-clock-status').textContent,/Preview again/);
  const saved=await draft(app); assert.equal(saved.cues[0].text,'Later'); assert.equal(saved.cues[0].start_ms,500);
});
