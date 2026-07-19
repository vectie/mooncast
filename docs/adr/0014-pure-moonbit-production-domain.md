# ADR 0014: Feature-first pure-MoonBit production domain

Status: implementation in progress

## Decision

Mooncast's canonical production behavior is moving into public, pack-owned
MoonBit packages. A temporary reference host remained during extraction but
was never the target architecture. Domain
behavior must not move into MoonSuite core, MoonDesk, MoonFlow, MoonWiki, or
Bookkeeper.

The feature boundary is deliberately larger than a lifecycle hardening shim.
It owns the actual `project → episode → scene → shot → asset` graph and the
evidence-bearing work products that move a paid 3–8 minute production through
G0–G7.

## Implemented MoonBit feature slices

- `production/project`: canonical graph, immutable asset references, saleable
  duration and graph validation.
- `production/creative`: versioned brief, rights ledger, IP bible, script,
  claims ledger, storyboard and animatic; exact named decisions; dependency
  binding and downstream invalidation policy.
- `production/governance`: customer qualification, G0–G7 receipts, model route
  and budget approval, generation-attempt lineage, technical/continuity/safety/
  claims/rights QC, master/client decisions, delivery acceptance, destination
  publication authorization and performance/economics review.
- `kernel`: canonical project snapshot, typed command/result contract,
  append-only project events, immutable reducer, deterministic replay,
  readiness projection, exact evidence receipts, versioned snapshot/event JSON
  codecs and an authority record whose external-effect fields are always false.
- `cmd/lifecycle_kernel`: pure-MoonBit native stdin/stdout command bridge. The
  legacy path name is retained temporarily; its protocol is production kernel
  v2, not the discarded evidence-boolean shim.
- `execution`: provider request plans, explicit host authority records, durable
  job state, attempt history, normalized artifact receipts, exact shot-to-route
  planning, cost ceilings, delivery build profiles/state/recovery, build
  acceptance and inert publication-authority requests. Reducers emit no IO.
- `commerce`: versioned leads and named qualification, exact scoped quotes,
  commercial/production/client decisions, margin and founder-hour forecasts,
  finite resources and reservations, capacity boards, quote conversion, client
  portals and timecoded review records, milestone billing, and safe repeat-order
  proposals that carry neither client approval nor publication authority.
- `handoff`: under the MC-8 correction, Mooncast-owned final-deliverable and
  production-outcome evidence plus opaque `moonflow.pack-handoff.v1` requests
  destined for MoonBook and exact external receipt references. MoonFlow
  orchestration and MoonBook Bookkeeper decisions are not pack-local contracts.
- `application/execution`: native application services for public provider
  catalog readiness, secret references, exact named authority, durable bounded
  HTTPS JSON jobs, retries/resume/cancel/restart recovery, normalized
  content-addressed artifacts, routed per-shot jobs, and argv-only ffmpeg/zip
  delivery builds with checksum manifests and acceptance-gated downloads.
- `application/commerce`: atomic commercial snapshot/audit persistence,
  revision-bound commands, lead/quote/capacity queries and rescheduling,
  one-time client token issuance with digest-only persistence, stale-safe client
  projections, timecoded annotations, delivery decisions, billing transitions,
  portal control and repeat-order records. No CRM, email, calendar, or payment
  effect exists in the service.
- `application/handoff`: an immutable Mooncast evidence/request/reference
  outbox and a non-routed read-only adapter for accepted MC-7 records. It has no
  learning, proposal, adoption, finalization, classification, or due-action
  authority.
- `application/http_contracts`: typed handler functions and route descriptors
  for the existing provider, routed execution, delivery build, commercial,
  client, and outbound handoff paths. There is no Mooncast Bookkeeper or
  MoonFlow orchestration mutation path.

## Authority and integration

The production kernel decides only domain state. It does not read files, call
models, access secrets, spend money, publish, or claim that an external effect
occurred. Hosts execute separately authorized effects and return immutable
observations as new commands. MoonWiki supplies stable intent/evidence
references. Mooncast prepares opaque requests; external MoonFlow schedules the
generic handoff, and MoonBook's canonical Bookkeeper consumes accepted evidence
for reviewed Three-Gap learning and any capability/ability decision.

## Remaining migration slices

The following behavior was identified outside the new MoonBit feature packages
and had to be extracted before the source cutover:

1. cut-editor timeline commands, transitions, undo/redo, proxy planning and
   frozen render/export plans;
2. editor and production project store migration, transactional multi-record
   commit/recovery, and schema migration tooling beyond the new application
   stores;
3. full media composition beyond the extracted ffmpeg delivery-profile runner,
   including timeline render plans, audio mixing, subtitles, and proxy/master
   promotion;
4. local studio and client-review HTTP/UI host registration and static serving;
5. final legacy-wire adapters for endpoints whose existing request payloads are
   transformed into the new typed commands by the then-current host;
6. removal of compatibility aliases and every retired runtime file after the
   equivalent MoonBit path is feature-complete.

The next feature slice is the cut-editor domain because accepted 3–8 minute
masters cannot be produced at commercial quality from generation records alone.
Hardening, exhaustive negative testing and performance tuning follow complete
feature extraction as one consolidated release pass.
