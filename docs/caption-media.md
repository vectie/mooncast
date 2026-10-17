# Add selectable captions to a video, then reopen them for editing

`cmd/caption_media` connects MoonCast's editable caption drafts to actual local
MP4 and Matroska video. Inspect the real subtitle tracks, preview a labelled
caption draft, append it as a selectable track to a new media version, and
extract a chosen track back to JSON, SRT and WebVTT for further correction.
Video and audio are copied without re-encoding. Captions are soft subtitles,
not text burned into the picture.

## Import, attach, reopen, correct

Use sources you have permission to edit. Build with the retained dependencies,
the pinned MoonBit toolchain, and installed FFmpeg/FFprobe:

```sh
moon --target-dir /absolute/external/mooncast-build build cmd/caption_media cmd/caption_edit --target native --frozen --strip -j 1
MEDIA=/absolute/external/mooncast-build/native/debug/build/cmd/caption_media/caption_media.exe
EDIT=/absolute/external/mooncast-build/native/debug/build/cmd/caption_edit/caption_edit.exe
"$EDIT" import English.srt 6000 english.json
"$MEDIA" inspect 'episode.mp4'
"$MEDIA" preview english.json 'episode.mp4' eng 'English captions'
"$MEDIA" attach english.json 'episode.mp4' eng 'English captions' 'captioned episode'
"$MEDIA" inspect 'captioned episode/media.mp4'
# Use the actual subtitle index returned by inspect or added_track.index:
"$MEDIA" extract 'captioned episode/media.mp4' 4 'reopened captions'
"$EDIT" set 'reopened captions/captions.json' 2 3001 5551 'Corrected wording.' corrected.json
"$MEDIA" attach corrected.json 'episode.mp4' eng 'English corrected' 'corrected episode'
```

The example's `4` is only valid when inspection identifies that stream. Indices
are the container's actual zero-based stream indices, not subtitle ordinals.
An audio/video index, absent index or unsupported image-subtitle track fails.
The tool does not guess a language or choose a track based on its title.

`inspect` reports duration, container, indices, codecs, language/title metadata,
default/forced flags, and existing chapters. `preview` additionally shows the
selected draft and intended append action. Both are read-only. Language is an
explicit three-letter lowercase metadata code, for example `eng`, `fra`, `zho`
or `und` for unknown. The syntax is validated, not the language of the text or
the code's registration. Use a short descriptive title. The added track is
never forced. An MP4's first subtitle is marked default by its container muxer;
preview explicitly reports this as `new_track_default: true`. Further MP4
subtitle tracks and Matroska additions are not default. The receipt/inspection
reports the actual flags. Viewers can choose a track in their player's subtitle
control. Availability and presentation of that control depend on the player.

Attachment always appends one track, retaining existing ones. To correct an
existing language without accumulating obsolete tracks or losing later additions,
use the [caption replacement workflow](caption-replacement.md): inspect the
explicit stream, preview the corrected draft, then replace it in a new media
version. To supply a new language, deliberately attach its draft instead.
There is no removal command. Translation and transcription are not performed.

## Outputs and actual verification

Each output directory must be new, with an existing parent. Paths may include
spaces and Unicode. Attachment creates:

- `media.mp4` or `media.mkv`, matching the input container
- `captions.json`, the original editable draft
- `captions.srt` and `captions.vtt`, reusable sidecars
- `ffmpeg.log`, local execution diagnostics
- `result.json`, written last after verification, including exact source/draft
  hashes, resulting media hash, mapped stream arguments and added stream index

Extraction writes the same three caption files and a result describing the
selected source track, without copying the media. The output draft can be used
with [caption editing](caption-editing.md), [layout](caption-layout.md),
[review interchange](caption-review.md) or [conforming](caption-conforming.md).

FFmpeg explicitly maps every existing video/audio/subtitle stream with `copy`,
then encodes only the new subtitle as MP4 `mov_text` or Matroska `subrip`.
Existing chapters are mapped from the source; MP4 navigation data is regenerated
from them. The product probes the output and checks retained stream order,
codecs, language and default/forced flags, chapter titles/timing, and the new
track's metadata. It then decodes that actual new subtitle back to SRT and
requires every cue's text and millisecond boundaries to equal the draft. A
conversion that cannot preserve those cues does not get a completion result.

This is a container remux, not a byte-identical file copy. Header and encoder
metadata can change; arbitrary/proprietary metadata and styling preservation
are not promised. The acceptance harness additionally compares the compressed
packet SHA-256 sequence of every retained A/V/subtitle stream and decodes all
MP4 video/audio. That focused synthetic result is not a guarantee for all
containers or players. FFmpeg documents [stream copying and explicit mapping](https://ffmpeg.org/ffmpeg.html#Streamcopy).

## Bounded profile and interrupted work

- Regular local `.mp4` or `.mkv` files only; actual container must match suffix.
  Maximum 2 GiB and two hours, media starts at zero within 1 ms. No URLs,
  playlists, attachment/font streams, cover pictures, unknown data streams,
  container conversion, trimming, playback-speed change or audio normalization.
- Exactly one video and at most 17 total A/V/subtitle tracks. Attachment needs
  an available track slot. Existing supported-container subtitle codecs are
  copied; extraction only supports `mov_text`, `subrip` or `webvtt`.
- Editable input follows the existing caption validator: up to 16 MiB and 5000
  plain-text cues with a known duration. The draft's duration must match the
  probed media within 50 ms; minor container/audio tails are allowed.
- Attachment requires nonoverlapping cues and preserves millisecond times.
  Resolve overlapping speakers deliberately in the caption editor first.
  Literal Unicode and nonempty line breaks are supported. SRT conversions that
  normalize unusual whitespace or formatting fail the exact round-trip check.
- Extraction uses the media's duration rounded to the nearest millisecond and
  converts only plain text at millisecond resolution. Styling, fonts, positioning,
  word-level timing and other format-specific information are not retained.
  The existing bounded SRT parser/validator applies, including normalization
  and rejection of unsupported markup/invalid cues. It is not OCR. Review the
  extracted text and timing against the media before editing or delivering it.
- Encoded/decoded sidecars are at most 2 MiB each. FFmpeg processes have bounded
  output and timeouts; normal overwrite is prevented through exclusive new
  folders/files and FFmpeg `-n`. Existing and dangling-symlink destinations fail.
- Late I/O, muxing or verification failure can leave a partial new directory.
  A missing `result.json` means the operation did not finish. Preserve it, fix
  the cause and choose a fresh folder. Original files are never rewritten.
  Allow enough free disk space for a complete additional media copy.
- Work in trusted, quiescent folders. Source hash rechecks detect ordinary
  changes but are not a sandbox or protection against change-and-restore races.

This is offline media preparation toward MOONCAST-R02/N05. It does not update a
Studio project, establish rights, approve a master, verify recipient access,
share files, publish, record client acceptance or certify accessibility. No
browser/player UI or real customer was qualified. Local paths appear in reports;
review them before sharing. Cumulative fully verified qualification remains R50.

`scripts/verify_caption_media.py --source SOURCE --target TARGET --output NEW_DIR`
regenerates small synthetic fixtures and verifies the entire workflow. See the
round's BUILD.md for exact pinned reproduction and focused acceptance commands.
