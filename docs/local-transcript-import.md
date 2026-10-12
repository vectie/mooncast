# Local transcription exports as editor captions

Cut Editor accepts timed text from local transcription tools without a conversion service:

- **Whisper JSON** (`application/json`): an object with a `segments` array. Each segment has numeric `start` and `end` in seconds and a plain `text` string. Extra Whisper metadata remains in the original file; segments become captions. Word timing, speaker formatting and language do not become inferred production approvals or caption-language declarations.
- **Whisper TSV** (`text/tab-separated-values`): exact `start`, `end`, `text` header separated by tabs; start/end are integer milliseconds.
- **Audacity region labels** (`.txt` or `.tsv`): no header; start seconds, end seconds and caption text separated by tabs. Point labels have no caption duration and are rejected. Extended frequency labels are not supported.
- Existing SRT and WebVTT input remains available.

The header determines TSV units; the importer never guesses units from numeric magnitude. UTF-8 BOM and CRLF are accepted. Caption starts must be ordered; overlaps remain valid. Each file is limited to 2 MiB and 5,000 plain-text cues. The full source duration bounds every cue. Malformed rows fail the whole import instead of silently dropping captions. Blank lines inside JSON caption text are normalized to ordinary line breaks.

## Use in Cut Editor

1. Open a project/shot and expand **Rights-cleared local media intake**.
2. Select **subtitle** as the role and choose the JSON, TSV or label TXT file. The file picker fills MIME, size and the exact SHA-256 even when the browser supplies no MIME.
3. Enter the full source duration, rights owner/basis/reference, territory/channels, source kind/reference and actor as usual. For the supplied fixtures, use 5 seconds and your own explicitly synthetic test attestations.
4. Choose **Create intake and upload exact bytes**, then **Add selected to timeline**.
5. Use the existing trim and placement controls to align the subtitle overlay with the video. Text corrections are made in the source file and uploaded as a new immutable source; this feature does not add per-word or in-place caption text editing.
6. Preview or export normally. Imported transcript cues generate a deterministic SRT derivative for native rendering, with source trims, placement and the selected render range applied. The original JSON/TSV bytes, source reference, rights receipt and digest remain retained. Repeated uses of one source share one combined native caption input; a trimmed gap produces no caption input.

The existing governed export/master workflow produces an SRT sidecar. Importing a transcript does not approve a production, clear other media rights, call a transcription service or publish anything.

## Samples and verification

The three equivalent synthetic samples are `fixtures/transcript-whisper.json`, `fixtures/transcript-whisper.tsv`, and `fixtures/transcript-audacity.txt`. Their cues span 0.250–1.500 and 2.125–4.750 seconds.

Focused checks:

```sh
moon test --frozen --target native --strip -j 1 -p editor/media
moon test --frozen --target native --strip -j 1 studio_service/transcript_import_wbtest.mbt
moon -C ui/rabbita-mooncast test --frozen --target js --strip -j 1 -p editor
moon -C ui/rabbita-mooncast build --frozen --target js --strip -j 1
```

The native workflow test needs existing `/usr/bin/ffmpeg`; it uses the production upload route, persisted take, edit commands, frozen plan, native materialization/compiler/executor, and SRT projection. It renders a small real H.264 MP4 and extracts its embedded subtitle track to compare exact cue timing with the SRT sidecar for all three formats. It is an offline synthetic test, not full G0–G7 production acceptance or a browser test.

Format references checked 2026-10-08: [official Whisper writers](https://github.com/openai/whisper/blob/main/whisper/utils.py), [Audacity label-file documentation](https://manual.audacityteam.org/man/importing_and_exporting_labels.html).
