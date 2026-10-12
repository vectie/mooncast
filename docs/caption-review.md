# Edit a caption review sheet and bring it back

`cmd/caption_review` exports a caption draft as editable UTF-8 comma-separated
CSV, compares edits, and applies the entire sheet to a **new** draft plus SRT
and WebVTT. This is an offline wording/timing workflow, with no provider,
approval step, Studio mutation or automatic delivery.

## Export, edit, preview, apply

First use `cmd/caption_edit import` if your source is a subtitle file rather
than a draft. For the supplied synthetic example:

```sh
moon run cmd/caption_edit -- import fixtures/caption-review.srt 10000 original.json
moon run cmd/caption_review -- export original.json review.csv
# Edit review.csv in a spreadsheet, save as UTF-8 CSV to edited.csv.
moon run cmd/caption_review -- preview original.json edited.csv
moon run cmd/caption_review -- apply original.json edited.csv reviewed
moon run cmd/caption_edit -- show reviewed.draft.json
```

Preview is optional and prints JSON with before/after values for changed cues.
Apply does the same validation and writes four new files: `reviewed.draft.json`,
`reviewed.srt`, `reviewed.vtt`, and `reviewed.changes.json`. Keep the original
JSON and sheet; neither is changed. Reopen the new draft in existing caption
edit/layout/conform workflows. Export a new sheet for another review pass.

The five columns, in this order, are:

- `source_binding`: keep unchanged; a SHA-256 of the validated source draft
- `cue_key`: keep unchanged; `cue-1`, `cue-2`, etc., scoped to that source
- `start_ms`, `end_ms`: edit as whole, nonnegative milliseconds, without units
- `text`: edit the words **after the literal `text:` prefix**, preserving it

For example, a cell `text:=a literal caption` displays `=a literal caption`
in the subtitles. The prefix keeps caption text from being evaluated as a
spreadsheet formula. It is removed exactly once, so `text:text:hello` produces
`text:hello`. Use in-cell line breaks for two-line captions. CSV export quotes
fields, doubles embedded quotes, and preserves actual newlines in text cells.
Do not replace line breaks with the two characters backslash-n.

Import into your spreadsheet as UTF-8, comma separator, double-quote qualifier;
keep the binding, keys and text as text columns. Export/save only that sheet as
CSV, not XLSX, TSV or a locale-dependent semicolon file. The importer accepts
quoted or unquoted fields, LF/CRLF records, a leading BOM and no final newline.
CRLF inside text cells becomes LF. Bare carriage returns, extra columns, blank
records and malformed quoting fail. Automatic trimming is never applied.

## Identity and all-at-once updates

Every original key must appear exactly once. Sorting spreadsheet rows is safe:
keys resolve back to original draft order. Missing, duplicate or unknown keys
fail; there is no insertion, deletion or reordering of captions. Text and timing
changes are applied together before validation. This allows coordinated timing
moves which would be invalid if made one cue at a time. The final cue starts
must still be nondecreasing; overlapping or equal-start cues remain supported.

The binding rejects a sheet from a different revision, including changes to
text, time, source label or duration. JSON formatting and object-key order do
not change it. This prevents accidentally applying a sheet to the wrong draft;
it is not a human approval, authentication, rights claim or global stable cue
identifier. For a deliberately revised source, export a fresh sheet and copy
the intended wording/timing edits into that sheet. Preview/apply do not require
an approval receipt.

## Bounds and failure behavior

Inputs are local files up to 16 MiB. Existing draft limits remain: 1–5000 cues,
a positive duration up to two hours, 1–2000 UTF-16 code units per cue, plain text
without angle brackets, control characters, blank captions or blank lines.
Times must fit the duration. SRT and WebVTT outputs must each fit 2 MiB.

All cue edits validate as one operation; an invalid row writes nothing. Apply
also prepares both subtitle exports before writing. All output paths are
preflighted and individually created with CreateNew; existing files are never
overwritten. A filesystem failure during the writes can leave a partial new
bundle. Preserve it, fix the filesystem issue and choose a fresh prefix.

The changes JSON contains source/output semantic bindings, cue count and exact
before/after values for changed cues in source order. No changes is a valid
roundtrip and produces an empty change list. It is a local editing record, not
an approval, attribution or delivery receipt.

Inspect timing against the actual media and reopen the subtitles in the target
player. This workflow does not validate speech alignment, font rendering,
accessibility, commercial readiness or client acceptance. Graphical spreadsheet
editing is not part of the automated checks; the fixture workflow exercises
CSV cell edits and reimport mechanically.

## Focused tests

```sh
moon test --frozen --target native --strip -j1 -p editor/caption_review
moon test --frozen --target native --strip -j1 -p editor/captions
moon build --frozen --target native --strip -j1 cmd/caption_review cmd/caption_edit
```
