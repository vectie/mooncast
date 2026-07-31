# MoonCast

> **Domain pack and studio · deterministic pipeline alpha.** Read the
> [product contract](docs/PRODUCT_CONTRACT.md) for the cut-editor boundary,
> provider truth, commercial acceptance and release gates.

Paid productions now enter through a pack-local commercial intake: qualified lead, immutable 3–8 minute quote, named commercial/production/client decisions, finite studio capacity, margin and founder-hour forecast, then exact quote-to-draft-project conversion. See [Contract, quote, capacity, and project intake](docs/contract-quote-capacity-intake.md). No CRM, email, payment, calendar, creative, delivery, or publication authority is inferred by this flow.

Studio also accepts a versioned MoonWiki needs/creative-strategy export. Exact
source identities are validated, approved by a named human, and bound to the
project brief, bible, and script without synthetic intent references. See
[MoonWiki needs and creative-strategy intake](docs/moonwiki-needs-intake.md).

Mooncast is an isolated MoonSuite domain pack for rights-aware AIGC production.
It turns a creative brief into generated assets, provenance,
review decisions, delivery packages, and optional reviewed publication.

The repository itself is an installable pack source:

```bash
moonbook pack inspect /path/to/mooncast
moonbook pack install /path/to/mooncast /path/to/workspace host-profile.json
```

Mooncast owns production policy and schemas. MoonLib, MoonBook, MoonClaw,
MoonDesk, and Moonstat only consume generic pack projections.

See [Responsibility and testability](docs/RESPONSIBILITY_AND_TESTABILITY.md)
for the executable ownership boundary and layered verification model.

Version 0.2 adds a systematic long-form production path alongside the original
12-second local preview: durable projects, episode/scene/shot plans, G0–G7
evidence gates, rights and bible locks, script/storyboard/animatic approval,
model routing, budget enforcement, immutable shot attempts, QC/editorial/client
review, 3–8 minute master composition, delivery packages, analytics, and
economics. The checked-in deterministic provider makes a real three-minute
H.264/AAC fixture with an embedded subtitle stream, visible AI labels, and full
shot-to-master SHA-256 lineage in seconds.

## Build and run the native production studio

```bash
npm --prefix ui/rabbita-mooncast install --no-audit --no-fund
npm --prefix ui/rabbita-mooncast run build
MOONCAST_RABBITA_DIST=ui/rabbita-mooncast/dist \
MOONCAST_DATA_ROOT=var/native \
MOONCAST_PORT=4302 \
moon run cmd/studio
```

Open <http://127.0.0.1:4302/apps/mooncast/studio>. The same native host serves
the editor, private client-review routes, typed APIs, range-capable media, and
the built Rabbita assets. Deployment must provide approved media tools and
provider configuration explicitly; the application does not download a
runtime or load a secondary application host.

Mooncast exposes exactly three product surfaces: Studio, Editor, and Client
Review. It does not ship or mount a Bookkeeper application. Final-deliverable
and outcome evidence is handed to MoonFlow for MoonBook's canonical Bookkeeper
and existing MoonBook Rabbita UI. The existing handoff outbox materializes an
inert, ordered Bookkeeper ingress bundle for MoonFlow; Mooncast retains only
outbound evidence, inert transfer values, and external receipt references.

For UI development, run the native host on port 8000 and the Rabbita Vite
server separately:

```bash
MOONCAST_RABBITA_DIST=ui/rabbita-mooncast/dist MOONCAST_PORT=8000 moon run cmd/studio
npm --prefix ui/rabbita-mooncast run dev
```

The studio accepts a rights-attested creative brief and produces a real local
H.264/AAC MP4. Each response includes its immutable video URL, SHA-256,
provider, model, prompt, bounded cost, rights, safety, explicit/implicit
labels, and human-review state. Approval is append-only and only makes an asset
eligible for a separate publishing adapter; this service does not publish.

The lower **Systematic long-form production** panel drives the complete v2
project lifecycle. It shows the G0–G7 rail, episode/scene/shot tree, rights,
provider and asset provenance, master evidence, budget, and economics after
every operation.

See [the endpoint contract](docs/local-studio-api.md) for request and response
details.

## Validate

```bash
moon run cmd/pack_boundary
moon run cmd/manifest
moon check --target native --deny-warn
moon test --target native --deny-warn
npm --prefix ui/rabbita-mooncast run build
```

`cmd/pack_boundary` is the fail-closed MoonBit-native boundary scanner. It
verifies strict manifest structure, compiled-manifest parity, pack-owned
references, symlink containment, and forbidden cross-product imports. The
runtime, validation, installation, and CI paths are MoonBit/Rabbita-only. The
completed source cutover and promotion requirements are recorded under
`migrations/`.
