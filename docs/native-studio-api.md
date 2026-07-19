# Native Studio API

The native Studio API is an application adapter over the deterministic
`kernel`, `production/*`, and `execution` packages. JSON paths retain the
existing `/api/v2/projects` and `/api/provider-executions` namespaces where the
canonical v2 types can support them without reintroducing legacy domain logic.

## Projects

- `GET /api/v2/projects` returns canonical project summaries.
- `POST /api/v2/projects` accepts either
  `{ "graph": ProjectGraph, "recorded_at": String? }` or the legacy creation
  subset `{ project_id, title, target_duration_seconds, max_budget_cny }`.
- `GET /api/v2/projects/{project_id}` returns the durable aggregate containing
  the canonical snapshot, event log, and command receipts.
- `DELETE /api/v2/projects/{project_id}` requires
  `{ "expected_revision": Int }`. Deletion writes a tombstone; it does not
  erase the snapshot, event log, or command receipts, and the ID cannot be
  silently reused.
- `GET /api/v2/projects/{project_id}/events` returns accepted kernel events.
- `POST /api/v2/projects/{project_id}/commands` accepts
  `ProjectCommandRequest`. The service replaces the supplied snapshot with the
  canonical snapshot before reduction.

Every mutation carries an expected revision. Reusing a command ID with the same
input returns its original receipt; reusing it for another input returns 409.
Stale revisions also return 409.

## Creative and governance

- `GET /api/v2/projects/{project_id}/creative/{kind}` returns the current typed
  artifact, its history, exact-version decisions, and project revision.
- `POST .../creative/{kind}/revise` accepts `CreativeArtifactRequest`.
- `POST .../creative/{kind}/decision` accepts `CreativeDecisionRequest` and
  rejects decisions that do not bind the canonical current artifact.
- `GET /api/v2/projects/{project_id}/governance` returns the current governance
  projection using the prior UI's field names where those fields map cleanly.
- `POST /api/v2/projects/{project_id}/advance` accepts `GateCommandRequest` for
  G0 through G7. Readiness, ordering, named-human authority, and evidence remain
  kernel decisions.

The generic project command endpoint records qualifications, routing plans and
decisions, generation attempts, five-dimension QC, masters, delivery,
publication authorization/observations, and performance reviews without adding
one HTTP implementation branch per domain type.

## Routed provider work

- `POST /api/v2/projects/{project_id}/routed-executions` accepts
  `RoutedPlanRequest` and binds the canonical project graph and routing plan.
- The corresponding collection and item GET routes expose durable plans.
- `POST /api/provider-executions` accepts a typed authorized
  `ProviderExecutionJob` in `ProviderAuthorizationRequest`.
- `POST /api/provider-executions/{job_id}/commands` reduces explicit state
  commands against the canonical job and persists its events and receipts.

Provider `execute`, `resume`, and `cancel` URLs are mounted from the
`application/execution` service. They consume a previously authorized exact
plan and use the native HTTPS, secret-reference, clock, ID and artifact-store
ports. Publication authority remains false in this layer.

## Native cut-editor application

The `/api/editor` namespace is now served by MoonBit application code over the
typed `editor/*` packages. It does not call the retired controller.

- `GET|POST /api/editor/projects` list and create durable editor workspaces.
- `GET /api/editor/projects/{id}` and `/snapshot` return the current snapshot,
  command log, rights-bound media bindings and take projection.
- `POST /api/editor/projects/{id}/production-import` creates a workspace from a
  typed production import. `production-refresh` is the same operation with an
  explicit expected editor revision.
- `POST /api/editor/projects/{id}/commands` accepts the canonical typed command
  envelope and the established `{ expected_revision, idempotency_key,
  command: { type, payload } }` form. Undo and redo remain reducer operations;
  the server never infers selection state.
- The two-step `media-intakes` API freezes rights, source, digest and revision
  evidence before accepting bytes. Completion registers the immutable object,
  durable binding and take without provider or publication authority.
- Take `analysis`, `source`, and `thumbnail` routes use local `ffprobe`/`ffmpeg`
  process ports. Analysis records stream metadata, bounded waveform peaks,
  a content-addressed thumbnail and a review proxy. Source and derived media
  support ETag and single byte ranges.
- `preview-sessions`, `jobs`, and `exports` freeze the same typed render plan,
  resolve only registered content digests and invoke ffmpeg through argv-only
  process execution. Job, render and export receipts survive restart.
- `exports/{job}/promote-master` requires a completed export, current canonical
  project revision, named actor and explicit authority reference. The receipt
  grants no publication authority.

Internal editor operations never return a not-implemented response. A failed
plan, missing rights-bound media, process failure or stale revision is an
explicit job/error state. Provider-network execution remains a distinct port.

`StudioService::register_route_extension` lets the execution, commerce and
handoff application packages mount their own bounded API prefixes. The native
studio owns transport and fallback routing; the extension owns its domain
state, evidence, authority and response contract. No domain branch is added to
the generic native host packages.

## Media and surfaces

`StudioService::register_media` writes the blob first and commits digest-bound
metadata last. `GET`/`HEAD /media/{media_id}` resolves only committed metadata,
rechecks size and SHA-256, and supports ETag and a single byte range.

The native entrypoint serves the production/editor surface at `/`, `/studio`,
`/editor`, and `/apps/mooncast/studio`; it serves the client surface at
`/client`, `/client/{token}`, and `/apps/mooncast/client`. Client tokens are
routes only in this slice: authorization and client-domain projections remain
separate application services.

These are the only Mooncast UI surfaces: Studio, Editor, and Client Review.
There is no Mooncast Bookkeeper UI or application route. Mooncast evidence
travels through the generic MoonFlow handoff to MoonBook, whose existing
Bookkeeper Rabbita UI is the sole Bookkeeper interface.
