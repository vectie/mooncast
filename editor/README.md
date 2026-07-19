# Mooncast MoonBit editor architecture

The editor is isolated under `editor/`; it does not add editor concepts to the
MoonSuite or Mooncast production kernels.

## Package graph

```text
editor/domain          pure timeline, commands, reducer, replay, codecs
       |
       +--> editor/render_plan   immutable renderer/cache projection
       |
       +--> editor/store         snapshot/event/job persistence adapters
       +--> editor/media         rights intake, registry, byte ranges, probe
       +--> editor/cache         proxy/segment index and dirty-range planning
       +--> editor/jobs          preview/export state, authority, recovery
       +--> editor/export        frozen export work orders and observation
       +--> editor/download      immutable content download descriptors
       +--> editor/integration   production import/master/MoonFlow handoff
       +--> editor/workspace     durable project/review/intake/job facade
       +--> editor/http          typed handlers and route descriptors

editor/render_plan --> editor/render_exec --> native_host/process
editor/store/media/cache/jobs -------------> native_host/store
editor/preview -----> media + cache + render_exec (proxy/segment/concat graph)
editor/workflow ----> jobs + media + render_exec + store (recoverable attempts)
editor/host_ports --> declared clock/ID/content/file/worker/CLI capabilities
editor/observation -> typed job projection plus SSE-or-poll descriptor
```

Only `editor/render_exec` may describe or execute FFmpeg/FFprobe processes. Only
store/media/cache application packages touch generic native storage. The domain
and render-plan packages remain deterministic and I/O-free.

## Closed editor loop

1. Import Moonwiki/MoonFlow production intent, graph bindings and verified take bytes.
2. Bind each take or local upload to immutable media and rights evidence.
3. Reduce explicit editor commands into an append-only project history.
4. Freeze one exact revision into a renderer-neutral plan.
5. Analyze sources, prepare content-addressed proxies, and derive deterministic
   segment/cache/concat work for responsive review.
6. Run recoverable preview/export jobs through argv-only process execution and
   require an exact FFprobe output inspection before delivery success.
7. Promote exactly one completed export with named authority and materialize the
   exact production `register_master` request; promotion still
   grants no publication authority.
8. Materialize Mooncast final-deliverable evidence and an opaque 3–8 minute
   handoff request from authoritative delivery bindings. An authorized host
   sends it through MoonFlow to MoonBook Bookkeeper; Mooncast receives only an
   external receipt reference.

## Deferred integration (single later validation phase)

- Register the typed route descriptors in the existing native router.
- Bind the declared clock/ID, file/content, worker and CLI ports to the host.
- Connect browser websocket/job polling to the typed handlers.
- Run one repository-wide MoonBit format/check/test pass plus UI-to-UI preview
  and export validation in the release-validation phase.

No MoonBit validation command was run while creating these packages, by design.
