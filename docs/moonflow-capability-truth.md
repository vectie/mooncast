# MoonFlow capability truth for Mooncast

MoonFlow is the generic director. Mooncast owns the production state machines,
provider ports, editor, render evidence, client review, and delivery records.
The adapter is a durable pack-local transport over `StudioService`; it is not a
second agent runtime and it contains no MoonFlow domain policy.

## Selected callable surface

Mooncast's manifest contains more tools than the review-episode graph needs.
The installed adapter deliberately declares only these 34 implemented
operations:

```text
project.create
→ creative.artifact.revise → creative.artifact.decide → project.advance
→ asset-factory.plan.record → asset-factory.generate
→ asset-factory.review → asset-factory.bind-shots
→ animatic.plan.record → animatic.render → animatic.approve
→ model-routing.plan.revise → model-routing.plan.decide (producer + finance)
→ routed-execution.create
→ production-coordinator.run-pending
→ production-coordinator.confirm-qc
→ editor.production.import → editor.command.apply
→ editor.preview.plan → editor.preview.start
→ editor.export.create → editor.production.export
→ editor.master.promote → production.review (technical + creative + rights)
→ delivery.prepare
→ delivery-build.plan → delivery-build.execute → delivery-build.accept
→ client-portal.create → client-portal.decide
→ handoff.final-deliverable.evidence
```

The same declaration includes the three independent operating operations:
`control-tower.observe`, `control-tower.actuals.record`, and
`control-tower.exception.assign`.

The canonical static declaration is
[`integration/moonflow/adapter-declaration.v1.json`](../integration/moonflow/adapter-declaration.v1.json).
At runtime, authority, input schema, output schema, and idempotence are read
from `manifest()` for every selected operation. The adapter adds only a claim
ceiling, reconcile support, and the fixed handler. This prevents it from
becoming a second drifting manifest.

MoonFlow/MoonFind must scope its capability source bundle to the operations in
this declaration. The other manifest tools are real Mooncast/UI capabilities,
but they are not automatically callable through this adapter.

## Invoke and reconcile

- `GET /api/moonflow/adapter/v2/declaration`
- `GET /api/moonflow/adapter/v2/pack-projection`
- `GET /api/moonflow/adapter/v2/health`
- `GET /api/moonflow/adapter/v2/health/evidence`
- `POST /api/moonflow/adapter/v2/invoke`
- `POST /api/moonflow/adapter/v2/reconcile`

Invoke accepts `{request, binding}`. `request` is the exact
`moonflow.adapter.v2` request. `binding` contains only transport routing and
named operator facts such as `project_id`, `resource_id`, reviewer identity,
decision, and authority-reference metadata. It cannot add publication
authority or replace the declared typed input artifact.

Input artifacts must be safe workspace-relative paths under the configured
Mooncast data root. The adapter resolves symlinks, rejects traversal and
absolute paths, applies a 16 MiB JSON limit, and verifies MoonFlow's
order-sensitive digest over the exact bytes. A real MoonFlow
`idempotency_key` is opaque and may contain `/` and `:`; Mooncast hashes it
before using a flat durable-store key.

Before invoking a product operation, Mooncast records a prepared attempt.
Successful output and result artifacts are immutable. Replaying the same key
and exact request returns the same result. Reusing a key with changed input,
binding, schemas, authority, or operation fails closed.

Reconcile replays only manifest-idempotent operations. If a process crashes
after a non-idempotent provider/client effect may have started, reconcile
returns `investigate-unknown`, `retry_allowed:false`, and never blindly repeats
the effect.

`pack-projection` returns a manifest-shaped projection containing only the 34
selected tools and the schemas they use. Capability-source compilers must pair
that projection with this adapter declaration; passing Mooncast's full
85-tool product manifest would correctly report the unrelated tools as having
no adapter declaration.

## Health means exercised

Health is installation-specific and expires after five minutes. It lists an
operation only after that exact operation has a successful durable adapter
exercise receipt. An unexercised installation is `degraded` with an empty
operation list; declaration alone is never evidence of health.

Health evidence is materialized below the data root as
`health/mooncast-pack-local-v2-<sha256>.json`. The returned
`evidence_ref` is workspace-relative and the digest binds its exact bytes.
The older control-tower adapter URLs remain aliases to the same declaration and
exercised-only health; they no longer publish unconditional health.

## Authority boundaries

Provider execution requires a separate
`mooncast.host-authority-grant.v1` input artifact for
`provider-execution`. Animatic rendering requires the same contract for
`sandbox-process`. These grants are evidence, not new schema contracts.

The bundled deterministic ffmpeg route is a bounded render/test port. It
cannot silently stand in for a licensed provider. Publication is absent from
the review-episode graph: delivery, a client decision, and final evidence all
retain `publication_authority:false`.

Mooncast does not declare a synthetic `episode.produce-review-cut` operation.
Rights, creative approval, animatic approval, producer/finance routing,
five-dimension QC, actual editor cuts, verified rendering, named review,
immutable ZIP acceptance, and client acceptance remain separately reviewable.
