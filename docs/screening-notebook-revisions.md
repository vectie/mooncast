# Review selected notebook revisions

A producer who receives a deliberately revised copy of their screening notebook
can now apply only the issue changes they accept. Compare exact current and
incoming wording, time range and open/resolved status; choose individual
replacements or additions. Unselected issues and local notes absent from the
returned copy remain intact. This avoids manually retyping accepted changes,
duplicating every edited issue through a union merge, or replacing the whole
working notebook just to take one correction.

This extends the local editorial inspection and exact-cut feedback preparation
in MC-W04 and MC-W05 of the MoonCast PRD (30 September 2026). It supports the
stale-aware review principle of MOONCAST-B08 within the offline notebook. It does
not establish a graph repair, immutable production edit history, named editorial
approval, MOONCAST-B09 hosted client review, or MOONCAST-R02 delivery acceptance.

## Use

1. Export a fresh screening using the existing `cmd/screening export` procedure
   in [offline-screening.md](offline-screening.md), then open `index.html`.
   Previously exported folders must be regenerated to gain these controls.
2. Load your working notebook, or capture notes in the player. **Download
   notebook** before applying revisions to retain a recovery copy. Confirm the
   browser actually saved that file.
3. Under **Load notebook JSON**, choose one deliberately revised copy of that
   notebook, bound to this same media and screening plan. Select **Review
   selected notebook revisions**. Multiple-file selections retain the existing
   merge workflow but cannot open revision review.
4. Read **Choose notebook revisions**. Each proposal has full current/incoming
   wording, point or range timecodes and status. A missing local ID is an optional
   addition. Identical notes are counted, and current-only notes are counted as
   retained. All choices start unchecked.
5. Check only the changes you intend. Inspect the selected replacement/addition
   counts and resulting notebook size. **Apply selected revisions** is disabled
   until at least one proposal is selected and the selection is applicable.
6. If a selected existing issue is open in the note editor, application is held.
   **Cancel edit** deliberately discards that editor draft and enables application;
   **Save note changes** keeps your local work and invalidates the entire review,
   so load and review the incoming file again against the saved version. You can
   instead uncheck that issue and apply other proposals, retaining the draft.
7. Choose **Apply selected revisions**, then **Download notebook** to preserve
   the result. Reopen the download through the usual notebook import. This
   feature requests a local download; it does not automatically store or send it.

**Cancel revision review** closes the comparison and clears every checkbox, while
retaining the loaded file for the existing merge/replace choices. Opening review
again starts with no choices. **Cancel loaded notebooks** also discards the loaded
selection. No notes or editor drafts change on either cancellation.

## ID correspondence is a human decision

The v1 notebook has exact media/plan binding and local numeric note IDs. It has
no notebook UUID, author identity, common-ancestor proof, edit timestamp or
version lineage. Matching IDs merely suggest before/after candidates. A file
from an unrelated reviewer can reuse the same IDs for different issues, so read
both versions before accepting a replacement. For independent reviewer files,
use [the existing content-union merge](screening-review-notebook.md) instead.
Filenames do not authenticate a reviewer, and no latest-wins or status consensus
is inferred. The UI presents this warning next to the comparison.

- A selected replacement keeps its local ID and storage position, taking all
  four incoming editorial fields: start, end, exact text and resolved status.
  There is no field-by-field merge. Point/range conversion and reopening an
  issue are visible and require the same explicit choice.
- Selected additions preserve incoming IDs and append in incoming file order.
  These IDs are absent from the current notebook, so they remain unique.
  Additions are not deduplicated by wording; the preview states this. Choose
  the existing union merge when content deduplication is desired.
- Absent, identical and unchecked notes remain unchanged. There is no deletion
  proposal. An empty or identical returned file cannot erase current notes.
- No provenance, approval, acceptance, rights or publication fields are added.
  Resolved stays a local issue status. The resulting download uses the existing
  `mooncast.screening-notebook.v1` contract and unchanged exact-source binding.

## Current work and bounds

Every saved note edit, status change, new note, merge or replacement invalidates
loaded previews and revision selections. New file selections, cancelled loads
and superseded asynchronous reads cannot revive an earlier comparison. The
whole selection applies together against the still-current saved revision, or
nothing changes. Repeated application after success has no effect.

An unrelated existing-note draft or new-note draft keeps its wording and captured
anchor. Filters, list order, playback and the marked/repeating range are retained.
If the selected navigation issue moves, its queue anchor updates to the accepted
time without seeking. Review and application never start or stop playback and
never edit the video, captions, chapters or source JSON file. Previously saved
notebooks can be explicitly reloaded with the existing replacement flow to
recover the earlier session; the bounded [session Undo/Redo controls](screening-notebook-history.md) also restore saved notebook states. Downloaded files and editor drafts are outside that history.

The existing file validation still runs first: exact source match, at most 500
notes in the input, valid unique IDs, bounded note text and valid media times.
The single input is limited by the existing 64 MiB selection bound. A selection
that would exceed 500 current notes cannot apply. Deselect additions to stay
within the limit; replacements remain possible at full capacity. Comparison text
is complete and inert, including multiline Unicode and literal markup.

## Focused verification

From the repository root, using the existing Node runtime with no dependencies:

```sh
node --test scripts/test-screening-notebook.cjs scripts/test-screening-merge.cjs scripts/test-screening-triage.cjs scripts/test-screening-brief.cjs scripts/test-screening-revisions.cjs
node scripts/test-screening-repeat.cjs
```

The 12 revision tests execute every literal line of the production embedded
player and assert its actual HTML control wiring, along with the 48 existing
notebook/merge/triage/brief tests. They cover a returned-copy comparison,
per-issue selection, exact field replacement, additions, current-only retention,
a real Blob-to-file-to-reopened-notebook roundtrip, status reversals, media and
draft preservation, stale/cancelled reviews, selected editor collisions and the
500-note bound. Both existing repeat-player profiles are regressed separately.
The roundtrip notebook file is retained and its path printed. Set
`MOONCAST_EVIDENCE_DIR` to an existing evidence directory to retain it there;
otherwise a fresh directory under the operating system temporary folder is used.

DOM, media and file-picker/download APIs are test doubles. Real Blob
serialization and a local filesystem roundtrip are exercised. MoonBit
compilation, native bundle export, real browser rendering or playback,
accessibility-device operation, deployed identity, external clients, providers
and the full product were not exercised by this change. No dependency install,
network call or Moon command is required for the focused checks. R50 remains the
last fully verified cumulative product qualification; R51–55 remain separate.
