# Episode actual-cost attribution

PRD: MC-W06, MOONCAST-R01, MOONCAST-B10.

## Normal entry

Open `/studio`, select a project, and open an episode's existing **Episode ledger** link. The native ledger page has an **Episode actual-cost attribution** section. Review the category reconciliation, enter an actual provider/labor/other cost in CNY or founder hours, a distinct evidence-line reference, named author and explanation, then explicitly confirm and submit. The controller redirects to a fresh durable read. No JavaScript is required for this form.

Use **Correct this exact record** on an effective record. Review its retained bytes, replace the value/evidence as needed, name the correcting author, explain the correction and confirm. Corrections retain both original and successor, with exact predecessor ID and digest. Reloading shows effective records and superseded history. A stale correction requires a fresh review.

## Meaning and boundaries

- Attribution is user-authored evidence, not an automatic split, forecast, provider charge, financial transaction, client acceptance, accounting approval or verified author identity.
- The project actuals store and commercial billing remain separate and unchanged by attribution writes. No media is regenerated.
- A missing episode category remains unknown. An explicit zero is displayed as zero.
- Unknown project totals remain unknown even when episode evidence has a known value. Confirmed provider totals are comparable only after the existing project-level reconciliation flag is set.
- A comparable remainder requires a current project actuals record and all effective category records bound to that exact project revision and actuals digest. Otherwise the category is visibly held, with no inferred remainder. Updating project actuals does not silently rebase older episode evidence; explicitly correct affected records after review.
- Known comparable over-attribution is rejected. A later change of project evidence holds the older attribution basis rather than silently allocating it.
- Evidence references identify distinct cost/time line items. Reuse across effective records is rejected. A correction may reuse its exact predecessor's reference. Shared invoices require distinct evidenced line references; the application does not infer such splits.

## Persistence and concurrency

One project-scoped attribution file contains immutable semantic records in append order. A single atomic store write commits the new record, command identity and predecessor reference together. Uncommitted temporary files are ignored; malformed committed data fails closed. Exact retries return the original record even after the project or ledger changes. A command ID with changed content or another episode is rejected.

The native production controller is a single service instance. Its existing mutation semaphore serializes attribution reads/writes and project-actuals writes with other operations using that same semaphore. This is not a global transaction across every production subsystem. Later project or evidence changes leave older attribution visibly held. This feature does not add multi-process shared-directory writer support. Use one Studio host per data root. A named author is supplied evidence, never an authentication claim.

API: POST `/api/v2/projects/{project}/episodes/{episode}/ledger/attributions` with JSON; the same ledger GET exposes `episode_actual_attribution`. The ordinary HTML form uses the sibling `/attributions/form` controller and a 303 redirect. Requests bind expected project revision, attribution revision, observed project-actuals digest, category/value, evidence, author, reason and command ID. Corrections additionally bind exact predecessor ID/digest. Form errors explain whether reload is needed; use Back to recover entered fields, and preserve a command ID for an exact uncertain-result retry.

## Qualification scope

Native persistence/controller/render tests, compiled Rabbita Studio entry and a genuine localhost HTTP write/reload/correction journey are the intended qualification boundary. Actual cloud graphical browsing was previously blocked by `ERR_BLOCKED_BY_CLIENT`; no bypass, pixel/layout acceptance, external provider/payment, client identity, deployment or customer acceptance is implied.
