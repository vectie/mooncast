# Resume saved caption corrections

The screening player can reopen its downloaded corrected-caption JSON so an editor can continue a wording/timing pass after closing the page. This closes a concrete gap in MC-W04: corrected drafts could be saved, but the screening editor could not resume them. This is local session editing, not master approval or delivery.

1. Open a screening with supplied captions. Correct wording or timing using the existing caption editor, then download **corrected caption draft (JSON)**.
2. Reopen the same screening. Beneath the transcript, choose the JSON in **Resume saved caption corrections**.
3. Read every changed cue's current and incoming wording and time interval. The transcript and playback captions still show the current draft.
4. Download current corrections first if you need a recovery copy, then choose **Apply previewed saved captions**. The saved draft replaces applied wording/timing together. Continue normal editing or literal replacements, and download again before closing.
5. **Cancel saved draft preview** dismisses the loaded draft without changing captions. It also cancels a file read that has not returned yet.

Example: change cue 1 from `First 🌙`, 0–1000 ms, to `Resumed & literal 🌖`, 200–1100 ms. Save JSON, reopen the screening, select the saved JSON, inspect that exact before/after pair, and apply. The focused roundtrip test then changes the resumed wording again and verifies the next download.

## Matching and boundaries

- Accepts the existing `mooncast.caption-draft.v1` corrected export, up to 16 MiB. The exact recorded media SHA-256 source string, duration and cue count must match.
- Cue order remains fixed. All starts must be nondecreasing, whole nonnegative milliseconds; every end must follow its start and fit the screening duration. Existing overlapping-end semantics remain supported.
- Plain-text validation matches the caption editor. Invalid cues reject the entire draft. Added/deleted cues, arbitrary unbound JSON and WebVTT are not supported here.
- A matching recorded digest is not a fresh media hash or proof that captions describe the speech. Same-media/same-count drafts require editorial review of the complete preview.
- Single-caption unsaved edits block loading/applying. Changes during reading or after preview require selecting the file again. A newer selected file or cancellation supersedes an older read.
- Applied transcript text, seek buttons, native captions or fallback captions update together. Playback state, review notes, supplied feedback context, original files and rights/QC state are unchanged.
- No automatic persistence or import undo is provided. Save current corrections before replacement when needed.

## Focused verification

`node --test scripts/test-screening-caption-resume.cjs` exercises the actual embedded production script with DOM/media/download doubles. `node --test scripts/test-screening-*.cjs` runs the surrounding regression tests. These do not establish a real browser, media decoder, native product build or release qualification.
