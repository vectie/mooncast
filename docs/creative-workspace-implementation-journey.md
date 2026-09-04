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
| Control flow risked becoming arbitrary scripting | Added bounded variants, map, rank/select, merge and policy semantics plus named human decisions. Reusable subgraphs expand an exact installed capsule version into a new parent-graph revision with mapped ports and parameters. |
| Agent changes could silently mutate work | MoonClaw-facing proposals contain a graph diff, providers, cost and approvals and apply only against the exact base revision. Agents cannot satisfy human gates. |
| Graph saves overwrote prior state | Every revision is stored immutably plus a latest pointer, with a history endpoint returning revisions in order. |
| Review-required generation looked like a human gate | External generation remains an operation owned by MoonFlow; only explicit review/approve/accept/decide tools become human gates. |
| Studio, Editor and Review felt disconnected | The Rabbita app now presents Graph, Editor and Review as persistent lenses with recipe/asset rail, canvas, inspector and run/activity drawer. |
| The provider recipe card was decorative | Recipe selection now switches the actual six-node canvas and inspector ownership between local concat and provider-backed delivery graphs. |
| The canvas was a static diagram | Nodes now support pointer dragging, keyboard nudging, typed connection editing, selectable/deletable edges, multi-select copy/paste/group, mute/bypass, auto-layout, zoom, overflow panning and durable revisioned positions. Asset cards bind the exact immutable artifact ID, version, digest, URI and kind. |
| Execution exposed only a whole-graph path | Recipe launch accepts public inputs and optional selected output nodes, freezes the exact plan, and creates one durable run. The UI exposes both full-recipe and run-through-selected-node actions. |
| Provider work could be mistaken for success when queued | External nodes create deterministic dispatch records. Only an imported receipt advances the dispatch/run; prepared or queued work never implies generation success. |
| Run progress was opaque | Every transition now appends a durable run event. SSE and JSON replay resume after an event id. The UI browses/reopens project run history and shows per-node attempts, errors, retries and outputs. |
| Assets lacked workspace actions | Project-scoped artifact APIs and UI actions now cover server-backed query/kind filters, pagination, multi-select comparison with retained results, tags, governed promotion, lineage-preserving branches and reference-checked soft deletion. Successful outputs are indexed as immutable workspace artifacts. |
| Recipes were not operational outside the graph | Capsules generated from successful runs and published versions are returned by the installable project catalogue, alongside built-ins, and render in simplified App view. |
| MoonClaw and MoonFlow were only architectural names | The workspace contains a bounded assistant journey for diagnosis and review-gated auto-layout/mute/bypass/repair proposals. MoonFlow remains the durable outbox/receipt boundary for separately deployed provider workers. |
| Creative artifact types all opened the same inspector | Script, storyboard/image comparison, timeline/media, review and delivery lenses are selected from declared artifact types and review semantics rather than hard-coded node IDs. |
| Collaboration was future-only | Durable comments, continuously renewed named presence leases, activity history, graph compare/fork, human-readable read-only client-review pages, cross-workspace search and run-to-template promotion now have typed contracts and service routes. Shares contain only token digests and never grant publication authority. |
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
| Saved graphs and user capsules were undiscoverable | Projects now list saved graphs, and promoted or published capsule versions re-enter the installable catalogue without replacing built-ins. |
| Runs stopped at queue/claim contracts | The native coordinator walks supported input, control, validation, project-envelope, delivery-envelope and registration nodes to quiescence, persists content-addressed outputs, and reports actionable blockers for provider, human or unavailable executors. |
| Client review links opened raw JSON | Secure links now open a token-validated, read-only HTML evidence page for graph, run or artifact targets. |
| Reusable subgraph nodes were only placeholders | The inspector loads all installable capsule versions and expands the selected exact version into durable child nodes and edges, rewiring public inputs/outputs and preserving graph history. |

## Verification evidence

- Workspace package includes pure tests for graph editing, artifact branching,
  comparison/promotion, capsule publication, collaboration and deterministic
  dispatch/SSE behavior.
- Studio service tests cover HTTP, immutable artifacts, graph revision history,
  recipe inputs and selected outputs, durable run transitions, receipts,
  collaboration, sharing, search and publishing.
- Rabbita workspace tests cover durable graph transforms, undo/redo, typed
  connections and exact-revision run requests.
- Studio service tests cover graph install/revision/run/cache, native graph
  walking, human decisions, scheduler claims, reconnect replay, asset
  indexing/tags/deletion, secure review pages, assistant proposals and
  exact-base proposal application.
- Workspace-domain tests cover validation, planning, diffs, artifacts,
  collaboration and provider dispatch (14 tests pass); Rabbita's focused
  workspace suite passes 11 tests.
- Integrated verification passes 68 native repository tests and 16 Rabbita
  tests. Both MoonBit projects check with zero warnings; the production Vite
  bundle and native release sidecar both build.
- Lepusa 0.1.6 strict macOS verification: native launch, bundle,
  release-readiness and package-readiness all pass with zero audit warnings.
- Native UI smoke: the rebuilt release renders the saved graph, 106 governed
  node definitions, typed ports, manifest-backed outcomes, structured
  parameters, collaboration identity and the workspace assistant in one state.

## Third-round feature comparison

The third comparison deliberately moves beyond foundation and hardening work.
It evaluates creator-visible feature depth: generation, transformation,
parameter controls, previews, templates, App Mode, asset discovery, editor
round-tripping and agentic iteration.

The detailed findings and prioritized roadmap are maintained in
[Third-iteration cfy feature comparison](cfy-feature-comparison-third-iteration.md).
The primary conclusion is that Mooncast should retain its high-level governed
production graph while adding a lower-level creative-compute graph inside
versioned Creative Capsules.

## Deliberate authority boundaries

The workspace does not fabricate external infrastructure. Presence is renewable
project state rather than a hosted identity service. Client-review pages are
revocable local capability views rather than internet deployment. Provider
dispatch remains pending until a real MoonFlow worker returns a receipt.
Capsule publication remains internal and never authorizes a third-party
destination. Public macOS signing and notarization still require
publisher-owned credentials.
