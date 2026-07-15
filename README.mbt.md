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

## Run the local campaign studio

```bash
python3 -m mooncast_app.server --port 4302
```

Open <http://127.0.0.1:4302/apps/mooncast/studio> (the same UI is also served
at `/`). The Apple Silicon development path automatically downloads a pinned,
SHA-256-verified ffmpeg/ffprobe pair into ignored `.tools/` on first use. Other
platforms should provide both tools on `PATH` or through `MOONCAST_FFMPEG` and
`MOONCAST_FFPROBE`.

The studio accepts a rights-attested creative brief and produces a real local
H.264/AAC MP4. Each response includes its immutable video URL, SHA-256,
provider, model, prompt, bounded cost, rights, safety, explicit/implicit
labels, and human-review state. Approval is append-only and only makes an asset
eligible for a separate publishing adapter; this service does not publish.

See [the endpoint contract](docs/local-studio-api.md) for request and response
details.

## Validate

```bash
python3 -m unittest discover -s tests -v
moon check --target native --deny-warn
moon test --target native --deny-warn
```
