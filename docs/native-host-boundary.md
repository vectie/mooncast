# Mooncast native host boundary

Mooncast's local runtime is a native MoonBit host. It does not load a secondary
application runtime or place AIGC concepts in the host.
Domain handlers will be registered by Mooncast packages through the generic
typed router.

## Package map

- `native_host/http` owns generic request, response, exact-router, static-path,
  MIME, ETag, byte-range, and same-origin resource-policy behavior.
- `native_host/store` owns a flat-key durable JSON/blob store. Writes use a
  mode-0600 temporary file, full sync, and same-filesystem atomic rename.
- `native_host/process` owns argv-only subprocess execution for tools such as
  `ffmpeg` and `ffprobe`. It provides timeout cancellation and bounded retained
  stdout/stderr; it never passes commands through a shell.
- `native_host/transport` owns certificate-verified outbound HTTPS JSON with
  timeout and response-size limits. Callers pass headers at runtime; no
  credential is bundled.
- `native_host/runtime` owns environment secret references, OS-random IDs,
  wall-clock access, platform status, and the public runtime descriptor.
- `cmd/studio` adapts the pinned `moonbitlang/async` HTTP server to the generic
  router and serves the compiled Rabbita Studio, Editor, and Client surfaces.

The pinned MoonBit libraries already implement sockets, HTTP, TLS, async file
I/O, process spawning/cancellation, cryptographic randomness, and SHA-256.
Mooncast adds no package-local C stubs for those capabilities. Atomic rename is
provided by the already-pinned `vectie/moonlib/fsx` native wrapper.

## Security and ownership rules

- Request bodies are retained only up to 1 MiB.
- Static assets are retained only up to 512 MiB and are confined beneath the
  real static root. Encoded and parent-traversal paths are rejected.
- Static responses include SHA-256 ETags, single-range support,
  `Cross-Origin-Resource-Policy: same-origin`, and `nosniff`.
- Store keys are flat ASCII identifiers; callers cannot inject path separators.
- Secret references name uppercase environment variables. Resolved values are
  never included in runtime metadata or identifier generation.
- Subprocesses receive an executable and argv array. NUL-containing values are
  rejected, output retained in memory is capped, and timeout cancellation uses
  the native process package.
- Outbound transport permits `https://` only, verifies TLS certificates through
  the pinned TLS client, rejects userinfo/fragments/header line injection, and
  caps response bodies.

## Runtime entrypoint

The entrypoint is `cmd/studio`. It serves:

- `GET /health`
- `GET /api/runtime`
- the compiled release under `ui/rabbita-mooncast/dist`

Configuration is by `MOONCAST_HOST`, `MOONCAST_PORT`,
`MOONCAST_RABBITA_ROOT`, and `MOONCAST_RABBITA_DIST`; canonical native records
use `MOONCAST_DATA_ROOT`. Defaults are `127.0.0.1`, `8765`,
`ui/rabbita-mooncast`, its `dist` subdirectory, and `var/native`.

The native application layer owns `/api/v2/projects`, creative artifact and
decision commands, G0-G7 gate commands, routed-execution plans, provider-job
state commands, and `/media/{id}` resolution. Each project is persisted as one
atomic aggregate containing its current snapshot, append-only accepted events,
and compact idempotency receipts. Full command results are stored as immutable
digest-verified side records before the aggregate receipt is committed, avoiding
quadratic snapshot duplication. Expected revisions are checked under the service's
mutation semaphore before the aggregate is replaced, so concurrent writers do
not silently overwrite a canonical revision.

Provider execute/resume/cancel URLs are composed from the pack-local execution
application. Exact authorization is still required before the application can
use the native HTTPS and artifact-store ports; no provider action grants
publication authority.

The pack-local `studio_service` also composes the MoonBit editor application.
It owns `/api/editor/*`, durable workspace and job adapters, media analysis and
the typed ffmpeg render boundary. These are application/domain concerns and do
not move into `native_host/*`. Execution, commerce and handoff application
packages mount through async prefix extensions; their reducers and storage are
not imported into the host or duplicated in the studio router.

macOS and Linux are supported. Windows reports an explicit unsupported status
and does not start the server. Supporting Windows later requires a separate
review of atomic-store guarantees and the complete media-tool process lifecycle.

## Domain isolation

The host API deals only with bytes, JSON, paths, HTTP messages, evidence-safe
storage, process results, and transport results. Projects, episodes, scenes,
shots, assets, rights, gates, providers, timelines, and delivery remain in
Mooncast domain packages. MoonSuite core and this native host must not branch on
those domain concepts.
