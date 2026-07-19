# MC-6A — Governed cut-editor workspace

> Superseded boundary note (2026-07-19): the production-cut handoff now adds a
> pack-local, rights-attested local media intake for voice, music, SFX,
> subtitles, images, and logos. It is content-addressed editor functionality,
> not provider generation or publication authority. The older “no
> upload/import system” exclusion below describes the original MC-6A slice only.
> Preview rendering is also superseded: accepted previews now use the real
> frozen timeline compositor at a bounded 640×360 review profile. The original
> deterministic placeholder description below applies only to the MC-6A slice.

Status: accepted for bounded pack-local implementation, 2026-07-16.

## Decision and user question

The single user question is: **“Can I assemble and review this governed project into a durable cut, then generate and inspect a deterministic local preview without gaining publication authority?”**

MC-6A keeps the existing Production tab and bundle and turns the Editor tab into one desktop-first workspace. It adds no server or HTTP interface: the accepted project-scoped editor endpoints already provide the complete required authority boundary.

## Inventory and reference limitation

Accepted authority is `EditorWorkspace` → `EditorKernel` → `EditorStore`, exposed by `EditorHTTPAPI` and the server’s validated preview-media route. Typed commands are defined by `schemas/editor-edit-command.schema.json`; preview authority and validation remain in the accepted store/worker/schema boundary. Relevant accepted tests cover editor UI/controller, HTTP routing and media ranges, kernel command/replay/history semantics, store persistence/recovery/preview authority, preview export/worker validation and tamper denial, production import, service, and v2 pipeline. The accepted full-suite baseline is 138/138; the pre-change focused UI/HTTP/kernel/store gate passed 51/51.

The requested read-only path `/Users/kq/Workspace/opencut` is absent. Only `/Users/kq/Workspace/.mooncode-inputs/opencut-classic-mc1` was inspected read-only, under its `AGENTS.md`, for interaction patterns and information architecture. Useful abstract patterns were a three-pane upper work area, a dedicated lower timeline, isolated panel scrolling, a duration/zoom-derived ruler, an explicit playhead, selection-driven properties, and visible timeline tools. No code, text, CSS, branding, assets, dependencies, identifiers, or implementation details will be copied, and neither reference directory will be modified.

## Information architecture

- Stable application bar: Production/Editor tabs, governed-project selector, revision and authority state.
- Left asset bin: search; media-kind, QC, rights, and placement/eligibility filters; keyboard-selectable take rows; one contextual add action and textual eligibility reason.
- Center program area: source/program mode switch, honest fixture state, real video surface, preview-job state, transport, and preview request/retry.
- Right inspector: selected clip identity, track/times/source range, take/media/intent, continuity, QC, provenance, rights, and time-ranged review comments.
- Bottom timeline: toolbar, zoom/fit, ruler, markers, fixed track headers, authoritative clips, playhead, trim handles, and confined horizontal scroll.
- Operational footer/live regions: loading, dirty, saved, empty/no-results, stale, conflict, error, preview status, deterministic/local statement, shortcut help, and publication-blocked statement.

At desktop widths the asset bin, preview, and inspector form a dense three-region row above the timeline. At narrower widths they stack in workflow order—assets, preview, timeline, inspector—without hiding primary actions. Only the timeline canvas scrolls horizontally; the page remains within 320 CSS pixels.

## Authoritative data flow

1. Opening a project increments an open-generation token and GETs the project read model followed by its snapshot.
2. The browser merges those two server responses into the displayed workspace. It may retain only ephemeral selection, filters, zoom, scroll, playhead, transport, and in-flight state. Derived flattened clip views are render-only and are never mutated, spliced, reordered, or persisted.
3. Every durable timeline edit POSTs one existing typed command with the current authoritative `expected_revision` and a fresh `idempotency_key`.
4. While a mutation is in flight, all conflicting mutation controls are disabled and dirty is announced. A successful response is accepted only for the same project/open generation; then the project and snapshot are re-read and the UI is replaced from current server authority. Saved is announced only after that reconcile.
5. A `409` announces conflict, reconciles the latest authority, and retains selection only if its identity still exists. Retry stores an operation descriptor, not a stale envelope; it rebuilds bounded payload and revision from the newly reconciled snapshot and uses a fresh idempotency key.
6. Review comments follow their existing endpoint with the same revision/idempotency discipline and are reconciled from the project read model. They do not alter timeline revision.

## Interaction and command mapping

| User action | Existing server operation | Bounded payload source |
| --- | --- | --- |
| Add selected take | `add` | Server-provided `add_clip_template` only; eligible iff approved, unplaced, and template present |
| Move left/right | `move` | Selected authoritative clip, same compatible track, bounded start tick |
| Move to track | `move` | Only when a compatible existing track is deterministically supported; otherwise omitted |
| Trim leading/trailing | `trim` | Selected authoritative clip; one committed button/pointer-safe step after validating source and duration bounds |
| Split | `split` | Actual media/playhead tick strictly inside the selected authoritative clip; fresh child IDs |
| Delete | `delete` | Selected authoritative clip ID |
| Undo/redo | `undo` / `redo` | Existing auditable command-log target semantics; no browser history reconstruction beyond deriving the current legal target |
| Add marker/comment | review-comments endpoint | Text plus bounded actual playhead range and current revision |

No command is optimistic. Space controls video play/pause; unmodified Left/Right step one project frame in preview/timeline context; `S` splits; Delete/Backspace deletes; Cmd/Ctrl-Z undoes; Cmd/Ctrl-Shift-Z redoes. Input, textarea, select, button editing, and contenteditable targets are guarded. Visible buttons remain available for every core keyboard action.

## Preview job and transport lifecycle

Program mode begins with an honest deterministic-fixture placeholder; source mode describes the selected take without pretending it is rendered media. Preview creation POSTs the existing preview-session contract using current project/timeline revisions and the authoritative timeline range. The controller records project ID, job ID, and preview-generation token, then polls only `/api/editor/projects/{project}/jobs/{job}`. Queued/running states are announced. Failed jobs expose the returned bounded failure and the existing retry endpoint only when retry is allowed. Succeeded jobs bind the same-project exact-job `/media` URL to the real `<video>`; no media URL is bound earlier. Older project/job/generation responses are ignored.

The `<video>` is transport authority after successful binding: play uses `video.play()` with promise rejection handling, pause uses `video.pause()`, scrub sets bounded `currentTime`, frame step uses project ticks-per-second as FPS, timeupdate/loadedmetadata/ended/error update the playhead and controls, mute remembers the previous nonzero volume, and volume stays in `[0,1]`. There is no timer-based simulated playback and no autoplay.

## Accessibility and responsive states

Semantic header/nav/main/aside/section landmarks and ordered headings define the workspace. Controls have programmatic names and labels; lists expose `aria-selected`, toggles expose `aria-pressed`, ranges expose values, jobs/status use polite live regions, and conflicts/media errors use assertive regions. Tab order follows visual order, focus is visibly outlined, selected/disabled/error/success states include text or iconography rather than color alone, and compact targets are at least 44px. Reduced-motion removes nonessential transition/scroll animation. Loading, empty fixture, no filter results, selected, disabled/ineligible, dirty, saved, conflict, preview queued/running/failed/succeeded, and media-unavailable states are explicit.

## Test plan

- Dependency-free controller tests: time/frame conversion; search/filter/no-results and keyboard selection; selection; zoom/fit; play/pause rejection; scrub/frame step; volume/mute; loadedmetadata/timeupdate/ended/error; stale preview/project suppression; queued/running/succeeded/failed/retry; exact media binding; typed add/move/trim/split/delete/undo/redo; split bounds; single-flight mutation; conflict reconcile and fresh retry; keyboard editing guard.
- Static tests: safe DOM construction and no `innerHTML`; same-origin project-scoped endpoints; no publisher/provider calls or controls; real video transport and no autoplay/timer simulation; accessible controls/live regions; visible trim handles; responsive 320px/global-overflow and isolated timeline-scroll rules; reduced motion; deterministic local/no-publication language.
- Live local journey through actual DOM handlers and exact HTTP calls: open → filter/select eligible take → add → select/move/trim → seek/split → undo/redo → add review marker → request/poll preview → bind validated media → transport → restart → confirm durable edits and comment. Exercise ineligible/no-results, failure/retry, missing media, conflict/stale response, and keyboard guards. Use only the resolved local ffmpeg/ffprobe pair.
- Gates after material slices: expanded UI/controller, HTTP, kernel, store, preview worker/export/adapter, focused editor modules, complete native test discovery, JSON parsing, whitespace/conflict/final-newline checks, frozen SHA-256 verification, `git diff --check`, process check, and explicit `errors/4` absence.

## Non-goals and boundaries

This is not a general MoonSuite-core editor, autonomous agent, publisher, provider client, upload/import system, waveform compositor, effect editor, or replacement timeline model. No publication call, adapter, endpoint, URL, control, receipt, or authority is added. Preview is deterministic and local; publication remains blocked. Existing frozen worker, workspace, store, store tests, preview-authority schema, kernel, and HTTP files remain byte-identical.

The fixture is intentionally bounded: it supplies deterministic generated takes, one role-compatible track per media role, fixed 1000 ticks-per-second timing, QC/rights values, lineage, annotations, comments, and delivery intents. It supplies no thumbnails, real source-view media, natural media names, codecs for each take, variable source durations, rejected QC/rights take, or general compatible-track graph. The UI therefore presents honest identity-based source placeholders, derives media kind from role/track, treats duration as known only when supplied, explains eligibility from available fields, and does not invent cross-track moves or unsupported metadata. Negative ineligible fixtures are controller-test inputs only unless already present in accepted server data.

## No-publication boundary

All editor fetches must begin with same-origin `/api/editor`; static and dynamic tests reject publisher/provider/network/destination routes or controls. The workspace states “Deterministic local preview” and “Publication blocked.” Preview requests contain only the accepted session fields, and bound media is the validated exact-job local route. Production remains separately available and unchanged; MC-6A introduces no publication capability anywhere.
