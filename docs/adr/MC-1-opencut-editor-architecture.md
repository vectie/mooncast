# ADR MC-1: OpenCut-informed editor architecture for Mooncast

- **Status:** Proposed; architecture decision only
- **Date:** 2026-07-16
- **Work order:** MC-1
- **Decision scope:** documentation and planning; no broad editor implementation is authorized
- **Evidence pins:** OpenCut rewrite `bab8af831b354a0b5a98a4a6e818ab7d633b94df`; OpenCut Classic `cf5e79e919144200294fb9fed22a222592a0aeea`

## 1. Decision

Mooncast will use a **clean-room, pack-owned editor implementation informed by OpenCut Classic's implemented patterns**. Mooncast will own its project, timeline, media, AIGC, preview, persistence, and export concepts and contracts. OpenCut is a reference, not a runtime dependency or domain owner.

Small, well-bounded Classic routines may later be selectively ported only when a work order demonstrates that this is safer than reimplementation. Every copied or substantially adapted fragment must carry file-level provenance and the applicable MIT notice. No whole application copy, fork, embed, or extraction is approved by MC-1.

This is the lowest-risk option because it combines an implemented reference with Mooncast-controlled boundaries, avoids coupling to an unfinished rewrite, prevents a foreign editor model from becoming Mooncast's source of truth, and leaves room to replace UI, storage, rendering, and model providers independently.

## 2. Evidence discipline

This ADR uses these labels:

- **Verified fact** means directly observed in the pinned sources named here.
- **Inference** means an architectural interpretation of those facts.
- **Proposal** means the Mooncast design selected or deferred by this ADR.

No claim in this ADR establishes production or commercial readiness.

## 3. OpenCut evidence

### 3.1 Rewrite at `bab8af831b354a0b5a98a4a6e818ab7d633b94df`

**Verified facts**

- The rewrite README says OpenCut is being rewritten from the ground up and presents Editor API, plugin-first architecture, a Rust core, MCP, headless operation, and scripting as direction/future architecture.
- The README directs people needing the current editor to OpenCut Classic.
- `apps/web/src/routes/index.tsx` is a route/application scaffold rather than evidence of an implemented editing surface.
- `apps/desktop/src/main.rs` is desktop bootstrap/scaffolding; it does not establish a complete timeline, command history, project persistence, media pipeline, preview renderer, or export path.
- The repository uses a multi-application workspace shape (web/API/desktop) and a web/TypeScript plus desktop/Rust direction.

**Inference**

- At this pin the rewrite is useful as a statement of future modular architecture, but it is **scaffolding and future architecture, not a usable editor**.
- Depending on its proposed API or Rust core now would make MC-2 depend on contracts that are not demonstrated by end-to-end implementation at the pin.

### 3.2 OpenCut Classic at `cf5e79e919144200294fb9fed22a222592a0aeea`

**Verified facts**

- `timeline/types.ts` defines concrete timeline/editor data types rather than only an aspirational API.
- `commands/base-command.ts` defines a command abstraction with execution/history semantics; `commands/timeline/element/split-elements.ts` supplies a concrete timeline mutation. Together they demonstrate a command-based mutation and undo/redo design.
- `timeline/timeline-store.ts` is an implemented editor state/store layer around timeline operations.
- `services/storage/service.ts` implements local persistence concerns.
- `export/index.ts` exposes an export path, while `services/renderer/scene-exporter.ts` implements scene rendering/export behavior.
- In combination, the inspected Classic paths demonstrate concrete timeline data and operations, command/undo behavior, local project persistence, media/editor state handling, preview/rendering structure, and renderer/export flow.

**Inference**

- Classic is the concrete implemented reference for MC-1. Its value is primarily in seams and patterns: typed timeline state, explicit commands, reversible mutations, storage isolation, and separation of interactive state from scene export.
- A working reference reduces design risk, but importing its entire domain model would transfer hidden UI and persistence assumptions into Mooncast.

### 3.3 Reusable paths and patterns

The following are references for bounded design work, not approved copy lists:

| Classic path | Reusable pattern | Mooncast treatment |
|---|---|---|
| `timeline/types.ts` | Explicit tracks, elements, timing, selection/state types | Re-express as Mooncast pack contracts with stable IDs and rational/integer time |
| `commands/base-command.ts` | Commands as the mutation boundary; undo/redo metadata | Implement pack-local command protocol and deterministic inverse/restore data |
| `commands/timeline/element/split-elements.ts` | Compound, reversible timeline edit | Use as a conformance scenario for split behavior |
| `timeline/timeline-store.ts` | Centralized state transitions and history integration | Keep UI adapters thin; pack service owns authoritative transitions |
| `services/storage/service.ts` | Persistence behind a service boundary | Map to Mooncast `project_store.py` conventions; no browser storage in domain code |
| `export/index.ts` | Export facade | Expose a pack-local job API rather than UI-coupled exports |
| `services/renderer/scene-exporter.ts` | Scene-to-render/export separation | Adapt through the timeline-compositor port; do not make renderer state authoritative |

### 3.4 Stack and dependency consequences

**Verified facts:** the rewrite points toward web/TypeScript and Rust desktop/core components; Classic demonstrates a TypeScript editor implementation and browser/local service patterns; Mooncast's inspected orchestration/storage surfaces used a temporary local host and a provider-port document.

**Inference:** directly sharing Classic UI/store objects with Mooncast would create a TypeScript/browser-shaped domain boundary, while adopting the rewrite would add premature Rust/API coupling.

**Proposal:** MC-2 should begin with language-neutral, versioned JSON contracts and fixture tests. A web editor may use TypeScript and a renderer may use browser media APIs, WebCodecs, Canvas/WebGL, or FFmpeg-backed providers, but those are adapters. No new dependency is selected by this ADR. Dependency additions require an MC-2 phase-specific review for license, size, target support, determinism, and offline behavior.

## 4. Mooncast architecture and ownership

### 4.1 Existing seams

**Verified facts**

- `production.py` and `longform.py` contain Mooncast production/long-form orchestration concerns.
- `project_store.py` is the existing project persistence seam.
- `providers/timeline-compositor.port.md` specifies a provider boundary for timeline composition rather than requiring one renderer implementation.

**Inference**

- Mooncast already has suitable conceptual seams for orchestration, persistence, and provider substitution. The editor should attach to those seams rather than establish a second application-owned project system.

### 4.2 Pack-owned domain boundary

**Proposal:** create a future `mooncast-editor` pack-owned Mooncast application/module boundary (final name deferred) that owns the following domain contracts. This boundary is not necessarily a separately installable pack, and it is never part of MoonSuite core:

- `ProjectManifest`: schema version, project identity, asset references, sequence IDs, intent links, and audit metadata;
- `Timeline`: sequences, ordered tracks, clips/elements, time ranges, transitions, captions, effects, and annotations;
- `MediaRef`: immutable asset identity plus locator/proxy metadata, never raw provider credentials;
- `AIGCArtifact`: prompt/intent reference, provider/model provenance, generation parameters, rights/review state, and links to immutable outputs;
- `EditCommand`: command ID, actor, expected revision, payload, inverse/restore data, and timestamp;
- `PreviewRequest/Result`: sequence/revision, viewport/range, quality, and ephemeral result locator;
- `ExportSpec/Job/Result`: immutable input revision, render settings, progress/error state, artifact/checksum, and provenance.

All durable objects are schema-versioned. Times use an unambiguous integer tick or rational representation. IDs remain stable across saves; media is content-addressed where available. Commands use optimistic revision checks and are idempotent by command ID. Undo/redo is represented as auditable domain operations, not UI snapshots alone.

### 4.3 API boundary

The pack exposes local application interfaces equivalent to:

- `open/create/load/save/migrate project`;
- `append_command(project_id, expected_revision, command)` and `undo/redo`;
- `import/register/resolve media`;
- `request_preview(sequence_id, revision, range, quality)`;
- `submit/cancel/status export(spec)`;
- `validate(project)` and `collect_provenance(project)`.

The editor UI receives immutable snapshots plus events and submits commands. `project_store.py` adapts durable manifests, command logs, and artifact references. The timeline-compositor provider consumes a frozen timeline snapshot and resolved media; it cannot mutate the project. Provider-specific payloads stay behind adapters. File paths, browser blobs, renderer handles, secrets, and model SDK objects do not cross the domain API.

## 5. MoonWiki, MoonFlow, Bookkeeper, and authority

### MoonWiki intent

**Proposal:** MoonWiki stores human-readable creative intent, research, source citations, scripts, shot rationale, and acceptance criteria. Timeline items reference stable MoonWiki intent IDs. The timeline may materialize intent but must not overwrite the knowledge record. A missing MoonWiki integration in early MC-2 is represented by opaque stable references and fixtures, not by duplicating wiki content into clips.

### MoonFlow orchestration

**Proposal:** MoonFlow orchestrates long-running import, proxy, AIGC, preview, validation, and export jobs. It passes immutable IDs/specifications, records retries and cancellation, and calls pack APIs. MoonFlow does not own timeline semantics and must not edit storage directly. Human approval nodes are explicit and cannot be silently bypassed by retry or automation.

### Bookkeeper finalization and the canonical Three-Gap Theory

> Ownership clarification (MC-8): this section describes the external MoonBook
> Bookkeeper reached through MoonFlow. It does not authorize a Mooncast-local
> Bookkeeper service, store, API, reducer, schedule, or UI.

**Proposal:** Bookkeeper finalizes an approved production revision: it records manifest and output checksums, source/model/license provenance, approvals, costs where available, and the export result. Finalization is append-only and does not imply legal or commercial clearance.

Bookkeeper uses the canonical Three-Gap Theory exactly as follows:

- **Information gap — Unknown to Known**
- **Recognition gap — Known to Matters**
- **Decisiveness gap — Matters to Act**

Production intent variance, execution variance, and outcome variance may be recorded as evidence inputs to those assessments, but they must not be renamed or presented as the three gaps.

Bookkeeper operates two reviewed learning loops:

- **Fast loop:** for each deliverable, record findings and receipts and return them immediately as reviewed feedback to planning.
- **Slow loop:** aggregate reviewed evidence into a versioned capability-change proposal. Applying that proposal requires human approval.

Bookkeeper must never silently self-modify policy or ability. Learning records are evidence and proposals, not authorization to change either.

### Human authority

Humans remain authoritative for creative intent, source/right-to-use decisions, acceptance of generated media, destructive edits, final-cut approval, publication, and Bookkeeper finalization. AI may only propose provenance-bearing, previewable, rejectable, undoable commands. Automation surfaces uncertainty/failures and cannot infer rights or commercial readiness.

### MoonCode execution provenance

Documentation correction session: `mooncast-mc1-editor-architecture-20260716`. The accepted authoring command was `mc1-study-004-gpt56sol-120s`, using model `gpt-5.6-sol`. Attempts 002 and 003 failed closed with no mutation. Command 005 changed only the heading before exhausting its bounded step limit; command 006 corrects the Bookkeeper content and records this provenance.

## 6. Options considered

1. **Clean-room pack-owned implementation informed by Classic — selected.** Lowest coupling and migration risk; preserves Mooncast domain ownership while using implemented behavior as evidence. Costs more initial contract/test work.
2. **Copy Classic wholesale — rejected.** Fastest apparent UI path but imports browser/store/storage assumptions, creates a large provenance surface, and makes later domain separation expensive.
3. **Fork Classic — rejected.** Adds upstream divergence, security/maintenance burden, and two product architectures. A fork does not solve domain ownership.
4. **Embed Classic (iframe/webview/application) — rejected.** Weak project, identity, undo, provenance, AIGC, and job boundaries; duplicated persistence and difficult end-to-end authority controls.
5. **Extract Classic core as a shared library — rejected for now.** The inspected implementation proves useful seams but not a stable, UI-independent library contract. Extraction would couple Mooncast to foreign internal types.
6. **Selective port — allowed only as an exception.** Appropriate for a small algorithm after tests and provenance review; not the default architecture. Every port needs explicit work-order scope and MIT handling.
7. **Build against the OpenCut rewrite — rejected at this pin.** Its direction is attractive, but the pinned tree does not demonstrate a usable end-to-end editor.

## 7. MC-2 bounded phases and checks

MC-2 is not authorized by this ADR; these are proposed approval slices, each separately reviewable:

1. **Contracts and fixtures:** schemas for project/timeline/media/AIGC/commands; sample projects; schema validation; stable serialization; invalid-input and revision-conflict tests.
2. **In-memory editing kernel:** add/move/trim/split/delete; deterministic command log; undo/redo and replay property tests; no UI and no renderer.
3. **Persistence adapter:** transactional save/load through `project_store.py`; crash/partial-write recovery; migration fixtures; no direct UI storage.
4. **Media and preview spike:** import/proxy metadata and one timeline-compositor adapter; A/V sync, missing-media, cancellation, and stale-revision checks.
5. **Thin editor UI:** snapshot/event adapter, selection and basic edits; accessibility/keyboard checks; no domain logic embedded in components.
6. **AIGC and MoonFlow:** proposal-to-command conversion, provenance, approval nodes, retry/idempotency and secret-boundary tests.
7. **Export and Bookkeeper:** frozen-revision render, checksum/provenance bundle, cancellation/failure tests, human finalization, and canonical Three-Gap assessment and fast-loop receipt capture.
8. **Hardening evaluation:** performance budgets, long-timeline/load tests, sandboxing, malformed media, recovery, security/privacy/license review. This produces evidence for a later readiness decision; it does not assert readiness.

At every phase run schema/fixture tests, deterministic replay and undo tests where applicable, provider contract tests, migration round trips, lint/type/test suites for touched code, license scans, and repository diff checks. Golden render tests must state tolerances and platform/provider versions.

## 8. Migration and compatibility

- Start at project schema version 1; every durable load validates a version.
- Migrations are ordered, deterministic, fixture-tested, and preserve the original plus a backup until successful atomic replacement.
- Unknown fields are preserved when safe; unsupported semantics fail visibly rather than being dropped.
- Command logs record their schema version. Saved snapshots are checkpoints, not substitutes for provenance.
- Import from Classic, if later requested, is a one-way adapter into Mooncast IDs/types with an import report for lossy or unsupported features. It is not a shared live format.
- Renderer/provider changes do not rewrite domain data. Export records pin project revision, adapter/version, settings, and artifact checksum.
- Rollback means reopening the pre-migration backup or replaying the last supported checkpoint; migration never silently downgrades.

## 9. Risks and mitigations

- **Semantic drift from Classic:** maintain behavior fixtures, but choose and document Mooncast semantics explicitly.
- **Undo/history growth:** checkpoint and compact only under a documented policy while retaining audit/provenance records.
- **A/V timing and nondeterminism:** rational/integer time, pinned render settings, frozen revisions, tolerance-based golden tests.
- **Large media and browser limits:** immutable originals, proxies, streaming adapters, quotas, and cancellation; do not place media blobs in command logs.
- **Concurrent edits:** begin single-writer with optimistic revisions; do not imply collaborative conflict resolution.
- **Provider/model churn:** ports and normalized provenance; no provider SDK objects in schemas.
- **Security/privacy:** validate hostile media and manifests, sandbox renderers where feasible, constrain paths/URLs, redact secrets, and define retention.
- **License/provenance loss:** enforce the procedure below and review generated/copy-pasted code.
- **Scope creep:** phase gates and the explicit coding gate below.

## 10. MIT license and provenance procedure

Before copying or substantially adapting any OpenCut code:

1. Record source repository, Classic commit `cf5e79e919144200294fb9fed22a222592a0aeea`, exact source path, source lines/symbol, retrieval date, and destination in a provenance ledger.
2. Confirm the source file and relevant dependencies are covered by MIT and inspect vendored/generated assets for separate terms.
3. Preserve the MIT copyright and permission notice in the distribution and add a clear SPDX/file comment where appropriate; do not replace Mooncast's Apache-2.0 project license.
4. Describe modifications and keep the smallest reviewable diff. Substantial translations count as adaptations.
5. Have a human review license, provenance, dependency, patent/trademark, media, font, and model-output concerns before merge and release.
6. Run repository license/notice checks and package/asset inventory checks in the implementing work order.

Clean-room reimplementation still cites Classic as design evidence in the work order, but must not falsely label independently written code as copied. This procedure is engineering policy, not legal advice.

## 11. Unknowns and deferred validation

- Exact MoonWiki, MoonFlow, and Bookkeeper runtime APIs, identity model, access control, retention, and deployment topology.
- Final editor host, supported browsers/desktops, offline requirements, collaboration requirements, accessibility target, and performance budgets.
- Canonical tick rate/timebase, color management, codec/container matrix, caption formats, and renderer determinism across platforms.
- `project_store.py` transaction/concurrency guarantees and the compositor provider's concrete implementations.
- Rights policy for imported and AI-generated media, model/provider terms, telemetry/privacy rules, and distribution notice packaging.
- Whether any Classic routine is valuable enough to justify selective porting after a clean-room prototype.

These unknowns must become explicit MC-2 acceptance criteria; they are not grounds to imply commercial readiness.

## 12. Approval gate

**No broad coding is approved.** MC-1 authorizes only this ADR. Before any editor implementation, a human sponsor must approve a bounded MC-2 phase with: exact files/packages allowed to change; schemas and ownership; acceptance tests; dependency and license budget; privacy/security constraints; rollback; responsible reviewers; and explicit exclusions. The first work order should be contracts-and-fixtures only. It must not copy/fork/embed OpenCut, install dependencies, build a full UI, or begin production integration without a subsequent approval gate.
