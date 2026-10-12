# Assemble a rough reel from several transcripts

`cmd/transcript_reel render-recipe RECIPE_JSON OUTPUT_PREFIX` builds an ordered
rough cut from local video/transcript pairs. Choose an answer from one interview,
a demonstration from another, then return to the first speaker. Sources can have
different dimensions and audio sample rates; a source without audio contributes
silence. Outputs are a real H.264/AAC MP4 with selectable captions, matching SRT,
and an edit/provenance JSON. This extends the local single-source tool; its
`inspect` and `render` commands and output contracts are unchanged.

## Choose sources, lines and a canvas

Use `transcript_reel inspect TRANSCRIPT [SEARCH]` for stable one-based cue
numbers. Create a recipe such as:

```json
{
  "contract": "mooncast.multi-source-reel-recipe.v1",
  "canvas": { "width": 1280, "height": 720, "fit": "letterbox" },
  "sources": [
    { "id": "interview", "media": "interview.mp4", "transcript": "interview.srt" },
    { "id": "demo", "media": "demo.mp4", "transcript": "demo.whisper.json" }
  ],
  "choices": [
    { "source_id": "interview", "selection": "3" },
    { "source_id": "demo", "selection": "1-2" },
    { "source_id": "interview", "selection": "1,3" }
  ]
}
```

Source paths resolve relative to the recipe's directory, regardless of the
process working directory. Absolute local paths are also accepted. Output
prefixes resolve from the working directory. Parent directories must exist.
The source IDs are unique ASCII letters/digits/underscores/hyphens. Every source
must be used. Unknown or missing JSON fields are refused. Duplicate JSON keys
follow the shared JSON parser's last-value semantics; don't use duplicate keys.

```sh
moon run cmd/transcript_reel -- render-recipe recipe.json rough-cut
```

Array order is playback order. Selection `3,1-2,3` plays cue 3, then the continuous
source interval from cue 1's start through cue 2's end, then repeats cue 3.
Gaps within a range stay in the media and captions; comma-separated choices cut
them out. Selected overlapping captions are refused, so the embedded subtitle
track cannot silently lose an overlapping line. Single cues may be repeated.
The same existing parsers accept SRT, WebVTT, Whisper JSON/TSV and Audacity labels.
There is no transcription, semantic search, word alignment or automatic edit.

## Deliberate media policy

- Explicit, even-sized canvas: width 32..1920, height 32..1080. `letterbox` is the
  only fit. Scale to fit, preserve square-pixel aspect ratio, and center with
  black bars. Odd scaled dimensions round down to even values. No stretching or
  cropping. MP4/MOV, MKV/WebM and AVI local containers are supported; playlists,
  audio-only inputs, attached cover art and anamorphic video are refused.
- First video/audio streams only. Source streams must start at zero (within
  1 ms); offset media needs prior conforming. Differing audio rates are resampled
  to 48 kHz, stereo, then encoded to AAC. Mono is mixed to stereo. Absent audio,
  early-ending audio and rounded tails receive silence. Even an all-silent
  multi-source reel includes a stereo audio track. Original single-source silent
  renders still have no audio track.
- Normal-speed hard cuts at 30 fps. Each selected source duration rounds upward
  to a whole frame; its last video frame is held and audio is padded as needed.
  For example, 34 ms becomes two frames (66.667 ms). Subsequent excerpt starts
  are computed from cumulative frame counts. Captions retain source-relative
  millisecond positions, with output frame positions converted down to the
  nearest millisecond. Caption positions therefore differ from a frame clock by
  less than 1 ms. Source boundaries can differ from decoded video by one frame.
- No transitions, burned-in captions, audio loudness normalization, multitrack
  mixing, color/HDR mastering or frame-interpolation claim. This is a rough cut;
  inspect picture, synchronization, sound and captions before further use.

## Edit record and rerender

Keep all three outputs. The JSON contains the complete normalized recipe with
absolute source paths; source byte counts, media and transcript SHA-256 hashes;
parser and cue identities; source probes; every source range and output frame
position; captions; renderer receipt/plan hash; output probe and media/sidecar
hashes; and exact local FFmpeg/FFprobe version reports. Replay it with:

```sh
moon run cmd/transcript_reel -- render-record rough-cut.json repeated-cut
```

Replay checks each saved source ID, media SHA-256 and transcript SHA-256 before
writing anything. A changed file at the same path is refused, even if its cue
numbering still fits. The saved record is the identity reference, not a signed
attestation; modifying it can deliberately change that reference. To revise the
edit or deliberately accept new media, extract its `recipe` object into a new
JSON file and use `render-recipe` with a fresh output prefix. To relocate identical
sources, update the paths in the saved record's `recipe` while retaining hashes.

Hashes are measured again after rendering, including transcripts and recipe.
Changed sources prevent a success record. The utility doesn't lock external
files and cannot defend against concurrent change-and-restore races; keep
inputs stable throughout. An ordinary recipe intentionally accepts the current
files; record replay requires the saved identities. Rerendering
with identical files/tools/recipe is reproducible as an edit; encoder-version or
platform changes can alter encoded bytes. No authenticity or rights attestation
is implied by a content hash.

All output names must be fresh. SRT/JSON use exclusive creation and FFmpeg uses
no-overwrite. Invalid inputs are checked before any output; rendering failures
can leave diagnostic partial outputs. Nothing is deleted. Pick a new prefix to
retry. The tool never modifies source media, transcripts, recipes or Studio.

## Bounds and authority

At most 8 sources, 100 choices and 100 expanded excerpts; 5,000 output captions;
1 MiB recipe (32 MiB saved edit record); 2 MiB per transcript; 1 GiB per media file and 2 GiB total source
media. Sources and normalized output timing are at most two hours. Each excerpt
is at least 34 ms. Source dimensions are at most 8192 in either direction.
The success record currently requires an output no larger than 1 GiB. Probes
and tool inspection time out after 30 seconds; FFmpeg rendering after 30 minutes.
Hashing uses bounded 1 MiB chunks. No network protocols are enabled for media.

This is a local editorial aid for MC-W03/MC-W04/MC-W07 and MOONCAST-B08. A
successful render is not a rights clearance, Studio edit, QC/master approval,
client acceptance, publication or commercial delivery. Use only media you are
authorized to edit; import the result through the usual governed project intake
for later production work. No provider, paid generation or upload is performed.

## Continue editing outside the rough-reel renderer

Use [`transcript_reel export-edl`](transcript-edl-handoff.md) with the same
recipe to hand the ordered video selections to an NLE or MoonCast's existing
native EDL importer. Choose the target integer frame rate and either exact or
outward-cover source boundaries explicitly. The handoff is video-only; its
frame-rounded timeline can differ from the rendered reel's timing.
