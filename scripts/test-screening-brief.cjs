'use strict';
const assert = require('node:assert/strict');
const {test} = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setup} = require('./screening-player-harness.cjs');
async function choose(app, id, value, event = 'change') { app.get(id).value = value; await app.get(id).emit(event); }
async function packet(app, notes) {
  const value = await app.exported();
  value.notes = notes.map((note, index) => ({id: index + 1, start_ms: 0, end_ms: null, text: 'Issue', resolved: false, ...note}));
  await app.load(value); await app.click('review-apply'); return value;
}
async function brief(app) {
  const before = app.downloads.length;
  await app.click('review-brief-download');
  assert.equal(app.downloads.length, before + 1);
  const file = app.downloads.at(-1);
  assert.equal(file.download, 'screening-feedback.html');
  assert.equal(file.blob.type, 'text/html;charset=utf-8');
  return file.blob.text();
}
const articles = html => [...html.matchAll(/<article>([\s\S]*?)<\/article>/g)].map(match => match[1]);
const issueIds = html => articles(html).map(article => Number(article.match(/Issue #(\d+)/)[1]));

test('merged feedback exports a clearly scoped readable brief and can be reopened from disk', async () => {
  const app = setup({data: {title: 'Episode seven', chapters: [{start_ms: 0, title: 'Setup'}, {start_ms: 3000, title: 'Payoff'}]}});
  await app.add('Colour balance', 5);
  const incoming = await app.exported();
  incoming.notes = [
    {id: 1, start_ms: 3500, end_ms: 4500, text: 'Colour transition', resolved: false},
    {id: 2, start_ms: 1000, end_ms: null, text: 'Colour opening', resolved: false},
    {id: 3, start_ms: 4000, end_ms: null, text: 'Sound', resolved: false}
  ];
  await app.load(incoming); await app.click('review-merge');
  await choose(app, 'review-filter', 'open'); await choose(app, 'review-search', ' colour ', 'input'); await choose(app, 'review-chapter', '2');
  assert.match(app.get('review-brief-status').textContent, /2 of 4 saved notes.*2 omitted/);
  const html = await brief(app);
  assert.deepEqual(issueIds(html), [2, 1]);
  assert.match(html, /Episode seven/); assert.match(html, new RegExp('a'.repeat(64)));
  assert.match(html, /00:00:06\.000/); assert.match(html, /Current matches\. Status: Open; chapter: 2\. Payoff/);
  assert.match(html, /note text contains: &quot;colour&quot;/);
  assert.match(html, /2 of 4 saved notes included; 2 omitted\. Included: 2 open, 0 resolved/);
  assert.match(html, /00:00:03\.500–00:00:04\.500/);
  assert(!html.includes('Colour opening')); assert(!html.includes('>Sound<'));
  assert.match(html, /IDs belong to this local notebook/); assert.match(html, /@media print/);
  assert(!/<(?:script|video|iframe|img|link)\b/i.test(html));
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mooncast-brief-'));
  try {
    const file = path.join(dir, 'screening-feedback.html'); fs.writeFileSync(file, html);
    assert.equal(fs.readFileSync(file, 'utf8'), html);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
  assert.match(app.get('review-brief-status').textContent, /download requested.*check that your browser saved/);
  const reopened = setup({data: app.data}); await reopened.load(await app.exported()); await reopened.click('review-apply');
  assert.equal(reopened.rows().length, 4);
});

test('all-saved scope ignores triage and sorts a copy by time then ID with exact statuses', async () => {
  const app = setup();
  await packet(app, [{id: 9, start_ms: 2000, text: 'Nine', resolved: true}, {id: 2, start_ms: 2000, text: 'Two'}, {id: 3, start_ms: 1000, text: 'Three'}]);
  const before = await app.exported();
  await choose(app, 'review-filter', 'open'); await choose(app, 'review-search', 'no matches', 'input');
  assert(app.get('review-brief-download').disabled);
  await choose(app, 'review-brief-scope', 'all');
  assert(!app.get('review-brief-download').disabled);
  const html = await brief(app);
  assert.deepEqual(issueIds(html), [3, 2, 9]);
  assert.match(html, /All saved notes\. Triage filters ignored/);
  assert.match(html, /Included: 2 open, 1 resolved/); assert.match(articles(html)[2], /Resolved · Point/);
  assert.deepEqual(await app.exported(), before); assert.equal(app.get('review-search').value, 'no matches');
});

test('point context honors caption endpoints, chapter boundaries, prelude and terminal points', async () => {
  const app = setup({data: {chapters: [{start_ms: 1000, title: 'First'}, {start_ms: 3000, title: 'Second'}], cues: [
    {start_ms: 1000, end_ms: 3000, text: 'First caption'}, {start_ms: 2500, end_ms: 4000, text: 'Overlap caption'}, {start_ms: 3000, end_ms: 6000, text: 'Second caption'}
  ]}});
  await packet(app, [{start_ms: 0, text: 'Prelude'}, {start_ms: 3000, text: 'Boundary'}, {start_ms: 6000, text: 'Terminal'}]);
  const [prelude, boundary, terminal] = articles(await brief(app));
  assert.match(prelude, /Before first chapter/); assert.match(prelude, /No supplied caption overlaps this point/);
  assert.match(boundary, /2\. Second/); assert(!boundary.includes('1. First')); assert(!boundary.includes('First caption'));
  assert.match(boundary, /Overlap caption/); assert.match(boundary, /Second caption/);
  assert.match(terminal, /2\. Second/); assert.match(terminal, /No supplied caption overlaps this point/);
});

test('range context includes all positive overlaps and excludes touching endpoints', async () => {
  const app = setup({data: {chapters: [{start_ms: 1000, title: 'First'}, {start_ms: 3000, title: 'Second'}], cues: [
    {start_ms: 0, end_ms: 1000, text: 'Touch start'}, {start_ms: 500, end_ms: 1500, text: 'Cross start'}, {start_ms: 2000, end_ms: 3500, text: 'Cross end'}, {start_ms: 3000, end_ms: 4000, text: 'Touch end'}
  ]}});
  await packet(app, [{start_ms: 1000, end_ms: 3000, text: 'Inspect transition'}]);
  const [article] = articles(await brief(app));
  assert.match(article, /00:00:01\.000–00:00:03\.000/); assert.match(article, /1\. First/);
  assert(!article.includes('Before first chapter')); assert(!article.includes('2. Second'));
  assert.match(article, /Cross start/); assert.match(article, /Cross end/);
  assert(!article.includes('Touch start')); assert(!article.includes('Touch end'));
});

test('missing sidecars and empty matching scope stay explicit without inventing context', async () => {
  const app = setup({data: {chapters: [], cues: []}});
  assert(app.get('review-brief-download').disabled); await app.click('review-brief-download'); assert.equal(app.downloads.length, 0);
  await app.add('No sidecars', 2);
  const html = await brief(app); assert.match(html, /No chapter draft supplied/); assert.match(html, /No supplied caption overlaps this point/);
  await choose(app, 'review-search', 'absent', 'input');
  assert(app.get('review-brief-download').disabled); const before = app.downloads.length;
  await app.click('review-brief-download'); assert.equal(app.downloads.length, before);
  assert.match(app.get('review-brief-status').textContent, /0 of 1 saved notes.*1 omitted/);
  await choose(app, 'review-search', '', 'input'); assert(!app.get('review-brief-download').disabled);
});

test('all supplied text is escaped while multiline Unicode note wording remains intact', async () => {
  const title = 'Cut </title><img src=x onerror=alert(1)> & "title"';
  const chapter = '<script>alert("chapter")</script>';
  const note = 'Café 🌱 & <img src=x onerror=alert(1)>\n"quote" and \'apostrophe\'';
  const app = setup({data: {title, chapters: [{start_ms: 0, title: chapter}], cues: [{start_ms: 0, end_ms: 6000, text: '<svg onload=alert(1)> & "caption"'}]}});
  await app.add(note, 1); await choose(app, 'review-search', '<img', 'input');
  const html = await brief(app);
  assert(!/<(?:img|svg|script)\b/i.test(html)); assert(!html.includes('</title><img'));
  assert.match(html, /&lt;\/title&gt;&lt;img src=x onerror=alert\(1\)&gt; &amp; &quot;title&quot;/);
  assert.match(html, /Café 🌱 &amp; &lt;img src=x onerror=alert\(1\)&gt;\n&quot;quote&quot; and &#39;apostrophe&#39;/);
  assert.match(html, /&lt;script&gt;alert\(&quot;chapter&quot;\)&lt;\/script&gt;/);
  assert.match(html, /&lt;svg onload=alert\(1\)&gt; &amp; &quot;caption&quot;/);
  assert.match(html, /note text contains: &quot;&lt;img&quot;/);
  assert.match(html, /Content-Security-Policy/);
});

test('long context is visibly bounded without shortening notes or splitting Unicode code points', async () => {
  const app = setup({data: {
    chapters: Array.from({length: 14}, (_, i) => ({start_ms: i * 400, title: 'Scene ' + i})),
    cues: Array.from({length: 10}, (_, i) => ({start_ms: i * 500, end_ms: i * 500 + 500, text: i === 0 ? '🌱'.repeat(601) : 'Cue ' + i}))
  }});
  await packet(app, [{start_ms: 0, end_ms: 6000, text: 'X'.repeat(2000)}]);
  const [article] = articles(await brief(app));
  assert.match(article, /2 more overlapping chapter labels omitted/); assert.match(article, /2 more overlapping caption cues omitted/);
  assert(article.includes('🌱'.repeat(600) + ' [excerpt shortened]')); assert(!article.includes('🌱'.repeat(601)));
  assert(article.includes('X'.repeat(2000))); assert(!article.includes('Cue 8')); assert(!article.includes('Scene 12'));
});

test('brief leaves unsaved edits, repeat, queue selection, merge preview and notebook-save warning intact', async () => {
  const app = setup(); await app.add('Saved first', 1); const incoming = await app.exported();
  incoming.notes[0].text = 'Incoming'; await app.add('Saved second', 4); await app.load(incoming);
  await app.actions(0)[0].emit('click'); app.get('review-text').value = 'Uncommitted replacement';
  app.video.currentTime = 2; await app.click('range-start'); app.video.currentTime = 3; await app.click('range-end'); await app.click('range-repeat');
  const anchor = app.get('review-anchor').textContent, noteStatus = app.get('review-status').textContent, importStatus = app.get('review-import-status').textContent;
  const html = await brief(app);
  assert(!html.includes('Uncommitted replacement')); assert(html.includes('Saved first'));
  assert.equal(app.get('review-text').value, 'Uncommitted replacement'); assert.equal(app.get('review-anchor').textContent, anchor);
  assert.equal(app.get('review-status').textContent, noteStatus); assert.match(noteStatus, /Download a notebook to keep these notes/);
  assert.equal(app.get('review-import-status').textContent, importStatus); assert(!app.get('review-merge').disabled);
  assert.equal(app.get('range-repeat').attrs['aria-pressed'], 'true'); assert.equal(app.video.currentTime, 2); assert.equal(app.video.plays, 0);
  await app.click('review-next'); const navigation = app.get('review-navigation').textContent; await brief(app);
  assert.equal(app.get('review-navigation').textContent, navigation);
  await app.click('review-merge'); assert.equal(app.get('review-text').value, 'Uncommitted replacement');
});

test('subsequent briefs reflect saved edits and status, revoke only prior brief URL, and failure preserves work', async () => {
  const app = setup(); await app.add('Original', 1); await app.exported(); const notebookURL = app.downloads.at(-1).href;
  const oldHTML = await brief(app), oldURL = app.downloads.at(-1).href;
  await app.actions(0)[0].emit('click'); app.get('review-text').value = 'Corrected'; await app.click('review-save');
  await app.actions(0)[1].emit('click');
  const newHTML = await brief(app); assert.match(oldHTML, /Original/); assert(!oldHTML.includes('Corrected'));
  assert.match(newHTML, /Corrected/); assert.match(newHTML, /Resolved · Point/);
  assert(app.revoked.includes(oldURL)); assert(!app.revoked.includes(notebookURL));
  const failed = setup({downloadError: true}); await failed.add('Keep me', 2); failed.get('review-text').value = 'Draft';
  await failed.click('review-brief-download'); assert.equal(failed.downloads.length, 0); assert.equal(failed.rows().length, 1);
  assert.equal(failed.get('review-text').value, 'Draft'); assert.match(failed.get('review-brief-status').textContent, /could not download.*remain unchanged/);
  assert.equal(failed.created.filter(node => node.tag === 'a' && node.parent.children.includes(node)).length, 0);
});
