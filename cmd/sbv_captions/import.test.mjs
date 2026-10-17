import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { importSbv, MAX_SOURCE_BYTES } from './main.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const sample = readFileSync(join(root, 'fixtures/sbv-captions.sbv'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const parse = (text, duration = 6000) => importSbv(Buffer.from(text), duration, 'original.sbv');
const block = (header = '0:00:00.000,0:00:01.000', text = 'Hello') => `${header}\n${text}`;

test('SBV Unicode, multiline captions, overlaps and exact original ranges feed the native draft contract', () => {
  const result = parse(sample);
  assert.deepEqual(result.draft.cues, [
    { start_ms: 200, end_ms: 2000, text: 'Hello 東京 & friends.' },
    { start_ms: 2200, end_ms: 4000, text: 'Two lines:\nGrow 🌱 together.' },
    { start_ms: 3900, end_ms: 5500, text: 'A preserved overlap.' },
  ]);
  assert.equal(result.report.source_sha256, digest(sample));
  assert.equal(result.report.draft_sha256, digest(result.draftText));
  assert.equal(result.draft.contract, 'mooncast.caption-draft.v1');
  assert.deepEqual(result.report.mappings.map(m => m.cue), [1, 2, 3]);
  for (const [i, m] of result.report.mappings.entries()) assert.equal(sample.subarray(m.source_byte_start, m.source_byte_end).toString(), `${m.timing}\n${result.draft.cues[i].text}`);
  assert.deepEqual(parse(sample), parse(sample));
});

test('BOM, CRLF/CR, empty separators, literal entities and equal starts preserve declared semantics', () => {
  for (const newline of ['\n', '\r\n', '\r']) {
    const input = Buffer.from('\ufeff' + [block(undefined, '  A &amp; 🌱  \n第二行'), block(undefined, 'Same start')].join('\n\n\n').replaceAll('\n', newline) + newline);
    const result = parse(input);
    assert.equal(result.draft.cues[0].text, '  A &amp; 🌱  \n第二行');
    assert.equal(result.draft.cues[1].start_ms, 0);
    assert.equal(result.report.mappings[0].source_byte_start, 3);
    for (const m of result.report.mappings) assert.ok(input.subarray(m.source_byte_start, m.source_byte_end).toString().startsWith(m.timing));
  }
  assert.equal(parse(block('1:59:59.999,2:00:00.000'), 7200000).draft.cues[0].end_ms, 7200000);
  assert.equal(parse(block('00:00:00.001,00:00:00.002')).draft.cues[0].start_ms, 1);
});

test('ambiguous timings, malformed blocks, controls, unsupported markup and out-of-order cues reject', () => {
  for (const header of ['0:00:00,0:00:01', '0:00:00.0,0:00:01.000', '0:00:00.0000,0:00:01.000', '0:60:00.000,1:01:00.000', '0:00:60.000,0:01:01.000', '-0:00:00.000,0:00:01.000', '0:00:00.000 --> 0:00:01.000', '0:00:00.000, 0:00:01.000', '0:00:01.000,0:00:01.000', '0:00:02.000,0:00:01.000', '0:00:00.000,0:00:07.000', '100:00:00.000,100:00:01.000']) assert.throws(() => parse(block(header)));
  for (const text of ['', ' ', '\n\n', '[SUBTITLE]\n' + block(), '1\n' + block(), block() + '\n' + block(), block(undefined, '<b>Hi</b>'), block(undefined, 'a\tB'), block(undefined, 'a\0b'), block(undefined, '\ufefftext'), block(undefined, 'a\n \nb'), block(undefined, 'x'.repeat(2001)), '0:00:00.000,0:00:01.000\n\n']) assert.throws(() => parse(text));
  assert.throws(() => parse(block('0:00:02.000,0:00:03.000') + '\n\n' + block()), /order/);
  for (const duration of [0, -1, 1.5, 7200001, NaN, Infinity]) assert.throws(() => parse(sample, duration), /duration/);
  assert.throws(() => importSbv(Buffer.from([255]), 6000), /UTF-8/);
  assert.throws(() => importSbv(Buffer.alloc(MAX_SOURCE_BYTES + 1), 6000), /2097152/);
  assert.throws(() => parse(Array(5001).fill(block()).join('\n\n')), /5000/);
  assert.equal(parse(Array(5000).fill(block()).join('\n\n')).draft.cues.length, 5000);
  assert.throws(() => parse(Array(1800).fill(block(undefined, '&'.repeat(1000))).join('\n\n')), /export/);
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
    scope: 'Exact local application package source-input closure against retained R633. External artifacts/toolchain inherited from pinned executable, not newly qualified.' };
}

test('real SBV CLI to pinned native correction/export/reimport preserves source and refuses overwrite', () => {
  const native = process.env.MOONCAST_CAPTION_EDIT, frozenRoot = process.env.MOONCAST_CAPTION_FROZEN_ROOT, evidenceRoot = process.env.MOONCAST_SBV_EVIDENCE;
  assert.ok(native && frozenRoot && evidenceRoot, 'Required native journey needs MOONCAST_CAPTION_EDIT, MOONCAST_CAPTION_FROZEN_ROOT and MOONCAST_SBV_EVIDENCE; never skips');
  const pins = verifyNative(native, frozenRoot), evidence = mkdtempSync(join(evidenceRoot, 'sbv-journey-'));
  const run = (program, args, label, expected = 0) => {
    const result = spawnSync(program, args, { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
    writeFileSync(join(evidence, `${label}.log`), JSON.stringify({ program, args, status: result.status, stdout: result.stdout, stderr: result.stderr }, null, 2));
    assert.equal(result.status, expected, `${label}: ${result.error ?? result.stderr}`); return result;
  };
  const cli = join(root, 'cmd/sbv_captions/main.mjs'), input = join(root, 'fixtures/sbv-captions.sbv'), bundle = join(evidence, 'imported');
  const preview = JSON.parse(run(process.execPath, [cli, 'preview', input, '6000'], 'preview').stdout);
  assert.deepEqual(preview.cues, parse(sample).draft.cues);
  run(process.execPath, [cli, 'import', input, '6000', bundle], 'import');
  const draft = join(bundle, 'captions.json'), originalDraft = readFileSync(draft), revised = join(evidence, 'revised.json');
  assert.deepEqual(readFileSync(join(bundle, 'source.sbv')), sample);
  const report = JSON.parse(readFileSync(join(bundle, 'import.json')));
  assert.equal(report.draft_sha256, digest(originalDraft)); assert.equal(report.source_sha256, digest(sample));
  assert.match(run(native, ['show', draft], 'native-show').stdout, /Hello 東京 & friends\./);
  run(native, ['set', draft, '2', '2400', '4100', 'Revised 🌱 caption.', revised], 'native-correct');
  assert.match(run(native, ['show', revised], 'native-reopen').stdout, /Revised 🌱 caption\./);
  const revisedData = JSON.parse(readFileSync(revised));
  assert.deepEqual(revisedData.cues[1], { start_ms: 2400, end_ms: 4100, text: 'Revised 🌱 caption.' });
  assert.deepEqual(revisedData.cues[0], JSON.parse(originalDraft).cues[0]);
  run(native, ['export', revised, join(evidence, 'corrected')], 'native-export');
  assert.match(readFileSync(join(evidence, 'corrected.srt'), 'utf8'), /00:00:02,400 --> 00:00:04,100\nRevised 🌱 caption\./);
  assert.match(readFileSync(join(evidence, 'corrected.vtt'), 'utf8'), /Hello 東京 &amp; friends\./);
  const reopened = join(evidence, 'reopened.json');
  run(native, ['import', join(evidence, 'corrected.srt'), '6000', reopened], 'native-srt-reimport');
  assert.deepEqual(JSON.parse(readFileSync(reopened)).cues, revisedData.cues);
  // Inherited SRT reimport trims each line, unlike the draft and exports.
  const spacedInput = Buffer.from('\ufeff\r\n0:00:00.000,0:00:01.001\r  🌱 &amp; literal  \rSecond line\n\n0:00:00.000,0:00:02.000\r\n東京\r\n');
  const spacedSource = join(evidence, 'spaced.sbv'), spacedBundle = join(evidence, 'spaced-bundle');
  writeFileSync(spacedSource, spacedInput);
  const spacedPreview = JSON.parse(run(process.execPath, [cli, 'preview', spacedSource, '2000'], 'spaced-preview').stdout);
  assert.ok(spacedPreview.losses.some(loss => loss.includes('SRT reimport trims')));
  run(process.execPath, [cli, 'import', spacedSource, '2000', spacedBundle], 'spaced-import');
  const spacedDraft = join(spacedBundle, 'captions.json'), spacedData = JSON.parse(readFileSync(spacedDraft));
  assert.equal(spacedData.cues[0].text, '  🌱 &amp; literal  \nSecond line');
  assert.deepEqual(readFileSync(join(spacedBundle, 'source.sbv')), spacedInput);
  assert.ok(JSON.parse(readFileSync(join(spacedBundle, 'import.json'))).losses.some(loss => loss.includes('SRT reimport trims')));
  run(native, ['export', spacedDraft, join(evidence, 'spaced-export')], 'spaced-native-export');
  assert.ok(readFileSync(join(evidence, 'spaced-export.srt'), 'utf8').includes('\n  🌱 &amp; literal  \nSecond line\n'));
  assert.ok(readFileSync(join(evidence, 'spaced-export.vtt'), 'utf8').includes('\n  🌱 &amp;amp; literal  \nSecond line\n'));
  const spacedReopened = join(evidence, 'spaced-reopened.json');
  run(native, ['import', join(evidence, 'spaced-export.srt'), '2000', spacedReopened], 'spaced-native-srt-reimport');
  assert.deepEqual(JSON.parse(readFileSync(spacedReopened)).cues, [
    { start_ms: 0, end_ms: 1001, text: '🌱 &amp; literal\nSecond line' },
    { start_ms: 0, end_ms: 2000, text: '東京' },
  ]);
  assert.equal(JSON.parse(readFileSync(spacedDraft)).cues[0].text, '  🌱 &amp; literal  \nSecond line');
  run(process.execPath, [cli, 'import', input, '6000', bundle], 'existing-destination', 1);
  const invalid = join(evidence, 'invalid.sbv'); writeFileSync(invalid, block() + '\n' + block());
  const rejected = join(evidence, 'must-not-exist');
  run(process.execPath, [cli, 'import', invalid, '6000', rejected], 'invalid-input', 1);
  assert.ok(!existsSync(rejected));
  assert.deepEqual(readFileSync(draft), originalDraft); assert.deepEqual(readFileSync(input), sample); assert.deepEqual(readFileSync(join(bundle, 'source.sbv')), sample);
  assert.deepEqual(verifyNative(native, frozenRoot), pins);
  writeFileSync(join(evidence, 'journey.json'), JSON.stringify({ outcome: 'passed', native, pins, runtime_rebuilt: false, source_sha256: digest(sample), draft_sha256: digest(originalDraft), revised_sha256: digest(readFileSync(revised)) }, null, 2) + '\n');
});
