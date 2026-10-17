'use strict';
// Execute the actual shipped player_script with DOM/media/VTTCue doubles.
// Blob output bytes are real. No browser, native exporter or codec claim.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const {setup} = require('./screening-player-harness.cjs');
const cues = [
  {start_ms:125, end_ms:2400, text:'Original first line'},
  {start_ms:1800, end_ms:3200, text:'Overlapping speaker'},
  {start_ms:4250, end_ms:5875, text:'Closing line'}
];
const fixture = options => setup({data:{cues}, ...options});
const edit = (app, index) => app.editButtons[index].emit('click');
const input = async(app, id, value) => {app.get(id).value=String(value);await app.get(id).emit('input');};
const timing = async(app, start, end) => {await input(app,'caption-edit-start',start);await input(app,'caption-edit-end',end);};
const preview = app => app.click('caption-preview');
const apply = app => app.click('caption-edit-save');
const words = (app,index=0) => app.cueRows[index].querySelector('.words').textContent;
const times = (app,index=0) => app.cueRows[index].querySelector('.time').textContent;
const retime = async(app,index,start,end) => {await edit(app,index);await timing(app,start,end);await preview(app);assert.equal(app.get('caption-edit-save').disabled,false);await apply(app);};
const download = async(app,format='json') => {const n=app.downloads.length;await app.click('caption-download-'+format);assert.equal(app.downloads.length,n+1);return app.downloads.at(-1);};
const draft = async app => JSON.parse(await (await download(app)).blob.text());
const clock = ms => `${String(Math.floor(ms/3600000)).padStart(2,'0')}:${String(Math.floor(ms/60000)%60).padStart(2,'0')}:${String(Math.floor(ms/1000)%60).padStart(2,'0')}.${String(ms%1000).padStart(3,'0')}`;

function inspectOrdinaryDraft(value, expected) {
  assert.deepEqual(Object.keys(value).sort(), ['contract','cues','duration_ms','source_file']);
  assert.equal(value.contract,'mooncast.caption-draft.v1');assert.equal(value.duration_ms,6000);
  assert.match(value.source_file,/^screening media\.mp4; recorded SHA-256: [a-f0-9]{64}$/);
  assert.deepEqual(value.cues,expected);
  value.cues.forEach((cue,index)=>{
    assert.deepEqual(Object.keys(cue).sort(),['end_ms','start_ms','text']);
    assert(Number.isInteger(cue.start_ms)&&Number.isInteger(cue.end_ms));
    assert(cue.start_ms>=0&&cue.start_ms<cue.end_ms&&cue.end_ms<=value.duration_ms);
    assert(index===0||cue.start_ms>=value.cues[index-1].start_ms);
    assert(cue.text.trim()&&cue.text.length<=2000&&!/[<>\x00-\x09\x0b-\x1f]/.test(cue.text));
    assert(cue.text.split('\n').every(line=>line.trim()));
  });
}

test('shipped HTML declares labeled timing controls, explicit preview/apply/cancel, initial disabled states',()=>{
  const source=fs.readFileSync(path.join(__dirname,'../editor/screening/output.mbt'),'utf8').replace(/\\"/g,'"');
  for(const id of ['caption-edit-start','caption-edit-end','caption-capture-start','caption-capture-end','caption-restore-timing','caption-preview'])assert.match(source,new RegExp('id="'+id+'"[^>]*disabled'));
  for(const id of ['caption-edit-start','caption-edit-end']){assert.match(source,new RegExp('<label for="'+id+'">'));assert.match(source,new RegExp('id="'+id+'"[^>]*inputmode="numeric"'));}
  assert.match(source,/id="caption-preview-status" role="status" hidden/);
  assert.match(source,/id="caption-edit-save"[^>]*>Apply correction/);
  assert.match(source,/id="caption-edit-cancel"[^>]*>Cancel edit/);
  const native=fs.readFileSync(path.join(__dirname,'../editor/captions/draft.mbt'),'utf8');
  assert.match(native,/cue\.start_ms >= previous/);assert.match(native,/cue\.end_ms <= self\.duration_ms/);
});

test('fallback timing preview connects transcript time, seek and overlap display; cancel restores applied cue',async()=>{
  const app=fixture();app.video.currentTime=2.8;app.video.paused=false;app.video.playbackRate=1.5;
  await edit(app,0);await timing(app,500,3500);await input(app,'caption-edit-text','Preview wording');
  assert.equal(words(app),cues[0].text);assert(app.get('caption-edit-save').disabled);
  await preview(app);
  assert.equal(words(app),'Preview wording');assert.equal(times(app),'00:00:00.500–00:00:03.500');
  assert.equal(app.cueRows[0].children[0].dataset.seekMs,'500');
  assert.equal(app.get('caption-fallback').textContent,'Preview wording\nOverlapping speaker');
  assert.equal(app.cueRows[0].attrs['aria-current'],'true');assert(!app.get('caption-preview-status').hidden);
  assert.match(app.get('caption-preview-status').textContent,/00:00:00.125–00:00:02.400 → 00:00:00.500–00:00:03.500/);
  assert.match(app.editButtons[0].textContent,/preview/);
  assert.equal(app.video.currentTime,2.8);assert.equal(app.video.paused,false);assert.equal(app.video.playbackRate,1.5);assert.equal(app.video.plays,0);
  await app.cueRows[0].children[0].emit('click');assert.equal(app.video.currentTime,0.5);
  await app.click('caption-edit-cancel');assert.equal(words(app),cues[0].text);assert.equal(times(app),'00:00:00.125–00:00:02.400');
  assert.equal(app.cueRows[0].children[0].dataset.seekMs,'125');assert(app.get('caption-preview-status').hidden);
  assert.equal(app.video.currentTime,0.5);inspectOrdinaryDraft(await draft(app),cues);
});

test('timing cannot apply before preview; repeated apply and explicit cancel retain the applied correction',async()=>{
  const app=fixture();await edit(app,1);await timing(app,1500,4001);
  await apply(app);assert.match(app.get('caption-edit-status').textContent,/Preview the timing correction/);
  assert.equal(app.cueRows[1].children[0].dataset.seekMs,'1800');
  await preview(app);await apply(app);assert.equal(times(app,1),'00:00:01.500–00:00:04.001');assert(app.get('caption-edit-save').disabled);
  await apply(app);await app.click('caption-edit-cancel');
  const expected=cues.map(cue=>({...cue}));expected[1].start_ms=1500;expected[1].end_ms=4001;
  inspectOrdinaryDraft(await draft(app),expected);assert.match(app.get('caption-edit-status').textContent,/1 of 3 captions corrected/);
});

test('invalid intervals and order changes are rejected without sorting, clipping or losing draft input',async()=>{
  const cases=[['',2500],['-1',2500],['0.5',2500],['1e3',2500],[' 500',2500],['NaN',2500],['Infinity',2500],['9007199254740993',2500],[500,''],[500,'2500.1'],[500,500],[501,500],[500,6001],[1801,3000]];
  for(const [start,end] of cases){
    const app=fixture();await edit(app,0);await timing(app,start,end);await preview(app);await apply(app);
    assert(app.get('caption-preview-status').hidden,`${start},${end}`);assert.equal(words(app),cues[0].text);assert.equal(app.cueRows[0].children[0].dataset.seekMs,'125');
    assert.equal(app.get('caption-edit-start').value,String(start));assert.equal(app.get('caption-edit-end').value,String(end));
    await app.click('caption-download-json');assert.equal(app.downloads.length,0);
    await app.click('caption-edit-cancel');inspectOrdinaryDraft(await draft(app),cues);
  }
  const app=fixture();await edit(app,1);await timing(app,124,3000);await preview(app);assert.match(app.get('caption-edit-status').textContent,/existing order/);assert(app.get('caption-preview-status').hidden);
  await timing(app,500,3000);await input(app,'caption-edit-text','<bad>');await preview(app);assert.match(app.get('caption-edit-status').textContent,/plain text/);assert(app.get('caption-preview-status').hidden);
});

test('equal starts, overlaps, a one-millisecond cue and exact terminal duration are legal',async()=>{
  const app=fixture();await retime(app,0,1800,1801);await retime(app,1,1800,6000);await retime(app,2,1800,5999);
  const expected=[{...cues[0],start_ms:1800,end_ms:1801},{...cues[1],start_ms:1800,end_ms:6000},{...cues[2],start_ms:1800,end_ms:5999}];
  inspectOrdinaryDraft(await draft(app),expected);
  app.video.currentTime=1.8;await app.video.emit('timeupdate');assert.equal(app.get('caption-fallback').textContent,cues.map(cue=>cue.text).join('\n'));
  app.video.currentTime=1.801;await app.video.emit('timeupdate');assert.equal(app.get('caption-fallback').textContent,cues.slice(1).map(cue=>cue.text).join('\n'));
  app.video.currentTime=6;await app.video.emit('timeupdate');assert(app.get('caption-fallback').hidden);
});

test('capture uses rounded playback milliseconds on the deliberate selection and rejects unavailable positions',async()=>{
  const app=fixture();await edit(app,1);app.video.currentTime=1.2345;await app.click('caption-capture-start');assert.equal(app.get('caption-edit-start').value,'1235');
  app.video.currentTime=4.5678;await app.video.emit('timeupdate');await app.click('caption-capture-end');assert.equal(app.get('caption-edit-end').value,'4568');
  assert.match(app.get('caption-edit-anchor').textContent,/caption 2 of 3/);
  assert.equal(app.cueRows[1].children[0].dataset.seekMs,'1800');await preview(app);await apply(app);
  assert.equal(times(app,1),'00:00:01.235–00:00:04.568');assert.equal(app.video.currentTime,4.5678);
  const prior=[app.get('caption-edit-start').value,app.get('caption-edit-end').value];
  for(const [ready,time] of [[0,1],[1,NaN],[1,Infinity],[1,-0.001],[1,6.1]]){
    app.video.readyState=ready;app.video.currentTime=time;await app.click('caption-capture-start');await app.click('caption-capture-end');
    assert.deepEqual([app.get('caption-edit-start').value,app.get('caption-edit-end').value],prior);assert.match(app.get('caption-edit-status').textContent,/Editor values are kept/);
  }
  app.video.readyState=1;app.video.duration=4;app.video.currentTime=4.1;await app.click('caption-capture-end');assert.equal(app.get('caption-edit-end').value,prior[1]);
});

test('native cue timing and text preview, cancel, repeated preview and apply never duplicate cues',async()=>{
  const app=fixture({nativeCaptions:true});const track=app.video.tracks[0];await app.click('captions-toggle');
  await edit(app,2);await timing(app,5000,5999);await input(app,'caption-edit-text','Café & 🌱');
  await preview(app);await preview(app);assert.equal(track.cues.length,3);assert.equal(track.cues[2].startTime,5);assert.equal(track.cues[2].endTime,5.999);assert.equal(track.cues[2].text,'Café &amp; 🌱');assert.equal(track.mode,'disabled');
  await app.click('caption-edit-cancel');assert.equal(track.cues[2].startTime,4.25);assert.equal(track.cues[2].endTime,5.875);assert.equal(track.cues[2].text,cues[2].text);
  await retime(app,2,5999,6000);assert.equal(track.cues[2].startTime,5.999);assert.equal(track.cues[2].endTime,6);
  await app.click('captions-toggle');assert.equal(track.mode,'showing');app.video.currentTime=5.999;await app.video.emit('timeupdate');assert(app.get('caption-fallback').hidden);
  assert.equal(app.video.tracks.length,1);assert.equal(track.cues.length,3);
});

test('each native cue mutation failure disables the track and uses the exact preview/applied fallback',async()=>{
  for(const failure of ['rejectStartUpdate','rejectEndUpdate','rejectTextUpdate']){
    const app=fixture({nativeCaptions:true});app.video[failure]=true;app.video.currentTime=3.3;
    await edit(app,0);await timing(app,500,3500);await input(app,'caption-edit-text','Replacement '+failure);await preview(app);
    assert.equal(app.video.tracks[0].mode,'disabled');assert.equal(app.get('caption-fallback').textContent,'Replacement '+failure);assert(!app.get('caption-fallback').hidden);
    await app.click('caption-edit-cancel');assert(app.get('caption-fallback').hidden);
    await retime(app,0,500,3500);assert.equal(app.get('caption-fallback').textContent,cues[0].text);
    const value=await draft(app);assert.equal(value.cues[0].end_ms,3500);
  }
});

test('typing or capturing after preview restores applied presentation and requires a fresh preview',async()=>{
  const app=fixture({nativeCaptions:true});await edit(app,0);await timing(app,500,3500);await input(app,'caption-edit-text','Orchard');
  await input(app,'search','Orchard');assert(app.cueRows.every(row=>row.hidden));await preview(app);assert(!app.cueRows[0].hidden);
  await input(app,'caption-edit-end',3600);assert(app.get('caption-preview-status').hidden);assert(app.cueRows[0].hidden);assert.equal(app.video.tracks[0].cues[0].endTime,2.4);assert(app.get('caption-edit-save').disabled);
  await apply(app);assert.equal(app.video.tracks[0].cues[0].endTime,2.4);await preview(app);
  app.video.currentTime=0.6;await app.click('caption-capture-start');assert(app.get('caption-preview-status').hidden);assert.equal(app.get('caption-edit-start').value,'600');
  await preview(app);await apply(app);assert.equal(app.video.tracks[0].cues[0].startTime,0.6);assert(!app.cueRows[0].hidden);
});

test('stale preview cannot apply or leak into export if controls change without an input event',async()=>{
  const app=fixture();await edit(app,0);await timing(app,500,3500);await preview(app);
  app.get('caption-edit-end').value='3600';await apply(app);assert(app.get('caption-preview-status').hidden);assert.equal(times(app),'00:00:00.125–00:00:02.400');
  await preview(app);app.get('caption-edit-start').value='125';app.get('caption-edit-end').value='2400';inspectOrdinaryDraft(await draft(app),cues);
  assert(app.get('caption-preview-status').hidden);assert.equal(times(app),'00:00:00.125–00:00:02.400');
});

test('unfinished and previewed timing protect both downloads and newer caption selections',async()=>{
  const app=fixture();await retime(app,0,250,2600);await timing(app,500,3500);await preview(app);
  await edit(app,2);assert.match(app.get('caption-edit-anchor').textContent,/caption 1 of 3/);assert.equal(app.get('caption-edit-start').value,'500');
  await app.click('caption-download-json');await app.click('caption-download-vtt');assert.equal(app.downloads.length,0);
  await app.click('caption-edit-cancel');await edit(app,2);assert.match(app.get('caption-edit-anchor').textContent,/caption 3 of 3/);
  assert.equal(app.get('caption-edit-start').value,'4250');assert.equal(times(app),'00:00:00.250–00:00:02.600');
  await timing(app,4400,5800);await preview(app);await apply(app);const value=await draft(app);assert.equal(value.cues[0].start_ms,250);assert.equal(value.cues[2].start_ms,4400);
});

test('restore supplied timing is a draft and is constrained by already applied neighboring starts',async()=>{
  const app=fixture();await retime(app,0,1000,3000);await input(app,'caption-edit-text','Keep wording');await apply(app);
  await app.click('caption-restore-timing');assert.equal(app.get('caption-edit-start').value,'125');assert.equal(times(app),'00:00:01.000–00:00:03.000');
  await app.click('caption-edit-cancel');await edit(app,0);assert.equal(app.get('caption-edit-start').value,'1000');
  await app.click('caption-restore-timing');await preview(app);await apply(app);assert.equal(words(app),'Keep wording');assert.equal(times(app),'00:00:00.125–00:00:02.400');
  await edit(app,1);await timing(app,100,3200);await preview(app);assert.match(app.get('caption-edit-status').textContent,/existing order/);assert(app.get('caption-preview-status').hidden);
  // Build a legal state where cue 1's supplied start is now after cue 2's start.
  await app.click('caption-edit-cancel');await retime(app,0,0,2400);await retime(app,1,100,3200);await edit(app,0);await app.click('caption-restore-timing');await preview(app);
  assert.match(app.get('caption-edit-status').textContent,/existing order/);assert(app.get('caption-preview-status').hidden);
});

test('preview/apply leave A–B repeat, pause, speed and pending media seek behavior intact',async()=>{
  const app=fixture();app.video.currentTime=1;await app.click('range-start');app.video.currentTime=4;await app.click('range-end');await app.click('range-repeat');
  await input(app,'speed',1.5);await app.get('speed').emit('change');app.video.currentTime=2;
  await retime(app,0,500,3500);assert.equal(app.video.currentTime,2);assert.equal(app.video.paused,true);assert.equal(app.video.plays,0);assert.equal(app.video.playbackRate,1.5);assert.equal(app.get('range-repeat').attrs['aria-pressed'],'true');
  app.video.paused=false;app.video.currentTime=4;await app.video.emit('timeupdate');assert.equal(app.video.currentTime,1);
  await app.click('range-clear');app.video.readyState=0;await app.cueRows[0].children[0].emit('click');await app.chapterButtons[0].emit('click');
  await edit(app,2);await timing(app,5000,5900);await preview(app);app.video.readyState=1;await app.video.emit('loadedmetadata');assert.equal(app.video.currentTime,0);assert.match(app.get('caption-edit-anchor').textContent,/caption 3 of 3/);
});

test('media errors and duration changes retain caption draft/preview and do not apply it',async()=>{
  const app=fixture();await edit(app,1);await timing(app,1500,3800);await preview(app);
  app.video.duration=3;await app.video.emit('durationchange');await app.video.emit('error');
  assert.equal(app.get('caption-edit-start').value,'1500');assert.equal(app.get('caption-edit-end').value,'3800');assert(!app.get('caption-preview-status').hidden);
  await app.click('caption-edit-cancel');inspectOrdinaryDraft(await draft(app),cues);assert.match(app.get('playback-status').textContent,/could not play/);
});

test('caption retiming keeps original notebook identity, revision history and supplied brief context',async()=>{
  const app=fixture();await app.add('Review original passage',1);const before=await app.exported();
  await input(app,'review-text','Unfinished note');const history=app.get('review-history-status').textContent;await edit(app,0);await timing(app,1500,3500);await input(app,'caption-edit-text','Changed caption');await preview(app);await apply(app);
  assert.deepEqual(await app.exported(),before);assert.equal(app.get('review-text').value,'Unfinished note');assert.equal(app.get('review-history-status').textContent,history);
  await app.click('review-brief-download');const brief=await app.downloads.at(-1).blob.text();assert(brief.includes(cues[0].text));assert(!brief.includes('Changed caption'));
  await app.load(before);assert.match(app.get('review-import-status').textContent,/matching notebook/);assert.deepEqual(app.data.cues,cues);
});

test('real JSON/VTT retiming bytes persist with ordinary contracts; reopen preserves edits, original reload does not',async()=>{
  const app=fixture();const original=app.get('screening-data').textContent;
  await retime(app,0,0,2999);await retime(app,2,5001,6000);await input(app,'caption-edit-text','Final & Café 🌱\nSecond line.');await apply(app);
  const expected=[{...cues[0],start_ms:0,end_ms:2999},{...cues[1]},{...cues[2],start_ms:5001,end_ms:6000,text:'Final & Café 🌱\nSecond line.'}];
  const json=await download(app),vtt=await download(app,'vtt');
  const directory=process.env.MOONCAST_EVIDENCE_DIR||fs.mkdtempSync(path.join(os.tmpdir(),'mooncast-caption-timing-'));fs.mkdirSync(directory,{recursive:true});
  const jsonPath=path.join(directory,'retimed-captions.json'),vttPath=path.join(directory,'retimed-captions.vtt');
  fs.writeFileSync(jsonPath,Buffer.from(await json.blob.arrayBuffer()),{flag:'wx'});fs.writeFileSync(vttPath,Buffer.from(await vtt.blob.arrayBuffer()),{flag:'wx'});
  const reopened=JSON.parse(fs.readFileSync(jsonPath,'utf8'));inspectOrdinaryDraft(reopened,expected);
  assert.equal(fs.readFileSync(vttPath,'utf8'),'WEBVTT\n\n'+expected.map((cue,index)=>`${index+1}\n${clock(cue.start_ms)} --> ${clock(cue.end_ms)}\n${cue.text.replace(/&/g,'&amp;')}\n`).join('\n'));
  assert.equal(app.get('screening-data').textContent,original);inspectOrdinaryDraft(await draft(fixture()),cues);
  const next=setup({data:{cues:reopened.cues,duration_ms:reopened.duration_ms}});inspectOrdinaryDraft(await draft(next),expected);await retime(next,1,2000,3500);assert.equal((await draft(next)).cues[2].start_ms,5001);
  console.log(JSON.stringify({timing_roundtrip:directory,sha256:{json:crypto.createHash('sha256').update(fs.readFileSync(jsonPath)).digest('hex'),vtt:crypto.createHash('sha256').update(fs.readFileSync(vttPath)).digest('hex')},qualification:'Production JS with DOM/media doubles; real output bytes, independent ordinary-draft validation, native consumer unrun.'}));
});

test('no-caption and failed-download paths never claim persisted timing or lose applied data',async()=>{
  const empty=setup({data:{cues:[]}});for(const id of ['caption-edit-start','caption-edit-end','caption-capture-start','caption-capture-end','caption-preview','caption-restore-timing'])assert(empty.get(id).disabled);
  await empty.click('caption-capture-start');await empty.click('caption-restore-timing');await preview(empty);await apply(empty);assert(empty.get('caption-preview-status').hidden);assert.equal(empty.downloads.length,0);
  const app=fixture({downloadError:true});await retime(app,0,500,3500);await app.click('caption-download-json');assert.equal(app.downloads.length,0);assert.match(app.get('caption-edit-status').textContent,/Could not download/);assert.equal(times(app),'00:00:00.500–00:00:03.500');assert.equal(app.get('caption-edit-start').value,'500');
});
