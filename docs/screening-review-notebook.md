# Timecoded editorial review notebooks

The existing offline screening player now lets an editor keep a working list of
issues while watching a cut. Capture a precise point or the existing A–B range,
write a note, revisit its timestamp, revise its wording and resolve/reopen it.
Download the notebook and load it into the same screening later to continue, or
combine matching notebooks from several reviewers through a previewed merge.
This closes the local inspection-to-feedback loop described by MC-W04/MC-W05
and supports the local preparation portion of MOONCAST-R02. It does not complete
the PRD's separately hosted identity, external review or acceptance requirements.

## Use the player

1. Create a new bundle through the existing `cmd/screening export` workflow in
   [offline-screening.md](offline-screening.md), then open its `index.html`.
   Previously exported folders do not automatically receive new controls.
2. Seek to the issue and click **Capture current position** before typing. The
   captured time stays fixed while playback or typing continues. For a span,
   first mark A and B with the existing review-range controls, then choose
   **Use marked A–B range**. Later changes to A/B do not alter a saved note.
3. Enter the note and choose **Add note**. Notes appear in creation order. The
   time button seeks to their start without starting paused playback; it turns
   off any active repeat range. The note is an editorial reference, not a cut.
4. Choose **Edit note**, correct its text and/or capture a different point/range,
   then **Save note changes**. **Cancel edit** discards only the editor draft.
   **Resolve issue** and **Reopen issue** change the local issue status. Use the
   All/Open/Resolved filter to work through remaining feedback. There is no
   deletion action; mistaken notes can be corrected or resolved.
5. Choose **Download notebook**. Check your browser actually saved
   `screening-notes.json`. The page can observe a download request, not whether a
   file reached your disk. A download includes saved notes, not uncommitted text
   in the editor. There is no automatic storage; closing/reloading the page
   loses notes that have not been downloaded.
6. On the matching screening, choose **Load notebook JSON (up to 10 files)**.
   Loading validates every selected file and previews its proposed changes
   without applying anything. Use the merge workflow below to combine feedback.
   When exactly one file is selected, **Replace current notebook** remains
   available: this replaces all current notes and uncommitted editor text.
   Download your current notebook first if you need to restore it later.

A newly added or revised note, or an issue-status change, invalidates a pending
load or merge preview. A later file selection supersedes an earlier in-progress read. Bad JSON,
invalid notes, stale reads and wrong-source notebooks leave current notes intact.
An empty matching notebook is allowed, but still needs the explicit replacement
button. You can load a previously downloaded notebook again to restore it.

## Combine feedback from several reviewers

1. Download the current notebook as a restore point. Select one to ten matching
   notebook JSON files using the existing load control. File selection order is
   the merge order; files are not sorted by their name or assumed author.
2. Read the preview counts: proposed additions, exact duplicates skipped,
   differing-status additions and same-ID content conflicts. Open **Inspect
   selected files and proposed additions** to see filenames with selection
   numbers, explicit ID conflicts, source and proposed local IDs, timestamps,
   open/resolved status and full text for each addition. Saved note rows also
   show their local IDs so conflicts can be cross-referenced. Filenames are local labels, not authenticated identities.
3. Choose **Merge into current notebook**. All current saved notes retain their
   IDs, order and contents. New distinct notes append in selected-file/note order
   with fresh local IDs. Any text, point/range anchor and in-progress edit in the
   editor remain intact, including a draft typed after the preview. Merge does
   not start playback, seek, resolve a note or clear the issue filter. If the
   current filter hides imported notes, select All to inspect the combined list.
4. Download the combined notebook, check it was saved, and continue with the
   existing jump/edit/resolve controls. Reopening uses the same v1 file contract;
   no new service, account or file format is required.

**Cancel loaded notebooks** discards only the preview (or pending file read).
Closing the file picker without choosing a file clears the pending selection
when the browser emits a change event; if it preserves the selection, use the
explicit Cancel button. Cancellation never modifies current saved notes or the
editor draft. The bounded [session Undo/Redo controls](screening-notebook-history.md)
can restore saved notebook states, including a merge. There is no automatic backup;
closing the page loses this history. To restore a downloaded notebook later,
load it and explicitly replace the current notebook; this also
clears the current editor draft. Replacement is disabled for multiple files so
it cannot silently choose one reviewer.

### Duplicate and conflict rules

- A note's integer ID is local to its notebook. Two reviewers may both have note
  `1`. If an incoming ID also occurs in current or earlier selected notes with
  different time, text or issue status, the preview names that as an **ID
  conflict** and identifies the files/IDs involved. Merge keeps both distinct
  contents and allocates a new local ID to each actual addition. It never chooses
  a winning reviewer, newer revision or majority status.
- Exact equality means the same start time, end time (including point versus
  range), text and resolved flag. Incoming exact duplicates of an existing or
  earlier incoming note are coalesced regardless of their IDs. The number of
  incoming duplicates skipped is shown; existing duplicate notes are never
  removed. Matching text is exact, including whitespace and Unicode code units.
- Same wording/time with different open/resolved status remains two separate
  notes, so an open concern is not silently resolved. Different text or timing
  remains separate too. A reused-ID conflict can itself be an exact duplicate of
  another note already present: the preview says it will coalesce that exact
  content while retaining both distinct contents involved in the conflict.
- Merging an unchanged file again adds nothing. After you edit or resolve a note,
  an older reviewer file can reintroduce its older content/status as a separate
  note. This is a content union, not a version-history reconciliation service.
  Resolve/rewrite the separate notes deliberately using the existing controls.
- The combined file stores the same local issue fields as before. It does not
  retain reviewer attribution or a merge audit trail; keep original reviewer
  files if provenance is needed. Coalescing identical comments is not evidence
  of reviewer count, consensus, client acceptance or external authority.

Every file must have the exact same media digest and screening-plan string.
One wrong-cut, malformed or unreadable file rejects the entire selection;
no valid prefix is applied. Each input retains the 500-note limit and unique IDs
within that file. The combined result must also fit 500 notes after deduplication,
otherwise Merge is disabled without dropping notes. Use smaller selections or
keep separate notebooks; resolving a note does not remove it from that bound.
For an over-capacity preview only the first 500 additions are listed and the
preview explicitly says it cannot be applied. The selection is limited to ten
files and 64 MiB total input bytes before reading. Single-file replacement remains
possible when that file is valid, even if a merge would exceed capacity.

## What identifies the cut

`mooncast.screening-notebook.v1` contains the media SHA-256 recorded by the
existing screening exporter, the exact `JSON.stringify` representation of its
embedded screening plan, and the notes. Thus a different media digest, title,
duration, caption text/timing or chapter plan cannot be loaded accidentally into
this notebook. Equivalent plans serialized with different key order are not
promised interchangeable. Moving the entire bundle does not change the binding.

The full plan is included rather than a second browser-computed digest so this
works offline without a secure-context hashing service. A notebook consequently
contains the screening title, supplied captions and chapters as well as feedback.
Handle it with the same care as the screening folder. Downloading does not share
it with anyone; this feature has no network calls or storage service.

The hash is the exporter's recorded media identity. The player does not rehash
`media.mp4`, authenticate the author, sign notes, or detect tampering with a copied
folder. If someone replaces the media after export, regenerate the bundle using
the existing exporter and use a notebook for that new cut. A supplied note or a
resolved issue never means client acceptance, QC approval, rights clearance,
delivery, payment or publication permission.

## Bounds and failure behavior

- At most 500 notes, each 1–2000 UTF-16 code units of nonblank text without NUL.
  Multiline Unicode and literal markup characters are retained as inert text.
- Millisecond integer times inside the declared media duration; point notes may
  mark the media end. Range end must follow start. Timestamps are inspection aids,
  not frame-accurate editing decisions.
- Notebook input/output is bounded to 64 MiB because the exact screening plan is
  embedded; ordinary note sets are much smaller. Larger or unreadable inputs are
  rejected before application. Existing notes remain available if a download
  fails; resolve the browser limitation before closing the page.
- Source binding must match before replacement or merge. Import does not edit the video,
  captions, chapters, bundle manifest, source project or original JSON file.
- JavaScript, file selection, Blob/object URLs and browser download support are
  needed. Browser download policy may prompt, block or rename the output. The
  native video, readable transcript and original sidecar downloads are unchanged.

## Focused executable checks

From the repository root, with the existing Node runtime and no dependencies:

```sh
node --test scripts/test-screening-notebook.cjs scripts/test-screening-merge.cjs
node scripts/test-screening-repeat.cjs
```

The 12 existing notebook tests and 16 merge tests share a harness that extracts
every literal line of the exact production `player_script` and verifies its
connection to the actual HTML controls. The notebook regressions cover
capture/edit/cancel/jump, frozen range notes, resolve/reopen/filter, actual Blob
serialization and a reopened session, wrong-cut rejection, partial read ordering,
malformed input preservation, maximum capacity and download failure. The existing
repeat and playback controls are separately regressed. Merge checks cover the
multi-reviewer preview/apply/download/reopen workflow, explicit ID conflicts,
exact duplicates and reimports, status variants, saved notes and editor-draft
preservation, cancellation and stale selections, all-or-nothing batches, combined
capacity, ten-file/total-byte bounds, inert text, and restore by replacement.

These are production JavaScript executions using DOM/media/file/download API
doubles. MoonBit compilation, native bundle generation, a real browser engine,
codec playback, accessibility devices, external clients and commercial outcomes
were not executed for this addition. It is not a full-product qualification.

## Work through a larger notebook

Use [screening feedback triage](screening-feedback-triage.md) to combine text,
status and chapter filters, switch the list to timeline order and navigate
matching issues without losing an unsaved draft. The default list still uses
notebook order; exports always retain all saved notes regardless of filters.

## Read or print a feedback brief

Use [readable feedback briefs](screening-feedback-brief.md) to download a
standalone timecoded report of saved issues and supplied chapter/caption context.
Select all notes or just current triage matches; scope and omissions are explicit.
This reading copy does not replace downloading the full editable notebook.

## Accept selected changes from a revised copy

For a deliberately revised copy of your current notebook, use
[selected notebook revision review](screening-notebook-revisions.md). Compare
full current/incoming time, wording and status, then choose each replacement or
addition you want. Unselected and current-only notes stay intact. Local IDs are
only correspondence candidates; independent reviewer notebooks should still use
the content-union merge. This is an explicit editing choice, not automatic
version-history reconciliation or proof of authorship.
