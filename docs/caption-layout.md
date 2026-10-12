# Reflow captions into readable lines and screens

Use `cmd/caption_layout` to wrap a transcript into shorter caption lines and
export an editable draft, SRT and WebVTT. Choose `reflow` to keep all cue times,
or explicitly choose `paginate` to divide long cues into smaller timed screens.
Preview the proposed layout before saving. Reading-speed and overlap feedback
helps identify the captions that still need your judgment.

This is a local, offline editing workflow. It uses an existing caption draft
from `cmd/caption_edit` or `cmd/caption_conform`; no provider, transcription,
network connection, FFmpeg or media file is required. Use sources you have
permission to edit.

## Import, preview, save, revise

From the repository root with MoonBit installed, choose new output names:

```sh
moon run cmd/caption_edit -- import fixtures/caption-layout.srt 20000 garden-original.json
moon run cmd/caption_layout -- inspect garden-original.json fixtures/caption-layout.profile.json
moon run cmd/caption_layout -- preview garden-original.json reflow fixtures/caption-layout.profile.json
moon run cmd/caption_layout -- export garden-original.json reflow garden-lines fixtures/caption-layout.profile.json
moon run cmd/caption_layout -- preview garden-original.json paginate fixtures/caption-layout.profile.json
moon run cmd/caption_layout -- export garden-original.json paginate garden-pages fixtures/caption-layout.profile.json
moon run cmd/caption_edit -- show garden-pages.draft.json
```

The supplied profile deliberately uses a narrow 12-character line to make this
synthetic example easy to inspect. Reflow retains the three original cues and
all their times, wrapping the first cue as:

```text
Grow fresh
herbs in
pots today.
```

Pagination instead produces five cues. The first two occupy 101–3901 ms and
3901–6102 ms; the next two occupy 8000–11220 ms and 11220–14001 ms. The last cue,
“Café & 🌱.”, remains at 16000–20000 ms. The original gaps stay empty.

Each export creates five new files:

- `.draft.json`: reopen with `caption_edit` to correct words, timing, split or merge
- `.srt`: numbered UTF-8 captions for an editor/player
- `.vtt`: UTF-8 WebVTT captions for a web player; literal ampersands are escaped
- `.layout.json`: exact source-draft/output-draft SHA-256, chosen mode/profile,
  before/after feedback and each output cue's original cue/page mapping
- `.tsv`: one physical row per output cue for inspection or spreadsheet import

The TSV's `text_json` field is `json:` followed by a JSON string: embedded
newlines are escaped, and the fixed prefix prevents caption text from starting
a spreadsheet formula. Remove that prefix and JSON-decode only if extracting
the original caption text programmatically. `cps_milli` is characters per
second multiplied by 1000, rounded upward; e.g. 12501 means 12.501 characters/s.

For a final wording or timing correction, use the existing editing commands:

```sh
moon run cmd/caption_edit -- set garden-pages.draft.json 2 3901 6102 'Pots today.' garden-reviewed.json
moon run cmd/caption_edit -- export garden-reviewed.json garden-reviewed
```

The earlier layout report describes its exact exported draft, not later edits.
Keep it for tracing, and run `caption_layout inspect` again on the revised draft.
Import WebVTT, Whisper JSON/TSV or Audacity labels through `caption_edit import`
in the same way; see [caption editing](caption-editing.md).

## Choose a profile

Omit the optional profile file to use defaults: 42 Unicode scalars per line,
two lines per screen, minimum 1000 ms per screen and 20 characters per second.
These are editable starting preferences, not a language-independent standard
or an accessibility certification. Print them with `caption_layout profile`
or copy `fixtures/caption-layout.profile.json` and edit it.

Fields are required. Allowed ranges are 8–120 for `max_line_chars`, 1–4 for
`max_lines`, 1–10000 for `min_duration_ms`, and 1–100 for
`max_chars_per_second`. The contract stays `mooncast.caption-layout-profile.v1`.

`inspect` and previews print the new text and cue numbers with any of these
advisory flags: `long_line`, `too_many_lines`, `short_duration`, `fast_reading`,
`overlap`. Both sides of an overlap are flagged, including nested speakers.
Cues touching at exactly the same endpoint do not overlap. A successful command
can still have flags; there is no automatic approval or delivery pass/fail.

## Wrapping and timing rules

Reflow preserves cue count, order, start/end times, source label and duration.
It greedily packs whole words into lines without exceeding `max_line_chars`.
Runs of ASCII spaces and original newlines become single spaces between words;
newlines are then inserted at wrap boundaries. Letters, punctuation, case and
word order are retained. Intentional line breaks or speaker-line separation
are not retained; check those cues manually. Reflow may exceed `max_lines`,
and reports that instead of changing cue timing silently.

Pagination is an explicit timing edit. It wraps first, then groups consecutive
lines into pages of at most `max_lines`. Each page receives a share of the
original interval proportional to its Unicode-scalar text length, counting
its internal linebreaks as spaces. Inter-page separators have no timing weight.
Cumulative boundaries round down to whole milliseconds; the first start and
last end remain exact. Pages are contiguous inside each original cue. No gap
is filled, no word is dropped, and every original cue has its own allocation.
Overlapping speakers remain overlapping, with all output cues sorted by start,
then source cue number and page number. Original arrays are not mutated.

This timing is estimated from text, not measured speech. Every split cue is
marked `estimated_timing: true` in the mapping. Listen and adjust before use.
Even a single-page cue must meet the profile's minimum duration in paginate
mode. If any page is too short, the whole operation fails before writing any
files. Prefer reflow or an explicit timing/wording edit; lowering the profile
minimum should be a deliberate choice. Neither mode guarantees reading-speed
limits. Only editorial changes or different approved timing can resolve those.

Counts use Unicode scalar values, so a supplementary-plane emoji counts once.
Combining marks and components of a joined emoji count separately; these are
not grapheme clusters, font widths or East Asian display-cell measurements.
Only ASCII spaces and newlines are break points. A long unbreakable token,
including text connected by nonbreaking spaces or a long unspaced CJK phrase,
fails with its source cue number; edit the text or choose a wider profile.
No hyphenation, grapheme splitting or linguistic line-break inference is made.

## Bounds and preservation

Input draft: 16 MiB, 1–5000 cues, at most two hours, 1–2000 UTF-16 code units
per cue, through the existing plain-text draft validator. Markup/voice tags,
empty/blank lines, tabs and control characters remain unsupported. Profile:
64 KiB. Pagination must remain within 5000 output cues. Each exported subtitle
must fit the existing 2 MiB caption-intake limit. No dependencies are added.

All payloads and all five destination names are checked before writing.
Existing files are never overwritten. Output parent directories must exist.
A later filesystem error can still leave a partial new bundle; preserve it and
use a new prefix after fixing the problem. Source drafts and transcripts are
never changed. SHA-256 identifies file bytes, not authorship or rights.

Reopen the output in your intended player and inspect actual speech timing,
line placement, font rendering and readability before delivery. This tool does
not inspect media, burn or mux captions, mutate a Studio project, grant rights,
approve a master, certify accessibility, publish or establish client acceptance.
The PRD's accessible delivery/package and real-provider qualifications remain
separate from this local preparation workflow.

## Focused checks

```sh
moon test --frozen --target native --strip -j1 -p editor/caption_layout
moon build --frozen --target native --strip -j1 cmd/caption_layout cmd/caption_edit
```
