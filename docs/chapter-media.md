# Put editable chapters into a playable media file

`cmd/chapter_media` completes the local chapter-authoring journey: preview a
chapter draft against an existing MP4 or Matroska video, embed it into a new
same-container copy, then extract the real embedded chapters back into an
editable draft. This makes chapter navigation available to chapter-aware media
players without rerendering the video or audio. It fills the deliberate muxing
gap in [chapter authoring](timeline-chapters.md),
[chapter import](chapter-import.md) and [chapter conforming](chapter-conforming.md).

## Preview, embed, inspect, edit again

With the retained native dependency graph and installed FFmpeg/FFprobe:

```sh
moon --target-dir /absolute/external/mooncast-build build cmd/chapter_media cmd/chapters --target native --frozen --strip -j 1
MEDIA=/absolute/external/mooncast-build/native/debug/build/cmd/chapter_media/chapter_media.exe
CHAPTERS=/absolute/external/mooncast-build/native/debug/build/cmd/chapters/chapters.exe
"$MEDIA" preview episode.chapters.json 'finished episode.mp4'
"$MEDIA" embed episode.chapters.json 'finished episode.mp4' 'chaptered episode'
"$MEDIA" extract episode.chapters.json 'chaptered episode/media.mp4' 'reopened chapters'
"$CHAPTERS" set 'reopened chapters/chapters.json' imported.2 3000 'Revised title' revised.json
"$MEDIA" embed revised.json 'chaptered episode/media.mp4' 'revised episode'
```

The output directory's parent must already exist and the directory itself must
be new. Spaces and Unicode work in explicit paths. `preview` creates nothing:
it hashes/probes the source and lists the copied stream indexes/codecs/languages,
existing chapters to replace, chosen draft and output container. Review the
chapter titles and timing against the intended media before embedding.

Embedding creates:

- `media.mp4` or `media.mkv`, with all selected video/audio/subtitle streams
  copied and the exact authored chapter titles/starts installed
- `chapters.json`, the original editable draft including its source identities
- `chapters.ffmetadata`, the exact generated chapter input
- `ffmpeg.log`, retained diagnostics
- `result.json`, written last after verification, with source/output hashes,
  exact source draft, probes and executable arguments

Extraction creates `chapters.json`, `chapters.ffmetadata` and `result.json`.
The explicit template supplies project/timeline identity, revisions, duration
and clock; those are retained. Embedded chapters replace its markers, with
`imported.1`, `imported.2`, etc. Native marker IDs are not stored by media
containers. Extraction preserves actual titles and exact rational boundaries,
then the existing `chapters` command can rename, move, add or remove markers.
It never claims that an arbitrary media file belongs to the template's project.

## What is preserved and replaced

The source is read-only. All video, audio and subtitle streams are explicitly
mapped in original order with FFmpeg's `-c copy`. There is no codec conversion,
caption generation, speed change, trim, audio normalization or filter. Existing
embedded captions remain embedded. Original global and per-stream metadata are
passed through FFmpeg's normal metadata-copy behavior, including language tags;
container headers and encoder tags can change. This is not byte-identical file
copying or preservation of every proprietary metadata field.

Existing chapters are deliberately replaced in the new file. Recognized MP4
`bin_data`/`text` chapter navigation streams are regenerated from the new chapter
set. Other data/attachment stream types are rejected instead of silently dropped.
The original version remains available. Unsupported muxer combinations fail with
retained partial output, never a silent transcoding fallback.

The tool probes the finished container and requires the original stream
codecs/order/languages and every chapter title/start/end to survive. It checks
source hashes again before completion. Stream-copy arguments and this structural
check do not independently prove every compressed packet or every player. The
focused synthetic acceptance also compares every video/audio/subtitle packet's
SHA-256 sequence and decodes the resulting MP4 video/audio.

FFmpeg's documented stream mapping, stream copying and chapter mapping are
explained in its [official manual](https://www.ffmpeg.org/ffmpeg.html).
The [FFmetadata format](https://www.ffmpeg.org/ffmpeg-formats.html#Metadata-1)
is used for the authored chapter input.

## Deliberately bounded profile

- Actual local MP4 (`.mp4`) or Matroska (`.mkv`), one video and up to 17 total
  video/audio/subtitle streams; no attached cover pictures, font attachments,
  unknown data streams, network URLs, playlists or container conversion
- Regular files, maximum 2 GiB media and 2 MiB chapter JSON; hashing is chunked
  at 1 MiB. Ensure room for a complete output copy plus small reports
- Positive chapter draft duration up to two hours; the media container duration
  must match within 50 ms, allowing small audio/container tail differences
- Media must start at zero within 1 ms. No timestamps are intentionally shifted
- Whole-millisecond chapter boundaries only. Fractional-frame clocks work when
  every actual boundary is exactly representable, otherwise revise the draft;
  no rounded chapter timing is silently adopted
- 1–1000 ordered titled chapters; extraction requires contiguous intervals
  ending exactly at the template's duration. Untitled chapters, gaps, overlaps,
  partial coverage or inexact clock conversions fail instead of inventing titles
  or intervals. A draft's own validators also apply
- Existing destinations, including dangling symlinks, are refused; exclusive
  folder/file creation and FFmpeg `-n` prevent normal overwrite. Late I/O,
  changed-source, timeout or verification failures can leave a partial folder.
  Preserve it and choose a fresh folder after fixing the cause. Absence of
  `result.json` means the workflow did not finish
- Work on trusted, quiescent folders. Hash rechecks are not an OS sandbox or a
  guarantee against concurrent change-and-restore races

## Scope and evidence

This is a local preparation workflow toward PRD MOONCAST-R02/N05. It does not
update the live Studio, approve a master, establish rights or source identity,
verify recipient access, share files, record client acceptance or publish.
Reports contain local paths and draft identities; review them before sharing.
Container chapter support varies by player. No browser or external-player UI,
accessibility certification, deployed host or real customer was qualified.

`scripts/verify_chapter_media.py --source SOURCE --target TARGET --output NEW_DIR`
exercises actual MP4/MKV outputs, two audio languages, retained Unicode captions,
chapter replacement, extraction, existing authoring and byte-preserved media
packet payloads. Native package tests cover timing, source/stream selection,
exact rational imports, unsupported inputs and output verification. These are
focused local checks only; cumulative qualification remains R50.
