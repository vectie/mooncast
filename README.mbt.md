# Mooncast

Mooncast is an isolated MoonSuite domain pack for rights-aware AIGC campaign
production. It turns a creative brief into generated assets, provenance,
review decisions, delivery packages, and optional reviewed publication.

The repository itself is an installable pack source:

```bash
moonbook pack inspect /path/to/mooncast
moonbook pack install /path/to/mooncast /path/to/workspace host-profile.json
```

Mooncast owns campaign policy and schemas. MoonLib, MoonBook, MoonClaw,
MoonDesk, and Moonstat only consume generic pack projections.
