'use strict';
// Run the exact emitted player script. Browser/media/file input APIs are doubled;
// Blob output and a local file roundtrip are real. No graphical browser is used.
const assert = require('node:assert/strict');
const {test} = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setup} = require('./screening-player-harness.cjs');
const rows = app => app.get('review-revision-list').children;
const choice = (app, index) => rows(app)[index].children[0].children[0];
const summary = app => app.get('review-revision-status').textContent;
const choose = async (app,index,on=true) => {const input=choice(app,index); input.checked=on; await input.emit('change');};
const open = async (app,file) => {await app.load(file); await app.click('review-revision-open');};
const note = (id,text,extra={}) => ({id,start_ms:1000,end_ms:null,text,resolved:false,...extra});
async function seeded() {
  const app=setup(); await app.add('Repair opening',1); await app.add('Keep this concern',2); await app.add('Only in my notebook',3);
  return {app,base:await app.exported()};
}

test('review returned edits, select replacements and additions, save a portable notebook and reopen it',async()=>{
  const {app,base}=await seeded();
  const incoming={...structuredClone(base),notes:[note(1,'Opening fixed after review',{start_ms:1250,end_ms:2500,resolved:true}),base.notes[1],note(8,'New end-card issue',{start_ms:5000})]};
  await open(app,incoming);
  assert(!app.get('review-revision-panel').hidden); assert(app.get('review-revision-apply').disabled);
  assert(rows(app).every((_,index)=>choice(app,index).checked===false));
  assert.match(summary(app),/2 proposed changes; 1 identical notes; 1 current-only notes kept/);
  assert.equal(rows(app)[0].children[1].textContent,'Current #1 · 00:00:01.000 · Open\nRepair opening');
  assert.equal(rows(app)[0].children[2].textContent,'Incoming #1 · 00:00:01.250–00:00:02.500 · Resolved\nOpening fixed after review');
  assert.deepEqual((await app.exported()).notes,base.notes,'preview and download do not apply proposals');
  await choose(app,0); await choose(app,1);
  assert.match(summary(app),/Selected: 1 replacements, 1 additions/);
  await app.click('review-revision-apply'); const saved=await app.exported();
  assert.deepEqual(saved.notes,[incoming.notes[0],base.notes[1],base.notes[2],incoming.notes[2]]);
  assert.deepEqual(saved.source,base.source); assert.equal(saved.contract,base.contract);
  assert.equal(app.video.plays,0); assert(app.get('review-revision-panel').hidden);
  assert(app.get('review-merge').disabled); assert(app.get('review-revision-open').disabled);
  const evidenceRoot=process.env.MOONCAST_EVIDENCE_DIR || os.tmpdir();
  const temp=fs.mkdtempSync(path.join(evidenceRoot,'screening-revisions-'));
  const filename=path.join(temp,'screening-notes.json'); fs.writeFileSync(filename,await app.downloads.at(-1).blob.text());
  console.log('Notebook roundtrip evidence retained: '+filename);
  const reopened=setup(); await reopened.load(JSON.parse(fs.readFileSync(filename,'utf8'))); await reopened.click('review-apply');
  assert.deepEqual((await reopened.exported()).notes,saved.notes);
});

test('choose only intended updates, uncheck choices and apply once without changing unrelated notes',async()=>{
  const {app,base}=await seeded(); const incoming={...base,notes:[note(1,'Take this'),note(2,'Leave this'),note(9,'Do not add')]};
  await open(app,incoming); await app.click('review-revision-apply'); assert.deepEqual((await app.exported()).notes,base.notes);
  await choose(app,0); await choose(app,1); await choose(app,2); await choose(app,1,false); await choose(app,2,false);
  assert.match(summary(app),/1 replacements, 0 additions; 2 proposals not selected/);
  await app.click('review-revision-apply'); await app.click('review-revision-apply');
  assert.deepEqual((await app.exported()).notes,[incoming.notes[0],base.notes[1],base.notes[2]]);
  assert.match(app.get('review-status').textContent,/No changes since the last download request/);
});

test('resolution and reopening are deliberate reviewed replacements, including exact point and range changes',async()=>{
  const {app,base}=await seeded(); const incoming={...base,notes:[note(1,'Repair opening',{resolved:true}),note(2,'Keep this concern',{start_ms:4000,end_ms:6000})]};
  await open(app,incoming); await choose(app,0); await choose(app,1); await app.click('review-revision-apply');
  const updated=await app.exported(); assert(updated.notes[0].resolved); assert.equal(updated.notes[1].end_ms,6000);
  const reopened={...updated,notes:[{...updated.notes[0],resolved:false,start_ms:6000}]};
  await open(app,reopened); assert.match(rows(app)[0].children[1].textContent,/Resolved/); assert.match(rows(app)[0].children[2].textContent,/00:00:06.000 · Open/);
  await choose(app,0); await app.click('review-revision-apply'); assert.equal((await app.exported()).notes[0].resolved,false);
  assert.equal((await app.exported()).notes[0].start_ms,6000);
});

test('unrelated editor draft, triage, queue anchor and media state survive selected revisions',async()=>{
  const {app,base}=await seeded(); await app.rows()[0].children[0].emit('click');
  await app.actions(1)[0].emit('click'); app.get('review-text').value='My unfinished local edit'; app.video.currentTime=4; await app.click('review-point');
  app.video.currentTime=1; await app.click('range-start'); app.video.currentTime=5; await app.click('range-end'); await app.click('range-repeat');
  app.video.paused=false; const playback=app.video.currentTime,range=app.get('range-status').textContent;
  app.get('review-order').value='timeline'; await app.get('review-order').emit('change');
  const incoming={...base,notes:[note(1,'Reanchored issue',{start_ms:3500})]};
  await open(app,incoming); await choose(app,0); await app.click('review-revision-apply');
  assert.equal(app.get('review-text').value,'My unfinished local edit'); assert.match(app.get('review-anchor').textContent,/00:00:04.000/);
  assert.equal(app.get('review-save').textContent,'Save note changes'); assert.equal(app.get('review-order').value,'timeline');
  assert.match(app.get('review-navigation').textContent,/Selected issue #1 at 00:00:03.500/);
  assert.equal(app.video.currentTime,playback); assert.equal(app.video.paused,false); assert.equal(app.video.plays,0);
  assert.equal(app.get('range-status').textContent,range); assert.equal(app.get('range-repeat').attrs['aria-pressed'],'true');
  await app.click('review-save'); const saved=await app.exported(); assert.equal(saved.notes[1].text,'My unfinished local edit'); assert.equal(saved.notes[1].start_ms,4000);
});

test('an active edit of a selected issue blocks all application until the editor deliberately cancels it',async()=>{
  const {app,base}=await seeded(); await open(app,{...base,notes:[note(1,'Incoming'),note(8,'Addition')]}); await choose(app,0); await choose(app,1);
  await app.actions(0)[0].emit('click'); app.get('review-text').value='Unsaved current wording';
  assert(app.get('review-revision-apply').disabled); assert.match(summary(app),/selected issue is open in the note editor/);
  await app.click('review-revision-apply'); assert.deepEqual((await app.exported()).notes,base.notes);
  assert.equal(app.get('review-text').value,'Unsaved current wording');
  await app.click('review-cancel'); assert(!app.get('review-revision-apply').disabled); await app.click('review-revision-apply');
  assert.deepEqual((await app.exported()).notes.map(n=>n.text),['Incoming','Keep this concern','Only in my notebook','Addition']);
});

test('saving local edits or changing issue status invalidates every selected revision without losing newer work',async()=>{
  const {app,base}=await seeded(); const incoming={...base,notes:[note(1,'Old incoming')]};
  await open(app,incoming); await choose(app,0); const old=choice(app,0);
  await app.actions(0)[0].emit('click'); app.get('review-text').value='New local wording'; await app.click('review-save');
  old.checked=true; await old.emit('change'); await app.click('review-revision-apply');
  assert(app.get('review-revision-panel').hidden); assert.equal((await app.exported()).notes[0].text,'New local wording');
  await open(app,incoming); await choose(app,0); await app.actions(1)[1].emit('click'); await app.click('review-revision-apply');
  const saved=await app.exported(); assert.equal(saved.notes[0].text,'New local wording'); assert(saved.notes[1].resolved); assert(app.get('review-revision-open').disabled);
});

test('cancel and restart review reset choices, while cancelling loaded files also prevents stale application',async()=>{
  const {app,base}=await seeded(); const incoming={...base,notes:[note(1,'Incoming')]};
  await open(app,incoming); await choose(app,0); const old=choice(app,0);
  await app.click('review-revision-cancel'); assert(app.get('review-revision-panel').hidden); assert(!app.get('review-merge').disabled);
  await app.click('review-revision-apply'); assert.deepEqual((await app.exported()).notes,base.notes);
  await app.click('review-revision-open'); old.checked=true; await old.emit('change');
  assert(!choice(app,0).checked); assert(app.get('review-revision-apply').disabled);
  await choose(app,0); await app.click('review-discard-import'); await app.click('review-revision-open'); await app.click('review-revision-apply');
  assert(app.get('review-revision-panel').hidden); assert.deepEqual((await app.exported()).notes,base.notes);
});

test('a newer file selection replaces the review and older asynchronous reads cannot revive it',async()=>{
  const {app,base}=await seeded(); await open(app,{...base,notes:[note(1,'Earlier preview')]}); await choose(app,0);
  let finish; app.get('review-file').files=[{size:100,text:()=>new Promise(resolve=>finish=resolve)}];
  const reading=app.get('review-file').emit('change'); assert(app.get('review-revision-panel').hidden);
  await open(app,{...base,notes:[note(1,'Latest incoming')]}); await choose(app,0);
  finish(JSON.stringify({...base,notes:[note(1,'Late old read')]})); await reading;
  assert.match(rows(app)[0].children[2].textContent,/Latest incoming/); await app.click('review-revision-apply');
  assert.equal((await app.exported()).notes[0].text,'Latest incoming');
});

test('multi-file or different-cut imports cannot open revision review, retaining the current notebook',async()=>{
  const {app,base}=await seeded(); const incoming={...base,notes:[note(1,'Incoming')]};
  await app.loadMany([incoming,incoming]); assert(app.get('review-revision-open').disabled); await app.click('review-revision-open'); assert(app.get('review-revision-panel').hidden);
  assert(!app.get('review-merge').disabled,'ordinary multi-reviewer merge stays available');
  await open(app,incoming); await choose(app,0);
  await app.load({...incoming,source:{...incoming.source,media_sha256:'b'.repeat(64)}}); await app.click('review-revision-open'); await app.click('review-revision-apply');
  assert(app.get('review-revision-panel').hidden); assert(app.get('review-revision-open').disabled); assert.deepEqual((await app.exported()).notes,base.notes);
});

test('capacity uses selected additions, so an editor can still revise a full notebook',async()=>{
  const {app,base}=await seeded(); const full={...base,notes:Array.from({length:500},(_,i)=>note(i+1,'Issue '+(i+1)))};
  await app.load(full); await app.click('review-apply');
  await open(app,{...base,notes:[note(1,'Corrected at capacity'),note(501,'Optional addition')]}); await choose(app,0); await choose(app,1);
  assert(app.get('review-revision-apply').disabled); assert.match(summary(app),/Result: 501 notes.*exceeds 500 notes/);
  await app.click('review-revision-apply'); assert.equal((await app.exported()).notes[0].text,'Issue 1');
  await choose(app,1,false); assert(!app.get('review-revision-apply').disabled); await app.click('review-revision-apply');
  const saved=await app.exported(); assert.equal(saved.notes.length,500); assert.equal(saved.notes[0].text,'Corrected at capacity');
});

test('empty and identical returned copies make no proposals and never delete current-only notes',async()=>{
  const {app,base}=await seeded(); await open(app,base); assert.equal(rows(app).length,0); assert.match(summary(app),/3 identical notes; 0 current-only/);
  assert(app.get('review-revision-apply').disabled); await app.click('review-revision-apply');
  await open(app,{...base,notes:[]}); assert.equal(rows(app).length,0); assert.match(summary(app),/3 current-only notes kept/);
  await app.click('review-revision-apply'); assert.deepEqual((await app.exported()).notes,base.notes);
});

test('exact Unicode, multiline text and markup stay readable inert text; IDs never imply authorship',async()=>{
  const {app,base}=await seeded(); const text='Café 🌱\n</script><img src=x onerror=alert(1)> & literal';
  await open(app,{...base,notes:[note(1,text),note(100,'Keep this concern',{start_ms:2000})]});
  assert.equal(rows(app)[0].children[2].textContent,'Incoming #1 · 00:00:01.000 · Open\n'+text);
  assert.match(rows(app)[1].children[1].textContent,/addition is not deduplicated by wording/);
  assert(!app.created.some(node=>node.tag==='img'));
  await choose(app,0); await choose(app,1); await app.click('review-revision-apply');
  const saved=await app.exported(); assert.equal(saved.notes[0].text,text); assert.equal(saved.notes.length,4); assert.equal(saved.notes[3].id,100);
  assert.deepEqual(Object.keys(saved).sort(),['contract','notes','source']); assert(!JSON.stringify(saved).includes('reviewer_identity'));
});
