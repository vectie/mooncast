# Editor native-source coverage

This is the authoritative migration inventory for the retired editor host.
Private helpers are grouped under the public behavior that exposes them. Every
editor behavior is now owned by MoonBit source. Native host registration,
browser binding and real executable/provider runs remain explicit external
validation boundaries; they are not alternate runtime paths.

| Retired public API | Observable behavior | MoonBit replacement | Status |
|---|---|---|---|
| `editor_export_cli.main` | Load an export request and invoke the editor export workflow | `editor/host_ports.EditorCliPort`, `editor/export.ExportWorkOrder` | MoonBit |
| `ProductionEditorExportProvider.render` / `render_review` | Resolve frozen media; compile effects, keyframes, transitions, audio and subtitles; run FFmpeg; probe exact output | `editor/render_exec.compile_with_encoding`, `execute`, `inspect_render_output`; `editor/workflow.run_verified_render` | MoonBit |
| `EditorExportService.import_project` | Materialize a production project as an editor project | `editor/integration.import_production_materialized`, `editor/workspace.import_production` | MoonBit |
| `EditorExportService.get_export` | Observe durable export state | `editor/export.observe_export`, `completed_export`, `editor/observation.observe_job` | MoonBit |
| `EditorExportService.export_media` | Return an immutable successful-export download | `editor/export.export_media`, `editor/download.export_download` | MoonBit |
| `EditorExportService.create_or_resume` | Idempotently freeze spec/plan, resume or execute bounded export | `editor/export.prepare_export`, `create_or_resume`; `editor/workflow.run_verified_render` | MoonBit |
| `EditorExportService.promote_master` | Verify an exact successful export and named authority, then promote one immutable master | `editor/integration.promote_master`, `register_master_handoff`, `production_register_master_request` | MoonBit |
| `EditorExportService.handoff_candidate` | Materialize an idempotent MoonFlow candidate after master promotion | `editor/integration.materialize_handoff_candidate` | MoonBit |
| `EditorHTTPError.response` | Stable status/code/message failure envelope | `editor/http.HttpFailure`, `failure` | MoonBit |
| `require_id`, `require_relative_path`, `require_object`, `require_expected_revision`, `require_idempotency_key`, `json_value`, `success` | Strict transport validation and response projection | `editor/http` typed validators and `HttpSuccess` | MoonBit |
| `EditorHTTPAPI.dispatch` / `dispatch_media_content` | Route project, edit, media, preview, export, promotion and handoff operations | `editor/http.routes` plus typed handlers; global router registration is a declared host boundary | MoonBit |
| `EditorKernel` / `snapshot` / `command_log` / `apply` / `undo` / `redo` / `replay` | Deterministic revisioned reducer, idempotency, immutable log and exact replay | `editor/domain.EditorSession`, `dispatch`, `replay` | MoonBit |
| Legacy edit command wire codec | Preserve exact `{contract, command_id, expected_revision, actor, type, payload}` behavior | `editor/domain.legacy_command_json`, `legacy_command_from_json` | MoonBit |
| `parse_subtitle` | Strict bounded UTF-8 SRT/VTT parsing and cue digest | `editor/media.parse_subtitles` | MoonBit |
| `inspect_visual` | Bounded PNG/JPEG/VP8X dimension inspection | `editor/media.inspect_visual` | MoonBit |
| `MediaFinding.as_dict` | Stable media-integrity finding | `editor/media.MediaFinding` | MoonBit |
| `EditorMediaRegistry.configure_analysis` | Bind FFmpeg/FFprobe executables without provider/publication authority | `editor/host_ports.MediaToolPort` | MoonBit |
| `ingest_bytes` / `ingest_file` | Immutable content-addressed original/proxy intake | `editor/media.MediaRegistry.ingest`; `editor/host_ports.EditorFileReader` | MoonBit |
| `get` / `list_proxies` / `resolve` / `source_file` / `availability` | Registry lookup, proxy lineage, byte integrity and safe availability | `editor/media.MediaRegistry` lookup, resolution, range descriptor and recovery APIs | MoonBit |
| `analyze` / `analysis_thumbnail` | FFprobe metadata, bounded thumbnail and waveform artifacts | `editor/media.probe`, `complete_analysis`, `analysis_thumbnail`; `editor/render_exec` analysis invocations | MoonBit |
| `ResponsivePreviewCache.prepare_proxies` | Resolve or generate content-addressed review proxies | `editor/preview.prepare_proxy_tasks`, `editor/render_exec.compile_proxy`, `editor/workflow.register_proxy` | MoonBit |
| `segments_for` | Deterministically slice plan and rebase keyframes into bounded segments | `editor/cache.segment_projections` | MoonBit |
| `ResponsivePreviewCache.render` | Reuse valid segments, render misses, concatenate, evict by quota and emit a report | `editor/preview.prepare_preview`, `commit_segment`, `finalize_preview_cache`; `editor/render_exec.compile_concat` | MoonBit |
| `build_render_plan` | Pin identities, revisions, media, provenance and rights; reject unsafe plans | `editor/render_plan.freeze` | MoonBit |
| `new_preview_session` / `transition_preview` | Strict preview lifecycle projection | `editor/jobs.EditorJob` and queued/start/progress/cancel/fail/retry/succeed transitions | MoonBit |
| `freeze_export_spec` | Pin export spec, estimate cost, enforce ceiling and retain provenance | `editor/export.freeze_spec` | MoonBit |
| `ExportJobStore` public methods | Atomic create/get/start/cancel/fail/retry/succeed/execute/resume | `editor/jobs`, `editor/store`, `editor/workflow` | MoonBit |
| `DeterministicEditorTestProvider.render` | Deterministic bounded renderer used only as a test provider | Real implementation is `editor/render_exec`; retained fixture behavior is an external validation provider | External validation |
| `PreviewWorker.submit/get/retry/media/close` | Durable authority-pinned worker, restart recovery and safe media observation | `editor/jobs`, `editor/observation`, durable authority store, `EditorWorkerWakePort` | MoonBit |
| `import_production_project` | Validate graph/takes/intent/budget/revisions, register payloads and build timeline | `editor/integration.import_production_materialized` | MoonBit |
| `EditorProductionImportResult.as_dict` | Typed import result envelope | `editor/integration.ProductionImportResult` | MoonBit |
| `EditorProductionAdapter.import_project` | Registry-backed production import facade | `editor/workspace.import_production` | MoonBit |
| `v0_to_v1`, `migrate_document` | Deterministic v0 editor migration and receipt | `editor/store.migrate_document` | MoonBit |
| `editor_store.replay` | Replay normalized durable command records | `editor/domain.replay`, `EditorRepository.replay` | MoonBit |
| `EditorStore.create_preview_authority` / `resolve_preview_authority` | Persist and verify exact revision/request/plan authority anchor | `editor/jobs.PreviewAuthority`, `verify_preview_authority`, `EditorRepository.put_authority/get_authority` | MoonBit |
| `EditorStore.save/load/resolve_backup/recover` | Atomic envelope, journal/backup recovery, quarantine and receipts | `editor/store.EditorRepository` save/load/backup/recover APIs | MoonBit |
| `validate_review_comment` | Bound review comments to timeline and revision round | `editor/integration.validate_review_comments`, `editor/workspace.save_review_comment` | MoonBit |
| `EditorWorkspace.import_production` / `list_projects` / `open_project` / `snapshot` | Workspace project import/list/open/current-state projections | `editor/workspace` | MoonBit |
| `create_local_media_intake` / `complete_local_media_intake` | Revision/idempotency/rights-attested two-step local intake | `editor/media.prepare_intake`, `complete_intake`; durable `editor/workspace` intake APIs | MoonBit |
| `source_media` / `source_analysis` / `source_thumbnail` | Safe take media and analysis/download descriptors | `editor/workspace.source_*`, `editor/download`, `editor/media` | MoonBit |
| `EditorWorkspace.apply` | Idempotent edit command dispatch and durable save | `editor/http.dispatch_project_command` | MoonBit |
| `save_review_comment` | Idempotent reviewed timeline comment persistence | `editor/workspace.save_review_comment` | MoonBit |
| `configure_preview_worker` / `close_preview_worker` | Bind/unbind native tools and worker lifecycle | `editor/host_ports.MediaToolPort`, `EditorWorkerWakePort` | MoonBit |
| `start_preview` / `poll_job` / `retry_preview` | Start and observe authority-pinned preview work | `editor/workspace.start_preview`, `poll_job`, `retry_job`, `editor/observation` | MoonBit |

## Declared external validation boundary

- Register the route, CLI, content, clock, ID and worker ports in the unchanged
  global native host.
- Bind the unchanged browser UI to the job observation endpoint/SSE descriptor.
- Run real browser, FFmpeg/FFprobe and external-provider validation after the
  assembled MoonBit migration is accepted for integration.

No editor-domain behavior is delegated to a secondary host at this boundary.
