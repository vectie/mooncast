# Continue a transcript-selected edit in an NLE

`transcript_reel export-edl RECIPE_JSON FPS exact|cover OUTPUT_PREFIX` exports
an existing multi-source transcript recipe as an editable CMX3600 video cut
list. It creates `OUTPUT_PREFIX.edl` and `OUTPUT_PREFIX.handoff.json`.
Choose transcript lines once, then continue trimming or arranging their video
in an editor instead of reconstructing the cuts from the rendered MP4.

This is an offline metadata workflow. Only recipe and transcript files are
read. Media can be offline; FFmpeg, FFprobe, a provider and Studio are not
needed. No media duration, frame rate, file identity or playback is verified.

## Try the checked-in example

Build `cmd/transcript_reel` and `cmd/edit_decisions` using your pinned MoonBit
environment. The commands below use their compiled executables on PATH. Run
from the repository root with fresh output names and an existing parent folder:

```sh
transcript_reel inspect fixtures/caption-conform-b.whisper.json
transcript_reel export-edl fixtures/transcript-edl.recipe.json 24 exact interview
edit_decisions preview fixtures/edit-decisions.project.json interview.edl fixtures/transcript-edl.reels.json
edit_decisions import fixtures/edit-decisions.project.json interview.edl fixtures/transcript-edl.reels.json interview-native
edit_decisions export interview-native.project.json fixtures/transcript-edl.reels.json interview-roundtrip.edl "MoonCast transcript rough cut"
```

The synthetic example makes four cuts at 24 fps: camera B cue 2, camera A cues
1–2, camera B cue 1, then camera B cue 2 again. It has 156 record frames (6.5
seconds), no gaps, and starts at record timecode `01:00:00:00`. The source
project and media locators are metadata fixtures; no playable video is supplied.
Native import creates a separate editable project snapshot. Export preserves
source/record cuts; descriptive comments need not survive the round-trip.

For your own recipe, use the same [source/choice format](multi-source-transcript-reels.md).
Paths in the recipe resolve beside that recipe. Media paths are made absolute
as locators without resolving symlinks or checking files. Transcript paths are
resolved and their exact read bytes are hashed in the handoff. Output prefixes
resolve from the working directory. The recipe, transcripts and media are not
modified or copied.

## Frame rate and source timing are deliberate choices

- Supply an integer FPS from 1 through 60, matching the intended source and
  editing timebase. EDL does not declare FPS, so set the same rate in the NLE.
  23.976, 29.97, 59.94, drop-frame and timecode rollover are unsupported.
- All source timecodes are zero-based file time. Camera-embedded timecode is
  not inferred. Before relinking, set each source's start to `00:00:00:00` and
  conform it to the selected integer FPS in the editor. For mixed-rate footage,
  prepare/conform source media separately; this command does not transcode it.
- `exact` refuses the entire request if any selected source boundary is not a
  whole frame at that FPS. It never silently rounds.
- `cover` rounds each source-in down and each source-out up to a whole frame,
  preserving the selected words. Each boundary can include less than one extra
  frame. The handoff retains the original milliseconds and marks every changed
  interval. For example, 17–1051 ms at 24 fps becomes source frames 0–26,
  lasting 1083.333 ms. Check the added picture/audio context and media end.
- Record cuts are contiguous and accumulate the actual rounded source duration.
  Cue ranges such as `1-3` retain their internal gaps; comma selections cut those
  gaps out. Order and deliberate repetition are preserved.

The EDL duration can differ from `render-recipe`: the renderer rounds each
excerpt's duration to 30 fps, whereas this handoff rounds its source boundaries
at your chosen FPS. The rendered reel's SRT therefore must not be assumed to
match this EDL. After native import, use the existing [caption conformer](caption-conforming.md)
with the original transcripts to make captions for the actual cut.

## Relink by the supplied source map

Sources are sorted by their ASCII recipe IDs and receive `SRC00001` through
`SRC00008`. Reordering recipe sources or choices does not alter this mapping.
Adding/removing/renaming a source can change it; always keep the handoff for the
particular export. Each event also has descriptive clip-name and source-file
comments. Some NLEs ignore comments; use the handoff's `plan.sources` mapping
to assign the matching reel and media manually.

For MoonCast native import, create an existing EDL reel map that binds those
reel names to your current media and template-clip IDs. Set its FPS to the
exported FPS, record origin to `01:00:00:00`, and source origins to
`00:00:00:00`. See [native EDL interchange](edit-decision-interchange.md).
The checked-in map is only for the checked-in synthetic project.

The handoff records the normalized recipe, input recipe/transcript hashes,
parser/cue identities, reel mapping, original cue ranges/milliseconds,
rounded source/record frame ranges, duration, and EDL hash. It is a readable
editing reference, not a media manifest or a signed authenticity claim.

## Scope and limits

The EDL has one video track, normal-speed cuts and inclusive-in/exclusive-out
ranges. It does not carry audio edits/mix, captions, the recipe canvas,
transitions, effects, transforms, production identities or rights records.
Choose a richer interchange format or reconstruct those separately when needed.
No external NLE import/playback compatibility has been qualified here; the
existing MoonCast EDL parser and native project importer/exporter are tested.

Existing recipe limits remain: 1–8 sources, 100 choices/expanded excerpts,
5000 selected captions, 34 ms minimum excerpts, nonoverlapping selected cues,
and two-hour source/output bounds. Output is also capped at two hours after
cover rounding. Recipe inputs are at most 1 MiB, transcripts 2 MiB each,
EDL 2 MiB and handoff JSON 32 MiB. A valid recipe canvas is still required by
the shared recipe format, but does not affect this video-only cut list.

Both output names must be fresh, including dangling symlinks. Validation and
name conflicts produce no files. A filesystem error between the two writes
can leave one output; keep it and retry with a fresh prefix. The output parent
must already exist. No source is deleted or overwritten. This workflow does
not render, mutate Studio, clear rights, accept a master or publish anything.
