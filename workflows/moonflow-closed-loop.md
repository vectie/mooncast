# Mooncast → MoonFlow → MoonBook handoff

Mooncast owns production. MoonFlow owns generic orchestration. MoonBook owns the
canonical Bookkeeper and its final-deliverable, Three-Gap, learning, capability,
and ability-update decisions. This workflow connects them without copying
authority into the Mooncast pack.

## Production evidence

1. Complete the governed production/editor lifecycle and create a successful
   3–8 minute export through the explicit editor import, cut, frozen-plan,
   preview, export-job, and verified production-export stages.
2. Promote and review the exact master through separate named technical,
   creative, and rights decisions.
3. Prepare the delivery package, plan and execute the delivery build, and
   obtain named acceptance of the exact immutable ZIP/build digest.
4. Create the client portal and record the exact client decision. Client
   acceptance records the client master decision and delivery milestone; it
   does not authorize publication.
5. Create `mooncast.final-deliverable-evidence.v1`, binding the project,
   episode, export job, master/render digests, lineage references, duration, and
   explicit no-publication/no-external-effect flags plus accepted-build/client
   evidence references.
6. After governed delivery, record any measurable result as
   `mooncast.production-outcome-evidence.v1`. Mooncast records facts and declared
   inference use; it does not classify a gap.

The editor shortcut
`POST /api/editor/projects/<project>/exports/<job>/handoff-request` performs
steps 3 and 5 for a successful 3–8 minute export. It does not call MoonFlow or
MoonBook.

## Generic handoff

7. Prepare `mooncast.external-handoff-request.v1`. Its transport contract is
   `moonflow.pack-handoff.v1`, its destination is `moonbook`, and its destination
   contract is `moonbook.bookkeeper.v1`. The payload is opaque evidence plus
   exact authority/review/lineage references. The existing request route also
   materializes `mooncast.bookkeeper-ingress-bundle.v1` in the immutable
   outbox. That bundle contains a canonically digested generic MoonBook durable
   record and ingress envelope; Mooncast does not submit either value.
8. An authorized host transfers the request to MoonFlow. That external effect
   is outside this pack and requires its own authority.
9. MoonFlow reads the bundle through
   `GET /api/handoffs/bookkeeper-ingress-bundle/<request-record-id>`, then
   posts the returned bundle's `record` to `/api/bookkeeper/records` before
   posting its `envelope` to
   `/api/bookkeeper/envelopes/ingress`. The bundle fixes both activation flags
   and the durable-record side-effect flag to `false`.
10. MoonBook
   Bookkeeper independently accepts or rejects the deliverable, classifies any
   Information/Recognition/Decisiveness gap, issues learning receipts, reviews
   capability proposals, and controls ability updates.
11. Mooncast may retain only an
   `mooncast.external-handoff-receipt-reference.v1` pointing to the exact
   MoonFlow or MoonBook receipt. The issuer's payload stays authoritative.

## Native interface

- `POST /api/handoffs/final-deliverables`
- `POST /api/handoffs/outcomes`
- `POST /api/handoffs/requests`
- `POST /api/handoffs/receipt-references`
- `GET /api/handoffs/{record-type}/{record-id}`

The active runtime exposes no Bookkeeper mutation, MoonFlow disposition,
Three-Gap assessment, improvement proposal, offline evaluation, adoption, due
action, publication, provider, or deployment authority through this interface.

An outcome bundle names the exact final-deliverable Bookkeeper record and is
not acceptable to MoonBook until that deliverable has a completed `Accept`
review. For the deliverable review, install a named human grant with
`moonbook bookkeeper authority install`; its `authority_ref` is local policy,
and every grant evidence ID must be present in the bundle record's
`evidence_refs`. Mooncast neither installs nor activates that grant.

## Legacy MC-7 evidence

Old accepted MC-7 records stay byte-identical in their original roots. The
read-only adapter exists for explicit, reviewed import into MoonBook; it cannot
write, repair, classify, apply, or delete. See
`migrations/mc7-bookkeeper-read-only.md` and ADR MC-8.
