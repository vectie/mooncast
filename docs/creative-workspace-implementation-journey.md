# Creative workspace implementation journey

Status: implemented operational workspace beta, 2026-09-04

## Goal

Turn Mooncast from a collection of pack tools, Studio tabs and editor drawers
into one governed creative-workspace model inspired by cfy/ComfyUI: visual
composition, typed connections, inspectable execution, reusable recipes and
asset provenance, without importing arbitrary-code nodes or weakening
Mooncast's rights and review rules.

## Problems found and resolutions

| Problem | Resolution |
| --- | --- |
| No shared workflow domain | Added a public MoonBit workspace façade with graphs, typed ports, plans, runs, attempts, artifacts, capsules and agent proposals. |
| A second node registry could drift from the pack | Node definitions are projected from the compiled pack manifest; safe workspace/control built-ins are the only additions. |
| Invalid edges failed too late | Editing and validation reject unknown nodes/ports, duplicate identities, cardinality violations, incompatible artifact kinds and cycles. |
| Re-running could repeat expensive work | Frozen selected-output plans embed the exact graph and use content-addressed cache keys covering graph inputs, tool definitions, policy, provider, model and upstream output digests. |
| Jobs were fragmented by feature | A durable run record projects every planned node, attempt, retry, progress value, cache hit and restart recovery. |
| Results were files rather than creative assets | Workspace artifacts are immutable versions with preview URI, digest, parents, producing graph/run/node, prompt, provider receipt, rights, QC, cost, duration and annotations. |
| Recipes had no reusable contract | Creative Capsules declare public ports, exposed parameters, constraints, examples, compatibility and immutable source graphs; installation creates a new project-owned lineage. |
| Control flow risked becoming arbitrary scripting | Added only bounded variants, map, rank/select, merge, policy, human-approval and subgraph primitives. |
| Agent changes could silently mutate work | MoonClaw-facing proposals contain a graph diff, providers, cost and approvals and apply only against the exact base revision. Agents cannot satisfy human gates. |
| Graph saves overwrote prior state | Every revision is stored immutably plus a latest pointer, with a history endpoint returning revisions in order. |
| Review-required generation looked like a human gate | External generation remains an operation owned by MoonFlow; only explicit review/approve/accept/decide tools become human gates. |
| Studio, Editor and Review felt disconnected | The Rabbita app now presents Graph, Editor and Review as persistent lenses with recipe/asset rail, canvas, inspector and run/activity drawer. |
| The provider recipe card was decorative | Recipe selection now switches the actual six-node canvas and inspector ownership between local concat and provider-backed delivery graphs. |
| The canvas was a static diagram | Nodes now support pointer dragging, keyboard nudging, typed connection editing, zoom, overflow panning and durable revisioned positions. Asset cards support both HTML drag/drop and an accessible add-to-graph action. |
| Execution exposed only a whole-graph path | Recipe launch accepts public inputs and optional selected output nodes, freezes the exact plan, and creates one durable run. The UI exposes both full-recipe and run-through-selected-node actions. |
| Provider work could be mistaken for success when queued | External nodes create deterministic dispatch records. Only an imported receipt advances the dispatch/run; prepared or queued work never implies generation success. |
| Run progress was opaque | Every transition now appends a durable run event. SSE and JSON replay resume after an event id, while the MoonBit UI explicitly replays unseen events. Events carry the complete per-node durable run projection. |
| Assets lacked workspace actions | Project-scoped artifact APIs and UI actions now cover indexed search/pagination, multi-select comparison, tags, governed promotion, lineage-preserving branches and reference-checked soft deletion. Successful local concat outputs are registered as immutable workspace artifacts. |
| Recipes were not operational outside the graph | Capsules can be generated from validated graphs, published immutably to a project/workspace catalogue, rendered in simplified App view, and promoted from successful runs. |
| MoonClaw and MoonFlow were only architectural names | The loopback MoonClaw tool surface can inspect, propose, compare, fork, run, dispatch and promote workspace work. MoonFlow integration is a durable outbox/receipt boundary and does not embed another runtime. |
| Creative artifact types all opened the same inspector | Script, storyboard/image comparison, audio/transcript, timeline/media, review and delivery lenses now render contextual controls from the same selected graph node. |
| Collaboration was future-only | Durable comments, server-timed renewable presence leases, activity history, graph compare/fork, read-only or client-review shares, cross-workspace search and run-to-template promotion now have typed contracts and service routes. The UI displays active collaborators and selected-node comments. Shares contain only token digests and never grant publication authority. |
| Desktop packaging could omit the new surface | Rebuilt the Rabbita release and validated the unchanged least-authority Lepusa bundle contract. |

## Second-round cfy comparison and fixes

The second pass compared Mooncast's working implementation, not only its
screens, with cfy's graph lifecycle, queue/history behavior, cache strategy,
asset discovery and extension ergonomics. Mooncast keeps its governed pack
boundary, but now closes the practical workspace gaps found in that pass.

| Gap found in the second pass | Implemented resolution |
| --- | --- |
| The UI edited an ephemeral projection and launch rebuilt a catalog recipe | Capsule installation loads one durable graph. Add, delete, duplicate, collapse, move, connect and parameter edits update that graph; save uses optimistic revision checks; launch freezes exactly the saved revision. |
| The node browser was a hard-coded recipe list | The palette is generated from the governed pack catalog, supports search, exposes type/authority/owner metadata and can create any catalog definition without arbitrary code loading. |
| Cache keys existed but runs did not discover prior outputs | Run creation scans durable cache records and marks exact matching nodes as cached. Successful direct commands and imported dispatch receipts update the cache. |
| There was no worker-friendly scheduler contract | Runs can be listed with pagination and state filters. A worker can atomically claim the next ready node matching its execution owner; cancel and retry are server-timed actions. |
| The SSE route synthesized only the latest state | Run creation and every transition persist immutable reconnect events. Consumers can request SSE or JSON replay after their last event id. |
| The asset rail showed upload staging rather than workspace assets | Immutable artifacts are indexed separately with tags, query/kind/tag filters, pagination and soft deletion. Hiding is rejected while an active graph or share references the asset. |
| Compare used the same artifact twice and specialized editors showed fake variants | The UI requires two distinct selected assets and renders their real digests. Delivery inspection reads the selected artifact's real rights/QC state; decorative pending variants and waveform claims were removed. |
| Agent proposals had no usable review/apply journey | A review endpoint calculates the exact graph diff and stale status. The UI shows node/edge counts and applies only the stored proposal to its stored base revision, then marks it applied. |
| Browser-generated share secrets and timestamps were forgeable | The native host now generates share ids, secrets and expiry, stores only a single SHA-256 digest, returns the token once, validates expiry/access and supports revocation. This pass also caught and fixed a double `sha256:` prefix defect. |
| Browser-generated comment ids and presence expiry were forgeable | The native host now generates comment ids/timestamps and presence lease expiry. Expired leases are filtered from collaboration projection. |
| Graph editing lacked recovery ergonomics | Revision-local undo/redo, delete, duplicate, collapse, keyboard save/undo/redo/duplicate/delete and generic versioned parameter editing are available. |
| Workspace logic kept growing inside existing monoliths | New graph-runtime, asset-library, collaboration and run-operation responsibilities live in separate MoonBit files; UI graph-state transformations and views are separated from transport/event handling. No non-MoonBit automation was introduced. |
| Desktop release could drift from the host contract | The Lepusa 0.1.6-verified contract remains the release source of truth: fixed loopback origin, supervised native sidecar, health check, Rabbita/static resources, bundled ffmpeg/ffprobe and only localhost/file-dialog grants. cfy itself has no Lepusa manifest to copy. |

## Verification evidence

- Workspace package includes pure tests for graph editing, artifact branching,
  comparison/promotion, capsule publication, collaboration and deterministic
  dispatch/SSE behavior.
- Studio service tests cover HTTP, immutable artifacts, graph revision history,
  recipe inputs and selected outputs, durable run transitions, receipts,
  collaboration, sharing, search and publishing.
- Rabbita workspace tests cover durable graph transforms, undo/redo, typed
  connections and exact-revision run requests.
- Studio service tests cover graph install/revision/run/cache, scheduler claims,
  reconnect replay, asset indexing/tags/deletion, secure shares and exact-base
  proposal application (7 focused tests pass).
- Workspace-domain tests cover validation, planning, diffs, artifacts,
  collaboration and provider dispatch (14 tests pass); Rabbita's focused
  workspace suite passes 7 tests.
- Integrated verification passes 66 native repository tests and 12 Rabbita
  tests; the production Vite bundle and native release sidecar both build.
- Lepusa 0.1.6 strict macOS verification: native launch, bundle,
  release-readiness and package-readiness all pass with zero audit warnings.
- Native UI smoke: both recipes switch visibly; the provider graph shows
  MoonFlow ownership, and the Review lens remains backed by the same app state.

## Deliberate authority boundaries

The workspace feature set is present, but it does not fabricate external
infrastructure. Presence is renewable project state rather than a hosted
identity service. Client-review shares are revocable capability records rather
than internet deployment. Provider dispatch remains pending until a real
MoonFlow worker returns a receipt. Capsule publication publishes inside the
workspace catalogue and never authorizes a third-party destination. Those are
intentional least-authority boundaries, not missing workspace behavior.
