# Correct one embedded caption track without rebuilding the other languages

A finished episode can contain several subtitle languages and audio versions.
When a reviewer catches a typo or timing error in one caption track, use
`caption_media replace` to produce a new file containing that correction while
keeping the other tracks. The corrected language occupies its existing track
position rather than adding another obsolete choice to the player's menu.
The original video and earlier revisions remain unchanged.

This connects `caption_edit`, corrected screening caption drafts, and the existing
MP4/Matroska caption interchange. It is local media preparation for MC-W04/MC-W07,
MOONCAST-B08 and MOONCAST-R02/N05. It does not promote a Studio master or satisfy
external client access, acceptance, rights or publication gates.

## Inspect, correct, preview and replace

Build the existing commands using the pinned environment from the accompanying
round's `BUILD.md`. Every Moon invocation uses an absolute external target:

```sh
flock "$MOON_NATIVE_LOCK" moon -C "$SOURCE" --target-dir "$TARGET" build cmd/caption_media cmd/caption_edit --target native --frozen --strip -j 1
MEDIA="$TARGET/native/debug/build/cmd/caption_media/caption_media.exe"
EDIT="$TARGET/native/debug/build/cmd/caption_edit/caption_edit.exe"
"$MEDIA" inspect 'captioned episode.mp4'
# Example only: choose the actual absolute subtitle stream index from inspect.
"$MEDIA" extract 'captioned episode.mp4' 3 'English draft'
"$EDIT" set 'English draft/captions.json' 1 711 2117 'Corrected wording.' corrected.json
"$MEDIA" preview-replace corrected.json 'captioned episode.mp4' 3
"$MEDIA" replace corrected.json 'captioned episode.mp4' 3 'Episode revision 2'
"$MEDIA" inspect 'Episode revision 2/media.mp4'
"$MEDIA" extract 'Episode revision 2/media.mp4' 3 'Reopened revision'
```

Use the actual returned replacement track index when reopening the output.
Container stream indices can change because MP4 chapter navigation data is
regenerated. The tool retains the order of audio/video/subtitle tracks, not
absolute indices belonging to obsolete container data. It never guesses a
language from a filename, cue text or default flag.

You can supply a corrected `mooncast.caption-draft.v1` downloaded from the
[screening caption editor](screening-caption-correction.md) instead of using the
CLI editor. Verify that the supplied draft belongs to the intended media and
language. Equal duration does not prove alignment. No transcription, translation,
retiming or matching against a Studio project is performed.

`preview-replace` is read-only. It decodes and displays the existing selected
captions alongside the proposed draft, exact source/draft hashes, preserved
labels, stream position and dispositions. Read the timing/text before creating
a new version. It performs local probing/decoding and can fail on malformed
existing text; no output folder is created by preview.

## Outputs and preservation

Each new folder contains:

- `media.mp4` or `media.mkv`, matching the input container
- `captions.json`, `captions.srt`, `captions.vtt`: the corrected editable draft
  and reusable sidecars
- `previous-captions.json`: the selected track decoded before replacement,
  compatible with the same caption tools
- `ffmpeg.log`: local muxing diagnostics
- `result.json`: completion receipt, written only after structural checks and
  exact decoded cue comparison succeed

FFmpeg copies all unselected compressed audio/video/subtitle streams. Only the
replacement text is encoded, as MP4 `mov_text` or Matroska `subrip`. Its original
language, title and complete disposition flags are copied, including default,
forced or hearing-impaired flags when present. No new default is chosen.
Chapter titles and boundaries are retained. Replacement needs no vacant track
slot, unlike append.

The product verifies the output's container, duration, track count/order, codecs,
language/title/dispositions and chapter titles/times, then decodes the replaced
track and requires every cue's text and millisecond boundaries to equal the
corrected draft. It rechecks input hashes before completion. The focused native
fixture additionally compares every unselected stream's compressed-packet
SHA-256 sequence and fully decodes output video/audio. Container headers and
unverified proprietary metadata may change; this is not a byte-identical file
copy or a guarantee for all players.

To undo a correction, use `previous-captions.json` with the same `replace`
command and a fresh folder. Inspect the current file first to choose its actual
track index. Original files and existing corrected outputs are never rewritten.
To revise another language, use the latest corrected media as the input; the
first correction remains present rather than being lost on a return to an
older master.

## Bounds and recovery

The existing [caption media profile](caption-media.md) applies: regular local
MP4/MKV files, at most 2 GiB/two hours, one video, at most 17 audio/video/subtitle
tracks, no attachment/font or unknown data streams, zero-origin media and a
valid plain-text caption draft within 50 ms of the probed duration. Selected
tracks must be `mov_text`, `subrip` or `webvtt`; image subtitles are refused.
Overlapping cues must be deliberately resolved first. Existing and replacement
text decoding uses the existing bounded parser and 2 MiB sidecar limit.

Replacement preserves subtitle role metadata rather than offering a relabel
operation. If a container cannot retain the declared dispositions or labels,
the output fails verification. The command does not certify that a hearing-
impaired flag, language label or caption wording is accurate.

Every destination must be new, with an existing parent. Existing folders and
dangling symlinks are rejected before decoding; invalid selection/draft is
rejected before creating the output. A later I/O, muxing or verification failure
can leave a partial new folder. Keep it for diagnosis and retry with a fresh
folder. Without `result.json`, the operation did not finish. Work in trusted,
quiescent folders and keep enough disk for another full media copy.

Source paths, caption text and metadata appear in local reports; review them
before sharing. Nothing is uploaded, sent or published. Correcting embedded
captions does not alter text already burned into a video's pixels.

## Focused verification

`scripts/verify_caption_replacement.mbtx` runs the real built commands with
synthetic MP4 and MKV through pinned, typed process APIs. With the private
environment sourced, launch it with a separate absolute external script target:

```sh
flock "$MOON_NATIVE_LOCK" moon --target-dir "$WORKER_ROOT/harness-build" run "$SOURCE/scripts/verify_caption_replacement.mbtx" --target native --strip -j 1 -- "$TARGET" "$WORKER_ROOT/evidence/replacement-reproduction-NEW"
```

It covers preview, extraction/edit/replacement, two caption languages, two audio
tracks, exact Unicode/multiline timing, default/forced/hearing-impaired metadata,
unchanged other-stream packets, chapters, second-language correction, restoration,
full A/V decode, unchanged inputs and rejected invalid/existing destinations.

Native package tests cover sparse stream identities, output renumbering, full
17-track replacement, invalid timing/selection, lost flags/labels, extra tracks
and changed chapters. Browser/player UI, physical playback, external recipients,
providers, paid episodes and cumulative product qualification are unrun.
