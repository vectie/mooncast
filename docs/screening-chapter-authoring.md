# Author chapter starts while watching a screening

The offline screening player now includes **Author chapters while watching**.
This is a new session-only set of playback markers, independent of supplied
chapter navigation, caption corrections and feedback notebooks. It is useful
when an editor can hear or see the right chapter boundary more easily than
entering it from a timeline report.

1. Open an already prepared screening folder's `index.html` and let its video
   metadata load. Seek or play to a chapter beginning, then choose **Capture
   chapter start here**. The captured position is frozen even as playback runs.
2. Enter a label. Optionally edit **Start (ms)** or choose **Use current
   position**. The latter keeps the label. Enter whole nonnegative milliseconds.
3. Choose **Preview marker intervals**. The list shows the proposed sorted
   intervals, including their inferred end times. Choose a **Preview** row to
   seek to its start without starting paused playback. Preview alone does not
   apply the marker.
4. Choose **Apply marker** to keep it for this session, or **Cancel edit** to
   discard the pending edit. Existing rows offer **Edit marker** and **Remove
   marker**. An open editor blocks another capture, editing another marker,
   removal and download until you explicitly apply or cancel it.
5. Choose **Download authored chapters (FFmetadata)** and verify the browser
   saved `screening-authored-chapters.ffmetadata` before closing. There is no
   automatic persistence or reopen/import control for this session editor.

Markers are sorted by start. One marker ends at the next marker's start; the
last ends at the screening plan's duration, even if a faulty media load reports
another duration. Leading time before the first marker has no chapter. Removing
one marker extends the preceding interval to the following marker or duration.
Removing the last marker leaves an empty authoring session with export disabled.

## Clock, bounds and interchange

Capture rounds playback seconds to the nearest millisecond. A rounded position
at the final endpoint is refused instead of clamped. Capture requires loaded
finite media duration, no media error, no pending seek and a stable position
inside both the loaded media and screening duration. After a media failure,
applied markers can still be downloaded; marker values and editor input remain
available. Preview seeks beyond the loaded media are refused rather than silently
clamped. The preview list highlights half-open intervals as playback moves.

The export is UTF-8 `;FFMETADATA1` with explicit `TIMEBASE=1/1000` on each chapter,
integer `START`/`END`, and FFmetadata-escaped titles. It supports 1–1000 markers,
distinct starts from zero through one millisecond before the positive screening
duration (maximum two hours). One-millisecond intervals are legal. Titles must
be nonblank, valid Unicode, single-line and at most 200 UTF-16 units. Control
characters, Unicode line separators and trailing backslashes are refused. Plain
literal HTML is displayed as text; `\\`, `=`, `;` and `#` are escaped in the file.

This creates an ordinary FFmetadata sidecar only. It invents no project,
timeline or marker IDs and does not reconstruct an editable native chapter
draft. In particular, supplied native chapter starts may originate on a
non-millisecond clock: the authoring session does not seed from, overwrite or
reinterpret those starts. The original `chapters.json` and notebook source plan,
chapter filters and feedback-brief context keep their supplied values.

For a deliberate later handoff, the existing [chapter import](chapter-import.md)
workflow can target a separately selected native draft of the same cut, only
when every exported millisecond boundary maps exactly to that draft's integer
ticks and its final duration matches. A 2001 ms marker will not land exactly on
a 24-tick/second clock. Do not round it silently or change the draft clock to
force an import. Matching duration does not prove that two files describe the
same edit. The importer, native draft editor and media mux are separate steps.

## What was verified

Run the focused production-script suite from the repository root:

```sh
node --test scripts/test-screening-chapter-author.cjs
```

The shared harness extracts every literal JavaScript line from the production
MoonBit `player_script` function and invokes the actual registered handlers.
Its DOM/media APIs are doubles, not a graphical browser. Tests cover capture,
preview, apply, cancel, edits, removal, duplicate and invalid boundaries, 1000
markers, title escaping, notebook/context preservation, media errors and no
unsolicited playback. Existing screening regressions also run.

The round's `run-focused.sh` creates private fresh output paths and additionally
runs a real FFmpeg/FFprobe roundtrip from the actual downloaded sidecar through
a tiny synthetic six-second Matroska file. This qualifies local output-format
interoperability only. It does not exercise the native chapter importer or
screening exporter. No recipient access, external acceptance or delivery is
claimed. No original video is copied or modified by this feature.

Release blockers: MoonBit `check`/build, native screening HTML generation,
native chapter import against matching and incompatible clocks, and real-browser
playback/download/accessibility qualification have not been run for this change.
The edit is confined to embedded JavaScript and literal HTML in the existing
MoonBit wrapper; native module logic and dependency versions are unchanged.
