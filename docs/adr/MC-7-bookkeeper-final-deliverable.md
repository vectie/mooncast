# MC-7: Pack-local Bookkeeper final-deliverable closed loop

> Superseded by [MC-8](MC-8-retire-pack-local-bookkeeper.md). The pack-local
> ownership decision below is historical and must not be used for new records,
> tools, routes, stores, applications, or UI.

- Status: accepted for implementation
- Date: 2026-07-16
- Scope: `/Users/kq/Workspace/mooncast` only

## Question

How can Mooncast freeze an already accepted delivery as a final deliverable,
link exact production/outcome evidence to reviewed Three-Gap learning, and remain
fail-closed without gaining publication or self-application authority?

## Inventory before implementation

Mooncast's mutable production authority is `ProjectStore`, backed by atomic
project JSON and an append-only project event log. `production.py` owns the G0
through G7 gate contract, rights, review, budget, and economics state.
`longform.py` creates the master provenance and delivery package and then stores
their read models in the production project. `server.py` is the same-origin HTTP
composition seam. Existing delivery schemas are
`mooncast.delivery-package.v2`, `mooncast.master-provenance.v2`,
`mooncast.production-project.v2`, `mooncast.economics-ledger.v1`, and the gate,
review, provenance, episode, analytics, provider, and editor contracts under
`schemas/`. The editor authority and all MC-6A UI/editor files are frozen and
outside MC-7.

The pre-edit full Python discovery baseline passed 141 tests in 132.176 seconds
(132.27 seconds `/usr/bin/time` wall clock). All thirteen frozen MC-6A/editor
authority SHA-256 values matched the work order before implementation.

Read-only inspection of MoonBook's generic Bookkeeper boundary and
`bookkeeper/` contracts established compatibility semantics, not a source
dependency. The generic contract is `moonbook.bookkeeper.v1`: exact candidate,
bundle, artifact and outcome identities; named authorized reviewer evidence;
complete workflow/gate/cost/authority/checklist evidence; immutable acceptance;
retention and rollback references; delivery authorization; and publication
remaining not requested or unauthorized. The generic learning protocol retains
the exact Three-Gap Theory terms: Information gap (`Unknown -> Known`),
Recognition gap (`Known -> Matters`), and Decisiveness gap (`Matters -> Act`).
Its learning receipts and capability proposals are non-applying values.

## Decision

Add an independent `BookkeeperStore` and `BookkeeperService`. The store lives
under a separate `bookkeeper/` authority root, never writes production project,
master, delivery, editor, policy, provider, or publication state, and receives
current production data only through a narrow read-only snapshot provider.

The service validates strict versioned pack-local JSON contracts and recomputes
all authoritative bindings from the current project snapshot. Caller digest
claims are comparisons only. Finalization requires an exact current revision,
delivered stage, passed G0-G7 receipts, complete cleared rights, approved QC,
editorial and client reviews bound to the current master, present economics,
matching delivery/master/project identities, an existing output artifact whose
SHA-256 matches the master, complete evidence references, an authorized named
human Bookkeeper attestation, explicit delivery-only state, explicit
publication-not-authorized state, and retention/rollback references.

Accepted records use canonical JSON (`UTF-8`, sorted keys, compact separators),
a SHA-256 envelope digest, and an independently persisted immutable detached
anchor for that envelope. One immutable file per safe record identity plus its
anchor is the sole authority; a verified in-memory index is rebuilt from every
accepted envelope and anchor on each operation. Creation uses
exclusive temporary files, fsync, atomic replace, and directory fsync. Existing
accepted files are never replaced. Exact duplicate content is replayed;
idempotency-key or record-identity reuse with different content conflicts.
Loading verifies filename identity, contract, embedded digest, and canonical
content. Truncated, corrupt, duplicate, or tampered accepted authority fails
closed and is left byte-identical; MC-7 performs no silent repair.

The immutable record flow is:

1. A finalization request/candidate and human authority decision produce one
   accepted finalization bundle/receipt.
2. An outcome observation binds exact accepted finalization identity and exact
   client/performance evidence; pending outcome is explicit.
3. Three immutable production-variance inputs compare intent to approved cut,
   approved cut to delivered artifact, and delivered artifact to exact outcome.
4. A named authorized human maps evidence to only the canonical Information,
   Recognition, or Decisiveness gap and its fixed transition.
5. The fast loop emits a reviewed, immutable, non-applying learning receipt.
6. The slow loop deterministically deduplicates reviewed findings and emits a
   versioned capability/ability proposal only when declared count, severity,
   and required-gap thresholds pass. The proposal cannot apply itself.

Production variance is evidence input and never renames a canonical gap. No
finding is inferred or fabricated from a variance summary. Outcome absence is
represented as `pending`, with no guessed result.

Expose narrow same-origin JSON endpoints in the existing server for create/get
operations. Every mutation requires strict versioned input, exact expected
binding/digest, idempotency, and human attestation where a review decision is
made. There is no publish, upload, provider, network, policy, execution, or
apply endpoint.

## Safety invariants

- Finalization and learning records are append-only and immutable.
- Corruption or tampering denies reads and all dependent writes without repair.
- Unsafe IDs and traversal are rejected before filesystem access.
- Project snapshots are deep-copied and read-only to MC-7; finalization and
  learning cannot alter delivery, master, editor, assets, policies, or gates.
- Only `reviewer_kind: human`, a non-anonymous reviewer ID, an authority
  reference, `authorized: true`, Bookkeeper role, and exact evidence references
  can accept or review.
- Automation, agent, system, anonymous, stale, incomplete, rejected, publishing,
  or externally effective requests fail closed and emit no accepted record.
- `delivery_state` is exactly `delivery-only`; `publication_state` is exactly
  `not-authorized`.
- Learning receipts and proposals set every application/effect flag to false and
  contain no executable action.
- Proposal adoption or execution requires a separate human review and MoonCode
  work order outside MC-7.

## Consequences and limitations

MC-7 can prove a locally persisted final-deliverable and reviewed learning
chain for the exact Mooncast project snapshot it observes. It does not publish,
render, upload, grant rights, infer commercial readiness, validate third-party
claims outside supplied evidence, or provide capability adoption/execution.
Operational backup, multi-host consensus, external identity federation,
signature/key management, regulatory review, and commercial approval remain
outside this work order.
