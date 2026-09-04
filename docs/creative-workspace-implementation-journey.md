# Creative workspace implementation journey

Status: implemented beta foundation, 2026-09-04

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
| The canvas was a static diagram | Nodes now support pointer dragging, keyboard nudging, typed connection editing, zoom, overflow panning and persisted positions for the active session. Asset cards support both HTML drag/drop and an accessible add-to-graph action. |
| Execution exposed only a whole-graph path | Recipe launch accepts public inputs and optional selected output nodes, freezes the exact plan, and creates one durable run. The UI exposes both full-recipe and run-through-selected-node actions. |
| Provider work could be mistaken for success when queued | External nodes create deterministic dispatch records. Only an imported receipt advances the dispatch/run; prepared or queued work never implies generation success. |
| Run progress was opaque | Every run has an SSE snapshot endpoint with one-second reconnect guidance, plus the MoonBit UI's one-second snapshot fallback. Events carry the complete per-node durable run projection. |
| Assets lacked workspace actions | Project-scoped artifact APIs and UI actions now cover drop-to-graph, comparison, governed promotion and lineage-preserving branches. Successful local concat outputs are registered as immutable workspace artifacts. |
| Recipes were not operational outside the graph | Capsules can be generated from validated graphs, published immutably to a project/workspace catalogue, rendered in simplified App view, and promoted from successful runs. |
| MoonClaw and MoonFlow were only architectural names | The loopback MoonClaw tool surface can inspect, propose, compare, fork, run, dispatch and promote workspace work. MoonFlow integration is a durable outbox/receipt boundary and does not embed another runtime. |
| Creative artifact types all opened the same inspector | Script, storyboard/image comparison, audio/transcript, timeline/media, review and delivery lenses now render contextual controls from the same selected graph node. |
| Collaboration was future-only | Durable comments, renewable presence leases, activity history, graph compare/fork, read-only or client-review shares, cross-workspace search and run-to-template promotion now have typed contracts and service routes. Shares contain only token digests and never grant publication authority. |
| Desktop packaging could omit the new surface | Rebuilt the Rabbita release and validated the unchanged least-authority Lepusa bundle contract. |

## Verification evidence

- Workspace package includes pure tests for graph editing, artifact branching,
  comparison/promotion, capsule publication, collaboration and deterministic
  dispatch/SSE behavior.
- Studio service tests cover HTTP, immutable artifacts, graph revision history,
  recipe inputs and selected outputs, durable run transitions, receipts,
  collaboration, sharing, search and publishing.
- Rabbita app: 9 MoonBit tests pass and the production Vite bundle builds.
- Repository suite: all 62 MoonBit tests pass after the integrated workspace
  changes.
- Lepusa 0.1.4 strict macOS verification: native launch, bundle,
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
