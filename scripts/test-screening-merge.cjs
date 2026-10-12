'use strict';
// Integration checks run the full literal production player through its real
// HTML-linked controls. The shared harness doubles DOM/media/file/download APIs.
const assert = require('node:assert/strict');
const {test} = require('node:test');
const {setup} = require('./screening-player-harness.cjs');
const preview = app => app.get('review-merge-preview').children.map(row => row.textContent).join('\n');
const summary = app => app.get('review-import-status').textContent;
const note = (id, text, extra = {}) => ({id, start_ms:1234, end_ms:null, text, resolved:false, ...extra});
const notebook = (base, notes) => ({...structuredClone(base), notes});
async function seed(text = 'Current issue') { const app=setup(); await app.add(text); return {app, base:await app.exported()}; }

test('merge two reviewer files into current notes, download and reopen combined notebook', async()=>{
  const {app,base}=await seed();
  const first=notebook(base,[note(1,'First reviewer'),note(2,'Shared suggestion',{start_ms:2000,end_ms:3000})]);
  const second=notebook(base,[note(1,'Second reviewer'),note(8,'Shared suggestion',{start_ms:2000,end_ms:3000})]);
  await app.loadMany([first,second]);
  assert.equal(app.rows().length,1); assert(app.get('review-apply').disabled); assert(!app.get('review-merge').disabled);
  assert.match(summary(app),/3 additions, 1 exact duplicates skipped/);
  assert.match(preview(app),/Add as #2 from Notebook 1 \(Reviewer 1.json\) \(source #1\)/); assert.match(preview(app),/Reviewer 2.json/);
  assert.match(app.rows()[0].children[0].textContent,/#1 ·/);
  await app.click('review-apply'); assert.equal(app.rows().length,1,'multi-file replacement is unavailable even through direct handler invocation');
  await app.click('review-merge'); await app.click('review-merge');
  const combined=await app.exported();
  assert.deepEqual(combined.notes.map(n=>n.text),['Current issue','First reviewer','Shared suggestion','Second reviewer']);
  assert.deepEqual(combined.notes.map(n=>n.id),[1,2,3,4]); assert.deepEqual(combined.source,base.source);
  assert.equal(app.video.plays,0); assert(app.get('review-merge').disabled); assert.equal(preview(app),'');
  const reopened=setup(); await reopened.load(combined); await reopened.click('review-apply');
  assert.deepEqual((await reopened.exported()).notes,combined.notes);
});

test('preview names same-ID divergent text, time and status conflicts and keeps both contents', async()=>{
  const {app,base}=await seed('Same wording');
  const files=[notebook(base,[note(1,'Changed wording')]),notebook(base,[note(1,'Same wording',{start_ms:2000})]),notebook(base,[note(1,'Same wording',{resolved:true})])];
  await app.loadMany(files);
  assert.match(summary(app),/3 same-ID content conflicts/);
  assert.match(preview(app),/ID conflict: Notebook 1 \(Reviewer 1.json\) #1 differs from Current notebook #1/);
  assert.match(preview(app),/Keep both distinct contents; the incoming note receives a new local ID/);
  assert.match(summary(app),/1 differing-status additions kept separately/);
  await app.click('review-merge'); const merged=await app.exported();
  assert.equal(merged.notes.length,4); assert.equal(merged.notes[0].resolved,false); assert.equal(merged.notes[3].resolved,true);
  assert.deepEqual(merged.notes.map(n=>n.id),[1,2,3,4]);
});

test('exact duplicates use content and status rather than IDs; repeat import is a no-op', async()=>{
  const {app,base}=await seed(); const file=notebook(base,[note(91,'Current issue'),note(3,'Fresh'),note(4,'Fresh')]);
  await app.load(file); assert.match(summary(app),/1 additions, 2 exact duplicates skipped/); await app.click('review-merge');
  const once=await app.exported(); await app.load(file); assert.match(summary(app),/0 additions, 3 exact duplicates skipped/);
  assert(app.get('review-merge').disabled); await app.click('review-merge'); assert.deepEqual((await app.exported()).notes,once.notes);
});

test('an exact duplicate with a divergent reused ID exposes the conflict without creating a third note', async()=>{
  const {app,base}=await seed(); await app.add('Already here',2);
  await app.load(notebook(base,[note(1,'Already here',{start_ms:2000})]));
  assert.match(summary(app),/0 additions, 1 exact duplicates skipped/); assert.match(summary(app),/1 same-ID content conflicts/);
  assert.match(preview(app),/exact content already exists and is coalesced; both distinct contents remain/);
  await app.click('review-merge'); assert.equal(app.rows().length,2);
});

test('merge preserves an in-progress edit, its anchor and stable local ID', async()=>{
  const {app,base}=await seed(); await app.actions(0)[0].emit('click');
  app.get('review-text').value='Unsaved revision'; app.video.currentTime=4; await app.click('review-point');
  await app.load(notebook(base,[note(1,'Incoming')])); await app.click('review-merge');
  assert.equal(app.get('review-text').value,'Unsaved revision'); assert.match(app.get('review-anchor').textContent,/00:00:04.000/);
  assert.equal(app.get('review-save').textContent,'Save note changes');
  await app.click('review-save'); const saved=await app.exported();
  assert.deepEqual(saved.notes.map(n=>[n.id,n.text,n.start_ms]),[[1,'Unsaved revision',4000],[2,'Incoming',1234]]);
});

test('merge preserves a new note draft typed after preview and does not autoplay', async()=>{
  const {app,base}=await seed(); await app.load(notebook(base,[note(7,'Incoming')]));
  app.video.currentTime=5; await app.click('review-point'); app.get('review-text').value='Draft after preview';
  await app.click('review-merge'); assert.equal(app.get('review-text').value,'Draft after preview'); await app.click('review-save');
  assert.equal((await app.exported()).notes[2].start_ms,5000); assert.equal(app.video.plays,0);
});

test('cancel preview or a pending read leaves current notes and draft untouched', async()=>{
  const {app,base}=await seed(); app.video.currentTime=2; await app.click('review-point'); app.get('review-text').value='My draft';
  await app.load(notebook(base,[note(8,'Incoming')])); await app.click('review-discard-import'); await app.click('review-merge');
  assert.equal(app.rows().length,1); assert.equal(preview(app),''); assert.equal(app.get('review-text').value,'My draft');
  let finish; app.get('review-file').files=[{size:100,text:()=>new Promise(resolve=>finish=resolve)}];
  const reading=app.get('review-file').emit('change'); assert(!app.get('review-discard-import').disabled);
  await app.click('review-discard-import'); finish(JSON.stringify(base)); await reading;
  assert(app.get('review-merge').disabled); assert(app.get('review-apply').disabled); assert.equal(app.get('review-text').value,'My draft');
  assert.match(summary(app),/discarded/);
});

test('a wrong-cut, malformed or unreadable file rejects the whole selected batch', async()=>{
  const {app,base}=await seed(); const good=notebook(base,[note(1,'Incoming')]);
  const wrong=structuredClone(good); wrong.source.media_sha256='b'.repeat(64);
  await app.loadMany([good,wrong]); assert.match(summary(app),/Notebook 2.*different media/);
  assert(app.get('review-merge').disabled); assert.equal(preview(app),''); await app.click('review-merge'); assert.equal(app.rows().length,1);
  for(const text of [async()=>'{bad',async()=>{throw Error('file no longer readable');}]) {
    app.get('review-file').files=[{name:'good.json',size:100,text:async()=>JSON.stringify(good)},{name:'broken.json',size:100,text}];
    await app.get('review-file').emit('change'); assert.match(summary(app),/Notebook 2 \(broken.json\)/);
    assert.match(summary(app),/no selected file was applied/); assert(app.get('review-merge').disabled); assert.equal(app.rows().length,1);
  }
});

test('batch bounds reject before reading; capacity blocks merge without partial additions', async()=>{
  const {app,base}=await seed(); let reads=0;
  for(const files of [Array.from({length:11},()=>({size:1,text:async()=>{reads++;}})),[{size:40*1024*1024,text:async()=>{reads++;}},{size:30*1024*1024,text:async()=>{reads++;}}]]) {
    app.get('review-file').files=files; await app.get('review-file').emit('change'); assert(app.get('review-merge').disabled); assert(app.get('review-apply').disabled);
  }
  assert.equal(reads,0);
  const full=notebook(base,Array.from({length:500},(_,i)=>note(i+1,'Incoming '+i)));
  await app.load(full); assert.match(summary(app),/501 total notes.*Merge blocked/); assert(app.get('review-merge').disabled);
  assert(!app.get('review-apply').disabled,'single-file replacement remains an explicit option');
  await app.click('review-merge'); assert.equal(app.rows().length,1);
});

test('capacity is based on distinct combined notes, including deduplication across ten files', async()=>{
  const {app,base}=await seed(); const existing=notebook(base,Array.from({length:499},(_,i)=>note(i+1,'Issue '+i)));
  await app.load(existing); await app.click('review-apply');
  const file=notebook(base,[note(999,'Issue 0'),note(1000,'Final issue')]);
  await app.loadMany(Array.from({length:10},()=>file)); assert.match(summary(app),/1 additions, 19 exact duplicates skipped/);
  assert(!app.get('review-merge').disabled); await app.click('review-merge'); assert.equal(app.rows().length,500);
  await app.load(file); assert(app.get('review-merge').disabled); assert.match(summary(app),/Nothing new to merge/);
});

test('saved local changes invalidate all merge previews and older asynchronous reads', async()=>{
  const {app,base}=await seed(); const incoming=notebook(base,[note(1,'Incoming')]);
  await app.load(incoming); await app.actions(0)[1].emit('click'); await app.click('review-merge');
  assert.equal(app.rows().length,1); assert(app.get('review-merge').disabled); assert.equal(preview(app),'');
  let finish; app.get('review-file').files=[{size:100,text:()=>new Promise(resolve=>finish=resolve)}]; const reading=app.get('review-file').emit('change');
  await app.add('New local note'); finish(JSON.stringify(incoming)); await reading; await app.click('review-merge');
  assert.equal(app.rows().length,2); assert(app.get('review-merge').disabled);
});

test('new file selection supersedes a slow multi-file selection without stale preview', async()=>{
  const {app,base}=await seed(); let finish, entered; const secondStarted=new Promise(resolve=>entered=resolve);
  app.get('review-file').files=[{size:100,text:async()=>JSON.stringify(notebook(base,[note(1,'Old first')]))},{size:100,text:()=>{entered(); return new Promise(resolve=>finish=resolve);}}];
  const old=app.get('review-file').emit('change'); await secondStarted; assert.equal(typeof finish,'function');
  await app.load(notebook(base,[note(1,'Latest')])); finish(JSON.stringify(notebook(base,[note(1,'Old second')]))); await old;
  assert(!preview(app).includes('Old first')); await app.click('review-merge'); assert.deepEqual((await app.exported()).notes.map(n=>n.text),['Current issue','Latest']);
});

test('merge preserves existing duplicate notes and pre-merge download restores via explicit replacement', async()=>{
  const {app,base}=await seed(); await app.add('Current issue'); const before=await app.exported();
  await app.load(notebook(base,[note(99,'Current issue'),note(100,'Incoming')])); await app.click('review-merge');
  assert.equal(app.rows().length,3); await app.load(before); assert.equal(app.rows().length,3);
  await app.click('review-apply'); assert.deepEqual((await app.exported()).notes,before.notes);
});

test('empty notebook batches never erase current notes; one empty notebook can explicitly replace', async()=>{
  const {app,base}=await seed(); const empty=notebook(base,[]);
  await app.loadMany([empty,empty]); assert(app.get('review-merge').disabled); assert(app.get('review-apply').disabled);
  await app.click('review-merge'); await app.click('review-apply'); assert.equal(app.rows().length,1);
  await app.load(empty); assert(app.get('review-merge').disabled); assert(!app.get('review-apply').disabled);
  await app.click('review-apply'); assert.equal(app.rows().length,0);
});

test('preview treats filename and Unicode feedback as inert exact text', async()=>{
  const {app,base}=await seed(); const words='Café 🌱\n</script><img src=x onerror=alert(1)>';
  const incoming=notebook(base,[note(1,words),note(2,words+' ')]); const raw=JSON.stringify(incoming);
  app.get('review-file').files=[{name:'<img src=x>.json',size:Buffer.byteLength(raw),text:async()=>raw}];
  await app.get('review-file').emit('change'); assert.match(preview(app),/<img src=x>.json/); assert(preview(app).includes(words));
  assert.match(summary(app),/2 additions, 0 exact duplicates skipped/); assert(!app.created.some(n=>n.tag==='img'));
  await app.click('review-merge'); assert.deepEqual((await app.exported()).notes.slice(1).map(n=>n.text),[words,words+' ']);
});

test('a selected notebook cannot reuse IDs within itself even though cross-file conflicts are mergeable', async()=>{
  const {app,base}=await seed(); await app.loadMany([notebook(base,[note(1,'Valid')]),notebook(base,[note(1,'One'),note(1,'Two')])]);
  assert.match(summary(app),/Notebook 2.*invalid ID/); assert(app.get('review-merge').disabled); assert.equal(app.rows().length,1);
});
