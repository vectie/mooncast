# Contract, quote, capacity, and project intake

Mooncast now starts before G0. The commercial intake surface answers one operational question: can the studio accept a specific paid 3–8 minute production without breaking scope, capacity, margin, rights restrictions, or the promised delivery date?

This is a pack-local record system. It does not contact a CRM, send email, sign a contract, charge a payment method, or write to an external calendar.

## Exact lifecycle

1. A lead records the customer, payable problem, current cost/time baseline, channels, measurable acceptance, and a repeat-purchase hypothesis.
2. A named human qualifies or disqualifies the exact lead version.
3. A scoped quote binds that qualified lead to a 180–480 second format, deliverables, at most two included revision rounds, overage policy, milestone amounts, rights/model/data restrictions, dates, a production budget, and an economics forecast.
4. Quote changes create a new immutable version and clear all previous approvals and acceptance.
5. Named commercial and production authorities independently approve the exact quote version. A named client acceptance is recorded only after both approvals.
6. Finite resources expose roles, skills, weekly hours, and availability. Quote-bound reservations expose hours, dates, dependencies, utilization, and conflicts. Rescheduling creates a new reservation revision.
7. Conversion requires the exact accepted quote and an exact conflict-free capacity-board digest. One conversion creates one canonical draft production project.

## Economics

The forecast retains quoted revenue, provider cost, direct labor, other direct cost, contingency, founder-hours, gross margin, contribution margin, and favorable/base/adverse cost sensitivity. The quote's three milestone amounts—deposit, approved animatic, and accepted master—must sum exactly to quoted revenue.

These are planning records, not accounting entries or a profit promise. Post-delivery billing evidence remains in the separate commercial portal ledger.

## G0 boundary

Conversion computes an intake digest over the exact lead, quote, commercial approval, production approval, client acceptance, capacity plan, and forecast. The draft brief stores that intake and quote digest. G0 requires both the exact brief approval and the unchanged intake binding.

Conversion prepopulates customer acceptance criteria, channels, objective, schedule, budget, deliverables, milestone plan, restrictions, forecast, and capacity reservations. Rights records remain pending. The brief and every creative artifact remain draft. `authority_carried_forward` and `later_authorities` are empty. Provider execution, delivery, publication, and payment authority are never inferred.

## Durable records

- `commercial-intake/studio.json` stores lead and quote histories, resources, reservation revisions, and conversions.
- `commercial-intake/audit.ndjson` stores append-only receipts for each mutation.
- `projects/` and `project-events/` receive the canonical draft and intake-binding event only at conversion.

The UI exposes Leads, Quote Builder, Capacity Board, Margin Forecast, and Convert to Project in the existing production studio.

## Next product gap

After intake, the next major product gap is a multi-project production control tower: planned versus actual labor/provider spend, live schedule drift, cross-project staffing changes, exception ownership, delivery-SLA risk, and portfolio-level contribution margin. The current slice decides whether work can be accepted; it does not yet manage several accepted productions as a studio portfolio.
