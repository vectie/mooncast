# Creative workspace

Mooncast exposes a governed visual workspace over its existing pack tools. The
workspace graph is a user-owned creative plan; it does not replace MoonClaw's
agent loop or MoonFlow's durable cross-product orchestration.

## Execution contract

1. Project, recipe, or natural-language intent selects a graph.
2. Every node resolves to a declared pack tool or a governed Mooncast built-in.
3. Typed ports and required inputs are validated before effects can run.
4. The selected output is frozen into an immutable execution plan.
5. Pack-local nodes use Mooncast jobs; cross-product effects are dispatched to
   MoonFlow and retain its receipts.
6. Node outputs become immutable workspace artifacts with input lineage,
   provider/model identity and receipt, prompt digest, cost, rights, concrete
   QC results, and time-ranged annotations.
7. Human gates remain explicit nodes and agents cannot satisfy them.
8. Runs may resume after restart, but an interrupted running attempt is never
   treated as successful.

## Built-in combine-videos capsule

The first workspace capsule is intentionally local and deterministic:

`Folder intake -> Probe media -> Normalize streams -> Concatenate -> Verify -> Register artifact`

The Editor remains the specialized preview and timeline lens. The capsule uses
the existing bounded, digest-pinned utility-concat transport and grants neither
provider nor publication authority.

## Provider-backed capsule

`Creative brief -> Validate brief -> Create project -> Generate shots -> Human review -> Package delivery`

The generation operation remains an external-effect operation owned by
MoonFlow even when its output requires review. The separate asset-review node
is the human gate. This distinction prevents a provider job from being
misrepresented as a human decision.

## Bounded controls

The catalogue contains finite variants, map, select/rank, merge, policy-gate,
human-approval and reusable-subgraph nodes. These carry typed artifacts and
versioned parameters; none accepts executable source code.

## Workspace lenses

- Graph: composition, validation, cost, execution, and provenance.
- Studio: governed production stages and human decisions.
- Editor: frame-accurate timeline and media work.
- Review: comments, approvals, and delivery evidence.

The native UI keeps graph, editor and review state in one MoonBit application.
The graph service exposes catalogue, capsules, validation, immutable graph
history, selected-output plans, durable runs, artifacts and agent proposals
under `/api/workspace`.

## Current alpha limits

- The combine-videos capsule is executable end-to-end through the UI. The
  provider-backed capsule exposes the planned graph and execution ownership;
  real-provider completion remains subject to configured adapters and rights.
- Run state is queryable with exact per-node progress; a long-lived SSE stream
  is not yet part of this contract.
- Graph edits are revisioned and type-checked in the MoonBit façade. Direct
  pointer dragging and connection drawing on the Rabbita canvas remain a
  follow-on interaction layer.
- Collaboration currently includes immutable annotations, fork/diff/history
  and review-gated agent proposals. Presence and public review links remain
  future authority-bearing features.
