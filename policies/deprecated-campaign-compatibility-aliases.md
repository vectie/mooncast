# Deprecated campaign compatibility aliases

The current product model is the project → episode → scene → shot → asset
production graph. The following identifiers and paths remain only so installed
workspaces and existing routes continue to resolve:

- `campaign-book` and `book/campaign-book.md` alias `production-book` and
  `book/production-book.md`.
- `campaign-producer` and `skills/campaign-producer.md` alias
  `episode-producer` and `skills/episode-producer.md`.
- `campaign.publish` aliases `production.publish` with the same reviewed
  external-effect boundary and publication-receipt contract.
- `campaign-studio` aliases `production-studio`; both resolve the existing
  `/apps/mooncast/studio` runtime route.
- `campaign-operator` is a deprecated audience label; `episode-producer` is the
  current audience.

These aliases do not define a flat campaign model and must not be used for new
pack declarations.
