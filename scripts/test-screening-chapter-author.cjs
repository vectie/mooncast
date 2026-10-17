'use strict';
// This executes every production #| line through the shared DOM/media harness.
// No copied authoring implementation, native importer, or browser claim.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {setup} = require('./screening-player-harness.cjs');
const get = (app, name) => app.get('chapter-author-' + name);
const click = (app, name) => app.click('chapter-author-' + name);
const rows = app => get(app,'list').children;
const actions = (app,index=0) => rows(app)[index].children[1].children;
const input = async(app,name,value) => {get(app,name).value=String(value);await get(app,name).emit('input');};
const begin = async(app,time,label) => {app.video.currentTime=time;await click(app,'capture');if(label!==undefined)await input(app,'label',label);};
const save = async app => {await click(app,'preview');assert(!get(app,'apply').disabled);await click(app,'apply');};
const add = async(app,time,label) => {await begin(app,time,label);await save(app);};
const download = async app => {const n=app.downloads.length;await click(app,'download');assert.equal(app.downloads.length,n+1);const file=app.downloads.at(-1);assert.equal(file.download,'screening-authored-chapters.ffmetadata');assert.equal(file.blob.type,'text/plain;charset=utf-8');return file.blob.text();};
const status = app => get(app,'status').textContent;
const expected = markers => ';FFMETADATA1\n'+markers.map(([start,end,title])=>'[CHAPTER]\nTIMEBASE=1/1000\nSTART='+start+'\nEND='+end+'\ntitle='+title+'\n').join('');

test('production HTML has accessible authoring controls and explicitly separate clock/context',()=>{
  const source=fs.readFileSync(path.join(__dirname,'../editor/screening/output.mbt'),'utf8').replace(/\\"/g,'"');
  for(const id of ['capture','label','start','recapture','preview','apply','cancel','download'])assert.match(source,new RegExp('id="chapter-author-'+id+'"[^>]*disabled'));
  for(const id of ['label','start'])assert.match(source,new RegExp('<label for="chapter-author-'+id+'">'));
  assert.match(source,/id="chapter-author-editor" hidden/);assert.match(source,/id="chapter-author-status" role="status"/);
  assert.match(source,/id="chapter-author-preview-status" role="status" hidden/);
  assert.match(source,/supplied native chapters keep their original clock/);
});

test('capture freezes rounded milliseconds, preview is unsaved, apply is explicit and repeat-safe',async()=>{
  const app=setup();assert.equal(rows(app).length,0);assert(get(app,'download').disabled);assert(get(app,'editor').hidden);
  await begin(app,1.2346,'Café 🌱');assert.equal(get(app,'start').value,'1235');app.video.currentTime=4.9;
  await click(app,'apply');assert.equal(rows(app).length,0);assert.match(status(app),/Preview the current marker/);
  await click(app,'preview');assert.equal(app.video.currentTime,4.9);assert.match(rows(app)[0].children[0].textContent,/00:00:01.235–00:00:06.000 · Café 🌱/);
  assert(!get(app,'preview-status').hidden);await click(app,'download');assert.equal(app.downloads.length,0);
  await click(app,'apply');await click(app,'apply');assert.equal(rows(app).length,1);assert(get(app,'editor').hidden);
  assert.equal(await download(app),expected([[1235,6000,'Café 🌱']]));assert.equal(app.video.plays,0);
});

test('author while playing, out-of-order capture sorts intervals, leading gap and 1ms final chapter survive',async()=>{
  const app=setup();app.video.paused=false;app.video.playbackRate=1.5;
  await add(app,5.999,'Final');await add(app,0.501,'First');await add(app,2.25,'Middle');
  assert.equal(await download(app),expected([[501,2250,'First'],[2250,5999,'Middle'],[5999,6000,'Final']]));
  assert.equal(app.video.paused,false);assert.equal(app.video.playbackRate,1.5);assert.equal(app.video.plays,0);
  for(const [position,index] of [[0.5,-1],[0.501,0],[2.25,1],[5.999,2],[6,-1]]){
    app.video.currentTime=position;await app.video.emit('timeupdate');
    rows(app).forEach((row,i)=>assert.equal(row.attrs['aria-current']==='true',i===index));
  }
  await rows(app)[0].children[0].emit('click');assert.equal(app.video.currentTime,0.501);assert.equal(app.video.paused,false);assert.equal(app.video.plays,0);
});

test('single and adjacent chapter intervals use exact 1001 ms seeks and strictly half-open submillisecond boundaries',async()=>{
  for(const adjacent of [false,true]){
    const app=setup({data:{duration_ms:2002,chapters:[],cues:[]}});app.video.duration=2.002;
    if(adjacent)await add(app,0,'Preceding');
    await add(app,1.001,'Following');const following=adjacent?1:0;
    await rows(app)[following].children[0].emit('click');assert.equal(app.video.currentTime,1.001);
    rows(app).forEach((row,i)=>assert.equal(row.attrs['aria-current']==='true',i===following));
    for(const [position,index] of [[1.000999,adjacent?0:-1],[1.001,following],[1.001001,following],[2.001999,following],[2.002,-1],[2.002001,-1]]){
      app.video.currentTime=position;await app.video.emit('timeupdate');
      rows(app).forEach((row,i)=>assert.equal(row.attrs['aria-current']==='true',i===index,`${adjacent}: ${position}`));
      await app.video.emit('seeked');rows(app).forEach((row,i)=>assert.equal(row.attrs['aria-current']==='true',i===index));
    }
    assert.equal(app.video.plays,0);
  }
});

test('edit title/start, cancel preview, stale input and recapture never change saved markers prematurely',async()=>{
  const app=setup();await add(app,1,'One');await add(app,3,'Three');const original=await download(app);
  await actions(app)[0].emit('click');await input(app,'label','Unsaved');await input(app,'start',4000);await click(app,'preview');
  assert.match(rows(app)[1].children[0].textContent,/Unsaved/);await click(app,'cancel');assert.equal(await download(app),original);
  await actions(app)[0].emit('click');await input(app,'label','Moved');await input(app,'start',4000);await click(app,'preview');
  get(app,'start').value='4500';await click(app,'apply');assert.match(status(app),/Preview the current marker/);assert.equal(rows(app).length,2);
  app.video.currentTime=4.4444;await click(app,'recapture');assert.equal(get(app,'start').value,'4444');assert.equal(get(app,'label').value,'Moved');
  await save(app);assert.equal(await download(app),expected([[3000,4444,'Three'],[4444,6000,'Moved']]));
  await begin(app,0.125,'Cancel new');await click(app,'preview');await click(app,'cancel');assert.equal(rows(app).length,2);
  await begin(app,0.125,'Keep draft');app.video.currentTime=2;await click(app,'capture');assert.equal(get(app,'start').value,'125');assert.equal(get(app,'label').value,'Keep draft');
});

test('remove recomputes neighboring ends, cannot erase during an edit, and empty exports stay blocked',async()=>{
  const app=setup();await add(app,0,'Opening');await add(app,2,'Middle');await add(app,4,'End');
  const remove=actions(app,1)[1];await actions(app)[0].emit('click');await remove.emit('click');assert.equal(rows(app).length,3);assert.match(status(app),/Apply or cancel/);
  await click(app,'cancel');await actions(app,1)[1].emit('click');assert.equal(await download(app),expected([[0,4000,'Opening'],[4000,6000,'End']]));
  await actions(app)[1].emit('click');await actions(app)[1].emit('click');assert.equal(rows(app).length,0);assert(get(app,'download').disabled);
  const n=app.downloads.length;await click(app,'download');assert.equal(app.downloads.length,n);assert.match(status(app),/1–1000/);
});

test('invalid millisecond inputs, duplicate starts and malformed labels retain original applied state and editor values',async()=>{
  const app=setup();await add(app,0,'Saved');await begin(app,1,'Candidate');
  for(const value of ['','-1','0.5','1e3',' 500','500 ','NaN','Infinity','9007199254740993','6000','6001','0']){
    await input(app,'start',value);await click(app,'preview');await click(app,'apply');
    assert(get(app,'preview-status').hidden,value);assert.equal(rows(app).length,1,value);assert.equal(get(app,'start').value,value);assert(get(app,'apply').disabled);
  }
  await input(app,'start','1000');
  for(const value of ['','  ','x'.repeat(201),'a\nb','a\rb','a\tb','a\x00b','a\x7fb','a\u2028b','a\u2029b','bad\ud800','trailing\\']){
    await input(app,'label',value);await click(app,'preview');assert(get(app,'preview-status').hidden);assert.equal(get(app,'label').value,value);assert.equal(rows(app).length,1);
  }
  await input(app,'label','🌱'.repeat(100));await save(app);assert.equal(rows(app).length,2);
  app.video.currentTime=1.0004;await click(app,'capture');assert(get(app,'editor').hidden);assert.match(status(app),/already starts at 1000/);
});

test('capture refuses unloaded, seeking, missing/short duration, invalid, end-rounded and media-error positions',async()=>{
  for(const patch of [{readyState:0},{seeking:true},{duration:NaN},{duration:Infinity},{duration:0},{duration:-1},{currentTime:NaN},{currentTime:Infinity},{currentTime:-0.01},{currentTime:6},{currentTime:6.1},{currentTime:5.9996},{duration:2,currentTime:2},{error:{code:3}}]){
    const app=setup();Object.assign(app.video,{currentTime:1,...patch});await click(app,'capture');assert(get(app,'editor').hidden,JSON.stringify(patch));assert.equal(rows(app).length,0);assert.match(status(app),/Load the video/);
  }
  const app=setup();await begin(app,1.25,'Keep');app.video.currentTime=2;await app.video.emit('error');await click(app,'recapture');assert.equal(get(app,'start').value,'1250');assert.equal(get(app,'label').value,'Keep');
  await save(app);assert.equal(await download(app),expected([[1250,6000,'Keep']]));
  await rows(app)[0].children[0].emit('click');assert.equal(app.video.currentTime,2);assert.match(status(app),/Load a playable video/);
  await app.video.emit('loadedmetadata');await rows(app)[0].children[0].emit('click');assert.equal(app.video.currentTime,1.25);assert.equal(app.video.plays,0);
});

test('seek errors and shorter media preserve markers; preview is explicit and never auto-plays paused video',async()=>{
  const app=setup();await add(app,4,'Later');app.video.duration=3;app.video.currentTime=1;
  await rows(app)[0].children[0].emit('click');assert.equal(app.video.currentTime,1);assert.match(status(app),/Load a playable video/);
  app.video.duration=6;Object.defineProperty(app.video,'currentTime',{configurable:true,get:()=>1,set(){throw Error('cannot seek');}});
  await rows(app)[0].children[0].emit('click');assert.match(status(app),/Could not reach/);assert.equal(app.video.plays,0);assert.equal(app.video.paused,true);
  assert.equal(await download(app),expected([[4000,6000,'Later']]));
});

test('pending supplied seek cannot be captured, and chapter changes preserve captions, notebook source/context and repeat',async()=>{
  const app=setup({nativeCaptions:true});const source=app.get('screening-data').textContent;
  await app.add('Review original context',1.5);const before=await app.exported();
  app.video.readyState=0;await app.chapterButtons[0].emit('click');app.video.readyState=1;app.video.currentTime=2;await click(app,'capture');assert(get(app,'editor').hidden);
  await app.video.emit('loadedmetadata');await add(app,1.5,'New chapter');
  await app.click('review-brief-download');const brief=await app.downloads.at(-1).blob.text();assert.match(brief,/Opening/);assert(!brief.includes('New chapter'));
  assert.deepEqual(await app.exported(),before);assert.equal(app.get('screening-data').textContent,source);assert.equal(app.chapterButtons.length,1);
  assert.equal(app.video.tracks[0].cues[0].text,'Café 🌱');
  app.video.currentTime=1;await app.click('range-start');app.video.currentTime=3;await app.click('range-end');await app.click('range-repeat');
  await actions(app)[0].emit('click');await input(app,'label','Updated');await save(app);assert.equal(app.get('range-repeat').attrs['aria-pressed'],'true');
  assert.equal(app.video.plays,0);
});

test('FFmetadata escapes Unicode, reserved characters and literal HTML; repeated downloads release prior URLs and failed download keeps work',async()=>{
  const app=setup();const title='  Café 🌱 = # ; \\ path <img src=x>  ';
  await add(app,0.001,title);const text=await download(app);
  assert(text.includes('title=  Café 🌱 \\= \\# \\; \\\\ path <img src\\=x>  \n'));
  assert.equal(rows(app)[0].children[0].textContent,'Preview 00:00:00.001–00:00:06.000 · '+title);
  assert(!app.created.some(node=>node.tag==='img'));await download(app);assert.deepEqual(app.revoked,['blob:0']);
  assert(!app.created.filter(node=>node.tag==='a').some(node=>node.parent?.children.includes(node)));
  const failed=setup({downloadError:true});await add(failed,0,'Saved');await click(failed,'download');assert.equal(failed.downloads.length,0);assert.match(status(failed),/Could not download chapters/);assert.equal(rows(failed).length,1);assert(!get(failed,'download').disabled);
});

test('unsupported screening duration blocks capture and never invents native project/timeline identities',async()=>{
  for(const duration_ms of [0,-1,0.5,7200001,null]){
    const app=setup({data:{duration_ms,chapters:[],cues:[]}});await click(app,'capture');assert.equal(rows(app).length,0);assert(get(app,'capture').disabled);await click(app,'download');assert.equal(app.downloads.length,0);
  }
  const app=setup({data:{duration_ms:7200000,chapters:[],cues:[]}});app.video.duration=7200;await add(app,7199.999,'Last millisecond');const text=await download(app);assert(text.includes('START=7199999\nEND=7200000'));assert(!/project_id|timeline_id|marker_id|ticks_per_second|chapter-draft/.test(text));
});

test('actual production marker handlers cap the session at 1000 without truncation',async()=>{
  const app=setup({data:{chapters:[],cues:[]}});const initialCreated=app.created.length;
  for(let i=0;i<1000;i++){
    await add(app,i/1000,'M'+i);
    // The harness keeps otherwise detached nodes for inspection. Release that
    // test-only bookkeeping here; production DOM/list/current rows remain live.
    app.created.splice(initialCreated);
  }
  assert.equal(rows(app).length,1000);assert(get(app,'capture').disabled);
  app.video.currentTime=2;await click(app,'capture');assert(get(app,'editor').hidden);assert.equal(rows(app).length,1000);assert.match(status(app),/already has 1000/);
  const text=await download(app);assert.equal((text.match(/\[CHAPTER\]/g)||[]).length,1000);assert(text.endsWith('START=999\nEND=6000\ntitle=M999\n'));
});

test('independent FFmpeg/FFprobe roundtrip uses the real downloaded FFmetadata bytes and tiny synthetic media',async t=>{
  if(!process.env.R614_FORMAT_DIR){t.skip('Set R614_FORMAT_DIR to a private empty evidence directory for the real format roundtrip.');return;}
  const dir=path.resolve(process.env.R614_FORMAT_DIR);fs.mkdirSync(dir,{recursive:true});
  const app=setup();await add(app,0.125,'Café 🌱 = ; # \\ path');await add(app,2.001,'<literal> chapter');await add(app,5.999,'Final');
  const metadata=await download(app);fs.writeFileSync(path.join(dir,'authored.ffmetadata'),metadata,{flag:'wx'});
  const run=(binary,args)=>{const result=spawnSync(binary,args,{encoding:'utf8',timeout:30000,maxBuffer:65536});assert.equal(result.status,0,binary+': '+result.stderr);return result.stdout;};
  const media=path.join(dir,'synthetic-six-seconds.mkv');
  run('ffmpeg',['-nostdin','-v','error','-f','lavfi','-i','color=c=black:s=16x16:r=1:d=6','-f','ffmetadata','-i',path.join(dir,'authored.ffmetadata'),'-map','0:v:0','-map_metadata','1','-map_chapters','1','-c:v','ffv1','-n',media]);
  const raw=run('ffprobe',['-v','error','-show_chapters','-of','json',media]);fs.writeFileSync(path.join(dir,'ffprobe-chapters.json'),raw,{flag:'wx'});
  const actual=JSON.parse(raw).chapters;assert.equal(actual.length,3);
  const markers=[[125,2001,'Café 🌱 = ; # \\ path'],[2001,5999,'<literal> chapter'],[5999,6000,'Final']];
  actual.forEach((chapter,i)=>{assert.equal(Number(chapter.start_time),markers[i][0]/1000);assert.equal(Number(chapter.end_time),markers[i][1]/1000);assert.equal(chapter.tags.title,markers[i][2]);});
  run('ffmpeg',['-nostdin','-v','error','-i',media,'-f','ffmetadata','-n',path.join(dir,'extracted.ffmetadata')]);
  fs.writeFileSync(path.join(dir,'qualification.json'),JSON.stringify({passed:true,format_only:true,production_download:true,chapters:3,synthetic_media_bytes:fs.statSync(media).size,native_chapter_importer_run:false,browser_run:false},null,2)+'\n',{flag:'wx'});
});
