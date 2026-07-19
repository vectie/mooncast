# MoonWiki needs and creative-strategy intake

Mooncast accepts a passive, versioned `moonwiki.mooncast-needs-export.v1`
packet at `POST /api/v2/needs-intakes`. MoonWiki remains the durable knowledge
owner. Mooncast has no MoonWiki credentials, API client, search index, agent
loop, or write-back authority.

The packet carries exact source IDs, versions, SHA-256 digests, provenance
references, and three source-owned intent records for the brief, bible, and
script. It also carries the customer and payable problem, audience and
channels, measurable acceptance, repeat hypothesis, contract and payment
boundary, budget and revision limits, rights and confidentiality constraints,
provider/data restrictions, creative objective, narrative proposition, claims,
metrics, negative constraints, and unresolved questions.

Mooncast computes a deterministic provenance digest over the typed packet and
stores each imported version immutably under `application/needs-intake`.
Incomplete packets remain inspectable, but cannot be approved. Approval uses
`POST /api/v2/needs-intakes/{packet-id}/decisions` and must bind the displayed
packet version and provenance digest to a named, explicitly confirmed human.

After approval, `POST /api/v2/needs-intakes/{packet-id}/seed-project` creates
the normal project → episode → scene → shot graph, seeds the governed creative
drafts, and records an immutable project/intake binding. The brief, bible, and
script copy the exact three MoonWiki evidence references supplied by the
packet. There is no `moonwiki:*` fallback and no synthesized source identity.

The import, decision, and seed paths always retain
`publication_authority=false` and `provider_execution_authority=false`. Provider
execution still begins only after G3 routing authority; publication remains a
separate G6 effect. MoonFlow transport, MoonBook learning, and MoonClaw
reasoning remain outside this evidence port.

Studio exposes this workflow in the existing **Needs / Strategy** tab; no
fourth Mooncast application is introduced.
