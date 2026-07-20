# Mooncast responsibility and testability

Mooncast is the production-domain pack. It owns project/episode/scene/shot/asset
state, rights-aware production policy, creative versions, provider routing,
continuity and QC evidence, edit decisions, delivery packaging, and production
economics. It does not own an agent runtime, generic orchestration, Bookkeeper,
payment authority, or publication authority.

## Responsibility boundary

| Concern | Responsible owner | Mooncast behavior |
|---|---|---|
| Needs and durable source intent | MoonWiki/MoonBook | Import an exact reviewed export and preserve its identity. |
| Agent/model loop | MoonClaw | Prepare typed work and provider plans; never create another runtime. |
| Durable cross-product orchestration | MoonFlow | Emit and consume typed receipts; keep production state pack-local. |
| Creative, rights, QC, edit, delivery | Mooncast | Own versioned evidence and deterministic G0–G7 readiness. |
| Final Bookkeeper closure | MoonBook Bookkeeper | Send an inert evidence bundle; do not implement a second Bookkeeper UI. |
| Publication/payment | Authorized external host | Require separate authority and immutable receipts. |

## Refactored decision seam

`gate_reviewer_issues` is a pure boundary applied by the production kernel.
Gate advancement still requires all domain evidence, but now also rejects
runtime identities such as MoonClaw, MoonFlow, provider hosts, generic agents,
and workflow automation as the approving role. This prevents a successful
automated pipeline from approving its own output.

The specialized underlying decisions remain typed and independently testable:
rights approval, creative approval, routing/budget approval, five-dimensional
shot QC, master/client acceptance, destination authorization, and economics
review. The gate receipt coordinates those facts; it does not replace them.

## Test layers

1. Pure kernel tests cover reducer transitions, invalidation, readiness, and
   human-responsibility policy without IO.
2. Application tests cover repositories, routing, retries, restart recovery,
   budgets, and provider receipts using deterministic adapters.
3. Studio/API tests cover pack-owned workflows and negative authority paths.
4. Provider and rendered-episode acceptance remains a separate operational
   gate; deterministic fixtures cannot prove commercial production readiness.
