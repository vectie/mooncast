'use strict';
const assert = require('node:assert/strict');
const {test} = require('node:test');
const {setup, script} = require('./screening-player-harness.cjs');

test('capture a frozen point, edit and cancel text, jump without playback', async()=>{
  const app=setup(); await app.add('Check Café 🌱\nA second line.');
  assert.equal(app.rows().length,1); assert.match(app.rows()[0].children[0].textContent,/00:00:01.234/);
  app.video.currentTime=5;await app.rows()[0].children[0].emit('click');assert.equal(app.video.currentTime,1.234);assert.equal(app.video.plays,0);
  await app.actions(0)[0].emit('click');assert(app.get('review-text').focused);app.get('review-text').value='Replacement';await app.click('review-cancel');assert.match(app.rows()[0].children[1].textContent,/Café/);
  await app.actions(0)[0].emit('click');app.get('review-text').value='Revised wording';await app.click('review-save');
  assert.equal(app.rows().length,1);assert.equal(app.rows()[0].children[1].textContent,'Revised wording');
  const saved=await app.exported();assert.equal(saved.notes[0].start_ms,1234);assert.equal(saved.notes[0].resolved,false);
});

test('capture marked A–B range, freeze it, resolve/reopen and filter issues', async()=>{
  const app=setup();app.video.currentTime=1.25;await app.click('range-start');app.video.currentTime=3.75;await app.click('range-end');await app.click('review-range');
  await app.click('range-clear');app.get('review-text').value='Repair transition';await app.click('review-save');await app.add('Another issue',4);
  await app.actions(0)[1].emit('click');assert.match(app.rows()[0].children[0].textContent,/Resolved/);
  app.get('review-filter').value='open';await app.get('review-filter').emit('change');assert.equal(app.rows().length,1);assert.match(app.rows()[0].children[1].textContent,/Another/);
  app.get('review-filter').value='resolved';await app.get('review-filter').emit('change');assert.equal(app.rows().length,1);await app.actions(0)[1].emit('click');assert.equal(app.rows().length,0);
  const saved=await app.exported();assert.equal(saved.notes[0].start_ms,1250);assert.equal(saved.notes[0].end_ms,3750);assert.equal(saved.notes[0].resolved,false);
});

test('download, reopen exact notebook and explicitly replace current notes',async()=>{
  const first=setup();await first.add('Source note');const saved=await first.exported();assert.equal(saved.contract,'mooncast.screening-notebook.v1');assert.equal(saved.source.media_sha256,'a'.repeat(64));assert.deepEqual(JSON.parse(saved.source.plan_json),first.data);
  const reopened=setup();await reopened.add('Keep until explicit replace');await reopened.load(saved);assert.equal(reopened.rows()[0].children[1].textContent,'Keep until explicit replace');assert.equal(reopened.get('review-apply').disabled,false);
  assert.match(reopened.get('review-import-status').textContent,/replace 1 current notes/);await reopened.click('review-apply');assert.equal(reopened.rows()[0].children[1].textContent,'Source note');assert.equal(reopened.get('review-apply').disabled,true);
  await reopened.add('New note',2);const next=await reopened.exported();assert.deepEqual(next.notes.map(note=>note.id),[1,2]);assert.equal(reopened.video.plays,0);
});

test('mismatched media or changed captions/chapter/title cannot replace current notes',async()=>{
  const app=setup();await app.add('Keep this');const saved=await app.exported();
  for(const change of [value=>value.source.media_sha256='b'.repeat(64),value=>{const plan=JSON.parse(value.source.plan_json);plan.title='Different cut';value.source.plan_json=JSON.stringify(plan);},value=>{const plan=JSON.parse(value.source.plan_json);plan.cues[0].text='Changed';value.source.plan_json=JSON.stringify(plan);}]) {
    const wrong=structuredClone(saved);change(wrong);await app.load(wrong);assert(app.get('review-apply').disabled);assert.match(app.get('review-import-status').textContent,/different media or a different screening plan/);await app.click('review-apply');assert.equal(app.rows()[0].children[1].textContent,'Keep this');
  }
});

test('late file reads and changes during import never erase newer notes',async()=>{
  const app=setup();await app.add('Original');const saved=await app.exported();let resolve;
  app.get('review-file').files=[{size:100,text:()=>new Promise(done=>resolve=done)}];const read=app.get('review-file').emit('change');await app.add('Newer');resolve(JSON.stringify(saved));await read;assert(app.get('review-apply').disabled);assert.equal(app.rows().length,2);
  await app.load(saved);await app.actions(0)[1].emit('click');await app.click('review-apply');assert.equal(app.rows().length,2);assert.match(app.rows()[0].children[0].textContent,/Resolved/);
});

test('latest file selection wins even when older read finishes last',async()=>{
  const app=setup();await app.add('Current');const saved=await app.exported();let resolve;
  app.get('review-file').files=[{size:100,text:()=>new Promise(done=>resolve=done)}];const old=app.get('review-file').emit('change');
  const next=structuredClone(saved);next.notes[0].text='Latest selected';await app.load(next);resolve(JSON.stringify(saved));await old;await app.click('review-apply');assert.equal(app.rows()[0].children[1].textContent,'Latest selected');
});

test('invalid note data and malformed/oversized files retain current session',async()=>{
  const app=setup();await app.add('Keep');const saved=await app.exported();
  for(const mutate of [n=>n.start_ms=-1,n=>n.end_ms=100,n=>n.start_ms=6001,n=>n.text=' ',n=>n.text='a'.repeat(2001),n=>n.resolved='yes',n=>n.id=0]) {
    const bad=structuredClone(saved);mutate(bad.notes[0]);await app.load(bad);assert(app.get('review-apply').disabled);assert.equal(app.rows().length,1);
  }
  const duplicate=structuredClone(saved);duplicate.notes.push({...duplicate.notes[0]});await app.load(duplicate);assert(app.get('review-apply').disabled);
  app.get('review-file').files=[{size:10,text:async()=>'{nope'}];await app.get('review-file').emit('change');assert.match(app.get('review-import-status').textContent,/Cannot load notebook/);
  let read=false;app.get('review-file').files=[{size:64*1024*1024+1,text:async()=>{read=true;}}];await app.get('review-file').emit('change');assert(!read);assert.match(app.get('review-import-status').textContent,/exceeds 64 MiB/);assert.equal(app.rows()[0].children[1].textContent,'Keep');
});

test('point needs loaded media and valid text; invalid marks preserve editor',async()=>{
  const app=setup();app.video.readyState=0;await app.click('review-point');app.get('review-text').value='Not anchored';await app.click('review-save');assert.equal(app.rows().length,0);
  app.video.readyState=1;app.video.currentTime=2;await app.click('review-point');await app.click('review-range');assert.match(app.get('review-status').textContent,/unchanged/);
  for(const text of [' ','a'.repeat(2001),'bad\0text']){app.get('review-text').value=text;await app.click('review-save');assert.equal(app.rows().length,0);}
  app.get('review-text').value='Valid';app.video.currentTime=5;await app.click('review-save');assert.equal((await app.exported()).notes[0].start_ms,2000);
});

test('notebook text is inert DOM text and IDs remain unique after external import',async()=>{
  const app=setup();await app.add('</script><img src=x onerror=alert(1)> & 🌱');let saved=await app.exported();saved.notes[0].id=Number.MAX_SAFE_INTEGER-1;
  await app.load(saved);await app.click('review-apply');await app.add('Second');saved=await app.exported();assert.equal(saved.notes[1].id,1);assert.equal(app.rows()[0].children[1].textContent,'</script><img src=x onerror=alert(1)> & 🌱');assert(!app.created.some(node=>node.tag==='img'));assert(!/\.innerHTML\s*=/.test(script));
});

test('download failures keep notes and subsequent downloads revoke older URLs',async()=>{
  const app=setup();await app.add('Keep');await app.exported();await app.exported();assert.equal(app.revoked.length,1);assert.equal(app.downloads[0].download,'screening-notes.json');assert.match(app.get('review-status').textContent,/check that your browser saved/);
  const blocked=setup({downloadError:true});await blocked.add('Keep on failed save');await blocked.click('review-download');assert.match(blocked.get('review-status').textContent,/could not download/);assert.equal(blocked.rows().length,1);
});

test('empty notebook is an explicit reversible-by-file replacement, not acceptance',async()=>{
  const app=setup();await app.add('Keep');const saved=await app.exported();await app.load({...saved,notes:[]});assert.equal(app.rows().length,1);await app.click('review-apply');assert.equal(app.rows().length,0);await app.load(saved);await app.click('review-apply');assert.equal(app.rows().length,1);assert(!('client_acceptance' in (await app.exported())));
});

test('500-note bound keeps existing feedback and allows editing at capacity',async()=>{
  const app=setup();await app.add('Seed');const saved=await app.exported();saved.notes=Array.from({length:500},(_,i)=>({...saved.notes[0],id:i+1,text:'Issue '+i}));await app.load(saved);await app.click('review-apply');await app.add('Too many');assert.equal(app.rows().length,500);assert.match(app.get('review-status').textContent,/limited to 500/);
  await app.actions(0)[0].emit('click');app.get('review-text').value='Fixed';await app.click('review-save');assert.equal(app.rows().length,500);assert.equal(app.rows()[0].children[1].textContent,'Fixed');
});
