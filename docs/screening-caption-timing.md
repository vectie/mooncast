# Correct caption timing during an offline screening

A supplied caption can now be retimed in the actual offline screening player.
This extends the existing [wording correction](screening-caption-correction.md)
workflow. It uses the video you are watching and the ordinary caption draft;
there is no transcription, provider, network service or new sidecar format.
Previously exported screening folders need a fresh export to receive the new
player controls. The existing [offline screening](offline-screening.md) command
and its input/media validation are unchanged.

## Select, capture, preview, apply, keep

1. Choose **Edit caption N** beside the transcript cue. The editor stays on that
   deliberate selection when playback moves to other captions. The anchor shows
   its currently applied session interval, with milliseconds.
2. Enter **Start (ms)** and **End (ms)** as whole nonnegative milliseconds, or
   seek the player and choose **Use current position as start/end**. Capture
   rounds the current player clock to the nearest millisecond. It does not seek,
   play, pause, alter speed or change A–B repeat. Loading/unavailable/outside
   positions leave the editor values intact. A captured draft can be invalid
   until its other endpoint is corrected.
3. Choose **Preview correction**. Validation checks the entire proposed cue,
   including wording. A successful preview temporarily changes the transcript
   text and millisecond range, that cue's seek button, search matches, active
   interval highlighting and native caption cue or plain-text fallback. A
   visible status identifies the original applied range and the proposed range,
   and labels the presentation as unsaved. Preview never starts playback; use
   the video's controls or the transcript seek button to inspect alignment.
4. Choose **Apply correction** to retain the candidate in this page's session,
   or **Cancel edit** to discard the candidate, restore the applied presentation
   and close the editor. Timing changes require a current matching preview.
   Changing wording/timing or capturing another endpoint invalidates the preview
   and restores the applied presentation until previewed again. Wording-only
   changes may still be applied directly, preserving the previous workflow.
5. Download **corrected caption draft (JSON)** or **corrected captions (WebVTT)**
   to keep every applied cue. Unfinished wording or timing blocks downloads and
   switching to a different editor cue. Searching and ordinary playback remain
   available. Check that your browser actually saved the file.

**Use supplied timing** places the original cue's start/end back in the editor;
preview and apply are still required. **Use supplied wording** affects only the
wording. Neither restoration silently changes other cues. A timing restoration
can be invalid if a neighboring cue's applied start has since moved past it;
resolve that order deliberately. There is no caption multi-step undo history.
Notebook Undo/Redo continues to affect only feedback notes.

## Timing contract

- Start and end must be integer milliseconds, with `0 <= start < end <=` the
  recorded screening duration. Fractions, signs, exponent notation and blank
  inputs are rejected. A one-millisecond interval and the exact terminal end
  are allowed. The screening's existing maximum duration is two hours.
- Starts must remain nondecreasing relative to both neighboring applied cues.
  Equal starts and overlapping end times are supported. Cue numbers remain
  stable; invalid times are never silently sorted, shifted, clipped or rounded.
  Only captured playback positions are rounded.
- The recorded screening duration bounds editable/exported data. A browser
  reporting a shorter duration does not rewrite captions. Capture additionally
  stays within that reported media duration. A media error or duration change
  keeps drafts for inspection; it does not approve or persist them.
- Millisecond fields describe the media clock, not frames. Browser playback
  clocks, seeking and scheduling are not guaranteed frame- or sample-accurate.
  Inspect timing, overlapping speech and readability against actual playback.
- The existing plain-text validation and JSON 16 MiB / WebVTT 2 MiB limits apply.
  If a native caption text/start/end update fails, its track is disabled and the
  corrected plain-text fallback is used for preview, apply and cancellation.

## Persistence and ordinary consumers

Applied corrections and previews are page-session state. There is no automatic
save or reload recovery. Reloading the original folder restores the original
supplied captions. The page does not modify the video, original caption files,
screening plan or result manifest. Downloads contain applied state only; an
unapplied preview is blocked from export. A failed download keeps all applied
and editor state and reports that the browser did not accept the request.

The JSON remains `mooncast.caption-draft.v1` with `contract`, `source_file`,
`duration_ms`, and `cues`; every cue contains only `start_ms`, `end_ms`, and `text`.
WebVTT carries exact `HH:MM:SS.mmm` intervals and escaped ampersands. Use the
existing [caption editing](caption-editing.md) tools or regenerate a screening
from the downloaded draft. No in-place player import or Studio import is added.
The informational `source_file` label carries the already recorded media hash;
this does not rehash the media or prove speech alignment.

Feedback notebooks, their saved notes/history and active note drafts retain the
original exact screening-plan identity. Feedback briefs keep quoting originally
supplied caption wording and times. They do not silently quote a temporary
preview or an applied caption correction. Exporting a new screening changes the
plan; old notebooks are not automatically rebound.

## Source evidence and focused checks

This is a bounded editor workflow contribution to PRD MC-W04 and preparation for
MC-W07, whose edge explicitly mentions caption defects blocking delivery. It
does not complete the graph-revision workflow, accessible delivery package,
recipient-access verification, named client acceptance or publication gates.

With existing Node, from any directory:

```sh
node --test /absolute/mooncast/source/scripts/test-screening-*.cjs
```

Seventeen new tests execute the exact literal production JavaScript through
`screening-player-harness.cjs`, inspect the shipped HTML declarations, and drive
the actual controls. They cover preview/apply/cancel, both presentation modes,
invalid inputs, neighboring order, legal overlaps/equal starts, boundary clocks,
capture, repeated edits, switching, stale previews, interrupted media, repeat,
notebook independence, no-caption screens and failed downloads. Real Blob JSON
and VTT bytes are written and reopened, independently checked against the
ordinary native draft contract, and supplied to another player instance.
The 84 previous named tests and the repeat test file (two caption profiles)
also run: 102 passing test-runner entries in total.

DOM, media and native cue APIs are doubles. No MoonBit compilation, native
screening exporter, native caption CLI, actual browser rendering, codec,
physical playback device, assistive technology, provider or full-product
qualification is claimed. R50 remains the last fully verified cumulative
checkpoint; R51–55 remain separate.
