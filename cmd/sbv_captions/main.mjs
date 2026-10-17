import { createHash } from 'node:crypto';
import { open, mkdir, writeFile } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const MAX_SOURCE_BYTES = 2 * 1024 * 1024;
const fail = message => { throw new Error(message); };
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const json = value => JSON.stringify(value, null, 2) + '\n';
const timestamp = '(\\d{1,2}):([0-5]\\d):([0-5]\\d)\\.(\\d{3})';
const timing = new RegExp(`^${timestamp},${timestamp}$`);
const ms = parts => Number(parts[0]) * 3600000 + Number(parts[1]) * 60000 + Number(parts[2]) * 1000 + Number(parts[3]);

/** Import the declared plain-text SBV subset without inference, sorting or clipping. */
export function importSbv(bytes, durationMs, sourceName = 'captions.sbv') {
  if (!Buffer.isBuffer(bytes) || !bytes.length || bytes.length > MAX_SOURCE_BYTES) fail('SBV input must contain 1–2097152 bytes');
  if (!Number.isSafeInteger(durationMs) || durationMs < 1 || durationMs > 7200000) fail('Known media duration must be an integer from 1 to 7200000 ms');
  if (typeof sourceName !== 'string' || !sourceName.trim()) fail('A source filename is required');
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); } catch { fail('SBV input must be valid UTF-8'); }
  // Retain exact original offsets: normalize line endings only in resulting cue text.
  const lines = []; let offset = 0;
  for (const match of text.matchAll(/([^\r\n]*)(\r\n|\r|\n|$)/g)) {
    if (!match[0]) break;
    const size = Buffer.byteLength(match[0]), contentSize = Buffer.byteLength(match[1]);
    lines.push({ text: match[1], start: offset, end: offset + contentSize }); offset += size;
  }
  if (lines[0]?.text.startsWith('\ufeff')) { lines[0].text = lines[0].text.slice(1); lines[0].start += 3; }
  const cues = [], mappings = []; let cursor = 0, previous = -1;
  while (cursor < lines.length) {
    while (cursor < lines.length && lines[cursor].text === '') cursor++;
    if (cursor === lines.length) break;
    const first = cursor, header = lines[cursor++], match = timing.exec(header.text);
    if (!match) fail(`Line ${first + 1}: expected H:MM:SS.mmm,H:MM:SS.mmm with no cue IDs, settings or headers`);
    const start = ms(match.slice(1, 5)), end = ms(match.slice(5, 9));
    if (end <= start || end > durationMs) fail(`Line ${first + 1}: interval must be positive and inside media duration`);
    if (start < previous) fail('SBV cues must remain in start-time order');
    const content = [];
    while (cursor < lines.length && lines[cursor].text !== '') {
      const line = lines[cursor++].text;
      if (timing.test(line)) fail('Missing blank separator before a timing line; literal timestamp-only caption lines are outside this subset');
      if (!line.trim() || /[<>\u0000-\u001f\u007f-\u009f\ufeff]/u.test(line)) fail('Caption lines must be nonblank plain text without markup, controls or embedded BOM');
      content.push(line);
    }
    const caption = content.join('\n');
    if (!caption || caption.length > 2000) fail('Each caption needs 1–2000 UTF-16 units of text');
    cues.push({ start_ms: start, end_ms: end, text: caption }); previous = start;
    if (cues.length > 5000) fail('SBV supports 1–5000 cues');
    mappings.push({ block: cues.length, cue: cues.length, first_line: first + 1, last_line: cursor,
      source_byte_start: header.start, source_byte_end: lines[cursor - 1].end,
      timing: header.text, start_ms: start, end_ms: end });
  }
  if (!cues.length) fail('SBV supports 1–5000 cues');
  const draft = { contract: 'mooncast.caption-draft.v1', source_file: sourceName, duration_ms: durationMs, cues }, draftText = json(draft);
  const exportBytes = 7 + cues.reduce((total, cue, index) => total + String(index + 1).length + 33 + Buffer.byteLength(cue.text.replaceAll('&', '&amp;')), 0);
  if (Buffer.byteLength(draftText) > 16777216 || exportBytes > 2097152) fail('Derived draft/export exceeds native byte bounds; split the source explicitly');
  return { draft, draftText, report: { contract: 'mooncast.sbv-caption-import.v1', source_file: sourceName,
    source_sha256: sha(bytes), source_bytes: bytes.length, draft_sha256: sha(draftText), duration_ms: durationMs,
    cue_count: cues.length, mappings,
    timing: 'Explicit media-relative integer milliseconds. Source order, equal starts and overlaps preserved; no clipping or rounding.',
    losses: ['Optional initial UTF-8 BOM and empty separator lines are omitted from the draft. CRLF/CR become LF inside captions; all other caption text is preserved literally, including ampersands and entity-looking strings.',
      'The inherited native SRT reimport trims leading/trailing whitespace from each caption line. The SBV draft and native SRT/WebVTT exports preserve those spaces, but an SRT-reimported draft may not. Keep and reopen the JSON draft when exact text preservation matters.',
      'No language, speaker, style, translation or alignment inference. Original bytes remain in source.sbv.',
      'Duration is operator supplied. Playback, rights, accessibility and client delivery acceptance require separate review.'],
    qualification: 'Offline bounded plain-text SBV subset; not general caption interchange or production approval.' } };
}

export async function main(args) {
  const [action, input, duration, destination] = args;
  if (!['preview', 'import'].includes(action) || args.length !== (action === 'preview' ? 3 : 4) || !/^[1-9]\d*$/.test(duration ?? '')) fail('Usage: node cmd/sbv_captions/main.mjs preview INPUT.sbv DURATION_MS\n       node cmd/sbv_captions/main.mjs import INPUT.sbv DURATION_MS NEW_DIRECTORY');
  if (input.includes('://') || destination?.includes('://')) fail('Use explicit local paths');
  const file = await open(input, 'r'); let bytes;
  try {
    const info = await file.stat();
    if (!info.isFile() || info.size < 1 || info.size > MAX_SOURCE_BYTES) fail('SBV input must be a regular file containing 1–2097152 bytes');
    const buffer = Buffer.alloc(MAX_SOURCE_BYTES + 1); let length = 0;
    while (length < buffer.length) { const read = await file.read(buffer, length, buffer.length - length, null); if (!read.bytesRead) break; length += read.bytesRead; }
    if (length > MAX_SOURCE_BYTES) fail('SBV input exceeds 2097152 bytes');
    bytes = buffer.subarray(0, length);
  } finally { await file.close(); }
  const result = importSbv(bytes, Number(duration), basename(input));
  if (action === 'preview') { process.stdout.write(json({ ...result.report, cues: result.draft.cues })); return; }
  await mkdir(destination);
  try {
    await writeFile(join(destination, 'source.sbv'), bytes, { flag: 'wx' });
    await writeFile(join(destination, 'captions.json'), result.draftText, { flag: 'wx' });
    await writeFile(join(destination, 'import.json'), json({ ...result.report, files: { original: 'source.sbv', draft: 'captions.json', report: 'import.json' } }), { flag: 'wx' });
  } catch (reason) { fail(`New bundle may be partial; retain it and retry at a fresh path after resolving the filesystem error: ${reason.message}`); }
  process.stdout.write(json({ directory: destination, cue_count: result.draft.cues.length, source_sha256: result.report.source_sha256 }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main(process.argv.slice(2)).catch(reason => { process.stderr.write(`SBV caption import: ${reason.message}\n`); process.exitCode = 1; });
