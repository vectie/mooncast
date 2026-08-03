# MoonCast product structure

MoonCast follows the MoonSuite product implementation standard v2 as a
**domain pack with a production-studio application**. This file records the
intentional repository mapping; folder names do not create new runtimes.

| Standard responsibility | MoonCast path | Boundary |
| --- | --- | --- |
| Domain model and policy | `production/`, `editor/domain/`, `kernel/` | Media-production concepts, G0–G7 gates and edit semantics only. |
| Application services | `application/`, `studio_service/` | Use cases and projections over domain records; no generic agent runtime. |
| Host/effects | `native_host/`, `execution/` | Typed process, transport and provider effects with receipts. |
| Pack boundary | `pack.json`, `schemas/`, `integrations/` | Versioned tools, evidence, authority and handoffs. |
| Visible application | `ui/rabbita-mooncast/` | Studio, cut editor and client review surfaces in Rabbita. |
| Composition roots | `cmd/` | Thin service/tool wiring only. |
| Qualification | `docs/qualification/`, focused `*_test.mbt` files | Ordinary journey, denial, recovery and cross-product evidence. |

The Studio package now keeps navigation and the production journey compass in
`navigation.mbt` and `journey.mbt`; the large domain workbenches remain in
cohesive view files until a behavior-preserving split is independently
reviewed. Public MoonBit APIs do not depend on filenames.

The L2 primary journey is: select a project → follow the next G0–G7 action →
resolve its blocker or record the named receipt → review the exact master and
delivery evidence. MoonClaw remains the agent runtime and MoonFlow remains the
orchestrator; neither implementation belongs in this repository.
