'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {setup} = require('./screening-player-harness.cjs');
const html = fs.readFileSync(path.join(__dirname, '../editor/screening/output.mbt'), 'utf8').replace(/\\"/g, '"');
for (const id of ['review-undo', 'review-redo']) assert.match(html, new RegExp('id="' + id + '"[^>]*disabled'));
assert.match(html, /id="review-history-status" role="status"/);
const undo = h => h.click('review-undo');
const redo = h => h.click('review-redo');
const notes = async h => (await h.exported()).notes;
const clone = value => JSON.parse(JSON.stringify(value));

test('add, edit and status changes undo and redo as exact notebook snapshots', async () => {
  const h = setup();
  assert(h.get('review-undo').disabled); assert(h.get('review-redo').disabled);
  await h.add('Original 月', 1.125); const initial = await notes(h);
  await h.actions(0)[0].emit('click'); h.get('review-text').value = 'Revised\n<script>';
  await h.click('review-save'); const edited = await notes(h);
  await h.actions(0)[1].emit('click'); const resolved = await notes(h);
  assert.equal(resolved[0].resolved, true);
  await undo(h); assert.deepEqual(await notes(h), edited);
  await undo(h); assert.deepEqual(await notes(h), initial);
  await undo(h); assert.deepEqual(await notes(h), []);
  await redo(h); await redo(h); await redo(h);
  assert.deepEqual(await notes(h), resolved); assert(h.get('review-redo').disabled);
});

test('a new saved change branches from undo and discards only the redo future', async () => {
  const h = setup(); await h.add('A'); await h.add('B');
  await undo(h); await h.add('C'); await redo(h);
  assert.deepEqual((await notes(h)).map(n => n.text), ['A', 'C']);
  assert(h.get('review-redo').disabled);
  await undo(h); assert.deepEqual((await notes(h)).map(n => n.text), ['A']);
});

test('same-ID merge conflict is one reversible step and keeps both distinct notes', async () => {
  const h = setup(); await h.add('Local'); const before = await h.exported();
  const incoming = clone(before); incoming.notes[0].text = 'Reviewer different text';
  await h.load(incoming); await h.click('review-merge'); const merged = await notes(h);
  assert.equal(merged.length, 2); assert.equal(merged[0].id, 1); assert.equal(merged[1].id, 2);
  assert.match(h.get('review-undo').textContent, /Merge notebooks/);
  await undo(h); assert.deepEqual(await notes(h), before.notes);
  assert(h.get('review-merge').disabled); await redo(h); assert.deepEqual(await notes(h), merged);
});

test('explicit empty replacement can recover the entire previous notebook', async () => {
  const h = setup(); await h.add('Keep me'); const before = await h.exported();
  await h.load({...before, notes: []}); await h.click('review-apply');
  assert.deepEqual(await notes(h), []); await undo(h); assert.deepEqual(await notes(h), before.notes);
  await redo(h); assert.deepEqual(await notes(h), []);
});

test('selected notebook revision application is atomic in history', async () => {
  const h = setup(); await h.add('Current'); const before = await h.exported();
  const incoming = clone(before); incoming.notes[0].text = 'Incoming'; incoming.notes[0].start_ms = 2500;
  await h.load(incoming); await h.click('review-revision-open');
  const choice = h.get('review-revision-list').children[0].children[0].children[0];
  choice.checked = true; await choice.emit('change'); await h.click('review-revision-apply');
  assert.deepEqual(await notes(h), incoming.notes);
  await undo(h); assert.deepEqual(await notes(h), before.notes); assert(h.get('review-revision-panel').hidden);
  await redo(h); assert.deepEqual(await notes(h), incoming.notes);
});

test('uncommitted new and existing-note drafts block history without discarding text or anchors', async () => {
  const h = setup(); await h.add('A'); await h.add('B');
  h.video.currentTime = 4; await h.click('review-point'); h.get('review-text').value = 'Uncommitted';
  await h.get('review-text').emit('input'); const anchor = h.get('review-anchor').textContent;
  assert(h.get('review-undo').disabled); await undo(h); assert.equal((await notes(h)).length, 2);
  assert.equal(h.get('review-text').value, 'Uncommitted'); assert.equal(h.get('review-anchor').textContent, anchor);
  await h.click('review-cancel'); await h.actions(0)[0].emit('click'); await undo(h);
  assert.equal((await notes(h)).length, 2); assert.equal(h.get('review-text').value, 'A');
  await h.click('review-cancel'); await undo(h); assert.equal((await notes(h)).length, 1);
});

test('undo invalidates a pending asynchronous notebook read and visible revision selections', async () => {
  const h = setup(); await h.add('A'); await h.add('B'); const incoming = await h.exported();
  let finish; h.get('review-file').files = [{name:'late.json', size:100, text:()=>new Promise(r=>finish=r)}];
  const read = h.get('review-file').emit('change'); await undo(h);
  finish(JSON.stringify(incoming)); await read;
  assert(h.get('review-apply').disabled); assert(h.get('review-revision-open').disabled);
  assert.deepEqual((await notes(h)).map(n=>n.text), ['A']);
});

test('history preserves triage, playback and repeat range without seeking or autoplay', async () => {
  const h = setup(); await h.add('A',1); await h.add('B',2);
  h.video.currentTime=1; await h.click('range-start'); h.video.currentTime=4; await h.click('range-end'); await h.click('range-repeat');
  h.video.paused=false; h.video.currentTime=3; h.get('review-search').value='A'; await h.get('review-search').emit('input');
  const range=h.get('range-status').textContent; await undo(h);
  assert.equal(h.video.currentTime,3); assert.equal(h.video.paused,false); assert.equal(h.video.plays,0);
  assert.equal(h.get('range-status').textContent,range); assert.equal(h.get('review-search').value,'A');
});

test('history retains at most twenty undo steps and no-op save does not create a step', async () => {
  const h=setup(); for(let i=0;i<25;i++) await h.add('Note '+i);
  for(let i=0;i<25;i++) await undo(h);
  assert.equal((await notes(h)).length,5); assert(h.get('review-undo').disabled);
  await redo(h); const status=h.get('review-history-status').textContent;
  await h.actions(0)[0].emit('click'); await h.click('review-save');
  assert.equal(h.get('review-history-status').textContent,status); assert(!h.get('review-redo').disabled);
});

test('restored state downloads and reopens, while earlier downloaded files stay unchanged', async () => {
  const h=setup(); await h.add('First'); await h.add('Second'); const before=await h.exported();
  const oldBlob=h.downloads.at(-1).blob; await undo(h);
  assert.match(h.get('review-status').textContent,/existing downloaded files are unchanged/);
  const restored=await h.exported(); assert.deepEqual(JSON.parse(await oldBlob.text()),before);
  const folder=process.env.MOONCAST_EVIDENCE_DIR || fs.mkdtempSync(path.join(os.tmpdir(),'screening-history-'));
  const file=path.join(folder,'history-restored-notebook.json'); fs.writeFileSync(file,await h.downloads.at(-1).blob.text());
  const next=setup(); await next.load(JSON.parse(fs.readFileSync(file,'utf8'))); await next.click('review-apply');
  assert.deepEqual(await notes(next),restored.notes); assert.equal(restored.notes.length,1);
  assert(!JSON.stringify(restored).includes('historyIndex')); console.log('Restored notebook evidence: '+file);
});

test('large notebooks evict old snapshots at the serialized-history byte bound', async () => {
  const h=setup(); const base=await h.exported();
  base.notes=Array.from({length:500},(_,i)=>({id:i+1,start_ms:1000,end_ms:null,text:'x'.repeat(2000),resolved:false}));
  await h.load(base); await h.click('review-apply');
  for(let i=0;i<8;i++) await h.actions(0)[1].emit('click');
  const available=Number(h.get('review-history-status').textContent.split(' ')[0]);
  assert(available>0 && available<8);
  for(let i=0;i<20;i++) await undo(h);
  assert(h.get('review-undo').disabled); assert.equal((await notes(h)).length,500);
});

test('history restores a selected issue anchor without jumping, or clears selection if removed', async () => {
  const h=setup(); await h.add('A',1); await h.add('B',2); await h.click('review-next');
  await h.actions(0)[0].emit('click'); h.video.currentTime=3; await h.click('review-point'); await h.click('review-save');
  assert.match(h.get('review-navigation').textContent,/00:00:03.000/);
  await undo(h); assert.match(h.get('review-navigation').textContent,/00:00:01.000/);
  assert.equal(h.video.currentTime,3);
  await undo(h); await undo(h); assert.match(h.get('review-navigation').textContent,/Choose Next matching issue/);
});
