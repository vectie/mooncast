# MC-8: Retire the pack-local Bookkeeper authority

- Status: accepted; supersedes MC-7
- Date: 2026-07-19
- Scope: `/Users/kq/Workspace/mooncast` only

## Context

MC-7 incorrectly treated Bookkeeper as a Mooncast pack-local service. The
canonical Bookkeeper is MoonBook's Bookkeeper and its generic contract is
`moonbook.bookkeeper.v1`. MoonFlow owns orchestration and the opaque transport
contract `moonflow.pack-handoff.v1`. Mooncast is a production system and must
not duplicate either authority.

## Decision

Retire all active Mooncast tools and mutable HTTP routes for Bookkeeper
finalization, outcome acceptance, variance review, Three-Gap classification,
learning review, capability proposals, or ability updates. Also retire the
pack-local MoonFlow disposition, delivery, assessment, proposal, evaluation,
adoption, and due-action command surface.

Mooncast owns only:

1. immutable evidence describing its final production deliverable;
2. immutable observations describing production outcomes;
3. an opaque outbound request conforming to `moonflow.pack-handoff.v1`, whose
   destination is MoonBook Bookkeeper; and
4. an immutable reference to a receipt issued by MoonFlow or MoonBook.

Preparing a request performs no external effect. Recording a receipt reference
does not copy, reinterpret, or supersede the issuer's canonical payload.
MoonBook Bookkeeper alone executes final acceptance, domain-specific Three-Gap
classification, learning-receipt creation, capability proposal review, and any
ability-update decision after handoff. MoonFlow sequences generic work and
validates opaque bindings; it does not classify gaps.

The active native routes are `/api/handoffs/**`. The former
`/api/bookkeeper/**` and `/api/moonflow-bridge/**` mutation routes are removed,
not redirected, so an old client cannot accidentally write into a different
authority.

Mooncast's only mounted product surfaces are Studio, Editor, and Client Review.
It has no separate Bookkeeper application or UI. MoonBook's existing Rabbita
Bookkeeper is the sole user interface for canonical Bookkeeper work after the
MoonFlow handoff.

## Accepted-record preservation

Previously accepted MC-7 records are user-owned evidence. Upgrade and uninstall
must leave the old `application/handoff`, `application/learning`, and
`application/handoff/immutable` roots byte-identical. Mooncast retains a
read-only migration adapter with no write, repair, delete, classification, or
application method.

Migration to MoonBook is explicit and review-driven:

1. enumerate legacy records without modifying them;
2. verify the legacy envelope, detached anchor, identity, and payload digest;
3. record an import decision made by an authorized operator;
4. hand exact payload bytes/digests to MoonBook through the generic handoff;
5. retain MoonBook's external receipt reference in the new Mooncast outbox; and
6. keep the legacy source record as read-only evidence after successful import.

No record is silently reclassified, rewritten into a new schema, adopted, or
deleted. Corrupt or unverifiable records stay in place and are reported for
manual resolution.

## Consequences

MC-7 remains historical documentation but is no longer an architectural
authority. Its stored JSON remains readable only through the raw read-only
migration adapter; the retired decision/reducer DTOs are not part of the active
Mooncast package API. The new outbox
under `application/handoff-outbox` is append-only Mooncast evidence, not a
Bookkeeper database. MoonBook and MoonFlow release, UI, policy, and storage
remain outside the Mooncast pack.
