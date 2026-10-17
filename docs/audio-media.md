# Import a selectable alternate soundtrack

An editor has a reviewed local episode and a separately recorded translation,
commentary or audio-description mix. The audio_media command joins those
existing assets into a new playable MP4 or Matroska file. A viewer can select
the added track while retaining the original mix. No provider or account is used.

This closes the reverse side of [audio editions](audio-edition.md): that tool
extracts one chosen track to a chaptered M4A; this one imports an explicitly
selected track into the picture. Existing caption and chapter media commands
can continue editing the resulting media.

## Build once

From the repository, choose an absolute build directory outside the source:

    moon --target-dir /absolute/external/build build cmd/audio_media --target native --strip -j 1

Use the native executable at
/absolute/external/build/native/debug/build/cmd/audio_media/audio_media.exe
as audio_media in the commands below. Approved local FFmpeg and FFprobe must
be on PATH. The command does not download or install media tools.

## Inspect, preview, import, listen

    audio_media inspect "/media/French mix.wav"
    audio_media preview "/media/episode.mp4" "/media/French mix.wav" 0 fra "Français"
    audio_media attach "/media/episode.mp4" "/media/French mix.wav" 0 fra "Français" "/media/French edition"
    audio_media inspect "/media/French edition/media.mp4"

Inspect lists audio tracks in the soundtrack or another container that has
audio. Select its absolute stream index, not its audio ordinal. For example,
the desired audio may be index 2 when a source MP4 also contains video. The
soundtrack can be WAV, FLAC, M4A, MP4 or MKV; only the named audio stream is used.
Other tracks, captions, artwork, chapters and global tags from the soundtrack
are not imported.

Preview writes no output. It shows:

- Original media streams, labels, dispositions, duration and chapters
- The selected source audio index, codec, channel count, sample rate, start
  and declared duration (which can be unknown in Matroska)
- The supplied three-letter lowercase language code and track title
- The actual encoding and default-track policy

Language is author-supplied metadata, never detected or translated. Use und
for unknown language, instrumental audio or a synthetic fixture. A title such
as “Audio description” does not certify accessibility, set an impairment flag
or establish that descriptive speech is present.

Attach requires a new destination folder and leaves all inputs untouched.
It first encodes only the selected soundtrack, verifies its measured duration,
then appends it while stream-copying every original video/audio/caption stream
and retaining chapter navigation. Output verification checks stream order,
codecs, labels, all disposition flags, chapters, duration and the new audio
channel count, sample rate and zero origin before writing result.json.

Open the resulting media.mp4 or media.mkv in a player that supports choosing
audio tracks, then choose the new track by its title/language. Listen across
the whole episode and compare timing and levels with the original. A matching
duration alone does not prove synchronization, correct translation, speech
intelligibility, mix quality or appropriate loudness.

To add another language, run the same command with the previously produced
media as the media input and a new destination. The earlier imported track
remains. To return to the earlier version, reopen the unchanged original or
prior output; this command does not remove or replace tracks.

## Output folder

- media.mp4 or media.mkv: the new selectable-track version
- soundtrack.m4a or soundtrack.flac: the measured encoded source track
- preview.json: exact local input paths/hashes and editorial selection
- encode.log, mux.log: local tool diagnostics
- result.json: successful output hash, selected output track, probes and argv

MP4 imports are lossy AAC at a 160 kb/s target and 48 kHz. Matroska imports use
FLAC lossless encoding after conversion to 48 kHz. Both retain the selected
mono/stereo channel count. Original streams are not re-encoded. If the media
already contains audio, every original disposition remains and the new audio
is non-default. If it has no audio, the added track is explicitly default.

## Bounded timing and media profile

- The picture is actual MP4 or Matroska with exactly one non-cover video.
- Media is at most two hours, with at most 17 retained streams after import
  and at most 1,000 chapters. Each input file is at most 2 GiB.
- Sources are regular local files, not URLs, playlists, links or device input.
- Picture and audio container must start at zero. The selected audio must be
  zero-origin mono/stereo; there is no implicit surround downmix.
- Both container and known selected-stream durations must match the picture
  within 50 ms. Start tolerances are 1 ms. There is no shift, padding, trimming,
  time stretch or automatic synchronization.
- Some containers omit the selected audio duration. Preview reports that
  unknown honestly. Attach measures the isolated rendition and refuses a
  short selected track even if another stream made its container longer.
- Unknown/attachment streams and unsupported remux combinations are rejected.
  Arbitrary source codecs, unusual metadata and physical players are not all
  qualified by the fixture tests.

For a failure before encoding, no destination is created. For encode, duration
or mux failure, the partial new folder and logs remain, but result.json is
absent. Inspect the error, correct the source externally and choose another new
folder. An existing or dangling-link destination is never overwritten.

The local helper prepares an editorial copy. It does not alter the Studio
master, recorded rights/QC decisions, client acceptance, publication authority
or payments. Use only audio you have permission to use, then review and approve
the final version through the normal production process.

## Reproducible checks

The scripts/verify_audio_media.mbtx harness builds no product code and downloads
nothing. After building cmd/audio_media, run it with the absolute build target,
a fresh evidence folder and a fresh sample folder:

    moon --target-dir /absolute/external/harness run scripts/verify_audio_media.mbtx --target native --strip -j 1 -- /absolute/external/build /absolute/new-evidence /absolute/new-samples

The synthetic-media matrix covers both output containers, four source formats,
explicit second-track selection, mono/stereo, repeated additions, first audio
on silent video, captions and chapters, original packet payload/timestamp
preservation, encoded-track packet identity and full decode. Negative cases
cover shifted, short, surround, hidden-short audio and invalid/existing targets.
The two-second sample is synthetic color motion with 440 Hz and 1320 Hz tones;
it contains no actual translated or descriptive speech.
