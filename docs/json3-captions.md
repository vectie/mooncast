# Continue editing a saved JSON3 caption track

This explicit offline import companion opens a local JSON3 caption file and
creates an ordinary `mooncast.caption-draft.v1` document for the existing native
caption editor. It fills a missing intake format: the native importer already
accepts SRT, WebVTT, Whisper JSON/TSV and Audacity labels, but does not read JSON3
events. No live YouTube access, download, transcription or provider is involved.
Use a file you have permission to edit and supply its known media duration.

## Preview, import, correct and export

From the source root, with Node.js 24 and the existing `caption_edit` executable
available (the companion does not install or build either runtime):

```sh
node cmd/json3_captions/main.mjs preview fixtures/json3-captions.json3 6000
node cmd/json3_captions/main.mjs import fixtures/json3-captions.json3 6000 /absolute/new-caption-folder
/absolute/caption_edit.exe show /absolute/new-caption-folder/captions.json
/absolute/caption_edit.exe set /absolute/new-caption-folder/captions.json 2 2400 4100 'Revised caption.' /absolute/revised.json
/absolute/caption_edit.exe export /absolute/revised.json /absolute/revised-captions
```

The synthetic fixture gives three captions at 200–2000, 2300–4000 and
4500–5500 milliseconds. The first contains multiple timed segments and Unicode;
the second has two lines. Segment strings join exactly, so their existing
spaces and newlines matter. The native correction creates a new JSON draft and
exports ordinary `.srt` and `.vtt` files. Existing split, merge, shift and
two-point synchronization remain available; see [caption editing](caption-editing.md).

Import requires a new directory with an existing parent. It writes:

- `source.json3`: exact original bytes, including formatting and BOM if supplied
- `captions.json`: the editable plain-caption derivative
- `import.json`: original and draft SHA-256, byte length, known duration,
  event-to-cue mapping and explicit losses

Keep all three to inspect the conversion later. Later native edits have their
own bytes; the original import record describes only the first imported draft.
The source filename is informational and is never a network locator.

## Supported independent-event profile

The JSON object has `wireMagic: "pb3"` and 1–5000 `events`. Each event has an
explicit nonnegative integer `tStartMs`, positive integer `dDurationMs`, and
1–2000 `segs` with `utf8` strings. Each entire event becomes one caption from
start through start + duration. Starts must already be ordered; overlaps and
equal starts are preserved. There is no sorting, duration inference, blank-event
discarding, clipping, deduplication or space insertion.

Optional segment `tOffsetMs`, `acAsrConf` and `pPenId` are retained in the
original source and counted in the report. Offsets must be ordered, integer and
within their event. Their word-level timing is flattened into one full-event
caption. Confidence and styling do not change caption text. Optional root
`pens`, `wsWinStyles` and `wpWinPositions` arrays are retained but not rendered.

Append and window-control events (`aAppend`, `wWinId`, `id`, `wpWinPosId`,
`wsWinStyleId`) reject with a diagnostic. This intentionally excludes rolling
automatic-caption streams that need window reconstruction. Missing durations,
empty update events and unknown root/event/segment fields also reject rather
than silently dropping possible behavior. Export those tracks as ordinary
independent SRT/WebVTT using their source tool before native import. This is a
bounded JSON3 profile, not a general YouTube caption validator or a promise that
every JSON3 download is accepted.

Input is at most 2 MiB of valid UTF-8. Known media duration is 1–7,200,000 ms.
Timing JSON numbers use base-10 integer tokens; fractional and exponent spellings
are refused even if JavaScript would round them to an integer. The source-context
JSON parser support was tested on Node.js 24.19.0. Other ordinary JSON parsing
behavior follows Node's built-in reader, including duplicate-key handling;
provide unambiguous JSON.

Each caption has 1–2000 UTF-16 units of valid plain text with no angle brackets,
tabs, CR, control characters or blank lines, matching the native draft's bounded
text surface. Plain entity-shaped text such as `&amp;` stays literal; this
companion does not HTML-decode it. The native WebVTT exporter escapes ampersands.
The native exporter independently enforces its 2 MiB SRT/WebVTT output bounds.

## Recovery, qualification and boundaries

Preview changes no files. Import validates and prepares every output before
creating its exclusive new directory. An existing directory is refused. A later
filesystem failure can leave a partial new bundle; retain it and retry with a
fresh path after resolving the error. Original inputs and native editor runtime
remain unchanged.

This Node companion is opt-in local file intake, separate from the MoonBit /
Rabbita application runtime, installer and live Studio. It grants no source
rights, reviewed master, client acceptance, publishing or production authority.
Media duration is supplied, not probed; inspect actual playback to judge timing
and readability. No actual YouTube export corpus, graphical browser, media
playback, installed lifecycle, live provider or full release was qualified.

Focused tests exercise valid captions, text/timing/profile refusals, the real
CLI, source preservation and actual retained native `show`, `set`, `show`,
`export` and exported-SRT reimport. To retain every generated file and log:

```sh
MOONCAST_CAPTION_EDIT=/absolute/caption_edit.exe \
MOONCAST_JSON3_EVIDENCE=/absolute/existing-private-evidence-directory \
node --test cmd/json3_captions/import.test.mjs
```

The test requires both paths; it does not skip the native journey, rebuild the
native binary or delete evidence. The native executable used in R746 is retained
from R633, with SHA-256
`480b74d956fdd6adbcaec070330790cb8a217748341767ca326af9415a23de55`.
No MoonBit source or generated interface changed in this feature, so `moon fmt`,
`moon info` and native rebuild were not run. Broader release gates stay open.
