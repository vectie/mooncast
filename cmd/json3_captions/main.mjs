import { createHash } from 'node:crypto';
import { readFile, stat, mkdir, writeFile } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const MAX_SOURCE_BYTES = 2 * 1024 * 1024;
const error = message => { throw new Error(message); };
const object = (value, label) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) error(`${label} must be an object`);
};
const fields = (value, allowed, label) => {
  object(value, label);
  for (const key of Object.keys(value)) if (!allowed.includes(key)) error(`${label}: unsupported field ${key}; convert this JSON3 profile explicitly before import`);
};
const integer = (value, label, minimum = 0, maximum = 7200000) => {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) error(`${label} must be an integer from ${minimum} to ${maximum}`);
  return value;
};
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const json = value => JSON.stringify(value, null, 2) + '\n';

/** Import complete independent JSON3 caption events; never infer rolling windows. */
export function importJson3(bytes, durationMs, sourceName = 'captions.json3') {
  if (!Buffer.isBuffer(bytes) || !bytes.length || bytes.length > MAX_SOURCE_BYTES) error('JSON3 input must contain 1–2097152 bytes');
  integer(durationMs, 'Known media duration', 1);
  if (typeof sourceName !== 'string' || !sourceName.trim()) error('A source filename is required');
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch { error('JSON3 input must be valid UTF-8'); }
  let source;
  try {
    source = JSON.parse(text, (key, value, context) => {
      if (['tStartMs', 'dDurationMs', 'tOffsetMs'].includes(key) && typeof value === 'number' &&
          !context) error('This companion requires JSON.parse source context (tested with Node.js 24)');
      if (['tStartMs', 'dDurationMs', 'tOffsetMs'].includes(key) && typeof value === 'number' &&
          !/^(?:0|[1-9][0-9]*)$/.test(context.source)) {
        error(`${key} requires a nonnegative base-10 integer token; fractional/exponent timing is unsupported`);
      }
      return value;
    });
  } catch (reason) { error(`Cannot read JSON3: ${reason.message}`); }
  fields(source, ['wireMagic', 'events', 'pens', 'wsWinStyles', 'wpWinPositions'], 'JSON3');
  if (source.wireMagic !== 'pb3') error('Expected JSON3 wireMagic "pb3"');
  for (const key of ['pens', 'wsWinStyles', 'wpWinPositions']) {
    if (source[key] !== undefined && !Array.isArray(source[key])) error(`${key} must be an array`);
  }
  if (!Array.isArray(source.events) || !source.events.length || source.events.length > 5000) error('JSON3 needs 1–5000 independent caption events');
  const cues = [], mappings = [];
  let previousStart = -1, timedSegments = 0, confidenceSegments = 0, styledSegments = 0;
  for (const [index, event] of source.events.entries()) {
    const label = `event ${index + 1}`;
    object(event, label);
    if (['aAppend', 'wWinId', 'id', 'wpWinPosId', 'wsWinStyleId'].some(key => key in event)) {
      error(`${label}: rolling/append/window-control events are unsupported; supply independent complete caption events`);
    }
    fields(event, ['tStartMs', 'dDurationMs', 'segs'], label);
    const start = integer(event.tStartMs, `${label} tStartMs`);
    const length = integer(event.dDurationMs, `${label} dDurationMs`, 1);
    if (start + length > durationMs) error(`${label} ends beyond the known media duration`);
    if (start < previousStart) error(`${label} is out of start-time order; source order is not silently changed`);
    if (!Array.isArray(event.segs) || !event.segs.length || event.segs.length > 2000) error(`${label} needs 1–2000 text segments`);
    let content = '', previousOffset = -1;
    for (const [segmentIndex, segment] of event.segs.entries()) {
      const segmentLabel = `${label} segment ${segmentIndex + 1}`;
      fields(segment, ['utf8', 'tOffsetMs', 'acAsrConf', 'pPenId'], segmentLabel);
      if (typeof segment.utf8 !== 'string') error(`${segmentLabel} needs utf8 text`);
      if (segment.tOffsetMs !== undefined) {
        const offset = integer(segment.tOffsetMs, `${segmentLabel} tOffsetMs`, 0, length);
        if (offset < previousOffset) error(`${segmentLabel} has decreasing segment offsets`);
        previousOffset = offset;
        timedSegments++;
      }
      if (segment.acAsrConf !== undefined) {
        if (typeof segment.acAsrConf !== 'number' || !Number.isFinite(segment.acAsrConf)) error(`${segmentLabel} acAsrConf must be finite`);
        confidenceSegments++;
      }
      if (segment.pPenId !== undefined) {
        integer(segment.pPenId, `${segmentLabel} pPenId`, 0, Number.MAX_SAFE_INTEGER);
        styledSegments++;
      }
      content += segment.utf8;
    }
    if (!content.trim() || content.length > 2000 || /[<>\u0000-\u0009\u000b-\u001f]/u.test(content) || /[\ud800-\udfff]/u.test(content) || content.split('\n').some(line => !line.trim())) {
      error(`${label}: use 1–2000 UTF-16 units of valid plain text, no markup/control characters or blank lines`);
    }
    cues.push({ start_ms: start, end_ms: start + length, text: content });
    mappings.push({ cue: cues.length, event: index + 1, segment_count: event.segs.length, start_ms: start, end_ms: start + length });
    previousStart = start;
  }
  const draft = { contract: 'mooncast.caption-draft.v1', source_file: sourceName, duration_ms: durationMs, cues };
  const draftText = json(draft);
  const report = {
    contract: 'mooncast.json3-caption-import.v1',
    source_file: sourceName,
    source_sha256: sha(bytes), source_bytes: bytes.length,
    draft_sha256: sha(draftText), duration_ms: durationMs,
    cue_count: cues.length, mappings,
    flattened: { timed_segments: timedSegments, confidence_segments: confidenceSegments, styled_segments: styledSegments,
      pens: source.pens?.length ?? 0, window_styles: source.wsWinStyles?.length ?? 0, window_positions: source.wpWinPositions?.length ?? 0 },
    losses: [
      'Segment text is concatenated exactly, without inserted spaces or HTML-entity decoding. Each entire caption uses its explicit event interval.',
      'Word offsets, confidence, pens, window styling and positioning remain in source.json3; they are not editable styling or word timing in the plain caption draft.',
      'Known media duration is operator supplied, not probed. Timing alignment, transcription quality, rights and delivery require separate review.'
    ],
    qualification: 'Offline JSON3 subset intake to an ordinary editable caption draft; no download, provider request, live Studio mutation or production approval.'
  };
  return { draft, draftText, report };
}

export async function main(args) {
  const usage = 'Usage: node cmd/json3_captions/main.mjs preview INPUT.json3 DURATION_MS\n       node cmd/json3_captions/main.mjs import INPUT.json3 DURATION_MS NEW_DIRECTORY';
  const [action, input, duration, destination] = args;
  if (!['preview', 'import'].includes(action) || args.length !== (action === 'preview' ? 3 : 4) || !/^[1-9][0-9]*$/.test(duration ?? '')) error(usage);
  if (input.includes('://') || destination?.includes('://')) error('Use explicit local paths');
  const info = await stat(input);
  if (!info.isFile() || info.size > MAX_SOURCE_BYTES) error('JSON3 input must be a regular file no larger than 2 MiB');
  const bytes = await readFile(input);
  const result = importJson3(bytes, Number(duration), basename(input));
  if (action === 'preview') { process.stdout.write(json({ ...result.report, cues: result.draft.cues })); return; }
  // Prepare every byte before creating a new, exclusive bundle directory.
  const report = json({ ...result.report, files: { original: 'source.json3', draft: 'captions.json', report: 'import.json' } });
  await mkdir(destination);
  try {
    await writeFile(join(destination, 'source.json3'), bytes, { flag: 'wx' });
    await writeFile(join(destination, 'captions.json'), result.draftText, { flag: 'wx' });
    await writeFile(join(destination, 'import.json'), report, { flag: 'wx' });
  } catch (reason) { error(`New bundle may be partial; retain it and retry at a fresh path after resolving the filesystem error: ${reason.message}`); }
  process.stdout.write(json({ directory: destination, cue_count: result.draft.cues.length, source_sha256: result.report.source_sha256 }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(reason => { process.stderr.write(`JSON3 caption import: ${reason.message}\n`); process.exitCode = 1; });
}
