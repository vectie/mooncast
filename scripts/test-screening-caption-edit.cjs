'use strict';
// The real production player script is extracted by the shared harness. This
// executes local editorial workflows with DOM/media/download doubles, not a
// browser, MoonBit compiler or native caption consumer.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const {setup, script} = require('./screening-player-harness.cjs');
const cues = [
  {start_ms:125,end_ms:2400,text:'Original first line'},
  {start_ms:1800,end_ms:3200,text:'Overlapping speaker'},
  {start_ms:4250,end_ms:5875,text:'Closing line'}
];
const fixture = options => setup({data:{cues},...options});
const edit = (app,index) => app.editButtons[index].emit('click');
const type = async(app,text) => {app.get('caption-edit-text').value=text;await app.get('caption-edit-text').emit('input');};
const save = async(app,index,text) => {await edit(app,index);await type(app,text);await app.click('caption-edit-save');};
const download = async(app,format) => {const before=app.downloads.length;await app.click('caption-download-'+format);assert.equal(app.downloads.length,before+1);return app.downloads.at(-1);};
const textAt=(app,index)=>app.cueRows[index].querySelector('.words').textContent;

// Independent shape/clock checks mirror the existing CaptionDraft data contract,
// without pretending that the unavailable MoonBit consumer was executed.
function validateDraft(draft,expectedCues) {
  assert.deepEqual(Object.keys(draft).sort(),['contract','cues','duration_ms','source_file']);
  assert.equal(draft.contract,'mooncast.caption-draft.v1');assert.equal(draft.duration_ms,6000);
  assert.match(draft.source_file,/^screening media\.mp4; recorded SHA-256: [a-f0-9]{64}$/);
  assert.equal(draft.cues.length,expectedCues.length);
  draft.cues.forEach((cue,index)=>{
    assert.deepEqual(Object.keys(cue).sort(),['end_ms','start_ms','text']);
    assert.deepEqual(cue,expectedCues[index]);assert(Number.isInteger(cue.start_ms)&&Number.isInteger(cue.end_ms));
    assert(cue.start_ms>=0&&cue.start_ms<cue.end_ms&&cue.end_ms<=draft.duration_ms);
    assert(index===0||cue.start_ms>=draft.cues[index-1].start_ms);
    assert(cue.text.trim()&&cue.text.length<=2000&&!/[<>\x00-\x09\x0b-\x1f]/.test(cue.text));
    assert(cue.text.split('\n').every(line=>line.trim()));
  });
}
function decodeVtt(raw) {
  assert(raw.startsWith('WEBVTT\n\n'));
  return raw.slice(8).trimEnd().split('\n\n').map((block,index)=>{
    const [number,range,...lines]=block.split('\n');assert.equal(Number(number),index+1);
    const clock=value=>{assert.match(value,/^\d{2}:\d{2}:\d{2}\.\d{3}$/);const [h,m,rest]=value.split(':');return Number(h)*3600000+Number(m)*60000+Math.round(Number(rest)*1000);};
    const [start,end]=range.split(' --> ');return {start_ms:clock(start),end_ms:clock(end),text:lines.join('\n').replace(/&amp;/g,'&')};
  });
}

test('production HTML exposes cue-specific editing, labels, disabled startup and unchanged native draft contract',()=>{
  const source=fs.readFileSync(path.join(__dirname,'../editor/screening/output.mbt'),'utf8').replace(/\\"/g,'"');
  for(const id of ['caption-edit-title','caption-edit-anchor','caption-edit-text','caption-edit-save','caption-edit-cancel','caption-edit-restore','caption-edit-status','caption-download-json','caption-download-vtt'])assert(source.includes('id="'+id+'"'));
  assert.match(source,/<label for="caption-edit-text">/);assert.match(source,/id="caption-edit-status" role="status"/);
  assert.match(source,/data-caption-edit-index=/);assert.match(source,/id="caption-edit-text"[^>]*maxlength="2000"[^>]*disabled/);
  for(const id of ['caption-edit-save','caption-download-json','caption-download-vtt'])assert.match(source,new RegExp('id="'+id+'"[^>]*disabled'));
  const consumer=fs.readFileSync(path.join(__dirname,'../editor/captions/draft.mbt'),'utf8');
  assert.match(consumer,/contract : String\s+source_file : String\s+duration_ms : Int\s+cues : Array\[Caption\]/);
  assert.match(consumer,/pub fn read_draft\(text : String\)/);assert.match(consumer,/mooncast\.caption-draft\.v1/);
  assert(!/\.innerHTML\s*=/.test(script));
});

test('edit stays on the selected overlapping cue while playback changes; saved fallback previews exact wording',async()=>{
  const app=fixture();app.video.paused=false;app.video.currentTime=1;
  await edit(app,1);await type(app,'Speaker two: Café 🌱\nKeep this second line.');
  app.video.currentTime=4.5;await app.video.emit('timeupdate');
  assert.match(app.get('caption-edit-anchor').textContent,/caption 2 of 3: 00:00:01.800–00:00:03.200/);
  assert.equal(app.get('caption-edit-text').value,'Speaker two: Café 🌱\nKeep this second line.');
  await app.click('caption-edit-save');assert.equal(app.video.currentTime,4.5);assert.equal(app.video.paused,false);assert.equal(app.video.plays,0);
  assert.equal(textAt(app,0),cues[0].text);assert.equal(textAt(app,1),'Speaker two: Café 🌱\nKeep this second line.');
  app.video.currentTime=2;await app.video.emit('timeupdate');
  assert.equal(app.get('caption-fallback').textContent,'Original first line\nSpeaker two: Café 🌱\nKeep this second line.');
  app.video.currentTime=3.2;await app.video.emit('timeupdate');assert(app.get('caption-fallback').hidden);
});

test('native caption text changes preserve cue clocks, toggle mode and paused playback',async()=>{
  const app=fixture({nativeCaptions:true});const track=app.video.tracks[0];
  const clocks=track.cues.map(cue=>[cue.startTime,cue.endTime]);await app.click('captions-toggle');
  await save(app,0,'Fish & chips &lt; literal');
  assert.equal(track.cues[0].text,'Fish &amp; chips &amp;lt; literal');assert.equal(track.mode,'disabled');
  assert.deepEqual(track.cues.map(cue=>[cue.startTime,cue.endTime]),clocks);
  assert.equal(app.video.currentTime,0);assert.equal(app.video.paused,true);assert.equal(app.video.plays,0);
  await app.click('captions-toggle');assert.equal(track.mode,'showing');
  app.video.currentTime=1;await app.video.emit('timeupdate');assert(app.get('caption-fallback').hidden);
});

test('caption text update failure uses corrected fallback and keeps downloadable saved wording',async()=>{
  const app=fixture({nativeCaptions:true});app.video.rejectTextUpdate=true;app.video.currentTime=1;
  await save(app,0,'Corrected fallback');assert.equal(app.video.tracks[0].mode,'disabled');
  assert.equal(app.get('caption-fallback').textContent,'Corrected fallback');assert.equal(app.get('caption-fallback').hidden,false);
  const draft=JSON.parse(await (await download(app,'json')).blob.text());assert.equal(draft.cues[0].text,'Corrected fallback');
});

test('saved corrections participate in transcript search without changing cue selection or timing',async()=>{
  const app=fixture();app.get('search').value='Original';await app.get('search').emit('input');
  assert.equal(app.cueRows.filter(row=>!row.hidden).length,1);
  await save(app,0,'Corrected orchard');assert(app.cueRows.every(row=>row.hidden));
  assert.match(app.get('caption-edit-anchor').textContent,/caption 1 of 3/);
  app.get('search').value='ORCHARD';await app.get('search').emit('input');assert.equal(app.cueRows.filter(row=>!row.hidden).length,1);
  await app.cueRows[0].children[0].emit('click');assert.equal(app.video.currentTime,0.125);
  assert.match(app.editButtons[0].textContent,/corrected/);
});

test('switch and downloads protect unfinished wording; cancel and supplied-wording reset are explicit',async()=>{
  const app=fixture();await save(app,0,'Saved correction');await type(app,'Unfinished revision');
  await edit(app,1);assert.match(app.get('caption-edit-anchor').textContent,/caption 1 of 3/);assert.equal(app.get('caption-edit-text').value,'Unfinished revision');
  assert(app.get('caption-download-json').disabled);await app.click('caption-download-json');await app.click('caption-download-vtt');assert.equal(app.downloads.length,0);
  await app.click('caption-edit-cancel');assert.equal(textAt(app,0),'Saved correction');assert(app.get('caption-edit-text').disabled);
  await edit(app,0);await app.click('caption-edit-restore');assert.equal(app.get('caption-edit-text').value,cues[0].text);assert.equal(textAt(app,0),'Saved correction');
  await app.click('caption-edit-cancel');await edit(app,0);assert.equal(app.get('caption-edit-text').value,'Saved correction');
  await app.click('caption-edit-restore');await app.click('caption-edit-save');assert.equal(textAt(app,0),cues[0].text);assert.match(app.get('caption-edit-status').textContent,/0 of 3 captions corrected/);
});

test('plain-text caption validation blocks unsupported markup, empty lines and controls without changing saved text',async()=>{
  const app=fixture();await edit(app,0);
  for(const bad of ['','  ','One\n \nTwo','<b>text</b>','Tab\ttext','Carriage\rreturn','x'.repeat(2001)]){
    await type(app,bad);await app.click('caption-edit-save');assert.equal(textAt(app,0),cues[0].text);assert.equal(app.get('caption-edit-text').value,bad);assert(app.get('caption-download-json').disabled);
  }
  await type(app,'é'.repeat(1998)+'🌱');await app.click('caption-edit-save');assert.equal(textAt(app,0).length,2000);
  assert.equal(app.get('caption-download-json').disabled,false);
});

test('real Blob JSON and VTT downloads reopen as exact ordinary caption drafts with unchanged cue order and clocks',async()=>{
  const app=fixture();const planBefore=app.get('screening-data').textContent;
  await save(app,0,'  Café & 🌱\nSecond line with "quotes".  ');await save(app,2,'Final correction.');
  const expected=cues.map(cue=>({...cue}));expected[0].text='  Café & 🌱\nSecond line with "quotes".  ';expected[2].text='Final correction.';
  const json=await download(app,'json'),vtt=await download(app,'vtt');
  assert.equal(json.download,'screening-corrected-captions.json');assert.equal(vtt.download,'screening-corrected-captions.vtt');
  assert.equal(json.blob.type,'application/json;charset=utf-8');assert.equal(vtt.blob.type,'text/vtt;charset=utf-8');
  const destination=process.env.MOONCAST_EVIDENCE_DIR||fs.mkdtempSync(path.join(os.tmpdir(),'mooncast-caption-edit-'));
  fs.mkdirSync(destination,{recursive:true});
  const jsonPath=path.join(destination,json.download),vttPath=path.join(destination,vtt.download);
  fs.writeFileSync(jsonPath,Buffer.from(await json.blob.arrayBuffer()),{flag:'wx'});fs.writeFileSync(vttPath,Buffer.from(await vtt.blob.arrayBuffer()),{flag:'wx'});
  const draft=JSON.parse(fs.readFileSync(jsonPath,'utf8'));validateDraft(draft,expected);
  assert.deepEqual(decodeVtt(fs.readFileSync(vttPath,'utf8')),expected);
  assert.equal(app.get('screening-data').textContent,planBefore);assert.deepEqual(app.data.cues,cues);
  // Reopen the consumer-shaped draft as the next screening's supplied cue data.
  const reopened=setup({data:{cues:draft.cues,duration_ms:draft.duration_ms}});assert.equal(textAt(reopened,0),expected[0].text);
  await save(reopened,1,'A later edit');const next=JSON.parse(await(await download(reopened,'json')).blob.text());
  assert.equal(next.cues[0].text,expected[0].text);assert.equal(next.cues[1].text,'A later edit');
  console.log(JSON.stringify({caption_roundtrip:destination,sha256:{json:crypto.createHash('sha256').update(fs.readFileSync(jsonPath)).digest('hex'),vtt:crypto.createHash('sha256').update(fs.readFileSync(vttPath)).digest('hex')},qualification:'Exact production JS and real output bytes; independent schema/clock checks, no native consumer execution.'}));
});

test('caption correction preserves notebook source, pending note draft, saved notes and original brief context',async()=>{
  const app=fixture();await app.add('Fix this line',1);const before=await app.exported();
  app.get('review-text').value='Unfinished note';await app.get('review-text').emit('input');
  await save(app,0,'New caption wording');const after=await app.exported();assert.deepEqual(after,before);
  assert.equal(app.get('review-text').value,'Unfinished note');
  await app.click('review-brief-download');const brief=await app.downloads.at(-1).blob.text();
  assert(brief.includes('Original first line'));assert(!brief.includes('New caption wording'));
  await app.load(before);assert.match(app.get('review-import-status').textContent,/matching notebook/);
});

test('screening without captions does not create a false caption draft or editor selection',async()=>{
  const app=setup({data:{cues:[]}});assert(app.get('caption-edit-text').disabled);assert(app.get('caption-download-json').disabled);assert(app.get('caption-download-vtt').disabled);
  await app.click('caption-edit-save');await app.click('caption-edit-restore');await app.click('caption-download-json');assert.equal(app.downloads.length,0);assert.match(app.get('caption-edit-status').textContent,/no supported caption draft/);
});

test('download failure retains saved captions and reports failure rather than a completed save',async()=>{
  const app=fixture({downloadError:true});await save(app,0,'Keep this correction');await app.click('caption-download-json');
  assert.equal(app.downloads.length,0);assert.equal(textAt(app,0),'Keep this correction');assert.equal(app.get('caption-edit-text').value,'Keep this correction');
  assert.match(app.get('caption-edit-status').textContent,/Could not download corrected captions/);
  assert(!app.created.some(node=>node.tag==='a'&&node.parent.children.includes(node)));
});

test('WebVTT respects the existing two-MiB export bound while a supported JSON draft remains available',async()=>{
  const many=Array.from({length:1100},(_,index)=>({start_ms:index,end_ms:index+1,text:'x'.repeat(2000)}));
  const app=setup({data:{cues:many}});await app.click('caption-download-vtt');assert.equal(app.downloads.length,0);assert.match(app.get('caption-edit-status').textContent,/2 MiB limit/);
  const json=JSON.parse(await(await download(app,'json')).blob.text());assert.equal(json.cues.length,1100);assert.equal(json.cues[1099].end_ms,1100);
});
