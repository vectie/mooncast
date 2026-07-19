# Customer delivery and commercial portal

This Mooncast pack-local surface closes the customer handoff loop without
granting payment, publication, email, provider, or filesystem authority.

## Client review links

An internal named authority creates a link for one project, one exact promoted
master SHA-256, one delivery-package digest, and one completed delivery-build
digest. The raw URL token is returned once. Mooncast persists only its SHA-256
digest. Links expire at their recorded timestamp and may be explicitly revoked
or expired through the internal studio.

Every link has the fixed least-authority scope set:

- view the customer-safe project and episode summary;
- stream the exact accepted review master;
- write timecode-bound annotations;
- approve or request revision for the exact master/build pair; and
- download the exact immutable ZIP only after milestone acceptance.

The client projection excludes local paths, token digests, credentials, raw
provider responses, provider configuration, and publication controls. Access,
annotation, decision, master-stream, and ZIP-download activity writes durable
commercial audit receipts.

Internal endpoints:

- `GET/POST /api/v2/projects/{id}/client-portals`
- `POST /api/v2/projects/{id}/client-portals/{portal-id}/revoke`
- `POST /api/v2/projects/{id}/client-portals/{portal-id}/expire`

Client endpoints use the one-time raw token:

- `GET /client/{token}`
- `GET /api/client/{token}`
- `GET /api/client/{token}/master`
- `POST /api/client/{token}/annotations`
- `POST /api/client/{token}/decision`
- `GET /api/client/{token}/download`

A client `request-revision` consumes the shared maximum-two revision policy.
Client approval creates the same exact `delivery-build` governance milestone
used by the internal factory. It does not authorize publication.

## Milestone billing ledger

The record-only ledger covers deposit, animatic, accepted master, provider
overage, and extra revision milestones. Each entry records currency, amount,
reference, due/paid/waived timestamps, state history, and named internal
authority. States are `quoted`, `due`, `paid`, and `waived`.

- `GET/POST /api/v2/projects/{id}/billing`
- `POST /api/v2/projects/{id}/billing/{billing-id}/state`

These APIs never contact a payment processor and every response states
`payment_effect_performed: false`.

## Repeat-order drafts

`POST /api/v2/projects/{id}/repeat-orders` creates a new draft only when the
source IP bible is exactly approved and the source customer build is accepted.
The proposal carries the approved bible's reusable world, character, style,
environment, and constraint references. Asset references are copied only when
they belong to the exact G4-approved source set and the named repeat-order
authority explicitly selects them by ID; the source G4 evidence is retained.

The new production gets a new brief and rights ledger in draft state. Client
acceptance, delivery acceptance, publication authority, master decisions, and
all downstream gate receipts are never carried forward.

## User interfaces

The internal Production/Delivery workspace manages links, revocation/expiry,
billing evidence, and repeat-order creation. The separate client page presents
one dominant review task: watch the bound master, leave timecoded feedback, and
make the milestone decision. Delivery download remains visibly locked until
the exact build is accepted.
