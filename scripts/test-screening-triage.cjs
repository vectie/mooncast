'use strict';
const assert = require('node:assert/strict');
const {test} = require('node:test');
const {setup} = require('./screening-player-harness.cjs');
const texts = app => app.rows().map(row => row.children[1].textContent);
async function choose(app, id, value, event='change') { app.get(id).value=value; await app.get(id).emit(event); }
async function packet(app, notes) { const value=await app.exported(); value.notes=notes.map((note,index)=>({id:index+1,start_ms:0,end_ms:null,text:'Issue',resolved:false,...note})); await app.load(value); await app.click('review-apply'); return value; }

test('merged feedback can be searched, ordered, traversed, resolved, downloaded and reopened', async()=>{
  const app=setup(); await app.add('Late colour',5); const incoming=await app.exported();
  incoming.notes=[{id:1,start_ms:2000,end_ms:null,text:'Early colour',resolved:false},{id:2,start_ms:3000,end_ms:null,text:'Sound',resolved:false}];
  await app.load(incoming); await app.click('review-merge');
  await choose(app,'review-filter','open'); await choose(app,'review-search','colour','input'); await choose(app,'review-order','timeline');
  assert.deepEqual(texts(app),['Early colour','Late colour']); assert.match(app.get('review-status').textContent,/2 shown \/ 3 notes/);
  await app.click('review-next'); assert.equal(app.video.currentTime,2); assert(app.rows()[0].classList.contains('current'));
  await app.actions(0)[1].emit('click'); assert.deepEqual(texts(app),['Late colour']);
  await app.click('review-next'); assert.equal(app.video.currentTime,5); assert(app.get('review-next').disabled);
  const saved=await app.exported(); assert.deepEqual(saved.notes.map(n=>n.text),['Late colour','Early colour','Sound']);
  const reopened=setup(); await reopened.load(saved); await reopened.click('review-apply'); assert.equal((await reopened.exported()).notes[1].resolved,true); assert.equal(reopened.rows().length,3); assert.equal(app.video.plays,0);
});

test('equal-time issues traverse by local ID, in both directions, without wrapping',async()=>{
  const app=setup(); await packet(app,[{id:9,start_ms:2000,text:'Nine'},{id:3,start_ms:2000,text:'Three'},{id:1,start_ms:1000,text:'First'}]);
  assert(app.get('review-previous').disabled); await app.click('review-previous'); assert.equal(app.video.currentTime,0);
  for(const id of [1,3,9]){await app.click('review-next');assert.match(app.get('review-navigation').textContent,new RegExp('Selected issue #'+id+' '));}
  assert(app.get('review-next').disabled); await app.click('review-next'); assert.match(app.get('review-navigation').textContent,/#9 /);
  for(const id of [3,1]){await app.click('review-previous');assert.match(app.get('review-navigation').textContent,new RegExp('#'+id+' '));}
  assert(app.get('review-previous').disabled);
});

test('chapter scoping uses interval intersection and includes terminal point in final chapter',async()=>{
  const app=setup({data:{chapters:[{start_ms:1000,title:'First'},{start_ms:3000,title:'Second'}]}});
  await packet(app,[{start_ms:0,text:'Prelude'},{start_ms:500,end_ms:1000,text:'Ends at first'}, {start_ms:1000,text:'First point'},{start_ms:2500,end_ms:3500,text:'Crosses chapters'},{start_ms:3000,text:'Second boundary'},{start_ms:6000,text:'End'}]);
  assert.deepEqual(app.get('review-chapter').children.map(c=>c.textContent),['All chapters','Before first chapter','1. First','2. Second']);
  await choose(app,'review-chapter','1'); assert.deepEqual(texts(app),['Prelude','Ends at first']);
  await choose(app,'review-chapter','2'); assert.deepEqual(texts(app),['First point','Crosses chapters']);
  await choose(app,'review-chapter','3'); assert.deepEqual(texts(app),['Crosses chapters','Second boundary','End']);
  await app.click('review-next'); assert.equal(app.video.currentTime,2.5); // Original range start, not a clipped/re-written issue.
});

test('chapterless cuts retain all issues and an inert all-chapters scope',async()=>{
  const app=setup({data:{chapters:[]}}); await app.add('At end',6); assert.equal(app.get('review-chapter').children.length,1); assert.deepEqual(texts(app),['At end']); await app.click('review-next'); assert.equal(app.video.currentTime,6);
});

test('search composes with status and chapter filters using literal Unicode text',async()=>{
  const app=setup({data:{chapters:[{start_ms:0,title:'<img>'},{start_ms:3000,title:'🌱'}]}});
  await packet(app,[{start_ms:1000,text:'CAFÉ 🌱 [fix]'},{start_ms:4000,text:'Café 🌱 [fix]',resolved:true},{start_ms:5000,text:'Other'}]);
  await choose(app,'review-search','  café 🌱 [fix]  ','input'); assert.equal(app.rows().length,2);
  await choose(app,'review-filter','resolved'); assert.deepEqual(texts(app),['Café 🌱 [fix]']);
  await choose(app,'review-chapter','1'); assert.equal(app.rows().length,0); assert(app.get('review-next').disabled); assert(app.get('review-previous').disabled);
  await choose(app,'review-chapter','2'); assert.equal(app.rows().length,1); assert(!app.created.some(n=>n.tag==='img'));
});

test('triage and navigation retain a frozen new draft and a pending merge preview',async()=>{
  const app=setup(); await app.add('Late',5); const value=await app.exported(); value.notes=[{id:1,start_ms:1000,end_ms:null,text:'Incoming',resolved:false}];
  await app.load(value); app.video.currentTime=2; await app.click('review-point'); app.get('review-text').value='Uncommitted';
  await choose(app,'review-order','timeline'); await choose(app,'review-search','Late','input'); await app.click('review-next');
  assert.equal(app.get('review-text').value,'Uncommitted'); assert.match(app.get('review-anchor').textContent,/00:00:02.000/); assert(!app.get('review-merge').disabled);
  await app.click('review-merge'); assert.equal(app.get('review-text').value,'Uncommitted'); await app.click('review-save');
  assert.equal((await app.exported()).notes.find(n=>n.text==='Uncommitted').start_ms,2000);
});

test('editing a saved issue survives filters and navigation and updates its selected anchor',async()=>{
  const app=setup(); await app.add('Early',1); await app.add('Late',5); await app.actions(0)[0].emit('click');
  app.get('review-text').value='Edited early'; await app.click('review-next'); await app.click('review-next');
  await choose(app,'review-search','Early','input'); assert.equal(app.get('review-text').value,'Edited early'); await app.click('review-next');
  app.video.currentTime=3; await app.click('review-point'); await app.click('review-save'); assert.match(app.get('review-navigation').textContent,/00:00:03.000/);
  const saved=await app.exported(); assert.deepEqual(saved.notes.map(n=>n.id),[1,2]); assert.equal(saved.notes[0].text,'Edited early'); assert.equal(saved.notes[0].start_ms,3000);
});

test('list jumps select an issue, stop repeat, and preserve paused or playing state',async()=>{
  for(const paused of [true,false]) {
    const app=setup(); await app.add('One',1); await app.add('Two',4);
    app.video.currentTime=2; await app.click('range-start'); app.video.currentTime=3; await app.click('range-end'); await app.click('range-repeat'); app.video.paused=paused;
    await app.rows()[0].children[0].emit('click'); assert.equal(app.get('range-repeat').attrs['aria-pressed'],'false'); assert.equal(app.video.paused,paused);
    await app.click('review-next'); assert.equal(app.video.currentTime,4); assert.equal(app.video.plays,0);
  }
});

test('filter changes restart navigation while order changes preserve selection and notebook bytes',async()=>{
  const app=setup(); await app.add('Late',5); await app.add('Early',1); const before=await app.exported();
  await app.click('review-next'); await choose(app,'review-order','timeline'); assert.match(app.get('review-navigation').textContent,/#2 /); assert.deepEqual(texts(app),['Early','Late']);
  await choose(app,'review-filter','open'); assert(app.get('review-previous').disabled); assert.match(app.get('review-navigation').textContent,/begin at the earliest/); await app.click('review-next'); assert.equal(app.video.currentTime,1);
  assert.deepEqual(await app.exported(),before); assert.match(app.get('review-status').textContent,/No changes since the last download request/);
});

test('replacement clears old selected ID and empty matches never seek',async()=>{
  const app=setup(); await app.add('Old',1); await app.click('review-next'); const value=await app.exported(); value.notes=[{...value.notes[0],start_ms:5000,text:'Replacement'}];
  await app.load(value); await app.click('review-apply'); assert.match(app.get('review-navigation').textContent,/begin at the earliest/); await app.click('review-next'); assert.equal(app.video.currentTime,5);
  await choose(app,'review-search','absent','input'); await app.click('review-next'); await app.click('review-previous'); assert.equal(app.video.currentTime,5); assert.equal(app.rows().length,0);
});

test('issue navigation waits for metadata through existing seek path without autoplay',async()=>{
  const app=setup(); await app.add('Inspect',4); app.video.readyState=0; app.video.currentTime=0;
  await app.click('review-next'); assert.equal(app.video.currentTime,0); assert.match(app.get('playback-status').textContent,/Loading video/);
  app.video.readyState=1; await app.video.emit('loadedmetadata'); assert.equal(app.video.currentTime,4); assert.equal(app.video.plays,0);
});
