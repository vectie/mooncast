# Keep captions in sync after cutting a video

`cmd/caption_conform` carries source transcripts through a native single-track
video edit. It handles reordered and repeated clips, multiple source files,
trimmed cue boundaries, and gaps. The result is an editable caption draft plus
SRT and WebVTT sidecars for the new cut, without transcribing the media again.

## Try an EDL-to-caption workflow

Run these commands from the repository root. Choose new output prefixes:

```sh
moon run cmd/edit_decisions -- import fixtures/edit-decisions.project.json fixtures/caption-conform.edl fixtures/edit-decisions.reels.json interview
moon run cmd/caption_conform -- preview interview.project.json fixtures/caption-conform.sources.json
moon run cmd/caption_conform -- export interview.project.json fixtures/caption-conform.sources.json interview-captions
moon run cmd/caption_edit -- show interview-captions.draft.json
```

The checked-in example selects camera B, then camera A, then repeats B. It
produces seven captions on a seven-second timeline. Empty record intervals stay
caption-free, the unused B line disappears, and repeated B excerpts get repeated
captions. A's frame-1 source boundary at 24 fps demonstrates submillisecond
timing. All inputs are synthetic metadata/transcripts, with no video included.

Export creates four new files:

- `interview-captions.srt`: timed captions for video-player/editor import
- `interview-captions.vtt`: UTF-8 captions suitable for an HTML video track
- `interview-captions.draft.json`: open and correct with `cmd/caption_edit`
- `interview-captions.conform.json`: exact input hashes, project/timeline
  revisions, each output cue's source file/cue/clip, and clipping/rounding flags

`preview` displays the same cue timing, source and clipping warnings without
writing files. Export calculates all outputs and checks all four destinations
before writing. Existing files are never overwritten. A filesystem failure
during writing can leave a partial set; retain it and use a new prefix after
fixing the problem.

## Bind captions to media

The caption map identifies media by its native `media_ref_id`, independent of
EDL reel names and source timecode origins:

```json
{
  "contract": "mooncast.caption-source-map.v1",
  "bindings": [
    { "media_ref_id": "media.interview", "format": "srt", "file": "interview.srt" },
    { "media_ref_id": "media.broll", "format": "silent", "file": "" }
  ]
}
```

Paths are relative to the current working directory, not the map's directory.
Absolute local paths work. Bind every media reference used by the cut exactly
once, either to a transcript or explicitly to `silent`. Unused and duplicate
bindings fail, so a mistyped ID cannot silently drop dialogue. An all-silent cut
or a cut with no intersecting captions produces a diagnostic and no files.

Supported explicit formats are `srt`, `vtt`, `whisper-json`, `whisper-tsv`,
`audacity`, and `draft` (a corrected `mooncast.caption-draft.v1` document).
They use the existing bounded, plain-text caption parser. Caption times always
start at the media file's time zero. Do not put an EDL's camera timecode offset
into the caption file. Correct an offset or clock drift first with
`cmd/caption_edit shift` or `sync`, then bind the corrected draft.

## Review words where the cut crosses a caption

Conforming knows cue times, not word-level alignment. It keeps the complete
original text when a cue is shortened, and marks that output cue
`clipped_at_cut: true`. Review those words against your cut. For example:

```sh
moon run cmd/caption_edit -- set interview-captions.draft.json 1 0 500 "Reviewed fragment" corrected.draft.json
moon run cmd/caption_edit -- export corrected.draft.json corrected-captions
```

The original conform report describes the initial output. It does not claim
that later text edits have the same content. Keep it for source tracing.

## Timing and scope

Intersections use exact integer arithmetic in the native timeline clock. A
cue ending exactly at a clip's in point, or starting exactly at its out point,
is excluded. Selected cues are shifted into record time, retaining intentional
gaps and overlapping speakers. Source and project arrays are never mutated.

SRT/WebVTT use whole milliseconds. Starts round up and ends round down only at
export, so a caption never extends outside its selected interval. This can
create tiny (less than 2 ms) gaps at fractional boundaries. `rounded_inward`
identifies affected cues. An intersection too short to represent fails rather
than silently disappearing. The editable draft duration rounds the timeline's
end up to a whole millisecond. No frame-rate assumption or floating-point
conversion is needed.

The supported cut has exactly one nonoverlapping video track, no transitions,
and normal-speed source ranges. Visual transforms do not change the caption
clock and are allowed; enabled speed ramps/retiming are rejected. Audio-only
or layered timelines and choosing dialogue from an independent audio mix need
a different workflow. The tool follows the visible clip's media binding and
does not inspect audio or infer which person is speaking.

Limits: 999 clips, 64 media bindings, 5000 cues per source and in the final
draft, two-hour source/cut duration, 2 MiB per transcript/map, 16 MiB total
transcripts and project input. Source media need known positive durations.
Transcripts must already be ordered and fit their source duration. Empty
subtitles, markup-rich captions, media probing/rendering/muxing, live studio
mutation, and real playback validation are outside this utility. SRT and VTT
are bounded to 2 MiB each by the existing caption exporter.

This is an offline editorial output, not a reviewed master, rights decision,
client acceptance or publication. No provider, account or external service is
used. The existing native project remains unchanged.
