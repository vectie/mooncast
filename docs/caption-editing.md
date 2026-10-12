# Correct and synchronize caption files

`cmd/caption_edit` is a local, offline caption-editing utility. Import an existing
transcript, correct the words and timing, split long captions or merge short
ones, then export SRT and WebVTT for your video player, web page or editor.
It requires MoonBit. It does not require FFmpeg, a provider account or a network
connection. Use captions and media you have permission to edit.

## A complete edit

Run from the MoonCast repository. Each command creates a new draft, so an earlier
version remains available for comparison or undo. Output parent directories
must already exist.

```sh
moon run cmd/caption_edit -- import fixtures/reel-garden.whisper.json 7000 garden-1.json
moon run cmd/caption_edit -- show garden-1.json
moon run cmd/caption_edit -- set garden-1.json 2 2000 3000 'Explain the seedlings and watering.' garden-2.json
moon run cmd/caption_edit -- split garden-2.json 3 4500 'Harvest time.' 'Thanks for watching.' garden-3.json
moon run cmd/caption_edit -- sync garden-3.json 500 750 5000 6150 garden-final.json
moon run cmd/caption_edit -- export garden-final.json garden-corrected
```

This synthetic example corrects cue 2, splits the ending, and fits a clock where
source 500 ms should appear at 750 ms and source 5000 ms at 6150 ms. The four
exported intervals are 750–1950, 2550–3750, 4950–5550 and 5550–6150 ms.
Outputs are `garden-corrected.srt` and `garden-corrected.vtt`. Keep the final JSON
if you want to revise the captions again.

Choose the two sync points by listening to the media and comparing two known
moments far apart. Sync applies the same linear offset and speed correction to
all cue boundaries, including outside the anchors. It rounds to the nearest
millisecond, with exact halves rounded upward. If any result falls outside the
media or becomes shorter than one millisecond, the whole command fails without
writing a draft. This does not detect speech or align words automatically.

For a constant delay or advance, use `shift` instead:

```sh
moon run cmd/caption_edit -- shift garden-3.json 250 garden-delayed.json
moon run cmd/caption_edit -- shift garden-delayed.json -250 garden-restored.json
moon run cmd/caption_edit -- merge garden-3.json 3 4 'Harvest time. Thanks for watching.' garden-merged.json
```

Merge replaces the full consecutive cue range with the supplied text, beginning
at the first cue's start and ending at the latest end in that range. Any gaps in
that range become captioned. Split preserves overlapping speakers' cues and
inserts its second half in start-time order, before cues with an equal start.
Cue numbers always refer to the current draft and
can change after split or merge; run `show` before the next edit.

## Direct JSON editing

The commands are convenient for individual corrections. For a larger revision,
open the draft JSON in your text editor and edit the `cues` array directly:

```json
{
  "contract": "mooncast.caption-draft.v1",
  "source_file": "interview.srt",
  "duration_ms": 7000,
  "cues": [
    {"start_ms": 750, "end_ms": 1950, "text": "Corrected caption.\nSecond line."}
  ]
}
```

You may add or remove cues, split or combine their text, change their times, and
change `duration_ms` if the target video's known duration has changed. Keep the
contract unchanged and cues ordered by start time. `source_file` is an
informational label, not a path the draft commands open or an integrity claim.
Export validates the entire draft before writing either sidecar.

To embed the resulting draft as a selectable subtitle track in a local MP4 or
Matroska video, or extract an existing track back into this editor, use
[caption media interchange](caption-media.md).

For ASS/SSA files from Aegisub or legacy subtitle editors, first use
[plain ASS/SSA import](ass-captions.md), which preserves the exact source beside
the editable draft and explicitly reports flattened styling.

To show two language drafts simultaneously, use
[bilingual composition](bilingual-captions.md). It preserves both timing clocks
without holding words across gaps and returns an ordinary editable draft.

## Formats and limits

- Import: local SRT, plain WebVTT, Whisper JSON segments, Whisper TSV and Audacity
  region labels through the existing [transcript importer](local-transcript-import.md).
  Input files are at most 2 MiB. Their existing plain-text parser normalization
  applies; styles, word timing, speaker styling, regions and positioning are not
  retained. WebVTT character escapes are decoded; literal angle brackets remain
  outside the supported plain-text subset.
- Drafts: at most 16 MiB, 1–5,000 cues, positive known media duration up to two
  hours, integer milliseconds, and at most 2,000 characters per cue. Overlaps
  are permitted. Blank lines, tabs, carriage returns, NUL and angle-bracket
  markup are rejected. Use `\n` in JSON for ordinary nonempty caption lines.
- SRT uses comma milliseconds; WebVTT uses dot milliseconds and escapes `&` so
  browser players preserve literal text. Both are UTF-8. Exported files are
  limited to 2 MiB each so they fit the existing editor intake.
- Use the SRT output for the existing rights-attested MoonCast editor intake;
  use WebVTT for an HTML video track. Inspect the actual media to confirm timing
  and readability before delivery. This utility cannot verify those judgments.

Existing output files are never overwritten. A validation failure creates no
output. A filesystem failure while writing the two export files may leave the
first file; inspect it and choose a new prefix after resolving the failure.
There is no GUI change, transcription, translation, video render, automatic
line wrapping, project mutation, approval, delivery, or publication action.

## Focused checks

```sh
moon test --frozen --target native --strip -j 1 -p editor/captions
moon build --frozen --target native --strip -j 1 cmd/caption_edit
moon check --frozen --target native --strip -j 1
```
