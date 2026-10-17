# Saved TTML captions into native correction

This offline Node companion reads a deliberately bounded **plain-caption TTML
subset** into the unchanged `mooncast.caption-draft.v1` contract. It does not
download captions, render TTML, claim IMSC interoperability or approve delivery.
No dependency installation or MoonBit build is needed.

## Preview, import, correct and reopen

From this source root, using Node.js 24:

```
node cmd/ttml_captions/main.mjs preview fixtures/ttml-captions.ttml 6000 en
node cmd/ttml_captions/main.mjs import fixtures/ttml-captions.ttml 6000 en /absolute/new-caption-bundle
```

Duration is the operator's known media duration in integer milliseconds. Language
selection is explicit, case-insensitive, and exact (no regional fallback).
Preview includes all paragraph mappings, selected cues, omission counts and
losses. Import requires a new directory and writes exact `source.ttml` bytes,
editable `captions.json`, and `import.json`. Existing destinations reject without
overwriting. A partial filesystem failure leaves its directory for inspection;
retry only at a fresh path after resolving the failure.

Use your qualified `caption_edit` executable to continue:

```
caption_edit show /absolute/new-caption-bundle/captions.json
caption_edit set /absolute/new-caption-bundle/captions.json 2 2400 4100 "Revised caption." /absolute/revised.json
caption_edit show /absolute/revised.json
caption_edit export /absolute/revised.json /absolute/new-export
caption_edit import /absolute/new-export.srt 6000 /absolute/reopened.json
```

The native export creates SRT and WebVTT. The import record attests only the
initial draft; later edits are new revisions. Keep the original and report with
the revised draft. The native editor does not interpret TTML or the sidecar.

## Declared subset and losses

- UTF-8 XML 1.0, optional BOM/declaration, canonical default namespace
  `http://www.w3.org/ns/ttml`; one `tt`, one `body`, one or more direct `div`
  containers with `p` children, untimed nested `span` and `br` inside paragraphs.
  No nested divs, head, region, layout, metadata, animation or foreign elements.
- Each paragraph has explicit `begin` and exactly one `end` or `dur`.
  Times are media-relative `HH:MM:SS[.mmm]`, decimal seconds with at most three
  fractional digits (`1.25s`), or integer milliseconds (`1250ms`). Hours use two
  digits; seconds/minutes are 00–59. No rounding, frame/tick rates, negative
  offsets, implicit duration, inherited timing or timed spans. Root timeBase
  may be `media` with canonical `xmlns:ttp`; other parameter attributes reject.
- Root/body/div/p may declare `xml:lang`; every paragraph must resolve to a
  language. Mixed-language spans reject. All paragraphs, including unselected
  languages, are validated and mapped; unselected ones have a null cue number.
  Selected cues retain source order, equal starts and overlaps. Out-of-order
  selected starts and intervals outside media duration reject.
- `xml:space="default"` only. CR/CRLF normalize; XML whitespace collapses across
  untimed spans, `br` creates a line break, and each line is trimmed. Predefined
  and numeric XML entities decode exactly once. Empty/blank lines, plain text
  containing angle brackets or controls, and overlong cues reject.
- With canonical `xmlns:tts`, inline p/span color, backgroundColor, fontFamily,
  fontSize, fontStyle, fontWeight, textAlign and textDecoration are retained as
  raw omitted styling in the report. Their values are not rendered or validated
  as visual style. Other attributes, including position, visibility, direction,
  writing mode and style/region references, reject rather than changing meaning
  silently. Unique simple `xml:id` values are retained.
- DTDs, external entities, processing instructions after the initial XML
  declaration, CDATA, undeclared prefixes, duplicate attributes, namespace
  rebindings and malformed structure reject. No URLs/resources are loaded.

Bounds: 2 MiB original, 20,000 elements, depth 16, 1–5000 paragraphs, 2000 UTF-16
units per caption, 1–7,200,000 ms duration, native 16 MiB draft and 2 MiB export.
The report maps one-based paragraph and cue numbers plus exact half-open UTF-8
byte ranges of each original p element. Source/draft hashes stay distinct.

## Evidence boundary

The focused test executes the real new CLI and hash-pinned retained native
show/set/show/export/SRT-reimport, checks the native application's local package
source-input closure against the frozen R633 manifest, and checks unchanged
original bytes. Run `node --test cmd/ttml_captions/import.test.mjs` with
`MOONCAST_CAPTION_EDIT`, `MOONCAST_CAPTION_FROZEN_ROOT` (R633 directory), and
`MOONCAST_TTML_EVIDENCE` (existing retained output directory). Missing native
inputs fail the test rather than skip. The fixture is synthetic. There is no
browser, playback/alignment, real-world TTML corpus, installed lifecycle,
accessibility sign-off, source-rights or client-acceptance qualification.
