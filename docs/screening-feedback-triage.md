# Work through a screening feedback queue

After combining reviewers' notebooks, an editor can now find related issues,
limit them to a scene's chapter, and work through matching concerns in timeline
order. This extends the existing offline screening and notebook workflow for
MC-W04 (editorial inspection) and MC-W05 (feedback tied to the exact master).
It does not establish hosted identity, client acceptance or commercial delivery.

## Use

1. Export a new screening with the existing `cmd/screening export` workflow in
   [offline-screening.md](offline-screening.md), then open `index.html`. An older
   export must be regenerated to receive these controls. Load or merge matching
   notebooks using [the existing preview-and-apply workflow](screening-review-notebook.md).
2. In **Editorial review notes**, choose **Open**, enter wording in **Find note
   text**, and optionally choose a **Chapter scope**. All three filters combine.
   The status shows matching rows, total notes, and total open notes. Search is a
   trimmed, case-insensitive literal substring of saved note text, not a regex,
   transcript search, ID search or linguistic/accent-normalized search.
3. Choose **Timeline order** for the list, or retain **Notebook order** to see
   original storage order. Ordering never rewrites the downloaded notebook.
4. Choose **Next matching issue** to begin at the earliest match. Each subsequent
   Next/Previous follows start time, breaking same-time ties by local integer ID.
   Clicking a row's time also selects that issue. The selected row is highlighted
   and the navigation status identifies its ID/time. Navigation never wraps; an
   unavailable direction is disabled. The initial Previous is disabled.
5. Use the existing **Edit note**, **Resolve issue** and **Reopen issue** actions.
   In Open view, resolving a selected issue removes its row but retains its
   navigation position, so Next advances to the following matching issue.
6. Download the notebook to keep changes. Check that the browser saved it.
   Filtering and navigation are temporary view settings, not saved content.

## Exact behavior

- A chapter spans its start up to (but excluding) the next chapter's start. A
  point at the media end belongs to the final chapter. A range appears in every
  chapter it overlaps with positive duration; touching the boundary alone does
  not count. A range crossing a chapter boundary is one issue, not duplicates.
  Jumping it seeks its original start, which can precede the selected chapter.
- A **Before first chapter** scope appears if the first chapter starts after
  zero. Chapterless screenings keep **All chapters** and remain fully usable.
  Chapter names are local labels, not semantic scene recognition.
- Search/status/chapter changes reset the navigation selection: Next starts at
  the earliest new match. List-order changes retain selection. An empty result
  disables both directions; clear the search and choose All/All chapters to
  restore the whole list. The playhead does not choose or reset the queue position.
- Row selection and Previous/Next seek through the existing player, stop range
  repeat, and never start playback. Playing media continues; paused media stays
  paused. Unloaded media uses the existing pending-metadata seek. Video duration
  limits and codec/seek failures remain visible through the playback status.
- Triage controls never save, resolve, rewrite or remove a note. Unsaved editor
  wording and its captured position remain intact, including when hidden by a
  filter. Pending notebook merge previews also remain valid. A saved content or
  status change still invalidates an import preview under the existing rules.
- Merging preserves queue selection and exposes incoming matches normally.
  Explicit notebook replacement clears selection as well as the existing editor
  draft. An explicit edit to a selected issue updates its navigation anchor.
- Download always contains every saved note in original notebook order, including
  hidden/resolved notes. It omits view settings and uncommitted drafts, retaining
  the existing exact media/plan binding and v1 format. There is no auto-storage,
  reviewer attribution, sending, or external acceptance action.

## Verification

From the repository root, using the existing Node runtime without dependencies:

```sh
node --test scripts/test-screening-notebook.cjs scripts/test-screening-merge.cjs scripts/test-screening-triage.cjs
node scripts/test-screening-repeat.cjs
```

The 11 triage tests execute the literal production embedded player JavaScript
and verify its HTML control wiring through the shared DOM/media/file/download
harness. They cover a merged-feedback→filtered queue→resolve→download→reopen
journey, equal-time issue ordering and no-wrap navigation, chapter intersections
and end points, chapterless cuts, combined literal Unicode search, frozen drafts,
pending merge previews, edits, repeat cancellation, paused/playing behavior,
unchanged full notebook serialization, replacement reset and metadata-delayed
seeking. The existing 28 notebook/merge tests and repeat-player regressions also
run. This is focused JavaScript functional evidence with API doubles: no MoonBit
compilation, native bundle generation, graphical browser, actual media decoding,
accessibility-device, provider or full-product qualification is claimed.

## Prepare a readable feedback handoff

Choose **Current triage matches** under **Readable feedback brief** to download
just the current queue as a standalone, print-friendly HTML report. The report
shows included/omitted counts, exact saved wording, local IDs, timecodes and
supplied context. **All saved notes** ignores the filters. Neither option changes
or saves the editable notebook. See [feedback briefs](screening-feedback-brief.md)
for the full workflow and limits.
