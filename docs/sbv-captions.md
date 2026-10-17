# Saved SBV captions into native correction

This offline Node companion imports a deliberately bounded plain-text SBV
subset into the unchanged `mooncast.caption-draft.v1` contract. It does not
download, translate or align captions. No dependencies or native build needed.

## Preview, import and correct

From this source root, using Node.js 24:

```
node cmd/sbv_captions/main.mjs preview fixtures/sbv-captions.sbv 6000
node cmd/sbv_captions/main.mjs import fixtures/sbv-captions.sbv 6000 /absolute/new-bundle
caption_edit show /absolute/new-bundle/captions.json
caption_edit set /absolute/new-bundle/captions.json 2 2400 4100 "Revised caption." /absolute/revised.json
caption_edit show /absolute/revised.json
caption_edit export /absolute/revised.json /absolute/new-export
caption_edit import /absolute/new-export.srt 6000 /absolute/reopened.json
```

Supply the known media duration in integer milliseconds. Preview returns cues,
hashes, source block mappings and declared losses. Import requires a new
directory and writes exact `source.sbv` bytes, `captions.json`, and `import.json`.
Existing destinations reject without overwrite. Filesystem errors can leave a
partial new bundle: retain it for inspection and retry only at a fresh path.
The native editor reads the draft, not SBV or the sidecar. Keep the original
and import record beside revised drafts; its draft hash attests only intake.

The inherited native SRT importer trims leading/trailing whitespace from each
caption line. SBV intake and native SRT/WebVTT export preserve surrounding
spaces, but SRT reimport normalizes them. Keep and reopen the JSON draft when
exact text preservation matters; SRT round-trip equality is not guaranteed.

## Declared subset

- UTF-8, optional initial BOM; LF, CRLF or CR line endings. Each block starts
  with `H:MM:SS.mmm,H:MM:SS.mmm` (one or two hour digits), without spaces.
  Minutes/seconds are 00–59; milliseconds have exactly three digits. No rounding,
  frame timing, headers, cue IDs, settings or inferred duration.
- One or more nonblank caption lines per block. Blocks have at least one empty
  separator line. Empty leading/trailing lines are allowed. Whitespace-only
  lines reject. A timestamp-only text line rejects to catch missing separators.
- Unicode and multiline text, literal ampersands/entity-looking strings and
  surrounding spaces are preserved. Only line endings normalize to LF. No
  markup, angle brackets, C0/C1 controls, embedded BOM, styling or translation.
- Every interval must have positive duration inside the supplied media duration.
  Source order is preserved; backwards starts reject. Equal starts and overlaps
  are retained, never silently merged or clipped. Language is not inferred.
- Limits: 2 MiB source, 1–5000 cues, 2000 UTF-16 units per caption,
  1–7,200,000 ms media duration, 16 MiB draft and 2 MiB native export. The CLI
  reads at most the source bound plus one byte even if the file grows.

The report maps one-based cue/block and original line numbers plus exact
half-open UTF-8 byte ranges from timing line start through final text line end,
excluding the final line terminator. Initial BOM and separators are outside
these ranges but remain in the original. Source and draft hashes are distinct.

## Verification and limits

Run `node --test cmd/sbv_captions/import.test.mjs` with `MOONCAST_CAPTION_EDIT`
set to the retained R633 executable, `MOONCAST_CAPTION_FROZEN_ROOT` to the R633
directory, and `MOONCAST_SBV_EVIDENCE` to an existing evidence directory. Missing
native inputs fail rather than skip. Tests verify the executable hash and exact
local application package source-input closure against frozen R633 before and
after real CLI/native show/set/show/export/SRT-reimport. TTML and JSON3 native
regressions also pass. A separate mixed-newline/BOM fixture proves preserved
draft/export spaces versus trimmed native SRT reimport, including literal
entity-shaped text. No MoonBit code or public interface was changed, so no
MoonBit build/check/fmt/info was run in this low-disk companion-only change.

Fixtures are synthetic, not a real-world export corpus. This supports bounded
editing toward MOONCAST-B08 and caption preparation toward MOONCAST-R02, without
closing their graph revision, recipient access or acceptance criteria. Browser
playback/alignment, installed lifecycle, rights, accessibility sign-off, delivery
and commercial/client acceptance require separate qualification.
