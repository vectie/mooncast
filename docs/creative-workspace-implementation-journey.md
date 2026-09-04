# Creative workspace implementation journey

Status: implemented alpha, 2026-09-04

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
| Desktop packaging could omit the new surface | Rebuilt the Rabbita release and validated the unchanged least-authority Lepusa bundle contract. |

## Verification evidence

- Workspace package: 11 MoonBit tests pass.
- Studio service: 14 MoonBit tests pass, including HTTP, immutable artifacts,
  graph revision history and durable run transitions.
- Rabbita editor: 7 MoonBit tests pass and the production Vite bundle builds.
- Repository suite: all 58 MoonBit tests pass after the final workspace and UI
  changes.
- Lepusa 0.1.4 strict macOS verification: native launch, bundle,
  release-readiness and package-readiness all pass with zero audit warnings.
- Native UI smoke: both recipes switch visibly; the provider graph shows
  MoonFlow ownership, and the Review lens remains backed by the same app state.

## Deliberate remaining boundaries

This alpha does not claim multiplayer presence, public client links, arbitrary
provider availability, automated publication or an infinite-canvas gesture
system. Those require separate security, identity and interaction work. The
underlying versioned contracts and authority seams are now present so those
features can be added without replacing the workspace core.
