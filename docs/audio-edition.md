# Make a chaptered listening edition

`cmd/audio_edition` turns one explicitly chosen audio track into a standalone
M4A/AAC listening copy. A producer can offer the dialogue in a finished cut for
listening away from the video, or prepare a chaptered edition of an existing
WAV/FLAC recording. The original media stays untouched, and ordinary editable
MoonCast chapter JSON accompanies the new file.

This fills a different output gap from same-container chapter/caption embedding,
video screening and scene indexing. Those paths preserve video. This path
transcodes only the audio track you select. It is a local adjunct to the PRD's
MC-W07/R02 delivery journey, not completion of that requirement or N05's
caption/accessibility qualification. Visual-only information is absent: this
command does not create audio description or replace a captioned video master.

## Inspect, choose, preview, export

Using the pinned environment and dependencies described in the round BUILD:

```sh
moon --target-dir /absolute/external/mooncast-build build cmd/audio_edition cmd/chapters --target native --frozen --strip -j 1
AUDIO=/absolute/external/mooncast-build/native/debug/build/cmd/audio_edition/audio_edition.exe
CHAPTERS=/absolute/external/mooncast-build/native/debug/build/cmd/chapters/chapters.exe
"$AUDIO" inspect 'finished episode.mp4'
"$AUDIO" preview 'finished episode.mp4' 2 episode.chapters.json
"$AUDIO" export 'finished episode.mp4' 2 episode.chapters.json 'French listening edition'
"$CHAPTERS" set 'French listening edition/chapters.json' detail 2000 'Revised title' revised.json
"$AUDIO" export 'finished episode.mp4' 2 revised.json 'Revised listening edition'
```

Use the absolute stream index returned by `inspect`, not an audio ordinal. For
example, a video at index 0 and English/French audio at 1/2 require `2` for the
French edition. No default audio is silently selected. Inspection lists codec,
language, title, channels, sample rate, start and known duration for each track.
A file without audio is rejected. Only a mono/stereo track can be selected;
surround is not automatically downmixed.

`preview` makes no files. It shows the selected track, every omitted source
stream index, chapter draft, input hashes and exact output profile. Confirm that
the chosen soundtrack is useful without its pictures and matches the chapter
clock. Each export needs a new output folder whose parent already exists.
Spaces and Unicode are supported in explicit local paths.

Existing [chapter authoring](timeline-chapters.md),
[chapter import](chapter-import.md), [chapter conforming](chapter-conforming.md)
and [scene indexing](scene-index.md) produce the input draft. The first marker
must be at zero. A minimal independently authored five-second recording draft is:

```json
{
  "contract": "mooncast.chapter-draft.v1",
  "project_id": "my-recording", "project_revision": 0,
  "timeline_id": "listening", "timeline_revision": 0,
  "ticks_per_second": 1000, "duration_ticks": 5000,
  "markers": [
    {"marker_id": "opening", "start_tick": 0, "title": "Opening"},
    {"marker_id": "detail", "start_tick": 2000, "title": "Details"}
  ]
}
```

Choose your real duration and identities; the command never infers that a file
belongs to a project. Draft revision/marker identities are kept in the JSON.
The container stores chapter titles and times, not native project/marker IDs.
The same `inspect` and `export` commands accept audio-only M4A, WAV or FLAC.
Prefer re-exporting the original source after a chapter edit, because reusing
an already-lossy M4A introduces another generation of audio encoding loss.

## Output and fidelity

The new folder contains:

- `audio.m4a`: one AAC-LC audio track, 48 kHz, the selected mono/stereo channel
  count, target 160 kb/s, language tag, and embedded chapter navigation
- `chapters.json`: editable draft preserving source project/timeline revisions
- `chapters.ffmetadata` and `chapters.vtt`: portable chapter sidecars
- `ffmpeg.log`: retained encoding diagnostics
- `result.json`: completion receipt written last after structural verification,
  with input hashes, selected/omitted streams, exact FFmpeg arguments, output
  hash and complete output probe

This is lossy transcoding, including for an AAC input. The target bitrate is an
encoder setting, not a guarantee of exact file bitrate or perceived quality.
Sample-rate conversion can occur; no loudness normalization, silence removal,
channel mixing, editorial trimming or playback-speed change is requested.
Video, unselected audio, captions/subtitles, cover pictures and attachments are
omitted intentionally. Global metadata comes from the generated chapter file,
not the source container. FFmpeg may retain ordinary selected-track metadata
and adds its encoder/container tags. This is not a metadata-scrubbing tool.

The format is ISO base media with the M4A brand, produced with FFmpeg's `ipod`
muxer. That muxer name is not a claim of iPod/device compatibility. A generated
`bin_data`/`text` stream carries QuickTime chapter navigation; it is not a video,
subtitle transcript, or second audio track. FFprobe must find exactly one AAC
audio stream and only these recognized chapter data streams. The tool checks
channel count, language, 48 kHz, zero start, duration and each exact chapter title,
start and end. Full decode and synthetic tone checks are in the focused smoke
script; a successful export alone does not certify listening quality or every
player. Chapter display varies across players.

## Deliberate bounds and recovery

- Actual MP4/M4A, Matroska, WAV or FLAC containers; no network URLs, playlists,
  microphone capture, provider calls, automatic language detection or uploads
- Regular local input, 1 byte–2 GiB; chapter JSON up to 2 MiB; 1–32 source
  streams and 1–16 audio tracks. Selected audio must be mono/stereo and have a
  three-letter lowercase language tag, or the absent-language default `und`
- Positive draft duration up to two hours; 1–1000 titled chapters beginning at
  zero. All chapter boundaries/duration must be exactly whole milliseconds
- Container and selected audio start at zero within 1 ms. WAV/FLAC's absent
  start value means their ordinary zero origin. Shifted sources need a separate
  edit; the command does not align commentary or repair offsets
- Source container, known selected audio duration, and output container/audio
  duration must match the draft within 50 ms. The allowance covers codec/container
  tails, not arbitrary silence padding. When an input omits its audio duration
  (common with Matroska), the encoded audio stream is checked afterward; a shorter
  track fails rather than stretching chapter metadata to disguise missing audio
- Chapter title and boundary verification is exact despite the audio-tail
  allowance. The output's audio may end a few milliseconds after the final chapter.
  Raw AAC decoding can additionally expose a final partial frame rounded to
  1024 samples; the smoke checks that separately from container playback duration
- Existing output folders/files, including dangling symlinks, are refused.
  Exclusive file creation and FFmpeg `-n` avoid normal overwrite. Failures after
  encoding begins can leave a partial folder. Keep it, inspect the diagnostics,
  correct the cause and choose a fresh destination. No `result.json` means the
  export did not finish
- Source hashes are checked again before completion. Work in trusted, quiescent
  folders; these checks are not an OS sandbox or race-proof custody guarantee

The receipt describes a local derivative. It neither establishes rights,
replaces the approved master, verifies recipient access, records client
acceptance, nor authorizes publishing. Reports contain local paths and draft
identities, so review them before external sharing. Keep captions/labels and the
full master in any delivery that requires them.

The official [FFmpeg stream/metadata mapping manual](https://www.ffmpeg.org/ffmpeg.html)
and [M4A/FFmetadata format reference](https://www.ffmpeg.org/ffmpeg-formats.html)
describe the underlying format and mapping behavior.

## Focused evidence

`scripts/verify_audio_edition.py --source SOURCE --target ABSOLUTE_EXTERNAL_TARGET
--output NEW_ABSOLUTE_FOLDER` builds no software and deletes nothing. It uses
already-built CLI binaries and retains all synthetic fixtures, decoded WAVs,
output editions and per-command logs. It exercises explicit two-language track
selection, mono/stereo outputs, real MP4/M4A/Matroska/WAV/FLAC inputs, ordinary
chapter editing/re-export, exact Unicode/special-character chapter navigation,
independent probes/full decodes/tone-frequency checks, unchanged input hashes,
and invalid/existing destination refusals. Six focused native tests cover pure
selection and verification. No UI, browser/device, paid-provider, actual client
or cumulative acceptance is claimed; cumulative qualification remains R50.
