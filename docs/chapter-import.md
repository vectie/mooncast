# Bring existing chapters into an editable episode draft

`chapters import` reads a local FFmetadata chapter sidecar and replaces the
markers of an explicitly selected chapter draft. Use it to reuse chapter names
and timing from another editor or an existing media container, then move or
rename them with the existing chapter commands and export WebVTT/FFmetadata.
It creates a new ordinary `mooncast.chapter-draft.v1`, not a separate schema.

## Build and try

From the source checkout, with the module's declared dependency sources
installed and MoonBit available:

```sh
moon build --frozen --target native --strip -j 1 --target-dir ../build cmd/chapters
../build/native/debug/build/cmd/chapters/chapters.exe seed fixtures/edit-decisions.project.json video selected.json
../build/native/debug/build/cmd/chapters/chapters.exe import selected.json incoming.ffmetadata imported.json
../build/native/debug/build/cmd/chapters/chapters.exe preview imported.json
../build/native/debug/build/cmd/chapters/chapters.exe set imported.json imported.2 6000 "New chapter name" edited.json
../build/native/debug/build/cmd/chapters/chapters.exe export edited.json episode
```

The example project lasts 20 seconds. The imported sidecar must describe that
same cut and end at 20 seconds. For the accompanying runnable three-second
example, use `fixtures/chapters-24fps.json` instead. The kit's `workflow/` holds
the actual inputs, outputs and FFmpeg inspection logs from that example.
Use fresh output filenames when replaying commands.

To obtain a sidecar from media you are authorized to edit, a separate explicit
local FFmpeg invocation is `ffmpeg -nostdin -i episode.mkv -f ffmetadata -n incoming.ffmetadata`.
The MoonCast importer itself reads no media, launches no process and makes no
network request. It does not assert that imported chapters belong to the chosen
cut: inspect placement and titles before delivery. Matching duration is not
proof of matching content.

## Supported interchange profile

- UTF-8 text beginning with `;FFMETADATA1`, LF or CRLF, with 1–1000 `[CHAPTER]`
  sections. Blank lines and whole-line `;`/`#` comments are accepted.
- Each chapter requires exactly one `TIMEBASE`, `START`, `END` and `title`.
  `TIMEBASE` is a positive rational, and timestamps are nonnegative decimal
  integers fitting Int64. Nanosecond timestamps exported by FFmpeg work.
  Rational factors are cancelled before multiplication, preventing overflow
  when a large timebase still maps to ordinary timeline ticks.
- Boundaries must land exactly on the selected draft's integer tick clock.
  No rounding or frame-rate guess occurs. The intervals must be ordered,
  nonempty and contiguous; the last end must equal the selected duration.
  A leading gap is allowed. Internal gaps, overlaps, out-of-order intervals
  and a shortened final chapter are refused because marker-only drafts
  cannot preserve their meaning.
- Unicode single-line titles and FFmetadata escapes `\\`, `\=`, `\;`, `\#`
  are supported. Titles retain spaces. The existing 200 UTF-16-unit nonblank
  title limit applies. Multiline values, unsupported escapes, unescaped
  reserved characters, duplicate or unknown chapter fields and non-chapter
  sections are refused. `TIMEBASE` must be explicit; no format default is
  guessed. Container-level key/value tags before the first chapter are
  ignored and are not included in the chapter draft.
- Input CLI files are capped at 2 MiB bytes; the library additionally caps
  text at 2 MiB UTF-16 units. Signed 32-bit draft tick bounds still apply.

Import replaces all old markers. New stable-in-file IDs are `imported.1`,
`imported.2`, etc. These are not recovered external IDs. The selected draft's
project/timeline IDs, revisions, duration and clock stay unchanged. Source
draft, sidecar and media are untouched. Keep the earlier draft as manual undo.
The output parent must exist and its filename must be unused; exclusive
creation refuses existing files and symlinks. No cleanup is attempted.

After import, `set`, `remove`, `preview` and `export` work normally. Export
still has its established limitations: WebVTT uses floored millisecond shared
boundaries; submillisecond chapters that collapse cannot export, and FFmetadata
export refuses titles ending in a backslash. Import does not silently change
such titles to satisfy a later output format.

This is local editorial interchange. It does not mutate Studio, conform
chapters to a recut, mux media, approve a master, grant rights, provide client
access, record acceptance or publish anything. Source revision metadata is
retained but not watched; after recutting select and review a new draft.

## Reproduce focused evidence

Qualified with recovered moon 0.1.20260920 / moonc 0.10.14, unchanged
`async@0.19.4`, `x@0.4.50`, `moonlib@0.1.19` source dependencies. No fresh
registry retrieval was tested.

```sh
moon test --frozen --target native --strip -j 1 --target-dir ../build -p editor/chapters
```

The kit also provides `verify_import.mbtx` (async 0.22.4 for its runner).
From the round directory, after the CLI build and runner dependency setup:

```sh
moon run --frozen --target native --strip -j 1 --target-dir runner-build verify_import.mbtx ROUND_ABSOLUTE NEW_OUTPUT_ABSOLUTE
```

It verifies importing nanosecond metadata, Unicode/escaped titles, native JSON
roundtrip, subsequent editing and export, actual FFmpeg mux/extraction and
reimport, four invalid-input refusals with no output, and input preservation.
The generated MKV is synthetic three-second local format evidence only.

For a later recut, use [chapter conforming](chapter-conforming.md) with explicit
media-to-source-draft bindings. Chapter import itself does not retime markers.
