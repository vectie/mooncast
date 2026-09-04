# MoonCast product contract

Class: governed creative-workspace pack
Visible surface: workspace graph, production studio, cut editor and review lens
Maturity: operational governed-workspace beta and production-pipeline alpha
Last reviewed: 2026-09-04

## Outcome

MoonCast produces governed 3–8 minute branded or IP episodes from qualified
commercial intent through rights, creative development, shots, editing, review,
delivery and outcome measurement.

## Users and jobs

- Producers qualify paid scenarios, contracts, scope and budget.
- Creative teams approve the bible, script, storyboard and animatic.
- Generators create versioned assets and shot attempts through provider ports.
- Editors assemble and revise the episode in the cut editor.
- Clients approve milestones and receive a rights/evidence delivery package.

## Ownership

MoonCast owns media-production domain schemas, G0–G7 gates, provider routing
plans, asset lineage, continuity, QC, editing, delivery, distribution receipts
and unit economics. It does not own agent runtime behavior, generic
orchestration, provider credentials or final publication authority.

## Capability status

| Capability | Status |
| --- | --- |
| Project → episode → scene → shot → asset model | available |
| Rights, budget, review and delivery gates | available |
| Deterministic multi-shot long-form fixture | available; fixture-only |
| Cut editor, timeline operations and QC/review UI | available locally |
| Multi-project cost, schedule, capacity and exception control | available locally |
| Typed workspace graph, validation and deterministic selected-output planning | available |
| Durable workspace graph revisions, runs, retries and restart recovery | available |
| Immutable workspace assets with lineage, provider receipts, cost and QC | available |
| Creative Capsules and project-owned capsule installation | available; built-ins plus promoted/published versions are installable |
| Bounded variants/map/select/merge/policy/human/subgraph controls | available with native execution semantics and exact-version subgraph expansion |
| Graph, Editor and Review lenses | available locally |
| Infinite canvas interaction, typed connect, selectable/deletable edges, multi-select copy/paste/group, mute/bypass, auto-layout, structured parameters, undo/redo and immutable asset drop | available locally |
| Exact-saved-revision whole/selected execution, native graph walking, explicit external/human blockers, cache reuse, claims/actions and event replay | available |
| Paginated/tagged asset library, compare, promotion, branch, guarded hide and run template promotion | available |
| Comments, renewable named presence, activity, search and expiring/revocable client-review pages | available; deployment/identity remains host-owned |
| In-workspace assistant diagnosis, bounded repair/layout proposals, stale-aware graph diffs and exact-base application | available through review-gated API and loopback tools |
| MoonFlow `adapter.v2` plus deterministic workspace dispatch/receipt boundary | available; workers remain separately deployed |
| Capsule publishing and simplified App view | available in the installable workspace catalogue |
| Text/image/video/voice/music provider ports | available as contracts |
| Real-provider complete episode | conditional and not yet commercially proven |
| External publication | separately authorized |

## Cut-editor boundary

The editor owns non-destructive timeline decisions, source/program preview,
trim/split/ripple, transitions, effects, audio, subtitles, comments, QC and
delivery preparation. It must preserve source asset lineage and produce an
immutable edit-decision/version history. Rendering a procedural fixture does
not prove provider quality or client acceptance.

## Creative-workspace boundary

The pack manifest remains the capability source of truth. Mooncast projects its
tools into typed node definitions and adds only a finite set of safe built-ins;
there is no arbitrary-code node. Mooncast owns graph validation, frozen plans,
run projections, artifacts, capsule versions and human gates. External-effect
nodes identify MoonFlow as execution owner, while provider credentials remain
host-injected. The workspace never grants publication authority implicitly.

## Pack and runtime contract

Domain tools and schemas remain in MoonCast. MoonFlow may orchestrate stages;
MoonClaw performs agent reasoning; MoonGate supplies provider access; MoonDesk
hosts the application. None of those components may embed media-production
policy.

## Authority, rights and economics

No generation starts before rights/data-use clearance. Every attempt records
provider/model version, source assets, prompt digest, seed when available,
cost, output digest and QC. Publication requires destination-specific
authority. Project review reports planned versus actual cost, accepted minutes,
revision burden, contribution margin and founder-hours.

The control tower computes only what canonical records prove. Provider
operations are costed from generation, asset-factory, animatic,
post-production and automated-QC records. Named operating evidence supplies
labor, other direct cost, recognized revenue, founder-hours and confirmed
provider spend. Missing evidence remains explicit and incomplete portfolio
totals remain unknown rather than becoming zero.

## Verification and commercial gate

Fixtures validate state transitions, deterministic rendering and recovery. A
commercial claim requires a real provider-generated 3–8 minute episode with
audio, subtitles, labels, QC, client acceptance, delivery receipt and complete
unit economics.

## Release gates and next milestones

- Connect production-approved real providers without storing credentials in the
  pack.
- Complete one populated cut-editor workflow from intake to accepted master.
- Deliver two paid design-partner episodes and record repeat-purchase evidence.
