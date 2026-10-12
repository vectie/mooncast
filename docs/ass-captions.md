# Bring ASS/SSA subtitles into the caption editor

`cmd/ass_captions` opens UTF-8 SubStation Alpha files from editors such as
Aegisub and converts their dialogue into MoonCast's editable plain captions.
Preview the exact text and timing before creating a new local folder, then
correct, synchronize, review, conform or export using the existing caption tools.
No FFmpeg, network service or account is needed for this conversion.

## Preview, import, edit and export

Use an external absolute Moon build target with the retained toolchain:

```sh
moon --target-dir /absolute/external/cast-build build cmd/ass_captions cmd/caption_edit --target native --frozen --strip -j 1
ASS=/absolute/external/cast-build/native/debug/build/cmd/ass_captions/ass_captions.exe
EDIT=/absolute/external/cast-build/native/debug/build/cmd/caption_edit/caption_edit.exe
"$ASS" preview fixtures/plain-import.ass 6000
"$ASS" import fixtures/plain-import.ass 6000 'garden captions'
"$EDIT" show 'garden captions/captions.json'
"$EDIT" set 'garden captions/captions.json' 1 250 1750 'Hello, garden! Welcome back.' corrected.json
"$EDIT" export corrected.json corrected
```

In a shell, provide an actual newline when entering a multiline caption, rather
than the two literal characters backslash-n. Alternatively edit `captions.json`
with JSON's ordinary `\n` escape. `DURATION_MS` is the known full target-media
duration, up to two hours; this importer does not probe or guess it.

Import writes:

- `captions.json`, the editable draft, and reusable `captions.srt`/`captions.vtt`
- `original.ass` or `original.ssa`, an exact byte copy of your original
- `import.json`, source SHA-256, full converted draft, original line numbers,
  counts of commented/overridden/effect events, and conversion omissions

Preview prints that same report without creating files. Out-of-order dialogue
is sorted by start time; equal starts keep source order. Overlaps remain separate
cues. The report maps each resulting cue to its original one-based source line.
Run `caption_edit show` before choosing cue numbers. The final cue numbering can
therefore differ from file order. Source files are never modified.

Use the resulting SRT for the existing rights-attested local editor intake, or
[append the draft as selectable captions](caption-media.md) to MP4/MKV media.
For overlapping speakers, resolve the overlap before that separate embedding
workflow, whose constraints still apply. These plain captions can also enter
[CSV review](caption-review.md), [layout](caption-layout.md) and
[cut conforming](caption-conforming.md).

## What the conversion means

This is intentionally a plain-text conversion, not a styled ASS renderer.
Fonts, colors, emphasis, layers, speaker metadata, margins, positioning, animation,
karaoke progression, inline comments, resolution and project metadata are not
carried into the captions. Event-level effects are counted and discarded. All
spoken words in a karaoke line become one ordinary cue covering the original
Dialogue interval. Retain the original whenever presentation matters.

Exact centisecond times become integer milliseconds without rounding. Text-field
commas and Unicode are preserved. Hard `\N` becomes a newline; `\h` becomes a
nonbreaking space. Soft `\n` becomes a space except under wrap mode 2, when it
becomes a newline. The script's `WrapStyle` starts each cue, `\q0`–`\q3` changes
it and `\r` resets it. Automatic visual wrapping is not reproduced. Inspect
converted line breaks and readable timing against the actual media.

Override/comment blocks in braces are stripped. Drawing-mode `\p` other than
`\p0` is refused so vector commands cannot silently become spoken text. Nested,
unclosed or unmatched braces also fail. The plain-caption model disallows angle
brackets, blank captions/lines and control characters other than newline. A cue
that becomes empty after stripping comments fails instead of disappearing.

## Supported input and recovery

- UTF-8, optional BOM, LF or CRLF, at most 2 MiB and 5000 Dialogue events
- `ScriptType: v4.00+` (ASS) or `v4.00` (SSA) before a single Events section
- One Events Format with all ten standard fields, each once, and Text last.
  Other field orderings are resolved by name. Standard ASS starts with Layer;
  SSA uses Marked. Unknown event fields/directives and duplicate formats fail.
- Times use H:MM:SS.cc or HH:MM:SS.cc. Each interval must fit the supplied
  duration. Non-100 Timer scaling is rejected rather than silently retimed.
- Script Info, V4+/V4 Styles and Aegisub Project Garbage metadata are accepted
  but not interpreted for presentation. Fonts, Graphics and unknown sections
  are refused; attached payloads are never decoded or opened.
- SRT/WebVTT must each fit the existing 2 MiB export bound, with 1–2000 UTF-16
  code units of text per cue. Existing caption validation remains unchanged.

Inputs must be regular local files; input symlinks and URI-like paths are refused.
The output folder must be new, with an existing parent. Every caption and export
is prepared before the folder is created. Validation failures write nothing.
Filesystem failures may leave a partial new folder; preserve it and choose a new
name after fixing the problem. A completed `import.json` is written last.

This tool does not regenerate ASS styling, import images/drawings/fonts, infer
speaker labels, translate, transcribe, verify rights, inspect recipient access,
certify accessibility or record client acceptance. It adds no UI or live project
mutation. Correct words, reading speed and final player presentation still need
human inspection.

References checked 2026-10-10: [Aegisub override tags](https://aegisub.org/docs/latest/ass_tags/)
and the [libass format guide](https://github.com/libass/libass/wiki/ASS-File-Format-Guide).
This documented bounded importer does not claim to accept every script supported
by those renderers.
