# Multi-project production control tower

MoonCast's control tower turns accepted production records into a durable,
evidence-aware studio portfolio. It is a domain projection and operating
surface, not another agent runtime.

## What it answers

For every canonical project, the projection shows:

- accepted quote plan versus actual provider, labor and other direct cost;
- recognized revenue, gross and contribution margin, and founder-hours;
- provider cost by generation, asset factory, animatic, post-production and
  automated-QC operations;
- remaining creative approvals, outputs, QC, master, delivery, acceptance and
  G7 review;
- promised date, forecast date, drift and delivery-SLA risk;
- revision rounds used, remaining and overage;
- accepted-minute cost only after exact master delivery and client acceptance;
- explicit missing evidence rather than inferred CRM, invoice, payment,
  provider, publication or accounting facts.

The portfolio projection aggregates values only when the underlying evidence is
complete. An absent actual labor or revenue record therefore produces `null`,
not a misleading zero.

## Capacity and exceptions

The existing intake board proves whether one quote can be converted. The
control tower additionally compares accepted project reservations against one
another. Overlapping hours above a finite resource's weekly capacity create a
stable, digest-bound conflict and list eligible alternative resources by role,
skills, availability and remaining hours.

Exceptions cover missing evidence, SLA risk, direct-cost overrun, revision
overage, provider-cost discrepancy and cross-project capacity conflict. A named
assignment records owner, role and due date against the exact exception digest.
Assignment is an operating acknowledgement only: it grants no provider,
payment, delivery or publication authority.

## Durable commands

Operating actuals are stored per project. They bind an idempotent command ID,
the exact project revision, optimistic prior version/digest, named actor,
observation time and at least one evidence reference.

Exception assignments are stored per stable exception ID. They bind an
idempotent command ID, exact exception digest, optimistic prior assignment,
named owner/assigner and a valid due date.

The service rejects stale revisions, stale exception evidence and re-use of an
idempotency key with different content. Both record types can be fetched by
their normal `GET` handler for reconciliation after a timeout or restart.

## Rabbita surface

The Production Studio's **Control tower** tab presents portfolio KPIs,
project-level plan/actual variance, provider components, work remaining,
schedule and revision risk, missing evidence, capacity conflicts and an
exception inbox. Operators can record evidenced actuals and assign exceptions
without leaving the existing studio.

## Authority boundary

The projection is read-only over canonical production, commerce, editor,
delivery and outcome records. Its two mutations record operating evidence and
ownership. It cannot:

- execute a model provider or edit an episode;
- infer a payment, invoice, CRM event or publication;
- accept a master or a client milestone;
- authorize an external effect;
- replace MoonFlow orchestration or MoonClaw reasoning.

See [MoonFlow capability truth](moonflow-capability-truth.md) for the exact
cross-product contract.
