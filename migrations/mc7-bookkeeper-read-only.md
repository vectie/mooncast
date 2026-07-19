# MC-7 Bookkeeper record preservation

MC-8 retires Mooncast's pack-local Bookkeeper authority. Existing accepted
records are not obsolete user data and must not be removed.

## Frozen legacy roots

- `<mooncast-data>/application/handoff`
- `<mooncast-data>/application/handoff/immutable`
- `<mooncast-data>/application/learning`

The native runtime no longer writes these roots. The
`LegacyBookkeeperReadOnlyAdapter` can read the old snapshot, immutable envelopes,
and exact learning-record keys for an explicit migration tool. It provides no
mutation or repair operation and is not mounted as an HTTP route.

## Exact legacy envelope

No retired Mooncast schema file is required. The adapter preserves the stored
JSON as opaque payload and recognizes the immutable envelope fields that were
actually persisted:

- `contract` (`mooncast.immutable-record-envelope.v1`)
- `record_type`
- `record_id`
- `idempotency_key`
- `payload_digest`
- `previous_anchor_digest` (nullable)
- `envelope_digest`
- `payload` (opaque JSON)

The immutable root also contains the original idempotency and per-record-type
anchor records. Migration verifies the payload digest and chain binding against
those stored records. It does not reinterpret the payload through a Mooncast
Bookkeeper or MoonFlow schema; MoonBook decides whether an exact legacy payload
is admissible under its canonical import policy.

## Import rule

An operator-authorized migration may verify and submit exact legacy bytes and
digests to MoonBook Bookkeeper through MoonFlow. Mooncast stores only the
outbound request and the returned external receipt reference. A successful
import does not authorize deletion of the source record. Failed verification
does not authorize repair or replacement.

New records are written only under
`<mooncast-data>/application/handoff-outbox` as Mooncast-owned evidence,
outbound requests, and external receipt references.
