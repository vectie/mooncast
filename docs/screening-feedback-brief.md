# Readable screening feedback briefs

A producer can turn saved screening feedback into a standalone reading and
printing copy. An editor no longer has to interpret notebook JSON or open the
whole video folder to read a timecoded change list. Export every saved note, or
use the existing triage controls to prepare a focused list for one chapter,
issue status or phrase. The downloaded HTML includes supplied caption/chapter
context, so a recipient can understand which moment a note refers to.

This supports the local inspection and feedback-preparation parts of MC-W04 and
MC-W05. It does not provide the hosted identity, access controls or client
acceptance required by MOONCAST-B09 or complete MOONCAST-R02 delivery.

## Use

1. Export a fresh screening using the existing `cmd/screening export` workflow
   in [offline-screening.md](offline-screening.md), then open `index.html`.
   Older exports must be regenerated to receive the new controls.
2. Add, load or merge [review notebooks](screening-review-notebook.md). Save any
   editor draft you want included. The brief uses saved notes only.
3. Optionally use [feedback triage](screening-feedback-triage.md) to select issue
   status, note text and chapter. In **Readable feedback brief**, choose
   **Current triage matches** (the default) or **All saved notes**.
4. Read the included/omitted counts. Choose **Download feedback brief (HTML)**.
   An empty scope disables the button. All-saved scope ignores triage filters.
5. Check that the browser saved `screening-feedback.html`. Open that file to
   read it without the screening folder, JavaScript, media or a server. Use
   the browser's Print command for paper or a PDF. Download policy, printing
   and actual browser rendering need separate device qualification.
6. Download the full notebook JSON separately to resume editing later. A brief
   is a reading snapshot, cannot be imported as a notebook and does not mark
   the session's notebook changes as saved. No files are sent anywhere.

## What the brief contains

- Screening title, millisecond duration and the exporter's recorded media
  SHA-256. The exact source video can be identified without copying its bytes
  into the report. This is a recorded identifier, not a fresh media hash check,
  signed proof, or authentication of an altered screening folder.
- The selected scope and, for current matches, the effective status, chapter
  and trimmed literal note-text filter. Included, omitted, open and resolved
  counts make a partial report explicit. Status counts describe included notes.
- Every selected note's local ID, full saved wording, point/range timecodes and
  open/resolved state. Entries always use timeline order, breaking ties by local
  integer ID. Export never reorders the stored notebook or changes the list view.
- Supplied chapter labels and timestamped caption excerpts intersecting each
  note. Context is from the currently embedded screening plan, not inferred
  speech, recognized scenes or independently verified editorial alignment.

A point uses a half-open interval: a cue ending exactly at the point is excluded,
and one starting there is included. A point at the media end belongs to the final
chapter but has no active caption ending there. Range context requires positive
intersection; touching an endpoint alone does not count. Before-first-chapter
context is labeled explicitly. Missing sidecars and caption gaps remain explicit.
An issue spanning a chapter boundary keeps its original full time range.

Context is bounded to the first 12 overlapping chapter labels and first 8
caption cues in supplied order, each excerpt limited to 600 Unicode code points.
Shortened excerpts and omitted counts are visible. Note text, timestamps, local
IDs and status are never shortened. The complete transcript and screening plan
are not embedded; only intersecting context is copied. The output is limited to
16 MiB; a failed download leaves all current work intact. Split a large report
using triage or use the notebook if it exceeds this bound.

## Snapshot and authority limits

The report contains no media or live links and never updates after download.
Saved edits, status changes or merges appear only in a newly exported brief.
Existing notebook order, unsaved text/anchor, playback, repeat range, queue
selection, filters and pending import previews remain unchanged by export.
Repeated exports request a new download; the browser may rename or block it.
The page can observe a download request, not successful storage on disk.

IDs are local notebook references. The existing merge assigns new local IDs to
incoming additions and does not retain reviewer identity, so neither the brief
nor a filename establishes authorship, consensus or acceptance. Keep original
reviewer files when provenance matters. A resolved note is a local editorial
status, never client acceptance, rights clearance, technical QC approval, a
delivery receipt, payment evidence or publication authority.

Text is escaped into a script-free, self-contained HTML document with a print
stylesheet. Treat the file as private editorial material: it includes selected
feedback, title, source digest and supplied context. It has no access control,
expiry, encryption or secure-sharing service. Sharing and recipient access
verification are separate actions.

## Focused executable verification

From the repository root using the existing Node runtime without dependencies:

```sh
node --test scripts/test-screening-notebook.cjs scripts/test-screening-merge.cjs scripts/test-screening-triage.cjs scripts/test-screening-brief.cjs
node scripts/test-screening-repeat.cjs
```

Nine new brief tests execute every literal line of the actual production player
script through the shared DOM/media/file/download API harness and verify real
HTML control wiring. They cover merged feedback to a filtered readable report,
local file write/reopen, full-notebook reopening, all-saved scope and stable
ordering, point/range boundaries, missing context and empty selection, literal
markup/Unicode/multiline text, visible excerpt bounds, saved-vs-draft behavior,
merge-preview/playback/queue preservation, subsequent exports and download
failure. Existing 39 notebook/merge/triage tests and both repeat-player profiles
also pass. Tests use actual Blob serialization with API doubles; they do not
qualify MoonBit compilation, native screening export, a graphical browser, print
layout, media decoding, accessibility devices, external clients, providers,
commercial delivery or the full product. No dependencies or Moon commands are
needed for this focused lane. R50 remains the last fully verified cumulative
product qualification; R51–55 remain separate.
