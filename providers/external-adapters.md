# Configurable external provider adapters

Mooncast can describe text, image, video, voice, and music providers without
putting credentials in the pack. Set `MOONCAST_PROVIDER_CONFIG` to a host-owned
JSON file shaped like `providers/provider-catalog.example.json`. Each adapter
pins its HTTPS endpoint, model, capability, timeout, commercial-use basis,
default parameters, and `host-secret:` references.

Loading the catalog and producing a `mooncast.provider-request-plan.v1` perform
no network call and resolve no secret. Execution is possible only when the host
injects both a secret resolver and a network transport into
`ExternalProviderAdapter.execute`. The returned provider result still requires
pack-local rights, cost, provenance, QC, and human-review processing before it
can become an accepted asset. Deterministic local adapters remain the default.

Provider configuration never grants publication authority. Publication remains
a separate destination-specific external effect.
