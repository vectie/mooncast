# Make a visual review sheet from a local cut

`cmd/review_sheet` turns an actual local MP4 or Matroska video into an offline
contact sheet: timestamped frame images, chapter titles when supplied, caption
excerpts and space for handwritten review notes. Open `index.html` locally or
print it using your browser. Every image and link lives inside the output folder;
move the whole folder together. The source video is not copied or changed.

This helps an editor scan a cut, compare the visual progression with the script,
and take timestamped notes before a full playback review. It complements the
existing [readable transcript](readable-transcript.md),
[chapter authoring](timeline-chapters.md), and
[caption editor](caption-editing.md). It is not automatic shot detection or a
replacement for listening to and watching the complete cut.

## Build and preview

With MoonCast's pinned native dependencies available, build into an external
absolute directory. The delivered kit's `BUILD.md` describes the exact compiler,
dependencies, private environment and shared native lock used for acceptance.

```sh
moon --target-dir /absolute/external/mooncast-build build cmd/review_sheet --target native --frozen --strip -j 1
SHEET=/absolute/external/mooncast-build/native/debug/build/cmd/review_sheet/review_sheet.exe
"$SHEET" preview '/local/cuts/episode.mp4' uniform 12 - 'Episode first review'
"$SHEET" export '/local/cuts/episode.mp4' uniform 12 - 'Episode first review' '/local/reviews/first look'
```

The destination's parent must already exist. The destination itself must be new.
Preview reads/hashes the source, probes its media and prints the exact planned
intervals and requested sample times. It creates no files and does not decode
frames. Export performs its own fresh preflight and extracts the actual images.
There is no implicit reuse of an earlier preview.

`uniform COUNT` partitions the full duration into COUNT half-open intervals,
including the start and end of the cut, and requests each midpoint. COUNT is
1–120. For example, a six-second cut with three samples gives intervals 0–2,
2–4 and 4–6 seconds and requested frames at 1, 3 and 5 seconds. Very short shots
can fall between samples, so increase the count where needed.

## Use existing editable chapter and caption drafts

```sh
"$SHEET" preview cut.mp4 chapters cut.chapters.json cut.captions.json 'Director review'
"$SHEET" export cut.mp4 chapters cut.chapters.json cut.captions.json 'Director review' '/local/reviews/chapter review'
"$SHEET" export cut.mp4 uniform 24 cut.captions.json 'Caption context' '/local/reviews/caption context'
```

The two positional draft inputs are the existing native formats:

- `chapters CHAPTERS.json`: a `mooncast.chapter-draft.v1` from `chapters`,
  `chapter_conform` or `chapter_media extract`. Each chapter contributes one
  sample at the midpoint of its span. If the first chapter starts after zero,
  an extra “Before first chapter” card covers that opening. At most 120 cards,
  including this opening, can be made. Chapter tick times must convert exactly
  to integer milliseconds.
- `CAPTIONS.json`: a `mooncast.caption-draft.v1` from `caption_edit`,
  `caption_conform` or `caption_media extract`. Pass a literal `-` instead if
  no captions should appear. The supplied draft is copied unchanged into the
  output, and every cue overlapping a card's interval appears with its original
  number, complete words and original timing. Overlapping speakers remain
  separate; a cue spanning two cards repeats on both. The excerpt describes
  the entire interval, not just the pictured instant. No supplied captions and
  a gap in supplied captions have different visible labels.

Draft duration must be within 50 ms of the probed container duration. This
allows millisecond rounding but does not prove that a draft belongs to that
video: select the correct revision yourself. The exact input hashes are saved.
No chapter or caption extraction is implicit. Existing embedded tracks are not
used unless you extract and select a draft through those earlier workflows.

## Read and move the result

The new folder contains:

- `index.html`: a responsive, scriptless contact sheet with ordinary keyboard
  links, sample navigation, semantic headings and print styling
- `frames/frame-N.png`: real 640 × 360 frame images; original aspect ratio is
  letterboxed, not cropped. Each image is linked for direct opening
- `captions.json` and/or `chapters.json`: exact selected sidecar bytes, when used
- `plan.json`: sampling intervals, titles, excerpts and input identity
- `frame-N.log`: the corresponding FFmpeg diagnostic output, including empty
  logs when the command succeeds quietly
- `result.json`: completion marker, source/sidecar hashes, each image hash and
  size, and the HTML hash

The HTML displays only the source basename and digest, not an absolute source
path. The optional copied drafts preserve whatever labels or source references
the drafts already contain; inspect them before any later authorized sharing.
Generated source clips, sidecars, image pixels and relative HTML resources were
checked locally. No browser or physical print-engine acceptance is claimed by
these focused checks. The design supplies navigation and descriptive image
labels; it does not generate visual descriptions of scene content or certify
accessibility compliance.

The displayed timestamp is a seek request. FFmpeg returns the first eligible
decoded frame at or after it; a variable-frame-rate or sparse stream can differ
by one frame or more. These are approximate review references, not frame-accurate
edit decisions. A static PNG cannot expose motion, audio defects, complete
caption timing, HDR fidelity or continuity between samples.

## Limits and recovery

- Local regular files only, 1 byte to 2 GiB. No source symlink, URL, device,
  provider, network fetch or hardware capture is accepted. The selected source
  and its containing directories must be trusted and quiescent; canonical path
  checks are not an operating-system sandbox against concurrent changes.
- The existing bounded media inspector requires one actual video stream in an
  MP4 or Matroska container starting at zero, at most 17 A/V/subtitle tracks and
  1,000 embedded chapters. Attached cover pictures and unknown stream kinds
  (apart from MP4 chapter navigation data) are outside the profile. The selected
  video itself must start at zero, have dimensions of 16–8192 pixels, and have
  square or unspecified sample aspect ratio. Explicit anamorphic media and
  identified PQ/HLG HDR are refused; prepare a suitable SDR review copy first.
- Duration is at most two hours. Each frame operation has a two-minute timeout.
  Sidecars are at most 16 MiB, with their existing format validation. Caption
  excerpts across the complete sheet are limited to 1,000,000 characters and
  20,000 cue references. Reduce the number of samples for unusually dense text.
- Existing destinations, including dangling symlinks, are refused. Each file is
  new, and FFmpeg is told not to overwrite. Validation failures before output
  creation leave no folder. A later I/O, decode or concurrent-input failure
  retains the new partial folder and its diagnostic logs. It has no successful
  `result.json`; don't present it as complete. No cleanup or overwrite occurs.
  Resolve the cause and use a fresh folder for the next attempt.
- A container can have audio longer than its video. If a requested frame does
  not exist, export fails instead of substituting a previous frame. A source that cannot decode a requested frame fails. Sampling is not an
  exhaustive corruption check; the full video still needs playback review.
- Source video and optional drafts are checked again before the completion
  receipt. This detects ordinary input changes but cannot guarantee absence of
  a concurrent change-and-restore race.

The utility does not edit the cut, render or approve a master, apply visual QC,
record client feedback/acceptance, deliver externally, publish or grant rights.
Use source media and captions you have permission to inspect. Local synthetic
acceptance is not real-provider production; cumulative qualification remains
R50, with this round limited to the recorded focused workflow.

## Reproduce focused acceptance

Build the native executable above, then choose a fresh output directory:

```sh
python3 scripts/verify_review_sheet.py --source /absolute/mooncast --target /absolute/external/mooncast-build --output /absolute/new-review-sheet-check
```

The harness uses Python's standard library and installed FFmpeg/FFprobe. It
creates real red/green/blue cuts, verifies the native uniform and chapter
outputs, decodes every acceptance frame to check its dimensions and expected
color, checks exact caption overlap/Unicode, resolves all HTML links after
relocation, and exercises refusal and partial-export recovery cases. Every
input, output, command and intentional failure log is retained.
