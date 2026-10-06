# Episode ledger

Open a project in Studio → Home → Episodes and scenes → **Open episode ledger**.
The page is an internal, read-only producer view. It joins one existing episode
to its converted quote, conversion-time capacity, rights/creative revisions,
shot/source/attempt/QC history, exact master, delivery builds, client responses
and separate commercial references. It gives the next useful step without
advancing a gate or granting any authority.

## Native host routes

- `GET /api/v2/projects/{project}/episodes/{episode}/ledger`
- `GET /api/v2/projects/{project}/episodes/{episode}/ledger/view`

A missing project or episode returns 404. A contradictory quote join is shown
as a reconciliation blocker. Costs and billing remain explicitly project-wide;
the view does not assign a project amount to every episode or total duplicates.
Absent actual provider cost, labor, other costs and founder hours remain null
and display **Unknown**. Recorded actuals from an older project revision are
labelled as last reported evidence. A quote forecast is never an actual cost.

The page distinguishes current gate readiness from retained receipts. Latest
shot attempts must have their own QC; previous passed attempts cannot make a
failed replacement look approved. Missing/revised graph source assets are
visible alongside retained attempts. Reusable asset approvals and shot
bindings are included separately from graph assets.

An **Open verified master** link requires a persisted matching episode/source
binding, current production readiness, an exact promoted export, and verified
master bytes. Historical master and gate evidence is retained. A package link
requires its exact completed build acceptance and intact archive bytes. This
does not establish that an external recipient can access it. Raw client tokens
are never reconstructed; issue/reissue links through the existing Delivery UI.

## Immutable delivery archive

Client acceptance is a separate durable fact. Acceptance now saves its receipt
beside the ZIP, rather than inserting it into and changing the already-digested
archive. The accepted download checks the exact build record, size and digest.
Historical archives that were changed by the old acceptance flow fail closed;
they require a new exact build/review, not a silent digest rewrite. Project-bound
download routes reject a build from another project.

Quote conversion retries return the original conversion record and canonical
project. A conflicting quote/project/capacity binding is held for reconciliation.
No CRM, billing, generation or publication authority is added.
Completed initialization and legacy conversions remain readback-only and preserve
subsequent edits. New quoted intakes retain a frozen, durable initialization plan;
the Commercial intake **Resume draft initialization** action completes only missing
initial records after interruption. Conflicting or removed acknowledged records
remain explicit conflicts. See [quote intake recovery](quote-intake-recovery.md)
for the exact recovery protocol and its bounded local qualification.

## Offline qualification

The focused native tests include an explicitly synthetic 180-second episode:
named fixture decisions, finite capacity, quote conversion/replay, versioned
needs, G0–G4, fifteen local deterministic shot outputs, editor export/promotion,
delivery ZIP, and a separate synthetic client decision establishing G5. G6 and
G7 semantics are unchanged. No real customer, licensed source, paid provider,
real payment, recipient access, or production economics is demonstrated.

Run the focused `studio_service/episode_ledger*_test.mbt`,
`studio_service/episode_ledger*_wbtest.mbt`, and
`studio_service/episode_acceptance_wbtest.mbt` selectors with `moon test --target
native --strip -j1`. Set `MOONCAST_LEDGER_FIXTURE_ROOT` to a new, empty owned
directory to retain the full synthetic state. Its `ledger-evidence/` directory
contains a standalone review page, master, ledger JSON, ZIP, and acceptance
sidecar. The standalone page represents the saved revision, not a live view.

The existing deterministic media fixture expects FFmpeg/FFprobe at
`.tools/ffmpeg/darwin_arm64/`; local Linux qualification uses links there to the
installed Linux tools, not a Mac executable or a paid provider. The native
module now pins `moonbitlang/x@0.4.50` because 0.4.40 uses removed `lexmatch`
syntax with the selected compiler. The UI's separate 0.4.40 pin remains intact
and is tested independently.

Caption-required delivery, deployed client identity/access, real provider costs,
two paid episodes, and full G6/G7 qualification remain open. In particular, the
existing UI delivery request still does not forward a subtitle path. This slice
does not claim the full accessible-delivery requirement.
