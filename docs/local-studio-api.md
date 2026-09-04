# Mooncast local studio API

## Commercial intake before G0

All commercial-intake endpoints are record-only and pack-local. They never send CRM/email/payment/calendar effects.

- `GET /api/commercial-intake` returns current leads, quote versions, resources, reservations, and conversions.
- `POST /api/commercial-intake/leads` records a draft payable scenario.
- `GET /api/commercial-intake/leads/{lead_id}` returns immutable lead history.
- `POST /api/commercial-intake/leads/{lead_id}/qualification` records named-human qualification against an exact version and digest.
- `POST /api/commercial-intake/leads/{lead_id}/quotes` creates quote v1 from the exact qualified lead.
- `GET /api/commercial-intake/quotes/{quote_id}` returns immutable quote history.
- `POST /api/commercial-intake/quotes/{quote_id}/revisions` creates a new exact quote version and clears approvals.
- `POST /api/commercial-intake/quotes/{quote_id}/internal-decisions` records independent commercial or production approval.
- `POST /api/commercial-intake/quotes/{quote_id}/client-acceptance` records named client acceptance after both internal approvals.
- `POST /api/commercial-intake/capacity/resources` records a finite role/skill resource.
- `POST /api/commercial-intake/capacity/reservations` reserves hours for an exact quote.
- `POST /api/commercial-intake/capacity/reservations/{reservation_id}/reschedule` versions a reservation.
- `GET /api/commercial-intake/capacity-board` returns studio-wide utilization and conflicts.
- `GET /api/commercial-intake/quotes/{quote_id}/capacity-board` returns an exact quote capacity digest.
- `POST /api/commercial-intake/quotes/{quote_id}/conversion` creates the canonical draft project from the exact accepted quote and capacity digest.

See `docs/contract-quote-capacity-intake.md` for lifecycle and authority boundaries.

## Multi-project production control tower

The systematic MoonFlow adapter is available independently of the UI:

- `GET /api/moonflow/adapter/v2/declaration` returns the 34-operation selected
  production/control declaration.
- `GET /api/moonflow/adapter/v2/pack-projection` returns the matching
  manifest-shaped tool/schema subset for MoonFlow catalog compilation.
- `POST /api/moonflow/adapter/v2/invoke` durably prepares and invokes one exact
  manifest operation.
- `POST /api/moonflow/adapter/v2/reconcile` imports a durable terminal result,
  safely replays a manifest-idempotent operation, or reports an unknown
  non-idempotent effect without retrying it.
- `GET /api/moonflow/adapter/v2/health` returns a five-minute attestation
  containing only successfully exercised operations.
- `GET /api/moonflow/adapter/v2/health/evidence` is the corresponding human
  inspection projection.

See `docs/moonflow-capability-truth.md` and
`workflows/moonfind-review-episode.md`. The control-tower adapter URLs below
remain compatibility aliases to this declaration and health state.

- `GET /api/control-tower` returns the durable portfolio projection. Optional
  `as_of_date=YYYY-MM-DD` makes schedule evaluation replayable.
- `GET /api/control-tower/projects/{project_id}/actuals` reconciles the latest
  named operating-evidence record.
- `POST /api/control-tower/projects/{project_id}/actuals` records actual labor,
  other direct cost, recognized revenue, founder-hours, completion forecast and
  optional confirmed provider cost against the exact project revision.
- `GET /api/control-tower/exceptions/{exception_id}/assignment` reconciles named
  ownership.
- `POST /api/control-tower/exceptions/{exception_id}/assignment` binds an owner
  and due date to the exact exception digest.
- `GET /api/control-tower/adapter/declaration` returns the installed
  `moonflow.adapter-declaration.v1`.
- `GET /api/control-tower/adapter/health` materializes digest-bound evidence
  below the host data root and returns a five-minute
  `moonflow.adapter-health.v1` with a workspace-relative `evidence_ref`.
- `GET /api/control-tower/adapter/health/evidence` is a human inspection view
  of the current handler/projection evidence; MoonFlow verifies the
  materialized bytes named by the attestation instead.

Operating actuals and assignments are idempotent, optimistic and durable across
restart. They record evidence/ownership only and cannot grant provider,
payment, client-acceptance or publication authority. See
`docs/production-control-tower.md` and
`docs/moonflow-capability-truth.md`.

## Project-free utility video concat

The Editor's Quick Combine drawer is separate from governed production export.
It freezes safe-file-name order, size, MIME type, and browser-computed SHA-256
for every selected MP4. It never creates production, provider, delivery, or
publication authority.

- `POST /api/editor/utility-concats` creates or idempotently retrieves a frozen
  job.
- `POST /api/editor/utility-concats/{job}/inputs/{index}` accepts one exact
  digest-pinned MP4 body, up to 64 MiB.
- `POST /api/editor/utility-concats/{job}/run` normalizes mixed audio when
  required, stream-copies compatible H.264/HEVC video, concatenates in frozen
  order, and verifies the result.
- `GET /api/editor/utility-concats/{job}` returns durable progress and evidence.
- `GET|HEAD /api/editor/utility-concats/{job}/media` serves the verified MP4
  with ETag, byte ranges, and an attachment filename.

The current job ceiling is 512 inputs and 1,000,000,000 aggregate source bytes.
Inputs must contain one supported video stream and at most one audio stream.

## Interactive proxy monitor

The Program monitor has two deliberately different surfaces. **Interactive proxy** is an immediate, browser-native timeline player driven from the canonical editor snapshot. It applies trims, cuts, track order, clip transforms, opacity, color controls, keyframes, text/image/logo/subtitle overlays, and track/clip audio gain and pan. Its clock, loop range, drift measurement, hidden media elements, and Web Audio graph are ephemeral browser state and never become editor authority.

Interactive media is served only by the existing same-origin, digest-bound take source endpoint. Video and audio are available there only after the responsive preview cache has registered a valid `mooncast-review-source-proxy@1.0.0`; rights-attested image/logo originals are the only direct visual exception. Missing or loading proxies produce an explicit blank/still range. The monitor never substitutes the procedural fixture renderer.

Opening a timeline can enqueue the authoritative low-resolution review render in the background when proxies are absent. That job remains the source of cached review segments and the **Approval render** surface. Neither surface autoplays; playback starts only from a user gesture. The interactive surface is labelled “not an approval master,” and G4/G5 decisions continue to bind to the frozen server render plan and authoritative review artifact.

If a canonical revision changes—including reconciliation after a `409`—the browser pauses all hidden media, discards its clock/media graph, and rebuilds from the returned snapshot. It does not merge stale browser edits into the new revision.

## Edit-point transitions

Transitions are durable timeline objects, not visual preferences stored on an individual clip. `configure_transition` binds one transition ID to two adjacent, contiguous clips on the same video or audio track; `remove_transition` removes it through the normal revisioned command log. Moving, trimming, splitting, or deleting either clip must leave the binding valid or the command fails closed. Undo and replay therefore preserve the transition and its provenance in exactly the same way as other edits.

Video tracks accept cut, cross-dissolve, black/white fade-through-color, wipe-left, and wipe-right. Audio tracks accept cut and equal-power crossfade. Non-cut transitions are limited to three seconds. Their outgoing post-edit handle and incoming pre-edit handle must both exist in the immutable source media, must sum to the transition duration, and may not overlap another transition region inside the same clip. The normalized object carries `transition_digest`; the frozen render plan adds its absolute cut and range without changing those parameters.

The preview cache places segment boundaries at transition edges and removes clip boundaries inside that range. A transition edit consequently changes the transition segment key while preserving unrelated cached shot segments. FFmpeg consumes the frozen transition range for `xfade` or equal-power `acrossfade` and remains the approval pixel authority.

The interactive monitor consumes the same timeline object. WebGL2 performs geometry, brightness, contrast, saturation, gamma, opacity, and transition blending. If WebGL2 or shader compilation is unavailable, the badge explicitly reports Canvas fallback; that fallback is editorial guidance only and never becomes an approval artifact.

Start from the repository root:

```bash
npm --prefix ui/rabbita-mooncast install --no-audit --no-fund
npm --prefix ui/rabbita-mooncast run build
MOONCAST_RABBITA_DIST=ui/rabbita-mooncast/dist \
MOONCAST_DATA_ROOT=var/native \
MOONCAST_PORT=4302 \
moon run cmd/studio
```

The native host never downloads runtime tools. Approved ffmpeg/ffprobe and
provider executable paths are supplied explicitly through deployment/provider
configuration.

The Studio UI is available at `/` and `/apps/mooncast/studio`; Editor and
Client Review are served by the same Rabbita release bundle.

## Endpoints

### `GET /health`

Returns service, pack, provider, model, and executable status.

### `GET /api/config`

Returns prompt, duration, cost, and publication bounds.

### `POST /api/generate`

Request:

```json
{
  "prompt": "A calm indigo launch film for a lunar notebook",
  "duration_seconds": 4,
  "rights_owner": "Mooncast operator",
  "rights_confirmed": true,
  "brand_name": "MoonSuite",
  "audience": "creative teams"
}
```

The duration must be 1–12 seconds. A successful new render returns `201`; an
identical brief reuses the immutable output and returns `200`. The response
includes the mount-relative playable `video_url`, output and request SHA-256, provider, model,
prompt, bounded CNY cost, media probe, rights, safety, labels, pending human
review, and an explicitly non-published publication state.

The endpoint accepts either bounded `Content-Length` framing or bounded
`Transfer-Encoding: chunked` framing. Both are capped at 16 KiB; combining the
two framing headers is rejected.

### `GET /api/assets` and `GET /api/assets/{asset_id}`

List or retrieve composed asset provenance and the latest append-only review.

### `GET /media/{immutable_name}.mp4`

Streams the MP4 with byte-range support for browser playback.

### `POST /api/assets/{asset_id}/review`

Request:

```json
{"reviewer_id": "creative-director", "decision": "approve", "note": "Approved"}
```

An approval makes the asset eligible for a separate publishing adapter. This
service intentionally has no publishing endpoint and never treats generation
as approval.

## V2 systematic production

### `POST /api/v2/projects`

Creates an atomic `mooncast.production-project.v2` with a 180–480 second target,
hard CNY budget, deterministic provider route, economics, and seven version-one
draft artifacts: brief, rights ledger, IP bible, script, claims ledger,
storyboard, and animatic. Creation does not approve creative work and does not
create production shots.

### `GET /api/v2/projects` and `GET /api/v2/projects/{id}`

List or retrieve complete durable projects. `GET
/api/v2/projects/{id}/events` returns the fsync-backed append-only event log.

### Creative artifact workflow

`GET /api/v2/projects/{id}/creative/{artifact}` returns the current artifact,
its immutable prior versions, exact decision lineage, and project revision.
`artifact` is `brief`, `rights-ledger`, `ip-bible`, `script`, `claims-ledger`,
`storyboard`, or `animatic`.

`POST /api/v2/projects/{id}/creative/{artifact}/revise` requires the expected
project revision, exact current artifact version/digest, named actor, and full
replacement content. It creates a new version superseding the old digest.
Creative revision closes after G3 production authorization.

`POST /api/v2/projects/{id}/creative/{artifact}/decision` separately records a
named-human `approve`, `reject`, or `request-revision` decision bound to the
exact artifact version/digest. `human_confirmed` must be true. A client
`request-revision` consumes one of the project's two revision rounds.

```json
{
  "expected_project_revision": 4,
  "expected_artifact_version": 2,
  "expected_artifact_digest": "sha256:...",
  "actor": "creative-director-wang",
  "actor_role": "creative-director",
  "human_confirmed": true,
  "decision": "approve",
  "note": "Approved for the next gate"
}
```

Revising, rejecting, or requesting revision invalidates dependent approvals
and affected gate receipts. Script binds to the current IP bible; claims and
storyboard bind to the current script; animatic binds to the current storyboard
and records expected duration and cost.

### `POST /api/v2/projects/{id}/advance`

```json
{"gate":"G0","actor":"producer","note":"Brief accepted"}
```

G0 requires exact brief approval. G1 requires exact rights-ledger and IP-bible
approvals plus cleared rights. G2 requires exact script, claims-ledger,
storyboard, and animatic approvals with current digest bindings and matching
duration. Passing G2 derives episodes, scenes, shots, timing, characters,
props, locations, transitions, and audio cues from those approved artifacts.
G3–G7 do not infer approval from generation, assembly, delivery, or analytics.
They consume the exact versioned governance records described below. Any new
upstream plan, attempt, finding, decision, master, delivery package,
publication evidence, or performance review clears affected downstream gate
receipts and appends an invalidation record.

### Production governance (G3–G7)

`GET /api/v2/projects/{id}/governance` returns the complete immutable lineage
and current project revision. Every mutation below requires
`expected_project_revision`; exact target version/digest fields are also
required where applicable.

G3 uses:

- `POST /api/v2/projects/{id}/governance/model-routing/revise`
- `POST /api/v2/projects/{id}/governance/model-routing/decision`

The plan lists every shot under a capability and asset class with provider,
model, permitted data class, fallback list, retry policy, unit estimate, and
total CNY ceiling. Every current shot must be covered. The separate decision
requires named, human-confirmed producer and finance approvals bound to the
exact plan version and digest.

G4 uses:

- `POST /api/v2/projects/{id}/governance/shots/{shot_id}/attempts`
- `POST /api/v2/projects/{id}/governance/shots/{shot_id}/qc/{dimension}/findings`
- `POST /api/v2/projects/{id}/governance/shots/{shot_id}/qc/{dimension}/decision`

`dimension` is `technical`, `continuity`, `safety`, `claims`, or `rights`.
Attempts are append-only and bind to the current model-routing digest. Findings
bind to the exact successful attempt. A named-human QC decision binds to both
that attempt and the digest of the complete current finding set. Every shot
must have an exact `pass` in all five dimensions; generation alone never
passes G4.

### Heterogeneous routed Provider Jobs

`POST /api/v2/projects/{id}/routed-executions` converts the currently passed,
exact G3 model-routing plan into one authorized Provider Job per shot. The
request requires:

```json
{
  "expected_project_revision": 12,
  "expected_routing_plan_version": 2,
  "expected_routing_plan_digest": "sha256:...",
  "actor_id": "host-provider-operator",
  "network_authority": true,
  "publication_authority": false
}
```

Each shot must resolve to exactly one configured video adapter matching the
authorized provider/model/capability. The application enforces the route's
retry and per-shot cost ceilings plus routing-plan and remaining-project
aggregate ceilings. Provider request plans bind project/shot, project revision,
G3 routing version/digest, route digest, prompt digest, prior-attempt digest,
and routed-execution identity. Public responses expose adapter identity and Job
state but never secret references or resolved secret values.

Each routed shot's `job_state.attempt_history` is a sanitized immutable phase
projection containing attempt id/ordinal, phase/state, start/end timestamps,
normalized error code/message, phase digest, usage/cost receipt digest, and
attachment receipt digest when present. `attempt_count` and `max_attempts`
remain on the job projection. It never contains raw request/response bodies,
headers, endpoints/URLs, filesystem or registry locators, secret references,
or resolved secrets.

- `GET /api/v2/projects/{id}/routed-executions`
- `GET /api/v2/projects/{id}/routed-executions/{execution_id}`
- `POST /api/v2/projects/{id}/routed-executions/{execution_id}/shots/{shot_id}/execute`
- `POST /api/v2/projects/{id}/routed-executions/{execution_id}/shots/{shot_id}/resume`
- `POST /api/v2/projects/{id}/routed-executions/{execution_id}/shots/{shot_id}/cancel`

Mooncast's pack-local **Production coordinator** composes those domain actions
without owning a general agent runtime:

- `POST /api/v2/projects/{id}/production-coordinator/routed-executions/{execution_id}/run-pending`
- `POST /api/v2/projects/{id}/production-coordinator/qc-batches`

The first preflights the complete routed shot/job binding before sequentially
running and adopting pending outputs. The second binds one explicit named-human
confirmation to the complete current shot/output set and records the five exact
QC findings and decisions required for G4. Neither route grants publication or
payment authority. Production automation is exposed only through
`/production-coordinator/...`; agent execution remains owned by MoonClaw.

Every action submits `expected_execution_revision` and
`expected_execution_digest`; cancel also submits its named `actor_id`. Planning
and Job authorization do not call a provider. If transport or host secret
resolution is absent, execute/resume returns
`routed_execution_host_not_ready` and leaves the durable Job resumable. No
routed endpoint has publication authority.

When a Job succeeds, ingestion requires exactly one video artifact and
atomically commits the project asset, budget cost, shot attachment, canonical
generation-attempt lineage, and G4+ invalidation in one project revision. The
lineage binds Job binding/config/request-plan/provider-attempt/response,
artifact/output/cost-receipt, routing-plan/route, provider/model, and timestamps.
Replaying the same `job_id:attempt_id` is idempotent; conflicting evidence,
project/shot/routing mismatches, stale unrelated project revisions, or stale
prior-attempt lineage fail before attachment.

`POST /api/v2/projects/{id}/generate` remains the local deterministic fixture
only. It is not the heterogeneous production execution path.

G5 uses:

- `POST /api/v2/projects/{id}/governance/master/technical-qc`
- `POST /api/v2/projects/{id}/governance/master/creative-director`
- `POST /api/v2/projects/{id}/governance/master/rights-compliance`
- `POST /api/v2/projects/{id}/governance/master/client`
- `POST /api/v2/projects/{id}/governance/delivery-package`
- `POST /api/v2/projects/{id}/governance/delivery-milestone`

All four decisions bind to the exact master SHA-256 and are distinct. Client
`request-revision` decisions share the same maximum-two-round counter used by
creative development. The delivery package is versioned, digest-bound to that
master, asset lineage, and rights ledger, and requires its own exact client
milestone acceptance. Only then can G5 pass.

### Customer delivery factory

After G5 passes, the local customer delivery factory turns the exact promoted
editor master into saleable delivery files. It does not edit the production
timeline and it has no publication authority. A build profile may request:

- the accepted source master;
- deterministic horizontal or vertical crop, pad, or scale variants;
- up to twelve channel cuts, each no longer than 180 seconds;
- cover frames;
- subtitle and metadata sidecars;
- a provenance, rights, and AI-label manifest; and
- checksums plus one immutable ZIP archive.

The profile is bound to the project revision, master SHA-256, delivery-package
version and digest, and profile version and digest. Their canonical combination
is the immutable build digest. Outputs are content-addressed; API projections
contain artifact digests and a download URL, never local filesystem paths.

The endpoints are:

- `GET/POST /api/v2/projects/{id}/delivery-builds`
- `GET /api/v2/projects/{id}/delivery-builds/{build-id}`
- `POST /api/v2/projects/{id}/delivery-builds/{build-id}/build`
- `POST /api/v2/projects/{id}/delivery-builds/{build-id}/retry`
- `POST /api/v2/projects/{id}/delivery-builds/{build-id}/cancel`
- `POST /api/v2/projects/{id}/delivery-builds/{build-id}/acceptance`
- `GET /api/v2/projects/{id}/delivery-builds/{build-id}/download`

Mutable actions require the displayed build revision and record digest. Durable
states are `queued`, `building`, `completed`, `failed`, `cancelled`, and
`invalidated`; a host restart returns an interrupted local build to `queued`.
Changing the upstream master, delivery package, or G5 authority invalidates the
old build. Build execution uses local ffmpeg and ZIP only, records bounded local
time/cost economics, and never calls a publication provider.

A completed build still requires a named-human `delivery-build` milestone
decision. G6 will not open until the current build is accepted. The static
Production/Delivery drawer exposes profile planning, build/retry/cancel,
artifact evidence, ZIP download, and exact build acceptance.

The subsequent customer handoff is implemented by the pack-local Customer
Delivery & Commercial Portal. It creates hashed-token, expiring/revocable links
for one exact master and build; provides a separate safe client review page;
records timecode annotations and exact client decisions; unlocks ZIP download
only after acceptance; records milestone billing without processing payment;
and creates clean repeat-order drafts without carrying approval. See
`docs/customer-delivery-commercial-portal.md` for its endpoints and authority
boundary.

G6 uses `POST
/api/v2/projects/{id}/governance/publication-authorizations`. One named-human
authorization is required for every destination in the exact delivery package.
Every authorization also binds the accepted completed delivery-build digest
and its acceptance receipt. The receipt always says
`external_effect_performed: false`; this API never publishes, uploads, or calls
a network provider. The pack no longer declares a publishing tool as part of
this lifecycle.

An already-performed publication may be observed without causing it through
`POST /api/v2/projects/{id}/governance/publication-receipts`. The observation
must bind the exact delivery and authorization digests.

G7 uses `POST
/api/v2/projects/{id}/governance/performance-review`. The named-human review
binds the exact delivery plus any observed publication receipts and records
performance metrics, recognized revenue, provider/labor/other cost, gross
margin, founder-hours, and repeat-purchase status. If the episode was not
published or metrics are unavailable, `status` must be `unavailable` or
`waived` with an explicit reason.

After G7 is recorded, `POST
/api/v2/projects/{id}/delivery/outcome-handoff` explicitly prepares three
pack-local immutable outbox records: `mooncast.production-outcome-evidence.v1`,
`mooncast.external-handoff-request.v1`, and
`mooncast.bookkeeper-ingress-bundle.v1`. The outcome binds the exact
client-accepted `mooncast.final-deliverable-evidence.v1`; the request and bundle
are inert transport inputs only. This route does not invoke MoonFlow, mutate
Bookkeeper, publish, or authorize payment. `GET /api/v2/projects/{id}` exposes
the candidates and prepared records under `outcome_handoff` for the Delivery UI.

### Production and delivery UI contract

The static studio consumes the governance and delivery-build projections and
provides:

1. a G3 route/budget table with per-shot coverage and separate producer and
   finance signature controls;
2. a G4 shot board showing attempt history, findings, and one decision control
   for each of the five QC dimensions;
3. a G5 master review surface with four independent decision cards, delivery
   package version/digest, client milestone acceptance, and a delivery factory
   for channel assets plus an immutable ZIP;
4. a G6 destination matrix bound to the accepted ZIP build that creates authorization receipts and never shows
   authorization as successful publication; and
5. a G7 review form for observed/unavailable/waived performance, economics,
   founder-hours, and repeat-purchase outcome, followed by an explicit inert
   outcome-outbox action bound to accepted final-deliverable evidence.

Every mutation form must submit the currently displayed project revision plus
the exact target version/digest. On HTTP `409`, the UI must reload governance
state rather than retrying a stale decision.

For routed execution, the UI adds a G3 execution drawer showing one resolved
adapter and ceiling per shot, aggregate committed/remaining budget, sanitized
Job state, attempts, errors, and attachment receipt. It offers Create plan,
Execute, Resume, and Cancel independently per shot; disables execution when
the exact G3 digest changes; renders `host-not-ready` as setup state rather
than a failed creative asset; and never renders or requests secret values. A
completed Job remains `pending QC` until all five G4 decision cards pass.

### `POST /api/v2/projects/{id}/generate` (local fixture)

Routes unique shots through the authorized provider, rejects estimated work
over the remaining budget, writes immutable attempt lineage, and attaches each
selected asset to every timeline shot. It leaves all five QC dimensions
pending; it cannot advance G4.

### `POST /api/v2/projects/{id}/assemble`

This is the deterministic fixture fallback, not the normal production-cut path.
After G4, it composes the selected shot timeline into a real 3–8 minute MP4 with
H.264 video, AAC audio, an embedded `mov_text` subtitle stream, visible AI
labels, ffprobe QC, master SHA-256, and complete shot lineage.

The normal path is Production G4 → Cut Editor → exact editor export → reviewed
promotion into the canonical G5 master. Production import revalidates the latest
successful attempt and all five current QC decisions per shot; legacy
`shot.status`/`shot.qc.status` flags are not authority. Attempt, provider,
model-routing, prompt, source, output, artifact, attachment, and QC digests are
retained in editor production provenance.

### `POST /api/v2/projects/{id}/review`

Compatibility route for the strict master-decision workflow. It accepts `qc`,
`editorial`, or `client` as aliases for `technical-qc`, `creative-director`, or
`client`, but still requires expected project/master digests, named actor role,
`human_confirmed: true`, and an exact decision. Rights/compliance uses its
dedicated governance endpoint.

### `POST /api/v2/projects/{id}/delivery-plan` and `/deliver`

`delivery-plan` is a compatibility alias for the strict versioned delivery
package mutation. `/deliver` only materializes an already accepted package; it
cannot create or approve one and has no publication effect.

### `POST /api/v2/projects/{id}/analytics`

Records a bounded performance observation and refreshes provider cost, revenue,
gross margin, and cost per accepted minute without changing an approved
creative contract.

## Governed cut editor media

Opening an editor project returns take records with a public `source` projection.
That projection contains only immutable digests, MIME/size, availability, and
same-origin URLs. Registry locators, filesystem paths, provider credentials, and
publication authority are never returned.

### `POST /api/editor/projects/{project_id}/media-intakes`

Freezes a typed, rights-attested local intake for `voice`, `music`, `SFX`,
`subtitle`, `image`, or `logo`. The request binds the current editor revision,
canonical production identity, safe basename, MIME type, byte size, SHA-256,
timeline duration, source reference, rights owner/basis/territory/channels, and
named rights reference. The response returns a same-origin one-use content URL.

### `POST /api/editor/projects/{project_id}/media-intakes/{intake_id}/content`

Accepts only `application/octet-stream` with a declared length of at most 64
MiB. Mooncast verifies exact length and SHA-256, stores the bytes in the
pack-local content-addressed registry, preserves immutable source and rights
metadata, and exposes the result in the asset bin on the correct existing track
kind: voice/music/SFX are audio; subtitle/image/logo are overlays. It performs
no provider or external-network call and grants no publication authority.

Subtitle intake accepts bounded, plain-text UTF-8 SRT or VTT cues. The parser
rejects unsupported styling/regions, malformed or unordered timestamps, unsafe
control/markup text, excess cues, and cues outside the declared media duration.
PNG, JPEG, and bounded VP8X WebP image/logo intake validates the file header and
pixel limits before registration. The frozen render plan carries the exact media
digest, complete intake receipt and digest, rights reference, parser/inspector
version, and subtitle cue digest. A project, rights, byte, or digest mismatch
makes the plan not ready.

The bounded low-resolution review preview and production export consume the same
real compositor graph and frozen bindings. Preview decodes the actual selected
video clips, applies cuts/transitions/color/geometry/keyframes, mixes actual
clip audio plus voice/music/SFX with track gain/pan/audio keyframes, and renders
image/logo/text/subtitle overlays at 640×360/24 fps for the complete requested
range (up to eight minutes). It never substitutes color bars, generated tone, or
fixture media when a selected registry object is unavailable. Deterministic
fixture output occurs only when the timeline explicitly references fixture
media. Existing preview queue, retry/restart, status, immutable authority, and
plan/provenance digest semantics remain unchanged. Promoted master provenance
retains the complete frozen local-media bindings and cut-plan digest.

### Responsive preview proxies and segment cache

The review profile creates at most one immutable 640×360 H.264/AAC video proxy
or AAC audio proxy for each exact original registry digest and proxy-profile
version. Proxy records retain the original digest, source provenance, and rights
references. A missing or mismatched proxy is invalidated explicitly and rebuilt
from the verified original; source assets and accepted masters are never cache
deletion targets.

The frozen timeline is divided at canonical video-clip boundaries. Each segment
key contains the project identity, exact tick range, compositor/profile version,
source or proxy digests, trims, transitions, color/effect settings, visual and
audio keyframes, track gain/pan/mute state, image/logo/text/subtitle bindings,
cue and intake-receipt digests, and transition handle settings. Revision numbers
are intentionally not cache identity: an unchanged segment is reusable after a
snapshot revision, while any render-affecting change creates a new key. Audio or
overlay clips crossing a segment boundary are source-trimmed, and their
keyframes are deterministically rebased before rendering.

The durable content-addressed index survives restart. Every hit rechecks file
size and SHA-256; missing or changed bytes become a miss. Misses rebuild only
their exact ranges, then cached segments are concatenated into the complete
preview. The cache is capped at 2 GiB and 2,000 rendered segments and evicts
least-recently-used unprotected segment outputs only. Preview status exposes hit,
miss, rebuilt-range, eviction, quota, and per-source proxy readiness evidence.

### `GET /api/editor/projects/{project_id}/takes/{take_id}/analysis`

Returns `mooncast.editor-media-analysis.v1`: probed duration, video/audio stream
metadata, a digest-bound thumbnail, and a bounded waveform peak projection. The
analysis is cached by the immutable source digest. Missing, unavailable, and
unsupported sources are returned as explicit states.

### `GET|HEAD /api/editor/projects/{project_id}/takes/{take_id}/source`

Streams a selected audio/video take read-only with `ETag`, byte-range support,
same-origin resource policy, and immutable private caching. It never accepts a
filesystem locator from the caller.

### `GET|HEAD /api/editor/projects/{project_id}/takes/{take_id}/thumbnail`

Streams the cached JPEG video thumbnail or SVG audio-waveform thumbnail. The
derived object is content addressed and revalidated against its digest before it
is served. Loading or playing source media does not invoke a paid model provider
and does not mutate the timeline.

## Governed creative workspace

The workspace API is served by the same native loopback process. Important
operational routes are:

- `GET /api/workspace/catalog`
- `POST /api/workspace/projects/{project_id}/capsules/{capsule_id}/install`
- `POST /api/workspace/projects/{project_id}/graphs/{graph_id}/revisions`
- `POST /api/workspace/projects/{project_id}/graphs/{graph_id}/runs`
- `GET /api/workspace/projects/{project_id}/runs?state=&offset=&limit=`
- `POST /api/workspace/runs/{run_id}/claim`
- `POST /api/workspace/runs/{run_id}/actions/{cancel|retry}`
- `GET /api/workspace/runs/{run_id}/events?after={event_id}` (SSE)
- `GET /api/workspace/runs/{run_id}/events/replay?after={event_id}` (JSON)
- `GET /api/workspace/projects/{project_id}/assets?q=&kind=&tag=&offset=&limit=`
- `POST /api/workspace/assets/{artifact_id}/{version}/tags`
- `POST /api/workspace/assets/{artifact_id}/{version}/delete`
- `GET /api/workspace/projects/{project_id}/proposals/{proposal_id}`
- `POST /api/workspace/projects/{project_id}/proposals/{proposal_id}/apply`
- `POST /api/workspace/comments/drafts`
- `POST /api/workspace/presence/leases`
- `POST /api/workspace/shares/secure`
- `GET /api/workspace/shares/{share_id}/access?token={token}`
- `POST /api/workspace/shares/{share_id}/revoke`

Graph writes are revision checked. Run requests freeze the exact saved graph,
and the host owns ids and timestamps for runs, comments, presence and shares.
Share creation returns the raw capability token once; storage retains only its
SHA-256 digest. Asset deletion is a reference-checked soft deletion of library
metadata and never erases immutable artifact evidence.

## External Bookkeeper handoff (MC-8)

MoonBook owns Bookkeeper. Mooncast records only its immutable production
evidence, opaque outbound MoonFlow requests destined for MoonBook, and exact
references to receipts issued externally.

- `POST /api/handoffs/final-deliverables`
- `POST /api/handoffs/outcomes`
- `POST /api/handoffs/requests`
- `POST /api/handoffs/receipt-references`
- `GET /api/handoffs/{record-type}/{record-id}`

These endpoints cannot finalize a deliverable, classify a Three-Gap finding,
approve learning, propose or apply a capability, publish, or execute a MoonFlow
step. The retired `/api/bookkeeper/**` and `/api/moonflow-bridge/**` routes are
not aliases. Accepted MC-7 records remain available only through the non-HTTP,
read-only migration adapter described in `migrations/mc7-bookkeeper-read-only.md`.
