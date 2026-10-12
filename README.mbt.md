# MoonCast

> **Domain pack and studio · deterministic pipeline alpha.** Read the
> [product contract](docs/PRODUCT_CONTRACT.md) for the cut-editor boundary,
> provider truth, commercial acceptance and release gates.

Paid productions now enter through a pack-local commercial intake: qualified lead, immutable 3–8 minute quote, named commercial/production/client decisions, finite studio capacity, margin and founder-hour forecast, then exact quote-to-draft-project conversion. See [Contract, quote, capacity, and project intake](docs/contract-quote-capacity-intake.md). No CRM, email, payment, calendar, creative, delivery, or publication authority is inferred by this flow.

Studio also accepts a versioned MoonWiki needs/creative-strategy export. Exact
source identities are validated, approved by a named human, and bound to the
project brief, bible, and script without synthetic intent references. See
[MoonWiki needs and creative-strategy intake](docs/moonwiki-needs-intake.md).

Mooncast is an isolated MoonSuite domain pack for rights-aware AIGC production.
It turns a creative brief into generated assets, provenance,
review decisions, delivery packages, and optional reviewed publication.

The repository itself is an installable pack source:

```bash
moonbook pack inspect /path/to/mooncast
moonbook pack install /path/to/mooncast /path/to/workspace host-profile.json
```

Mooncast owns production policy and schemas. MoonLib, MoonBook, MoonClaw,
MoonDesk, and Moonstat only consume generic pack projections.

See [Responsibility and testability](docs/RESPONSIBILITY_AND_TESTABILITY.md)
for the executable ownership boundary and layered verification model.

Version 0.2 adds a systematic long-form production path alongside the original
12-second local preview: durable projects, episode/scene/shot plans, G0–G7
evidence gates, rights and bible locks, script/storyboard/animatic approval,
model routing, budget enforcement, immutable shot attempts, QC/editorial/client
review, 3–8 minute master composition, delivery packages, analytics, and
economics. The checked-in deterministic provider makes a real three-minute
H.264/AAC fixture with an embedded subtitle stream, visible AI labels, and full
shot-to-master SHA-256 lineage in seconds.

For an editable video-cut handoff, `transcript_reel export-edl` turns the same
ordered transcript recipe into a CMX3600 EDL plus source/reel mapping and exact
rounding details. Continue the cut in an NLE or the existing native EDL importer
without rendering first. See [transcript-to-EDL handoff](docs/transcript-edl-handoff.md).

For a portable editing folder, `project_collect` copies all native snapshot media,
preserves the editable timeline and lets you verify/reopen it after relocation.
See [collect an editable project](docs/project-collection.md).

For external ASS/SSA subtitles, `ass_captions` previews and imports dialogue
into editable plain captions, preserving the original styled source. See
[ASS/SSA caption import](docs/ass-captions.md).

For selectable captions in an actual MP4/MKV, `caption_media` appends a labelled
caption track and reopens a selected embedded track in the existing caption
editor. See [caption media interchange](docs/caption-media.md).

## Build and run the native production studio

```bash
npm --prefix ui/rabbita-mooncast install --no-audit --no-fund
npm --prefix ui/rabbita-mooncast run build
MOONCAST_RABBITA_DIST=ui/rabbita-mooncast/dist \
MOONCAST_DATA_ROOT=var/native \
MOONCAST_PORT=4302 \
moon run cmd/studio
```

Open <http://127.0.0.1:4302/apps/mooncast/studio>. The same native host serves
the editor, private client-review routes, typed APIs, range-capable media, and
the built Rabbita assets. Deployment must provide approved media tools and
provider configuration explicitly; the application does not download a
runtime or load a secondary application host.

Mooncast exposes exactly three product surfaces: Studio, Editor, and Client
Review. It does not ship or mount a Bookkeeper application. Final-deliverable
and outcome evidence is handed to MoonFlow for MoonBook's canonical Bookkeeper
and existing MoonBook Rabbita UI. The existing handoff outbox materializes an
inert, ordered Bookkeeper ingress bundle for MoonFlow; Mooncast retains only
outbound evidence, inert transfer values, and external receipt references.

For UI development, run the native host on port 8000 and the Rabbita Vite
server separately:

```bash
MOONCAST_RABBITA_DIST=ui/rabbita-mooncast/dist MOONCAST_PORT=8000 moon run cmd/studio
npm --prefix ui/rabbita-mooncast run dev
```

The studio accepts a rights-attested creative brief and produces a real local
H.264/AAC MP4. Each response includes its immutable video URL, SHA-256,
provider, model, prompt, bounded cost, rights, safety, explicit/implicit
labels, and human-review state. Approval is append-only and only makes an asset
eligible for a separate publishing adapter; this service does not publish.

The lower **Systematic long-form production** panel drives the complete v2
project lifecycle. It shows the G0–G7 rail, episode/scene/shot tree, rights,
provider and asset provenance, master evidence, budget, and economics after
every operation.

See [the endpoint contract](docs/local-studio-api.md) for request and response
details.

Cut Editor can import local Whisper JSON/TSV and Audacity region-label files as
timed caption overlays, alongside SRT and WebVTT. Original source bytes remain
bound to their rights receipts; native preview/export uses deterministic SRT
derivatives. See [local transcript import](docs/local-transcript-import.md).

## Validate

```bash
moon run cmd/pack_boundary
moon run cmd/manifest
moon check --target native --deny-warn
moon test --target native --deny-warn
npm --prefix ui/rabbita-mooncast run build
```

`cmd/pack_boundary` is the fail-closed MoonBit-native boundary scanner. It
verifies strict manifest structure, compiled-manifest parity, pack-owned
references, symlink containment, and forbidden cross-product imports. The
runtime, validation, installation, and CI paths are MoonBit/Rabbita-only. The
completed source cutover and promotion requirements are recorded under
`migrations/`.

For transcript-driven rough cuts, inspect/search numbered lines and select
spoken excerpts in playback order with the local `cmd/transcript_reel` utility.
It renders an MP4 with retimed captions and an edit-decision record. See
[transcript reel workflow](docs/transcript-reels.md).

For a rough cut combining several interviews or demonstrations, the
[multi-source transcript recipe](docs/multi-source-transcript-reels.md) preserves
ordered and repeated cue selections, fits an explicit letterboxed canvas and
normalizes audio/silent spans. It exports MP4, retimed SRT and content-bound
edit provenance without changing Studio or granting production approval.

To correct caption text and timing without rebuilding a reel, use the local
`cmd/caption_edit` utility. It supports editable JSON drafts, cue corrections,
split/merge, offset or two-point synchronization, and SRT/WebVTT export. See
[caption editing](docs/caption-editing.md).

For cuts-only interchange with another editor, use `cmd/edit_decisions` to
preview/import CMX3600 EDL into a native timeline draft and export it again.
See [edit-decision interchange](docs/edit-decision-interchange.md).

After a cut changes, use `cmd/caption_conform` to carry source captions through
reordered, repeated and trimmed clips. It exports synchronized SRT/WebVTT,
an editable caption draft and cue-to-source tracing. See
[caption conforming](docs/caption-conforming.md).

To add navigation chapters to an edited episode, use `cmd/chapters` to seed
markers from a chosen timeline track, rename/move/add/remove chapters, and
export chapter WebVTT, exact-clock FFmetadata and a reusable JSON draft. See
[timeline chapters](docs/timeline-chapters.md).

To turn existing captions into shorter lines or timed screens, use
`cmd/caption_layout` to preview word wrapping, optionally paginate with explicit
estimated timing, and export editable drafts plus SRT/WebVTT. Reading-speed
feedback and source-cue mappings support manual review. See
[caption layout](docs/caption-layout.md).

To edit many caption cues in a spreadsheet and bring the changes back, use
`cmd/caption_review`: export keyed multiline CSV, optionally preview differences,
then apply to a new draft with SRT/WebVTT outputs. See
[caption review sheets](docs/caption-review.md).

## Relink moved project media

Inventory a native editor snapshot, edit a source-bound media-ID/path map, and
verify every relocated file by SHA-256 and size before saving a separate native
snapshot. See [media relinking](docs/media-relinking.md). This offline utility
preserves the cut and media identities; it does not mutate the live Studio.

## Local chapter interchange

Existing FFmetadata chapters can be imported into an editable chapter draft,
then renamed, moved and exported. See [chapter import](docs/chapter-import.md).

## Carry chapters through a recut

Use the local `cmd/chapter_conform` workflow to carry source chapter titles
through trimmed, reordered and repeated video clips into an editable draft,
chapter WebVTT and FFmetadata. [Chapter conforming](docs/chapter-conforming.md)
explains explicit source bindings, exact clocks and the per-chapter trace.

## Embed chapters in playable media

Use `cmd/chapter_media` to preview an authored chapter draft, embed its chapters
in a new MP4/MKV without re-encoding existing video/audio/captions, and extract
embedded chapters back into an editable draft. See
[chaptered media interchange](docs/chapter-media.md).

## Offline visual cut review

Use `cmd/review_sheet` to export a portable contact sheet from actual local video:
real sampled frame images, timestamps, optional chapter titles and editable-draft
caption excerpts. Preview the intervals first, then open or print the generated
HTML. See [the visual review sheet guide](docs/visual-review-sheet.md) for exact
commands, supported media and recovery limits. This is local editorial aid;
client acceptance, publication and full-motion/audio review remain separate.

## Offline full-motion screening

Use `cmd/screening` to copy a local H.264/AAC MP4 into a portable player with
searchable click-to-seek captions, chapter navigation, caption toggle and playback
speed controls. Existing caption/chapter drafts remain editable alongside the
video. See [offline screening bundles](docs/offline-screening.md) for the bounded
media profile, relative-file layout, controls and local-review limits.

## Find navigation boundaries in unchaptered media

`cmd/scene_index` detects visual changes in a local video and exports editable
chapter suggestions with complete candidate scores and suppressed-boundary
explanations. Rename or move the markers with `chapters`, then use them in the
existing offline player. See [local scene indexing](docs/scene-index.md).

## Show two caption languages together

`cmd/bilingual_captions` combines independently timed caption drafts into one
editable track, preserving the exact active text at every input boundary.
Preview coverage, export both originals with SRT/WebVTT and source mappings,
then edit or embed the result using the existing caption tools. See
[bilingual caption composition](docs/bilingual-captions.md).
