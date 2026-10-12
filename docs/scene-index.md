# Find scenes in an unchaptered local video

`cmd/scene_index` scans actual video frames for visual changes, shows the resulting
ranges, and exports a chapter draft you can rename, move, or prune. This is useful
when a recording or finished cut has no timeline or chapter sidecar: get starting
navigation points without manually scrubbing the entire file.

The tool works offline with installed FFmpeg/FFprobe. It changes no media bytes
and makes no network request. Audio is ignored by detection, not removed from
the original file. The output is an editorial starting point, not semantic scene
recognition: a flash or camera movement can trigger a candidate, and a gradual
transition or cut between similar images can be missed.

## Preview, export, and edit

The retained R375 `BUILD.md` next to this checkout documents the exact pinned
environment. Every Moon invocation must use an absolute external target. With
that environment sourced and the binaries built:

```sh
TARGET=/workspace/scratch/665adc5202cf/.moonsuite-background/r371-375/work/r375-mooncast/build
"$TARGET/native/debug/build/cmd/scene_index/scene_index.exe" preview /path/to/episode.mp4 10 1000
"$TARGET/native/debug/build/cmd/scene_index/scene_index.exe" export /path/to/episode.mp4 10 1000 /path/to/new-episode
"$TARGET/native/debug/build/cmd/chapters/chapters.exe" preview /path/to/new-episode.chapters.json
"$TARGET/native/debug/build/cmd/chapters/chapters.exe" set /path/to/new-episode.chapters.json scene-2 12500 'Interview begins' /path/to/revised.chapters.json
"$TARGET/native/debug/build/cmd/screening/screening.exe" export /path/to/episode.mp4 - /path/to/revised.chapters.json 'Episode review' /path/to/new-player
```

Replace paths and the example marker/time with values from your preview. The
screening tool has its own narrower H.264/AAC MP4 profile; scene indexing also
accepts the existing MP4/Matroska media profile. A scene-index result does not
promise compatibility with every downstream player. You can instead export the
revised draft with `chapters export`, use it with `chapter_media`, or supply up
to 120 markers to the existing `review_sheet chapters` workflow.

`preview` writes no files. `export` writes four new files:

- `.chapters.json`: ordinary `mooncast.chapter-draft.v1`, compatible with the
  existing editor commands. `scene-1`, `scene-2`, etc. initially have neutral
  titles; rename them after watching the corresponding ranges.
- `.chapters.vtt`: navigation WebVTT, not speech captions.
- `.ffmetadata`: chapter sidecar with an exact 1/1000 timebase.
- `.scenes.json`: the analysis report, including source SHA-256, threshold,
  gap policy, every above-threshold candidate, selected ranges, and draft.

The source hash is embedded in the draft's local-media and scene-index IDs.
These are local analysis identities, not Studio project IDs or approval
receipts. Changing options can produce another draft with the same media
identity; use a new output prefix. The report records the option values. After
manual chapter edits, keep the original report as provenance for the initial
suggestions; it does not claim to describe the later edits.

## Tune the suggestions

The threshold is an integer from 1 to 100, passed to FFmpeg's `scdet` filter.
Start with 10 and inspect the output. Higher values generally produce fewer
candidates; lower values include smaller visual changes. The reported score
is the filter's visual-change measure, not a confidence or accuracy percentage.
Scores are emitted with FFmpeg's precision.

`MIN_SCENE_MS` must be 100–60000. Candidates are considered in chronological
order. Keep the earliest candidate at least that far from the previous kept
boundary, provided it also leaves that much time before the media end. A later,
stronger candidate does not replace an earlier kept one. Every suppressed
above-threshold candidate retains its time, score, and reason in `.scenes.json`.
Below-threshold frames are not candidates and are not stored.

A generated opening boundary always starts at zero, even if nothing changes
visually. A static or very short recording therefore produces one range, not
an empty file or a fabricated detected cut. All ranges end at the next selected
boundary or the reported container duration. If audio extends beyond video,
that last range can include an audio-only tail. These ranges are navigation
suggestions, not a promise of continuous video-frame coverage.

## Analysis clock and limits

- One video stream in a real local MP4 or Matroska file, using the existing
  bounded media probe. Alternate video angles are refused rather than selected.
- 1 byte to 2,147,483,647 bytes; positive duration at most 30 minutes; video
  dimensions 16–4096 per side; container and video begin within 1 ms of zero.
  Video start time must be available. Attached pictures and unsupported stream
  types fail. HDR PQ/HLG transfer metadata is refused; missing color metadata is
  not proof that a file is SDR.
- Analysis alone resizes each frame to a fixed 320×180 yuv420p frame, potentially
  stretching its aspect ratio. This bounds work and defines the detector profile;
  it neither creates nor modifies a viewing copy. No audio or textual analysis,
  transcription, face identification, or scene naming occurs.
- FFmpeg's `settb=1/1000` rescales analysis PTS to integer milliseconds. Output
  boundaries use that clock, not rounded `pts_time` text. They are not guaranteed
  to remain exact frame boundaries for fractional rates; inspect the actual cut
  before using a marker as an edit point. Equal quantized milliseconds are
  suppressed by the minimum gap.
- Maximum 10,000 candidates and 1,000 selected scenes. If exceeded, increase the
  threshold or minimum gap, or deliberately split the input with another tool.
  Analysis is bounded to five minutes and 2 MiB of captured detector output.
  Timeout, decode failure, or truncated output rejects the whole result.
- Use a regular local file, not a URL or file symlink. Paths containing a colon
  are outside this profile. FFmpeg receives argv directly without a shell;
  spaces, Unicode and semicolons in a permitted path remain literal.

## Recovery and review boundary

All output paths must be new, and their parent directory must already exist.
Source hashing is checked before and after scanning. Validation, source-change,
or detector failures write no export files. Output files are created with
exclusive-create semantics. A filesystem failure can leave some chapter
sidecars; retain those for diagnosis and retry with a new prefix. The report is
written last. No partial export should be treated as complete without it.

This workflow does not mutate a live Studio project, clear rights, authorize
spend, make an editorial decision, send a review, record acceptance, or publish.
It does not qualify external access, browser playback, provider production,
paid episodes, or semantic detection accuracy on arbitrary footage.

The focused native tests cover the metadata parser, millisecond clock, range
selection, short/static inputs, invalid options/profiles, and editable chapter
handoff. The real CLI workflow generates an eight-second H.264/AAC video with
known changes at 2, 4, and 6 seconds; it detects those boundaries, exports and
edits the draft, packages it into the existing offline screening player, checks
all artifact hashes, and decodes actual A/V. Cumulative full qualification
remains R50; these are new focused local checks only.
