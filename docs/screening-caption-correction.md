# Correct caption wording while screening

The offline screening player now lets an editor correct supplied caption text
while watching the cut, then download an ordinary MoonCast caption draft or
WebVTT sidecar. This closes a local editing gap: the existing caption CLI can
correct text, but the player previously offered only read-only captions and
feedback notes. No transcription, provider or network is used.

## Watch, correct, preview, download

Generate a new screening folder through the existing
[offline screening workflow](offline-screening.md), with a matching caption
draft, and open its `index.html`. Previously exported folders retain their
older player and need a fresh export to receive these controls.

1. Search the transcript or select a timestamp to hear the relevant passage.
   Choose **Edit caption N** beside that cue. The editor identifies its fixed
   one-based number and exact millisecond range.
2. Correct **Caption wording**, then choose **Save wording**. The transcript,
   active caption overlay (or plain-text fallback) and transcript search use the
   saved correction immediately. Only wording changes. Cue order, overlaps,
   starts and ends stay exact. Playback, pause, speed and A–B repeat are not
   changed by editing, saving or downloading. Playback can move to another cue
   while the editor remains on the cue you deliberately selected.
3. Unfinished wording blocks switching to another caption and both downloads.
   Save it, or choose **Cancel edit** to discard that editor draft and close the
   editor. Cancel preserves all previously saved corrections.
4. To undo a saved correction to the originally supplied text, select that cue
   and choose **Use supplied wording**. This replaces the editor text only.
   **Save wording** applies the restoration; **Cancel edit** keeps the earlier
   saved correction. There is no multi-step caption history.
5. Choose **Download corrected caption draft (JSON)** to keep an editable
   `mooncast.caption-draft.v1` file, or **Download corrected captions (WebVTT)**
   for a player-ready sidecar. Each download contains all saved captions, even
   when transcript search hides some. Check the browser actually saved the file.

Changes exist only in this open page until downloaded. Reloading the original
folder restores its original captions. The browser does not edit `captions.json`,
`captions.vtt`, `plan.json`, `result.json` or the video. A downloaded draft is not
loaded back into this player in place; use it in the existing caption tools or
regenerate a fresh screening folder with it. No Studio import is automatic.

## Continue in the existing caption workflow

The JSON has exactly the ordinary caption-draft fields: `contract`,
`source_file`, `duration_ms` and `cues`. Each cue has `start_ms`, `end_ms` and
`text`. It can be inspected and revised through
[caption editing](caption-editing.md), used as the next screening input or
embedded through [caption media interchange](caption-media.md). For example,
with the existing caption CLI already available:

```sh
caption_edit show screening-corrected-captions.json
caption_edit export screening-corrected-captions.json corrected-sidecars
```

Here `caption_edit` denotes your already-built `cmd/caption_edit` executable;
use its actual path. The export prefix must be fresh. These native consumer
commands were not executed in this round because the native toolchain and
required dependencies remain unqualified; the focused evidence checks the
existing source contract and output bytes independently.

The exported duration is the screening media's millisecond duration. It may
therefore differ by up to 50 ms from an original accepted caption draft's total
duration, but individual cue boundaries never change. `source_file` is an
informational label naming `media.mp4` and its recorded SHA-256. It is not a
filesystem path, a new media hash, a signature, a rights receipt or a proof of
matching speech. The player does not rehash the copied media.

## Text, output and review boundaries

- The existing plain-text profile applies: nonblank wording, at most 2,000
  UTF-16 code units per cue, nonblank lines, no angle brackets or control
  characters below U+0020 except newline. Multiline Unicode, literal ampersands,
  punctuation, leading/trailing ordinary spaces and overlapping captions remain.
  Invalid edits stay visible in the editor and do not replace the saved cue.
- JSON downloads are limited to 16 MiB; WebVTT to 2 MiB. All cues are validated
  before a download is requested. WebVTT uses exact `HH:MM:SS.mmm` boundaries and
  escapes ampersands so literal entity-like text stays literal. A too-large VTT
  cannot be silently truncated; a supported JSON can still be downloaded.
- A browser download request is not proof of a completed save. Failed downloads
  leave session wording intact. Browser download naming/overwrite prompts belong
  to the browser; the player never writes a local path or overwrites source files.
- If a browser cannot update its native text-track cue, the player disables that
  track and displays corrected plain text below the video instead. Actual device
  compatibility and rendering still require inspection.
- Feedback notebooks stay bound to the original exact screening plan. Their
  saved notes, active note drafts and history are independent of caption edits.
  Feedback briefs continue to quote originally supplied caption context, as the
  UI explicitly says. Regenerating a screening with corrected captions produces
  a new plan; old exact-plan notebooks are not silently rebound.
- No caption creation, deletion, timing edit, split/merge, translation, burn-in,
  master approval, recipient access check, publication or client acceptance is
  performed. Timing edits and other operations remain in the existing tools.

This supports the editorial part of PRD MC-W04 and caption preparation within
MC-W07/MOONCAST-R02. It does not complete the roadmap delivery package or qualify
the full graph/cut workflow in MOONCAST-B08.

## Focused executable checks

From the repository root with existing Node:

```sh
node --test scripts/test-screening-caption-edit.cjs scripts/test-screening-notebook.cjs scripts/test-screening-merge.cjs scripts/test-screening-triage.cjs scripts/test-screening-brief.cjs scripts/test-screening-revisions.cjs scripts/test-screening-history.cjs
node scripts/test-screening-repeat.cjs
```

Twelve new tests execute every literal line of the real production player
JavaScript and check actual HTML control declarations. They exercise selection
through playback changes, overlapping cues, both caption display paths,
searching corrected text, draft protection, cancel/restoration, plain-text
validation, actual Blob downloads reopened from files, exact output clocks and
schema, notebook independence, no-caption behavior, download failure and the
existing VTT size limit. The 72 prior notebook tests and both repeat profiles
remain covered. Set `MOONCAST_EVIDENCE_DIR` to a fresh output directory to retain
JSON/VTT roundtrip files there; exclusive creation preserves prior evidence.

DOM, media and download APIs are doubles. The generated bytes and independent
shape/clock checks are real; no MoonBit build, native caption consumer/exporter,
actual browser, codec playback, assistive technology, provider or full-product
execution is claimed. No installation or network access is required. R50
remains the last fully verified cumulative checkpoint; R51–55 remain separate.
