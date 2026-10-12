# Cut a rough reel by choosing transcript lines

The local `cmd/transcript_reel` utility turns transcript choices into a real
H.264 MP4 with original audio (when present), embedded selectable captions,
a matching SRT sidecar, and an editable-selection record in JSON. Use it to
pull an interview answer, put a demonstration's conclusion first, or assemble
a short highlight reel without manually entering every timestamp.

It accepts existing local Whisper JSON/TSV, Audacity region labels, SRT and
WebVTT through the same parsers as Cut Editor. It does not transcribe audio.
Use media and transcripts you have permission to edit.

For interleaved selections from several sources, use the new
[multi-source recipe workflow](multi-source-transcript-reels.md). The single-source
commands below retain their original behavior.

## Explore, choose, render

From the repository with MoonBit, FFmpeg and FFprobe installed:

```sh
moon run cmd/transcript_reel -- inspect fixtures/reel-garden.whisper.json
moon run cmd/transcript_reel -- inspect fixtures/reel-garden.whisper.json harvest
moon run cmd/transcript_reel -- render fixtures/reel-garden.whisper.json garden.mp4 '3,1-2' garden-short
```

Inspection prints stable one-based cue numbers, source milliseconds and text.
Search is case-insensitive and retains the original cue numbers. Edit the
comma-separated selection to revise your story, then render under a new prefix.
`3,1-2` plays cue 3 first, then the continuous interval from cue 1's start to
cue 2's end. Silence between cues in a range remains; `1,2` removes that gap.
Repeating a cue is supported, for example `3,1-2,3`. Each excerpt starts and
ends at the selected cue boundaries. Captions are retimed in playback order.

Outputs are `garden-short.mp4`, `garden-short.srt`, `garden-short.json`.
The JSON contains the exact selection, source paths, transcript digest,
parser version, source/output excerpt times, captions, renderer receipt and
output media probe. Keep it beside your files; reproduce an edit with its
selection value. Existing output files are never overwritten. The parent
output directory must already exist. On failure, partial outputs are retained
for diagnosis; choose a new prefix after resolving the cause.

## Scope

This is a separate local rough-cut utility, not a Studio project mutation or
production delivery approval. The JSON is not rights, provenance or publication
authority. Import the resulting media through the usual rights-attested editor
intake if you want to continue within a project. No provider or network request
is made. The CLI accepts one local video source with its first video/audio
streams; it does not ingest playlists, batch sources, or audio-only recordings.
Captions are soft subtitles rather than burned-in text. Output is normalized
to 30 fps, square pixels and even dimensions; video-frame boundaries can differ
from millisecond caption times by one frame. At most 100 excerpts and two hours
of source/output timing are supported. FFmpeg work has a 30-minute timeout.
Each excerpt must be at least 34 ms long. This is a normal-speed hard-cut workflow; transitions, automatic word alignment,
smart silence detection and timeline GUI editing are not included.
