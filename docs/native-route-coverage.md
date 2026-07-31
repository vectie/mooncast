# Native route coverage

This inventory records the route cutover to the MoonBit-native `cmd/studio`
host. “Native” means every request enters a typed MoonBit handler. A compatibility payload is
accepted only where it can be translated without inventing authority; otherwise
the same URL accepts the typed v2 contract and returns an explicit 4xx for an
old ambiguous body.

## Host and static surfaces

| Previous route | Native owner | Status |
|---|---|---|
| `GET /health` | `cmd/studio` router | Native |
| `GET /api/config` | `studio_service/api.mbt` | Native capability projection |
| `GET /`, `/studio`, `/editor`, `/apps/mooncast/studio` | `cmd/studio` Rabbita release adapter | Native; resolves studio/editor built entrypoints, Vite assets and MoonBit JS target assets with navigation fallback |
| `GET /client`, `/client/{token}`, `/apps/mooncast/client` | `cmd/studio` Rabbita release adapter | Native; resolves the client built entrypoint while preserving the portal token path |
| `/apps/mooncast/*` API and media paths | `direct_mount_path` | Native direct-mount alias |
| `GET|HEAD /media/{id}` | `StudioService::resolve_media` | Native digest, ETag and byte-range verification |

## Canonical production project

| Previous route family | Native owner | Status |
|---|---|---|
| `GET|POST /api/v2/projects` | project application service | Native; graph request plus the small legacy create request |
| `GET|DELETE /api/v2/projects/{id}` | project application service | Native; deletion is a tombstone |
| `GET /api/v2/projects/{id}/events` | project application service | Native |
| `GET /api/v2/projects/{id}/governance` | project application service | Native projection |
| `GET /api/v2/projects/{id}/master/provenance` | project application service | Native current master evidence |
| `GET /api/v2/projects/{id}/creative/{kind}` | creative application adapter | Native exact UI projection with artifact history and decision receipts |
| `POST .../creative/{kind}/revise|decision` | creative application adapter | Native typed contracts plus the studio's exact-version/digest payloads |
| `POST /api/v2/projects/{id}/advance` | kernel gate command | Native typed contract plus the studio's named-actor gate payload |
| `POST /api/v2/projects/{id}/commands` | kernel command application | Native generic command for routing, attempts, QC, master, delivery, publication observations and performance |
| `GET .../governance/stages/{G3..G7}` | governance application adapter | Native stage projection with exact records, readiness and explicit authority boundary |
| `POST .../governance/model-routing` and `/model-routing/decisions` | G3 governance application | Native versioned plan plus independent producer/finance decisions |
| `POST .../governance/shots/{shot}/attempts`, `/qc/{dimension}/findings`, `/qc/{dimension}/decisions` | G4 governance application | Native exact route/output evidence, five-dimensional findings and named independent decisions |
| `POST .../governance/master`, `/master/{kind}/decisions`, `/delivery-package`, `/delivery-milestones` | G5 governance application | Native master lineage, four required review kinds, versioned delivery intent and client milestone acceptance |
| `POST .../governance/publication-authorizations`, `/publication-observations` | G6 governance application | Native destination-specific inert authorization; observation requires a separately supplied host authority receipt |
| `POST .../governance/performance-reviews` | G7 governance application | Native performance, unit economics, founder-hours and repeat-purchase evidence |
| `POST .../delivery/outcome-handoff` | G7 outcome handoff application | Native immutable outcome evidence plus inert MoonFlow request and Bookkeeper ingress bundle; publication/payment authority remains false |
| `POST .../{generate,assemble,review,delivery-plan,deliver,analytics}` | governed replacements below | Old monolithic aliases intentionally removed with 410 |

The replacements are explicit: provider/routed execution for generation, the
cut-editor export for assembly, typed master decisions for review, delivery
builds for materialization, and a typed performance-review command for
analytics.

## Provider execution, routed work and delivery

| Previous route | Native owner | Status |
|---|---|---|
| `GET /api/provider-executions/config` | `application/execution` | Native adapter/secret readiness |
| `GET|POST /api/provider-executions` | `application/execution` | Native durable jobs and exact authorization |
| `GET /api/provider-executions/{job}` | `application/execution` | Native |
| `POST /api/provider-executions/{job}/execute|resume|cancel` | `application/execution` | Native HTTPS/secret/store ports; no internal 501 |
| `GET|POST /api/v2/projects/{id}/routed-executions` | routed application/project compatibility adapter | Native; resolves the approved plan through the provider catalog and projects per-shot adapters/jobs |
| `GET .../routed-executions/{execution}` | routed application/project compatibility adapter | Native studio projection with route binding, attempts, artifacts, errors and ingest receipt |
| `POST .../routed-executions/{execution}/shots/{shot}/execute|resume|cancel` | `application/execution` | Native provider action |
| `GET|POST /api/v2/projects/{id}/delivery-builds` | `application/execution.DeliveryFactoryService` | Native durable build collection |
| `GET .../delivery-builds/{build}` | delivery factory | Native |
| `POST .../{build}/build|retry|cancel` | delivery factory | Native argv-only ffmpeg/ZIP process ports; bounded source master, variants, channel cuts and cover frames |
| `POST .../{build}/acceptance` | delivery factory | Native exact human receipt |
| `GET .../{build}/download` | delivery factory | Native; denied until accepted |

Every completed build also materializes project metadata, provenance, rights,
AI labeling, subtitle evidence, a client-acceptance template, SHA-256 checksum
manifest, delivery manifest and a ZIP archive. Burned-in subtitles remain bound
to the master; a requested sidecar requires and packages an actual subtitle
source. `MOONCAST_PROVIDER_CATALOG_JSON` supplies the typed provider catalog.
Secrets remain `host-secret:` references and are resolved only by the execution
port.

## Cut editor

| Previous route | Native owner | Status |
|---|---|---|
| `GET|POST /api/editor/projects` | editor application service | Native durable workspaces |
| `GET /api/editor/projects/{id}` and `/snapshot` | editor application service | Native workspace, command log, takes, comments and bindings |
| `POST .../production-import` | production-to-editor adapter | Native; empty body creates the canonical project timeline and typed body imports exact production evidence |
| `POST .../production-refresh` | production-to-editor adapter | Native expected-revision refresh |
| `POST .../commands` | editor reducer | Native typed command plus legacy `{type,payload}` adapter; nested clip color/effect and output preset fields are normalized |
| `POST .../review-comments` | editor application service | Native durable, revision-bound time-range comment |
| `POST .../media-intakes` | editor media intake | Native rights/source/digest freeze |
| `POST .../media-intakes/{intake}/content` | editor media registry | Native raw bytes up to 64 MiB, immutable receipt and take |
| `POST /api/editor/utility-concats`, `POST .../{job}/inputs/{index}`, `POST .../{job}/run`, `GET .../{job}` | standalone utility concat application | Native project-free ordered manifest, digest-pinned uploads, idempotent execution, and explicit no-publication/no-provider authority |
| `GET|HEAD /api/editor/utility-concats/{job}/media` | utility concat media reader | Native verified MP4, ETag, byte ranges, and attachment filename |
| `GET .../takes/{take}/analysis` | editor media application | Native ffprobe, thumbnail, waveform and proxy status |
| `GET|HEAD .../takes/{take}/source|thumbnail` | editor media application | Native ETag and byte ranges |
| `GET|HEAD /api/editor/media/{digest}` and `/thumbnail` | editor media application | Native content-addressed media |
| `POST .../preview-sessions`, `/previews`, or `/jobs` | editor render application | Native frozen plan and ffmpeg preview |
| `GET .../jobs/{job}`, `POST .../retry`, `GET|HEAD .../media` | editor job application | Native durable status/retry/output |
| `POST .../exports`, `GET .../exports/{job}`, `GET|HEAD .../media` | editor export application | Native production export and receipts |
| `POST .../exports/{job}/promote-master` | editor/production integration | Native named-authority promotion receipt |
| `POST .../exports/{job}/handoff-request` | Mooncast evidence outbox | Records final-deliverable evidence plus an opaque MoonFlow request destined for MoonBook; performs no external effect |

## Commercial and client delivery

| Previous route family | Native owner | Status |
|---|---|---|
| `GET /api/commercial-intake` | `application/commerce` | Native dashboard with leads, qualification, versioned quotes, margin forecasts, capacity and conversion state |
| `GET /api/commercial-intake/leads/{id}` and `/quotes/{id}` | commerce queries | Native |
| `GET /api/commercial-intake/capacity-board` and quote capacity board | commerce queries | Native |
| `POST /api/commercial-intake/leads`, lead qualification/quotes, quote revisions/decisions/acceptance/conversion, resources/reservations/reschedule | commerce command application | Native studio payloads and typed commands; accepted quote conversion creates a canonical project with seven creative drafts; no payment effect |
| `GET|POST /api/v2/projects/{id}/client-portals` and portal revoke/expire | commerce client application | Native opaque-token records |
| `GET|POST /api/v2/projects/{id}/billing` and billing state | commerce billing application | Native records; no payment processing |
| `POST /api/v2/projects/{id}/repeat-orders` | commerce command application | Native fresh canonical project seeded from approved reusable references; client/publication approval is never carried |
| `GET /api/client/{token}` | commerce client projection + exact delivery build | Native safe projection |
| `GET|HEAD /api/client/{token}/master` | exact accepted master reader | Native digest/range verification |
| `POST /api/client/{token}/annotations|decision` | commerce client application | Native exact-master review records |
| `GET /api/client/{token}/download` | accepted delivery archive | Native; denied before acceptance |

## External MoonFlow/MoonBook handoff

| Previous route family | Native owner | Status |
|---|---|---|
| `POST /api/handoffs/final-deliverables` | Mooncast evidence outbox | Native immutable Mooncast evidence |
| `POST /api/handoffs/outcomes` | Mooncast evidence outbox | Native immutable Mooncast observation |
| `POST /api/handoffs/requests` | generic handoff outbox | Prepares an opaque `moonflow.pack-handoff.v1` request destined for MoonBook; no external effect |
| `POST /api/handoffs/receipt-references` | generic handoff outbox | Stores only an exact external receipt reference |
| `GET /api/handoffs/{type}/{record}` | handoff outbox query | Reads Mooncast-owned evidence/reference payloads |
| `/api/bookkeeper/**`, `/api/moonflow-bridge/**` | none | Retired by MC-8; canonical authority is external |

## MoonFlow systematic adapter

| Route | Native owner | Status |
|---|---|---|
| `GET /api/moonflow/adapter/v2/declaration` | Mooncast pack adapter | Exact 34-operation review-episode/control declaration |
| `GET /api/moonflow/adapter/v2/pack-projection` | Mooncast manifest projection | Exact selected tool/schema subset; unrelated manifest tools are excluded |
| `POST /api/moonflow/adapter/v2/invoke` | pack-local `StudioService` bridge | Durable prepared attempt, exact input digest, fixed operation dispatcher, immutable result |
| `POST /api/moonflow/adapter/v2/reconcile` | pack-local durable state | Idempotent replay or investigate-unknown without blind external retry |
| `GET /api/moonflow/adapter/v2/health[/evidence]` | pack-local exercise ledger | Five-minute health for successfully exercised operations only |

This bridge reuses the production/editor/delivery owners listed above. It is
not a MoonFlow runtime and cannot authorize publication.

## Intentionally removed aliases

| Previous route | Reason and replacement |
|---|---|
| `POST /api/generate` | Ungoverned single-asset generation; use authorized provider execution and attach evidence through project commands |
| `GET /api/assets/{asset}` | Flat legacy asset store exposed implementation identity; use `/media/{id}` or `/api/editor/media/{digest}` |
| `POST /api/assets/{asset}/review` | Review must bind a typed artifact/master/QC identity, not a flat asset |
| Monolithic project `generate`, `assemble`, `delivery-plan`, `deliver`, `analytics`, and compatibility `review` | Split into routed execution, editor export, typed governance, delivery factory and performance review |

`GET /api/assets` remains an empty migration projection so the old surface can
start without a 404; it directs callers to the two content-addressed media APIs.
