import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { importJson3, MAX_SOURCE_BYTES } from './main.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const sample = readFileSync(join(root, 'fixtures/json3-captions.json3'));
const parse = value => importJson3(Buffer.from(JSON.stringify(value)), 6000, 'fixture.json3');
const fixture = () => JSON.parse(sample);
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

test('independent captions retain exact text, intervals, Unicode and source-event locators', () => {
  const result = importJson3(sample, 6000, 'original.json3');
  assert.deepEqual(result.draft.cues[0], { start_ms: 200, end_ms: 2000, text: 'Hello 東京 & friends.' });
  assert.equal(result.draft.cues[1].text, 'Two lines:\nGrow 🌱 together.');
  assert.equal(result.report.source_sha256, digest(sample));
  assert.equal(result.report.draft_sha256, digest(result.draftText));
  assert.deepEqual(result.report.mappings.map(row => [row.cue, row.event]), [[1, 1], [2, 2], [3, 3]]);
  assert.equal(result.report.flattened.timed_segments, 2);
  assert.equal(result.report.flattened.confidence_segments, 1);
  assert.equal(result.report.flattened.styled_segments, 1);
});

test('overlapping and equal starts stay ordered rather than clipped or merged', () => {
  const value = fixture();
  value.events[1].tStartMs = 200;
  const result = parse(value);
  assert.equal(result.draft.cues[1].start_ms, 200);
  assert.equal(result.draft.cues[0].end_ms, 2000);
  assert.equal(result.draft.cues.length, 3);
});

test('normal unsupported rolling controls and partial events explain the unsupported profile', () => {
  for (const field of ['aAppend', 'id', 'wWinId', 'wsWinStyleId', 'wpWinPosId']) {
    const value = fixture(); value.events[0][field] = 1;
    assert.throws(() => parse(value), /rolling\/append\/window-control/);
  }
  const value = fixture(); delete value.events[0].dDurationMs;
  assert.throws(() => parse(value), /dDurationMs/);
  const unknown = fixture(); unknown.events[0].unknownTiming = 0;
  assert.throws(() => parse(unknown), /unsupported field unknownTiming/);
});

test('timing must be exact, ordered and within explicit media bounds', () => {
  for (const duration of [0, 6000.5, 7200001, NaN]) assert.throws(() => importJson3(sample, duration), /duration/i);
  for (const start of [-1, 0.5, 5000]) {
    const value = fixture(); value.events[0].tStartMs = start;
    assert.throws(() => parse(value), /integer|duration/);
  }
  const order = fixture(); order.events.reverse(); assert.throws(() => parse(order), /order/);
  const offset = fixture(); offset.events[0].segs[1].tOffsetMs = 1801; assert.throws(() => parse(offset), /tOffsetMs/);
  assert.throws(() => importJson3(Buffer.from(sample.toString().replace('"tStartMs": 200', '"tStartMs": 200.00000000000000001')), 6000), /integer token/);
});

test('caption-incompatible text and wrong input shapes fail without dropped records', () => {
  for (const text of ['', ' ', '<b>Text</b>', 'a\n\nb', 'a\tb', '\ud800', 'x'.repeat(2001)]) {
    const value = fixture(); value.events[0].segs = [{ utf8: text }];
    assert.throws(() => parse(value), /plain text/);
  }
  const missing = fixture(); missing.events[0].segs = []; assert.throws(() => parse(missing), /segments/);
  assert.throws(() => parse({ wireMagic: 'pb3', events: [] }), /1–5000/);
  assert.throws(() => parse({ wireMagic: 'other', events: fixture().events }), /wireMagic/);
  assert.throws(() => importJson3(Buffer.from([255]), 6000), /UTF-8/);
  assert.throws(() => importJson3(Buffer.alloc(MAX_SOURCE_BYTES + 1), 6000), /2097152/);
});

test('actual CLI import survives native show, correction, export and reopen', () => {
  const native = process.env.MOONCAST_CAPTION_EDIT;
  const evidenceRoot = process.env.MOONCAST_JSON3_EVIDENCE;
  assert.ok(native && evidenceRoot, 'Set MOONCAST_CAPTION_EDIT and MOONCAST_JSON3_EVIDENCE; this journey requires the retained native consumer and retained output directory');
  const evidence = mkdtempSync(join(evidenceRoot, 'json3-journey-'));
  const run = (program, args, label, expected = 0) => {
    const result = spawnSync(program, args, { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
    writeFileSync(join(evidence, `${label}.log`), JSON.stringify({ program, args, status: result.status, stdout: result.stdout, stderr: result.stderr }, null, 2));
    assert.equal(result.status, expected, `${label}: ${result.error ?? result.stderr}`);
    return result;
  };
  const cli = join(root, 'cmd/json3_captions/main.mjs');
  const input = join(root, 'fixtures/json3-captions.json3');
  const bundle = join(evidence, 'imported');
  run(process.execPath, [cli, 'preview', input, '6000'], 'preview');
  run(process.execPath, [cli, 'import', input, '6000', bundle], 'import');
  const original = readFileSync(input), draft = join(bundle, 'captions.json');
  assert.deepEqual(readFileSync(join(bundle, 'source.json3')), original);
  const shown = run(native, ['show', draft], 'native-show');
  assert.match(shown.stdout, /Hello 東京 & friends\./);
  const revised = join(evidence, 'revised.json');
  run(native, ['set', draft, '2', '2400', '4100', 'Revised 🌱 caption.', revised], 'native-correct');
  run(native, ['show', revised], 'native-reopen');
  const revisedData = JSON.parse(readFileSync(revised));
  assert.deepEqual(revisedData.cues[1], { start_ms: 2400, end_ms: 4100, text: 'Revised 🌱 caption.' });
  assert.deepEqual(revisedData.cues[0], JSON.parse(readFileSync(draft)).cues[0]);
  run(native, ['export', revised, join(evidence, 'corrected')], 'native-export');
  const srt = readFileSync(join(evidence, 'corrected.srt'), 'utf8');
  assert.match(srt, /00:00:02,400 --> 00:00:04,100\nRevised 🌱 caption\./);
  assert.match(readFileSync(join(evidence, 'corrected.vtt'), 'utf8'), /Hello 東京 &amp; friends\./);
  run(native, ['import', join(evidence, 'corrected.srt'), '6000', join(evidence, 'reopened-from-srt.json')], 'native-srt-reimport');
  assert.deepEqual(JSON.parse(readFileSync(join(evidence, 'reopened-from-srt.json'))).cues, revisedData.cues);
  run(process.execPath, [cli, 'import', input, '6000', bundle], 'existing-destination', 1);
  const bad = fixture(); bad.events[0].aAppend = 1;
  const badPath = join(evidence, 'unsupported.json3'); writeFileSync(badPath, JSON.stringify(bad));
  const rejected = join(evidence, 'must-not-exist');
  run(process.execPath, [cli, 'import', badPath, '6000', rejected], 'unsupported-profile', 1);
  assert.ok(!readdirSync(evidence).includes('must-not-exist'));
  assert.deepEqual(readFileSync(input), original);
  writeFileSync(join(evidence, 'journey.json'), JSON.stringify({ outcome: 'passed', native, native_sha256: digest(readFileSync(native)), source_sha256: digest(original), draft_sha256: digest(readFileSync(draft)), revised_sha256: digest(readFileSync(revised)), output_srt_sha256: digest(Buffer.from(srt)), runtime_rebuilt: false }, null, 2) + '\n');
});
