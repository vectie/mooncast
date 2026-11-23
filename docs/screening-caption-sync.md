# Synchronize a whole subtitle track while screening

The offline screening player now shifts every caption together or corrects a
drifting subtitle clock using two speech anchors. This brings the existing
caption CLI's clock operations into the player where you can hear the speech.
Use a newly generated screening folder to get the new controls.

1. Open the screening's `index.html` and find **Synchronize the caption track**
   below its transcript. Finish or cancel any single-caption edit first.
2. For a constant mismatch choose **Constant offset** and enter milliseconds.
   `250` delays every caption by a quarter second; `-250` advances it.
3. For drift choose **Two speech anchors**. Enter two increasing source times
   from the currently applied captions. Seek to each corresponding spoken
   moment and capture its target time from the player, or type it directly.
4. Choose **Preview track timing**. Inspect the before/after cue times. Preview
   leaves playback captions unchanged. **Apply track timing** updates transcript
   timestamps, seek buttons and displayed captions together. Listen again.
5. Download corrected caption JSON or WebVTT using the existing caption editor
   controls. The JSON can be reopened with **Resume saved caption corrections**
   or edited with `cmd/caption_edit`. Download before closing the page.

Example: source speech anchors at 500 and 4500 ms belong at 750 and 5150 ms.
The resulting clock is `750 + (time - 500) * 1.1`. A 500–1500 ms caption becomes
750–1850 ms. A cue at 4000–5000 ms becomes 4600–5700 ms. Its words stay intact.

Both methods apply to all captions, including hidden transcript search results.
Anchors refer to the current session clock, so applying again uses the latest
timings. Download the current draft first if you want a restore point. Cancel
discards only the un-applied clock proposal; it does not undo an applied change.

The two-anchor calculation uses the same integer formula as
`editor/captions/timing.mbt`: nearest millisecond, exact halves upward. It maps
all boundaries, including those outside the two anchors. Existing gaps and
overlaps follow that clock; wording and cue count remain intact. The entire
proposal fails if any cue falls outside the known duration or collapses below
one millisecond. It never clips or deletes a caption to fit. Changing captions
or inputs after preview requires a fresh preview before applying.

This is local session editing. It does not detect speech, rewrite the original
screening, change supplied feedback context, or grant QC/client acceptance.

## Focused verification

`node --test scripts/test-screening-caption-sync.cjs` executes the shipped
embedded script with the established DOM/media/download harness. It covers
offset, captured two-anchor drift, a download/resume roundtrip, native-track
presentation doubles, and BigInt checks of the native integer clock formula.
The neighboring caption edit/timing/replace/resume tests exercise integration.
These checks do not establish a real browser/media-decoder or release approval.
