import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { importTtml, MAX_SOURCE_BYTES } from './main.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const sample = readFileSync(join(root, 'fixtures/ttml-captions.ttml'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const parse = (text, lang = 'en', duration = 6000) => importTtml(Buffer.from(text), duration, lang, 'original.ttml');
const xml = (body, attrs = '') => `<tt xmlns="http://www.w3.org/ns/ttml" xml:lang="en" ${attrs}><body><div>${body}</div></body></tt>`;
const p = (attrs = 'begin="0s" end="1s"', text = 'Hello') => `<p ${attrs}>${text}</p>`;

test('timed paragraphs, language selection, Unicode, line breaks and source byte ranges are exact', () => {
  const result = parse(sample);
  assert.deepEqual(result.draft.cues, [
    { start_ms: 200, end_ms: 2000, text: 'Hello 東京 & friends.' },
    { start_ms: 2200, end_ms: 4000, text: 'Two lines:\nGrow 🌱 together.' },
    { start_ms: 3900, end_ms: 5500, text: 'A preserved overlap.' },
  ]);
  assert.equal(result.report.source_sha256, digest(sample)); assert.equal(result.report.draft_sha256, digest(result.draftText));
  assert.equal(result.report.unselected_paragraph_count, 1);
  assert.deepEqual(result.report.mappings.map(m => [m.paragraph, m.cue]), [[1, 1], [2, 2], [3, null], [4, 3]]);
  assert.deepEqual(result.report.mappings[0].omitted_styling[0].attributes, { 'tts:fontWeight': 'bold' });
  for (const mapping of result.report.mappings) assert.match(sample.subarray(mapping.source_byte_start, mapping.source_byte_end).toString(), new RegExp(`^<p xml:id="${mapping.xml_id}"[\\s\\S]*</p>$`));
  assert.equal(parse(sample, 'FR').draft.cues[0].text, 'Grandissons ensemble.');
  assert.throws(() => parse(sample, 'de'), /No paragraphs/);
  assert.deepEqual(parse(sample), parse(sample));
});

test('default whitespace normalizes across spans with exact media-relative timing and equal-start overlaps', () => {
  const text = '\ufeff<?xml version="1.0" encoding="UTF-8"?>\r\n' + xml(p('begin="0.001s" dur="999ms"', ' A\r\n<span> B </span> C<br/> D &#38; E ') + p('begin="00:00:00.001" end="2s"', 'Same start'));
  const result = parse(text);
  assert.deepEqual(result.draft.cues[0], { start_ms: 1, end_ms: 1000, text: 'A B C\nD & E' });
  const bytes = Buffer.from(text), mapping = result.report.mappings[0]; assert.match(bytes.subarray(mapping.source_byte_start, mapping.source_byte_end).toString(), /^<p /);
  assert.equal(result.draft.cues[1].start_ms, 1);
  assert.equal(parse(xml(p('begin="7199.999s" dur="1ms"')), 'en', 7200000).draft.cues[0].end_ms, 7200000);
});

test('unsupported timing, languages, inherited semantics and styling fail rather than discard paragraphs', () => {
  for (const attrs of ['begin="-1s" end="1s"', 'begin="0.0001s" end="1s"', 'begin="1.5ms" end="1s"', 'begin="00:00:00:12" end="1s"', 'begin="1f" end="1s"', 'begin="1t" end="1s"', 'begin="0s"', 'end="1s"', 'begin="1s" end="1s"', 'begin="0s" end="1s" dur="1s"', 'begin="0s" end="7s"']) assert.throws(() => parse(xml(p(attrs))));
  for (const text of [xml(p()).replace('<div>', '<div begin="1s">'), xml(p(undefined, '<span begin="0s">Timed</span>')), xml(p(undefined, '<span xml:lang="fr">Mixed</span>')), xml(p('begin="0s" end="1s" region="bottom"')), xml(p(), 'xml:space="preserve"'), xml(p(), 'xmlns:ttp="http://www.w3.org/ns/ttml#parameter" ttp:frameRate="30"'), xml(p()).replace('xml:lang="en"', ''), xml(p('begin="0s" end="1s" xml:lang="fr" style="hidden"'))]) assert.throws(() => parse(text));
  assert.throws(() => parse(xml(p('begin="2s" end="3s"') + p())), /order/);
  for (const duration of [0, 6000.1, 7200001, NaN]) assert.throws(() => parse(sample, 'en', duration), /duration/);
});

test('XML ambiguity, foreign namespaces, external entities, invalid text and resource bounds reject', () => {
  for (const value of ['<!DOCTYPE tt SYSTEM "file:///etc/passwd">' + xml(p()), xml(p()).replace('</p>', '</span>'), xml(p()) + xml(p()), xml(p()).replace('<body>', '<head/><body>'), xml(p()).replace('http://www.w3.org/ns/ttml', 'urn:foreign'), xml(p('begin="0s" end="1s" begin="0s"')), xml(p(undefined, '&unknown;')), xml(p(undefined, '<![CDATA[text]]>')), xml(p(undefined, 'a<br/><br/>b')), xml(p(undefined, '&lt;b&gt;')), xml(p(undefined, '&#0;')), xml(p(undefined, '&#xD800;')), xml(p(undefined, ']]>')), xml(p(undefined, 'x'.repeat(2001))), xml(p('xml:id="same" begin="0s" end="1s"') + p('xml:id="same" begin="1s" end="2s"'))]) assert.throws(() => parse(value), undefined, value.slice(0, 160));
  assert.throws(() => importTtml(Buffer.from([255]), 6000, 'en'), /UTF-8/);
  assert.throws(() => importTtml(Buffer.alloc(MAX_SOURCE_BYTES + 1), 6000, 'en'), /2097152/);
  assert.throws(() => parse(xml(p().repeat(5001))), /1–5000/);
  assert.throws(() => parse(xml(p(undefined, '<span>'.repeat(14) + 'deep' + '</span>'.repeat(14)))), /nesting/);
});

function verifyNative(native, frozenRoot) {
  assert.equal(digest(readFileSync(native)), '480b74d956fdd6adbcaec070330790cb8a217748341767ca326af9415a23de55');
  const manifestBytes = readFileSync(join(frozenRoot, 'identity/final/SOURCE_MANIFEST.json'));
  assert.equal(digest(manifestBytes), 'db9f12d0c633e65030028a290047792d38407156bf28eef04b26d946e3d92185');
  const manifest = new Map(JSON.parse(manifestBytes).map(row => [row[0], row[3]]));
  const pending = ['cmd/caption_edit'], packages = new Set(), pins = {};
  const verify = path => {
    assert.ok(manifest.has(path), `No frozen source pin for ${path}`);
    for (const base of [root, join(frozenRoot, 'source')]) assert.equal(digest(readFileSync(join(base, path))), manifest.get(path), `Native source pin changed: ${base}/${path}`);
    pins[path] = manifest.get(path);
  };
  verify('moon.mod');
  while (pending.length) {
    const pkg = pending.pop(); if (packages.has(pkg)) continue; packages.add(pkg);
    const definition = readFileSync(join(root, pkg, 'moon.pkg'), 'utf8'); verify(`${pkg}/moon.pkg`);
    for (const match of definition.matchAll(/"vectie\/mooncast\/([^"]+)"/g)) pending.push(match[1]);
    for (const name of readdirSync(join(root, pkg))) if (name.endsWith('.mbt') && !/(?:_test|_wbtest)\.mbt$/.test(name)) verify(`${pkg}/${name}`);
  }
  return { executable_sha256: digest(readFileSync(native)), source_manifest_sha256: digest(manifestBytes), packages: [...packages].sort(), source_pins: pins,
    scope: 'Exact application source-input package closure and module manifest against retained R633 frozen source. External dependency artifacts/toolchain are inherited from the pinned executable, not rebuilt or newly qualified.' };
}

test('actual TTML CLI -> pinned native show/set/reopen/export/SRT-reimport retains originals and refuses overwrite', () => {
  const native = process.env.MOONCAST_CAPTION_EDIT, evidenceRoot = process.env.MOONCAST_TTML_EVIDENCE, frozenRoot = process.env.MOONCAST_CAPTION_FROZEN_ROOT;
  assert.ok(native && evidenceRoot && frozenRoot, 'Set MOONCAST_CAPTION_EDIT, MOONCAST_TTML_EVIDENCE and MOONCAST_CAPTION_FROZEN_ROOT; required native journey never skips');
  const pins = verifyNative(native, frozenRoot), evidence = mkdtempSync(join(evidenceRoot, 'ttml-journey-'));
  const run = (program, args, label, expected = 0) => {
    const result = spawnSync(program, args, { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
    writeFileSync(join(evidence, `${label}.log`), JSON.stringify({ program, args, status: result.status, stdout: result.stdout, stderr: result.stderr }, null, 2));
    assert.equal(result.status, expected, `${label}: ${result.error ?? result.stderr}`); return result;
  };
  const cli = join(root, 'cmd/ttml_captions/main.mjs'), input = join(root, 'fixtures/ttml-captions.ttml'), bundle = join(evidence, 'imported');
  run(process.execPath, [cli, 'preview', input, '6000', 'en'], 'preview');
  run(process.execPath, [cli, 'import', input, '6000', 'en', bundle], 'import');
  assert.deepEqual(readFileSync(join(bundle, 'source.ttml')), sample);
  const draft = join(bundle, 'captions.json'), revised = join(evidence, 'revised.json');
  assert.match(run(native, ['show', draft], 'native-show').stdout, /Hello 東京 & friends\./);
  run(native, ['set', draft, '2', '2400', '4100', 'Revised 🌱 caption.', revised], 'native-correct');
  assert.match(run(native, ['show', revised], 'native-reopen').stdout, /Revised 🌱 caption\./);
  const revisedData = JSON.parse(readFileSync(revised));
  assert.deepEqual(revisedData.cues[1], { start_ms: 2400, end_ms: 4100, text: 'Revised 🌱 caption.' });
  assert.deepEqual(revisedData.cues[0], JSON.parse(readFileSync(draft)).cues[0]);
  run(native, ['export', revised, join(evidence, 'corrected')], 'native-export');
  assert.match(readFileSync(join(evidence, 'corrected.srt'), 'utf8'), /00:00:02,400 --> 00:00:04,100\nRevised 🌱 caption\./);
  assert.match(readFileSync(join(evidence, 'corrected.vtt'), 'utf8'), /Hello 東京 &amp; friends\./);
  const reopened = join(evidence, 'reopened-from-srt.json');
  run(native, ['import', join(evidence, 'corrected.srt'), '6000', reopened], 'native-srt-reimport');
  assert.deepEqual(JSON.parse(readFileSync(reopened)).cues, revisedData.cues);
  run(process.execPath, [cli, 'import', input, '6000', 'en', bundle], 'existing-destination', 1);
  const invalid = join(evidence, 'unsupported.ttml'); writeFileSync(invalid, xml(p()).replace('<div>', '<div begin="1s">'));
  const rejected = join(evidence, 'must-not-exist'); run(process.execPath, [cli, 'import', invalid, '6000', 'en', rejected], 'unsupported-profile', 1);
  assert.ok(!existsSync(rejected)); assert.deepEqual(readFileSync(input), sample); assert.deepEqual(readFileSync(join(bundle, 'source.ttml')), sample);
  assert.deepEqual(verifyNative(native, frozenRoot), pins);
  writeFileSync(join(evidence, 'journey.json'), JSON.stringify({ outcome: 'passed', native, pins, source_sha256: digest(sample), draft_sha256: digest(readFileSync(draft)), revised_sha256: digest(readFileSync(revised)), runtime_rebuilt: false }, null, 2) + '\n');
});
