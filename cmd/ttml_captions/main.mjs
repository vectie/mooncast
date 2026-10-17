import { createHash } from 'node:crypto';
import { readFile, stat, mkdir, writeFile } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const MAX_SOURCE_BYTES = 2 * 1024 * 1024;
const error = message => { throw new Error(message); };
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const json = value => JSON.stringify(value, null, 2) + '\n';
const language = value => typeof value === 'string' && /^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$/.test(value);
const styles = ['tts:color', 'tts:backgroundColor', 'tts:fontFamily', 'tts:fontSize', 'tts:fontStyle', 'tts:fontWeight', 'tts:textAlign', 'tts:textDecoration'];
const xmlChar = n => n === 9 || n === 10 || n === 13 || n >= 32 && n <= 0xd7ff || n >= 0xe000 && n <= 0xfffd || n >= 0x10000 && n <= 0x10ffff;

function decode(text) {
  if (/&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9A-Fa-f]+);)/.test(text)) error('Only predefined and numeric XML entities are supported');
  return text.replace(/&(amp|lt|gt|quot|apos|#\d+|#x[0-9A-Fa-f]+);/g, (_, entity) => {
    const known = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
    if (entity in known) return known[entity];
    const n = entity.startsWith('#x') ? parseInt(entity.slice(2), 16) : Number(entity.slice(1));
    if (!Number.isSafeInteger(n) || !xmlChar(n)) error('Invalid XML character reference');
    return String.fromCodePoint(n);
  });
}

function attributes(raw) {
  const out = Object.create(null), re = /\s+([A-Za-z_][A-Za-z0-9_.:-]*)\s*=\s*(?:"([^"<]*)"|'([^'<]*)')/y;
  let offset = 0;
  while (raw.slice(offset).trim()) {
    re.lastIndex = offset; const match = re.exec(raw);
    if (!match || Object.hasOwn(out, match[1])) error('Expected distinct quoted XML attributes');
    out[match[1]] = decode((match[2] ?? match[3]).replace(/\r\n|[\r\n\t]/g, ' ')); offset = re.lastIndex;
  }
  return out;
}

function parseXml(text) {
  for (const character of text) if (!xmlChar(character.codePointAt(0))) error('Invalid XML character');
  const declaration = /^(?:\ufeff)?<\?xml\s+version\s*=\s*(['"])1\.0\1(?:\s+encoding\s*=\s*(['"])UTF-8\2)?(?:\s+standalone\s*=\s*(['"])(?:yes|no)\3)?\s*\?>/i.exec(text);
  let offset = declaration?.[0].length ?? (text.startsWith('\ufeff') ? 1 : 0), root = null, count = 0;
  const stack = [], ids = new Set();
  const tokens = /<!--[\s\S]*?-->|<\/[A-Za-z_][A-Za-z0-9_.:-]*\s*>|<[A-Za-z_][A-Za-z0-9_.:-]*(?:\s+[A-Za-z_][A-Za-z0-9_.:-]*\s*=\s*(?:"[^"<]*"|'[^'<]*'))*\s*\/?>|[^<]+/gy;
  const children = { tt: ['body'], body: ['div'], div: ['p'], p: ['span', 'br'], span: ['span', 'br'], br: [] };
  while (offset < text.length) {
    tokens.lastIndex = offset; const match = tokens.exec(text), start = offset;
    if (!match) error('Malformed or unsupported XML: DTD, CDATA and processing instructions reject');
    const token = match[0]; offset = tokens.lastIndex;
    if (token.startsWith('<!--')) { if (token.slice(4, -3).includes('--')) error('Malformed XML comment'); continue; }
    if (!token.startsWith('<')) {
      if (token.includes(']]>')) error('Invalid XML character data');
      if (!['p', 'span'].includes(stack.at(-1)?.tag)) { if (token.trim()) error('Text is only supported inside p/span'); }
      else stack.at(-1).content.push(decode(token.replace(/\r\n?/g, '\n')));
      continue;
    }
    if (token.startsWith('</')) {
      const node = stack.pop();
      if (node?.tag !== token.slice(2, -1).trim()) error('XML elements must close in order');
      node.end = offset; continue;
    }
    const parts = /^<([A-Za-z_][A-Za-z0-9_.:-]*)([\s\S]*?)(\/?)>$/.exec(token), tag = parts[1];
    if (!Object.hasOwn(children, tag)) error(`Unsupported TTML element ${tag}; use the declared tt/body/div/p/span/br subset`);
    if (++count > 20000 || stack.length >= 16) error('TTML exceeds 20000 elements or 16 nesting levels');
    const parent = stack.at(-1);
    if (!parent && (root || tag !== 'tt') || parent && !children[parent.tag].includes(tag)) error(`Unsupported TTML structure at ${tag}`);
    const attrs = attributes(parts[2]);
    const allowed = new Set(['xml:lang', 'xml:id', ...(tag === 'tt' ? ['xmlns', 'xmlns:tts', 'xmlns:ttp', 'ttp:timeBase', 'xml:space'] : []), ...(tag === 'p' ? ['begin', 'end', 'dur'] : []), ...(['p', 'span'].includes(tag) ? styles : [])]);
    for (const key of Object.keys(attrs)) if (!allowed.has(key)) error(`Unsupported ${key} on ${tag}; inherited timing, timed spans, regions, style references and frame/tick conventions reject`);
    if (tag === 'tt' && (attrs.xmlns !== 'http://www.w3.org/ns/ttml' || attrs['xmlns:tts'] !== undefined && attrs['xmlns:tts'] !== 'http://www.w3.org/ns/ttml#styling' || attrs['xmlns:ttp'] !== undefined && attrs['xmlns:ttp'] !== 'http://www.w3.org/ns/ttml#parameter')) error('Use the canonical default TTML namespace and declared tts/ttp namespaces');
    if (attrs['ttp:timeBase'] !== undefined && (attrs['ttp:timeBase'] !== 'media' || attrs['xmlns:ttp'] === undefined)) error('Only explicitly declared media timeBase is supported');
    if (attrs['xml:space'] !== undefined && attrs['xml:space'] !== 'default') error('Only xml:space="default" is supported');
    if (styles.some(key => key in attrs) && !(root ?? { attrs }).attrs['xmlns:tts']) error('Styling attributes require the canonical tts namespace');
    if (attrs['xml:lang'] !== undefined && !language(attrs['xml:lang'])) error('xml:lang must be a nonempty simple language tag');
    if (attrs['xml:id'] !== undefined) {
      if (!/^[A-Za-z_][A-Za-z0-9_.-]*$/.test(attrs['xml:id']) || ids.has(attrs['xml:id'])) error('xml:id must be a unique simple XML identifier');
      ids.add(attrs['xml:id']);
    }
    const node = { tag, attrs, lang: attrs['xml:lang'] ?? parent?.lang, content: [], start, end: parts[3] ? offset : null };
    if (parent) parent.content.push(node); else root = node;
    if (['span', 'br'].includes(tag) && node.lang !== parent.lang) error('Mixed-language spans are unsupported; select separately timed paragraphs');
    if (!parts[3]) stack.push(node);
  }
  if (!root || stack.length || root.content.length !== 1 || root.content[0].tag !== 'body' || !root.content[0].content.length) error('A complete tt/body/div document is required');
  return root;
}

function time(value, label) {
  if (typeof value !== 'string') error(`${label}: explicit paragraph timing is required`);
  let ms, match;
  if ((match = /^(\d{2}):([0-5]\d):([0-5]\d)(?:\.(\d{1,3}))?$/.exec(value))) ms = Number(match[1]) * 3600000 + Number(match[2]) * 60000 + Number(match[3]) * 1000 + Number((match[4] ?? '').padEnd(3, '0'));
  else if ((match = /^(0|[1-9]\d*)(?:\.(\d{1,3}))?s$/.exec(value))) ms = Number(match[1]) * 1000 + Number((match[2] ?? '').padEnd(3, '0'));
  else if ((match = /^(0|[1-9]\d*)ms$/.exec(value))) ms = Number(match[1]);
  else error(`${label}: supported timing is HH:MM:SS[.mmm], seconds[.mmm]s or integer ms; no rounding/frame/tick timing`);
  if (!Number.isSafeInteger(ms) || ms > 7200000) error(`${label}: timing exceeds the 7200000 ms bound`);
  return ms;
}

function plain(node) { return node.tag === 'br' ? '\n' : node.content.map(child => typeof child === 'string' ? child.replace(/[\t\n\r ]+/g, ' ') : plain(child)).join(''); }
function styling(node, records = []) {
  const attrs = Object.fromEntries(Object.entries(node.attrs).filter(([key]) => styles.includes(key)));
  if (Object.keys(attrs).length) records.push({ tag: node.tag, xml_id: node.attrs['xml:id'] ?? null, attributes: attrs });
  for (const child of node.content) if (typeof child !== 'string') styling(child, records);
  return records;
}

/** Deliberate plain-caption TTML subset. No XML execution, references or inferred timing. */
export function importTtml(bytes, durationMs, selectedLanguage, sourceName = 'captions.ttml') {
  if (!Buffer.isBuffer(bytes) || !bytes.length || bytes.length > MAX_SOURCE_BYTES) error('TTML input must contain 1–2097152 bytes');
  if (!Number.isSafeInteger(durationMs) || durationMs < 1 || durationMs > 7200000) error('Known media duration must be an integer from 1 to 7200000 ms');
  if (!language(selectedLanguage)) error('Select an explicit language tag');
  if (typeof sourceName !== 'string' || !sourceName.trim()) error('A source filename is required');
  let text; try { text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); } catch { error('TTML input must be valid UTF-8'); }
  const root = parseXml(text), paragraphs = root.content[0].content.flatMap(div => div.content);
  if (!paragraphs.length || paragraphs.length > 5000) error('TTML needs 1–5000 timed paragraphs');
  const cues = [], mappings = []; let previousStart = -1, byteCursor = 0, charCursor = 0;
  for (const [index, p] of paragraphs.entries()) {
    if (!language(p.lang)) error(`Paragraph ${index + 1} needs an explicit or inherited xml:lang`);
    const start = time(p.attrs.begin, `Paragraph ${index + 1} begin`);
    if ((p.attrs.end === undefined) === (p.attrs.dur === undefined)) error('Each paragraph needs exactly one end or dur');
    const end = p.attrs.end === undefined ? start + time(p.attrs.dur, 'dur') : time(p.attrs.end, 'end');
    if (end <= start || end > durationMs) error('Paragraph interval must be positive and within the known media duration');
    const content = plain(p).split('\n').map(line => line.replace(/[\t\r ]+/g, ' ').trim()).join('\n');
    if (!content.trim() || content.length > 2000 || /[<>\u0000-\u0009\u000b-\u001f]/u.test(content) || content.split('\n').some(line => !line.trim())) error('Each paragraph must yield 1–2000 UTF-16 units of plain caption text without markup, controls or blank lines');
    const selected = p.lang.toLowerCase() === selectedLanguage.toLowerCase();
    if (selected) {
      if (start < previousStart) error('Selected paragraphs must be in start-time order; source order is never changed');
      cues.push({ start_ms: start, end_ms: end, text: content }); previousStart = start;
    }
    byteCursor += Buffer.byteLength(text.slice(charCursor, p.start)); const byteStart = byteCursor;
    byteCursor += Buffer.byteLength(text.slice(p.start, p.end)); charCursor = p.end;
    mappings.push({ paragraph: index + 1, xml_id: p.attrs['xml:id'] ?? null, language: p.lang, selected, cue: selected ? cues.length : null,
      source_byte_start: byteStart, source_byte_end: byteCursor,
      begin: p.attrs.begin, end: p.attrs.end ?? null, dur: p.attrs.dur ?? null, start_ms: start, end_ms: end, omitted_styling: styling(p) });
  }
  if (!cues.length) error('No paragraphs match the selected language');
  const draft = { contract: 'mooncast.caption-draft.v1', source_file: sourceName, duration_ms: durationMs, cues }, draftText = json(draft);
  const vttBytes = 7 + cues.reduce((total, cue, index) => total + String(index + 1).length + 33 + Buffer.byteLength(cue.text.replaceAll('&', '&amp;')), 0);
  if (Buffer.byteLength(draftText) > 16777216 || vttBytes > 2097152) error('Derived caption draft/export exceeds native byte bounds; split the source explicitly');
  return { draft, draftText, report: { contract: 'mooncast.ttml-caption-import.v1', source_file: sourceName, source_sha256: sha(bytes), source_bytes: bytes.length,
    draft_sha256: sha(draftText), duration_ms: durationMs, selected_language: selectedLanguage, cue_count: cues.length, paragraph_count: paragraphs.length,
    unselected_paragraph_count: paragraphs.length - cues.length, mappings,
    timing: 'Media-relative explicit paragraph begin plus exactly one end/dur; exact integer milliseconds, no inherited timing. Overlaps retained.',
    whitespace: 'XML CRLF/CR normalization, predefined/numeric entity decoding, default XML whitespace collapsed across untimed spans; br becomes newline; trim each resulting line.',
    losses: ['Selected language paragraphs only; every other paragraph is explicitly mapped as unselected. No translation or language inference.',
      'Allowed inline visual styling is recorded but not rendered: color, backgroundColor, fontFamily, fontSize, fontStyle, fontWeight, textAlign, textDecoration. Regions, position, style references and other semantics reject.',
      'Untimed span boundaries and XML whitespace layout are flattened to plain text. Original bytes remain in source.ttml.',
      'Duration is operator supplied. Timing alignment, playback, rights, accessibility and delivery acceptance require separate review.'],
    qualification: 'Offline bounded TTML plain-caption subset, not general TTML/IMSC compatibility, rendering or production approval.' } };
}

export async function main(args) {
  const [action, input, duration, lang, destination] = args;
  if (!['preview', 'import'].includes(action) || args.length !== (action === 'preview' ? 4 : 5) || !/^[1-9]\d*$/.test(duration ?? '')) error('Usage: node cmd/ttml_captions/main.mjs preview INPUT.ttml DURATION_MS LANGUAGE\n       node cmd/ttml_captions/main.mjs import INPUT.ttml DURATION_MS LANGUAGE NEW_DIRECTORY');
  if (input.includes('://') || destination?.includes('://')) error('Use explicit local paths');
  const info = await stat(input); if (!info.isFile() || info.size > MAX_SOURCE_BYTES) error('TTML input must be a regular file no larger than 2 MiB');
  const bytes = await readFile(input), result = importTtml(bytes, Number(duration), lang, basename(input));
  if (action === 'preview') { process.stdout.write(json({ ...result.report, cues: result.draft.cues })); return; }
  const report = json({ ...result.report, files: { original: 'source.ttml', draft: 'captions.json', report: 'import.json' } });
  await mkdir(destination);
  try {
    await writeFile(join(destination, 'source.ttml'), bytes, { flag: 'wx' });
    await writeFile(join(destination, 'captions.json'), result.draftText, { flag: 'wx' });
    await writeFile(join(destination, 'import.json'), report, { flag: 'wx' });
  } catch (reason) { error(`New bundle may be partial; retain it and retry at a fresh path after resolving the filesystem error: ${reason.message}`); }
  process.stdout.write(json({ directory: destination, cue_count: result.draft.cues.length, source_sha256: result.report.source_sha256 }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main(process.argv.slice(2)).catch(reason => { process.stderr.write(`TTML caption import: ${reason.message}\n`); process.exitCode = 1; });
