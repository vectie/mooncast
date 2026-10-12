# Undo saved screening notebook changes

Editors can step backward and forward through saved feedback edits in the
existing offline screening player. An accidental issue resolution, wrong
notebook replacement or unwanted merge no longer requires a previously
downloaded recovery copy. This is session-local notebook history, separate from
production cut history, downloaded files and client acceptance.

## Use

Regenerate the screening folder using [offline-screening.md](offline-screening.md)
to receive the controls, then open `index.html`.

1. Capture and save an issue, edit its wording or time, or resolve/reopen it.
2. Under the notebook status, **Undo: ...** names the latest saved change.
   Choose it to restore the complete previous saved notebook. **Redo: ...**
   restores that change again. Neither button seeks or starts/stops playback.
3. Merging notebooks, replacing the notebook (including an empty replacement),
   and applying selected incoming revisions are each one reversible step. A
   merge that kept two conflicting same-ID notes restores both exact IDs and
   wording on redo. Review selections are invalidated after any history move.
4. Save or **Cancel edit** before using history. An active edit, a captured
   anchor or any uncommitted text blocks both buttons and their handlers; it is
   never silently discarded by Undo/Redo. Cancel edit deliberately clears that
   draft. A prior explicit whole-notebook replacement still discards an editor
   draft as warned by that existing action; history cannot recover drafts.
5. **Download notebook** again to retain the restored state. An earlier download
   remains unchanged. Undo does not undo a file download or alter any existing
   file. Downloads do not reset history or create history steps.

Saving a new distinct notebook change after Undo discards the redo future.
Saving identical content does not consume a step or discard redo. Searches,
filters, list order, playback, caption choice and A–B repeat settings do not enter
history and remain as currently set. A selected issue's time anchor follows the
restored note; selection clears if that ID no longer exists. No seek occurs.

## Retention and boundaries

History holds at most 20 changes (21 snapshots), additionally limited to 8 MiB
of serialized UTF-16 notebook JSON payload. This is a history-payload bound,
not a browser total-memory guarantee. Oldest snapshots are evicted first, so a
large notebook may have fewer undo steps; the visible counts are authoritative.
The current state is retained. Reloading or closing the page loses all history;
only downloaded notebook JSON preserves the current notes. The notebook schema
and exact-media/plan binding remain unchanged, and history is not exported.

Any history move increments the local revision and invalidates loaded merge,
replacement and selective-revision previews, including unfinished asynchronous
file reads. Reload a file to review it against the restored state. History does
not restore old checkboxes or silently apply a pending import. Download warnings
remain conservative after history moves, even when the content happens to equal
an earlier download; no browser save completion is inferred.

This extends PRD MC-W04/MC-W05 local editorial feedback preparation and the
MOONCAST-B08 principle of retaining current edits. It does not implement graph
undo, immutable production lineage, hosted client identity or review acceptance.
The actual DOCX PRD keeps these larger release requirements separate.

## Focused checks

From this repository root with the existing Node runtime:

```sh
node --test scripts/test-screening-notebook.cjs scripts/test-screening-merge.cjs scripts/test-screening-triage.cjs scripts/test-screening-brief.cjs scripts/test-screening-revisions.cjs scripts/test-screening-history.cjs
node scripts/test-screening-repeat.cjs
```

Twelve new history journeys execute the literal production player JavaScript and
check its actual HTML controls. They cover local edits, merge conflicts,
replacement, selected revisions, branching, draft blocking, pending imports,
byte/step limits, selected anchors and real Blob-to-file reopening. The 60 prior
notebook tests and both repeat profiles are regressed. Retained roundtrip output
is printed; set `MOONCAST_EVIDENCE_DIR` to an existing directory to choose it.

DOM/media/download APIs are doubles. No MoonBit compilation, native exporter,
real browser/rendering/playback, accessibility device, provider or full-product
execution was performed. No dependency installation or network is required.
R50 remains the last fully verified cumulative checkpoint; R51–55 are separate.
