# Install

Create production namespaces and register generic tools and the production
studio. No shared runtime receives Mooncast-specific policy or schemas.

The installation release path is MoonBit-native:

```bash
moon run cmd/pack_boundary
moon build --target native cmd/studio
npm --prefix ui/rabbita-mooncast install --no-audit --no-fund
npm --prefix ui/rabbita-mooncast run build
moonbook pack inspect /path/to/mooncast
moonbook pack install /path/to/mooncast /path/to/workspace host-profile.json
```

Run the installed source with an explicit immutable UI bundle and durable data
root:

```bash
MOONCAST_RABBITA_DIST=/path/to/mooncast/ui/rabbita-mooncast/dist \
MOONCAST_DATA_ROOT=/path/to/workspace/packs/mooncast/data \
MOONCAST_PORT=4302 \
moon run cmd/studio
```

The host profile supplies provider executable paths, secret references, and
network authority. Installation never downloads tools, loads a secondary
application host, or copies domain policy into MoonSuite core.

Install only the Studio, Editor, and Client Review surfaces. Do not register a
Mooncast Bookkeeper app or UI: generic MoonFlow handoff carries Mooncast
evidence to MoonBook's canonical Bookkeeper and existing Rabbita interface.

If an existing data root contains MC-7 `application/handoff` or
`application/learning` records, leave them byte-identical and mount them only
through `LegacyBookkeeperReadOnlyAdapter` for an explicit reviewed migration.
Write new evidence and external receipt references only to
`application/handoff-outbox`. New handoff requests also write immutable
`bookkeeper-ingress-bundle` values there for MoonFlow pickup; never silently
import, rewrite, repair, or delete an accepted legacy record.

For v0.2, also create `projects`, `project-events`, `masters`,
`master-provenance`, and project-scoped `deliveries` namespaces. Existing v0.1
asset and review records remain readable and are not rewritten. New v2 projects
start with contract `mooncast.production-project.v2` and atomic revision 1.

The legacy `campaign-book`, `campaign-producer`, `campaign.publish`, and
`campaign-studio` identifiers remain registered as explicitly deprecated
compatibility aliases. They preserve installed workspace lookups and the
existing `/apps/mooncast/studio` route without defining a flat campaign model.

The retired reference runtime and vanilla static controllers were removed in
the recorded source cutover. Startup,
installation, CI, and application behavior now use only the native MoonBit host
and the built Rabbita release bundle.
