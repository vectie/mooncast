# Mooncast non-editor MoonBit migration coverage

Status: implementation-complete at the domain and application boundaries described below. This document deliberately excludes editor packages. The replacement behavior lives in MoonBit packages under `production/`, `kernel/`, `execution/`, `commerce/`, `handoff/`, and `application/`.

The only work intentionally outside this matrix is:

- global native-host route registration against the descriptors in `application/http_contracts/routes.mbt`;
- deployment-specific ffmpeg, ffprobe, font, storage-root, provider-endpoint, and host-secret configuration;
- live-provider acceptance and browser UI-to-UI validation.

Those are host wiring, external credentials, or deferred live validation. The domain and application behavior is covered. The MoonBit runtime never downloads tools silently or loads a secondary host.

## Public module and host entrypoints

| Retired public entrypoint | Exact MoonBit replacement | Status |
|---|---|---|
| `server.MooncastServer`, `MooncastHandler.do_GET/do_POST/do_HEAD` | `application/http_contracts.ApplicationRouteDescriptor`, the typed handlers in `application/http_contracts/handlers.mbt`, and the existing generic native HTTP request/response ports | Complete at application boundary; global native-host route registration remains host wiring |
| `server.create_server/main`, `MooncastServer.server_close` | Host composition over `all_application_routes`; service lifecycle and signal handling contain no domain policy | Host wiring |
| `moonflow_cli.main` | Retired as an in-pack orchestrator; `OutboundHandoffService` records only Mooncast evidence, opaque requests, and external receipt references | Complete ownership correction; authorized host transport remains external |
| `provider_execution.JSONPostRequest/JSONPostTransport/HostSecretResolver/ResultNormalizer` | `ProviderHttpPlan`, `native_host/transport`, `SecretRef`, `ProviderWireResult`, and `ProviderExecutionService.materialize_artifacts` | Complete |
| `providers.DeterministicShotProvider` | `LegacyPreviewService` and the deterministic preview provider path | Complete |
| `project_store.ProjectStore` | `ProjectRepository` | Complete |
| `store.AssetStore` | `LegacyPreviewService` asset/review/projection queries | Complete |
| `bookkeeper.BookkeeperService`, `bookkeeper_store.BookkeeperStore` | No active replacement in Mooncast; MoonBook Bookkeeper is canonical. `LegacyBookkeeperReadOnlyAdapter` preserves accepted MC-7 records for explicit migration | Retired by MC-8 |
| `moonflow_bridge.MoonFlowBridge`, `moonflow_bridge_store.MoonFlowBridgeStore` | No in-pack orchestrator; `ExternalHandoffRequest` targets the external `moonflow.pack-handoff.v1` contract | Retired by MC-8 |
| `commercial_intake.CommercialIntakeService`, `commercial_portal.CommercialPortalService` | `CommercialApplicationService` and commercial reducer | Complete |
| `routed_execution.RoutedExecutionService` | routed execution application methods and `ProductionPipelineService` | Complete |
| `delivery_factory.DeliveryFactory` | `DeliveryFactoryService` | Complete |

## Production project and creative development

| Retired reference | Public behavior | Exact MoonBit replacement | API/store replacement | Status |
|---|---|---|---|---|
| `production.py:utc_now` | Host timestamp | `application/production.production_recorded_at` | Host timestamp is injected into typed commands and receipts | Complete |
| `production.py:canonical_digest` | Canonical evidence digest | `application/production.canonical_json_digest`; package-local `content_digest` | Digests bind commands, graph breakdowns, analytics, economics, and provenance | Complete |
| `production.py:validate_project_id` | Enforce lowercase A–Z project identifier policy | `production/project.valid_project_id`; `ProjectRepository.get/create` policy checks | `/api/v2/projects/{id}` handlers and repository keys | Complete |
| `production.py:new_project` | Build a bounded 3–8 minute production | `application/production.NewProductionRequest`; `new_production_snapshot`; `production/project.validate_graph` | `production_project_create_handler`; `POST /api/v2/projects` descriptor; `ProjectRepository.create` and `project.created` | Complete |
| `production.py:flattened_shots` | Canonical shot order | `production/project.flattened_shots` | Used by routing and long-form composition | Complete |
| `production.py:next_gate` | First unpassed G0–G7 gate | `kernel.next_gate`; `kernel.projection` | Project projection returned by every command | Complete |
| `production.py:advance_gate` | Ordered, evidence-bound named-human gate advance | `kernel.gate_readiness`; `kernel.handle`; `ProjectRepository.advance_gate` | `production_advance_gate`; `gate-advanced` domain event and repository event | Complete |
| `production.py:apply_delivery_plan` | Compatibility delivery-plan mutation | `ProjectRepository.revise_delivery_package`; `production/governance.delivery_package_valid` | `production_delivery_plan`; `delivery-package-recorded` | Complete |
| `production.py:record_analytics` | Bounded reach/completion evidence and G7 invalidation | `AnalyticsObservation`; `ProjectRepository.record_analytics`; `kernel.invalidate_from_gate` | `production_analytics_handler`; immutable `analytics-{project}-{id}.json` | Complete |
| `production.py:refresh_economics` | Provider cost, revenue, margin, accepted-minute cost | `EconomicsProjection`; `ProjectRepository.refresh_economics/economics` | Exact `economics-{project}.json`; performance review remains the G7 governing record | Complete |
| `creative_development.py:current_artifact` | Latest artifact by kind | `production/creative.current_artifact` | `creative_artifact_get_handler` and creative GET descriptors | Complete |
| `creative_development.py:artifact_approved` | Exact-current human approval | `production/creative.exact_approval`; `creative_decision_is_current` | G0–G2 readiness | Complete |
| `creative_development.py:initial_creative_bundle` | Initial brief, rights, bible, script, claims, storyboard, animatic | `application/production.new_production_snapshot` and its artifact factory | Initial project snapshot | Complete |
| `creative_development.py:revise_artifact` | Optimistic revision, immutable version, downstream invalidation | `artifact_revision_valid`; `invalidation_for`; `ProjectRepository.revise_creative_artifact` | Creative revise descriptors; `creative-artifact-recorded` with `invalidates_from_gate` | Complete |
| `creative_development.py:decide_artifact` | Named-human exact-version decision | `creative_decision_valid`; `ProjectRepository.decide_creative_artifact` | Creative decision descriptors; `creative-decision-recorded` | Complete |
| `creative_development.py:creative_gate_ready` | G0–G2 requirements | `kernel.gate_readiness` | Readiness/advance command result | Complete |
| `creative_development.py:derive_production_breakdown` | Episode/scene/shot/duration derivation | `application/production.derive_production_breakdown` | Returned as typed `ProductionBreakdown` | Complete |

## Production governance

| Retired reference | Public behavior | Exact MoonBit replacement | Event/API replacement | Status |
|---|---|---|---|---|
| `initial_governance_state` | Empty governed state and inert authority | `kernel.empty_snapshot`; `production/governance.no_external_authority` | Initial snapshot | Complete |
| `invalidate_from_gate` | Remove stale gate receipts and preserve evidence | `kernel.invalidate_from_gate`; event `invalidates_from_gate`; `DependencyInvalidation` | All revision commands and analytics | Complete |
| `revise_model_routing_plan` | Complete shot coverage, retry and budget limits | `routing_plan_valid`; `ProjectRepository.revise_model_routing_plan` | `routing-plan-recorded`; model-routing revise descriptor | Complete |
| `decide_model_routing_plan` | Exact producer/finance decision | `routing_decision_valid`; `routing_exact_approved`; `ProjectRepository.decide_model_routing_plan` | `routing-decision-recorded`; decision descriptor | Complete |
| `model_routing_approved` | Producer and finance approval over exact version | `routing_exact_approved` | G3 readiness | Complete |
| `append_generation_attempt` | Route-bound, cost-bounded attempt | `generation_attempt_valid`; `ProjectRepository.append_generation_attempt` | `generation-attempt-recorded`; shot-attempt descriptor | Complete |
| `ingest_provider_job_artifact` | Normalize provider result, persist content-addressed bytes, bind attempt and exact project-ingest receipt | `ProviderExecutionService.materialize_artifacts/record_project_ingest`; `ProductionPipelineService.routed_action_and_ingest`; `ProviderResultArtifact`; `ProjectRepository.append_generation_attempt` | Provider job/attempt/ingest records plus generation event | Complete |
| `record_shot_qc_finding` | Exact successful output and five-dimension finding | `qc_finding_valid`; `ProjectRepository.record_shot_qc_finding` | `qc-finding-recorded`; QC finding descriptors | Complete |
| `decide_shot_qc` | Named-human exact-finding decision | `qc_decision_valid`; `ProjectRepository.decide_shot_qc` | `qc-decision-recorded`; QC decision descriptors | Complete |
| `shot_qc_passed` | All five dimensions pass every shot | `qc_dimensions`; `shot_passes_qc` | G4 readiness | Complete |
| `register_master` | Versioned master lineage | `master_record_valid`; `master_domain_record`; `ProjectRepository.register_master` | `master-recorded` | Complete |
| `decide_master` | Technical, creative, rights, and client decisions | `master_decision_valid`; `ProjectRepository.decide_master` | Master decision descriptors; `master-decision-recorded` | Complete |
| `master_decisions_approved` | Four exact-master approvals | `master_exact_approved` | G5 readiness | Complete |
| `revise_delivery_package` | Exact master, destinations, manifest, rights lineage | `delivery_package_valid`; `ProjectRepository.revise_delivery_package` | `delivery-package-recorded` | Complete |
| `decide_delivery_milestone` | Exact package acceptance | `delivery_acceptance_valid`; `ProjectRepository.decide_delivery_milestone` | `delivery-acceptance-recorded` | Complete |
| `delivery_accepted` | Current delivery accepted | `delivery_exact_accepted` | G5 readiness | Complete |
| `decide_delivery_build` | Exact completed build decision | `DeliveryFactoryService.record_acceptance/acceptance/accepted_build` | Delivery-build acceptance endpoint and immutable acceptance record | Complete |
| `delivery_build_accepted` | Current exact accepted build query | `DeliveryFactoryService.accepted_build/accepted_archive` | Client download and publication-authority preparation | Complete |
| `authorize_publication` | Destination-specific human authority without performing publication | `publication_authorization_valid`; `ProjectRepository.authorize_publication`; `execution.authorize_publication` | `publication-authorization-recorded`; authority request remains inert | Complete |
| `publication_authorized` | Every destination exactly authorized | `publication_exact_authorized` | G6 readiness | Complete |
| `observe_publication_receipt` | Observe host-performed publication receipt | `publication_observation_valid`; `ProjectRepository.observe_publication_receipt` | `publication-observation-recorded` | Complete |
| `record_performance_review` | Metrics, economics, founder hours, repeat-purchase status | `performance_review_valid`; `ProjectRepository.record_performance_review` | `performance-review-recorded` | Complete |
| `performance_review_complete` | Current evidence-bound performance completion | `performance_current` | G7 readiness | Complete |
| `governance_gate_ready` | G3–G7 policy | `kernel.gate_readiness` | Project readiness command | Complete |

The application enforces the two-round client revision limit across all portals for a project in `CommercialApplicationService.record_client_decision`.

## Provider adapters and execution

| Retired reference | Public behavior | Exact MoonBit replacement | Durable/API replacement | Status |
|---|---|---|---|---|
| `ProviderAdapterConfig.parse` | Typed provider config decoding | `application/execution.provider_catalog_from_json`; derived `FromJson` on `ProviderAdapterConfig` | Host supplies a provider catalog document | Complete |
| `ProviderAdapterConfig.public_record` | Secret-safe readiness view | `ProviderAdapterConfig.public_readiness`; `ProviderCatalog.readiness` | `/api/provider-executions/config` | Complete |
| `ExternalProviderAdapter.plan` | Inert bounded POST plan | `ProviderAdapterConfig.request_plan`; `ProviderHttpPlan` | Provider authorization endpoint | Complete |
| `ExternalProviderAdapter.estimate_cost` | Bound request cost before authority | Route `cost_ceiling_cny`; `ProviderHttpPlan.cost_ceiling_cny`; `deterministic_preview_cost` for the local fixture | Plan/authority exact binding | Complete |
| `ExternalProviderAdapter.generate` | Compatibility generation entrypoint | `ProviderExecutionService.authorize/execute`; local fixture `LegacyPreviewService.render` | Provider job or preview asset records | Complete |
| `ExternalProviderAdapter.execute` | Bounded HTTPS JSON request | `ProviderExecutionService.execute`; existing `native_host/transport.send_json` port | `ProviderHostEffectReceipt` records the network effect | Complete |
| `ProviderAdapterCatalog.from_document` | Catalog construction | `provider_catalog_from_json`; `ProviderCatalog` | Host-owned catalog configuration | Complete |
| `ProviderAdapterCatalog.from_host_environment` | Resolve deployment config and secret references | `ProviderCatalog` plus `SecretRef` resolution inside execution | Deployment-specific catalog/credentials | Host wiring / external credentials |
| `ProviderAdapterCatalog.resolve` | Exact adapter/capability lookup | `ProviderCatalog.find/resolve` | Routed provider planning | Complete |
| `ProviderAdapterCatalog.public_records` | Safe adapter list | `ProviderCatalog.readiness`; `ProviderExecutionService.capabilities` | Config handler | Complete |
| `JSONPostRequest` / `JSONPostTransport` | Bounded JSON POST port | `ProviderHttpPlan`; existing `native_host/transport.JsonRequest/send_json` | Provider execution application service | Complete |
| `HostSecretResolver` | Resolve a named host secret without persisting its value | existing `native_host/runtime.SecretRef`; `ProviderExecutionService.headers_for` | Only secret references are durable | Complete |
| `ResultNormalizer` | Typed provider response normalization | `ProviderWireResult`; `ProviderExecutionService.materialize_artifacts` | Content-addressed `ProviderResultArtifact` records | Complete |
| `ProviderExecutionService.from_host_environment` | Construct service from deployment configuration | `ProviderExecutionService.new` with host-decoded `ProviderCatalog` | Host supplies roots/catalog and external credentials | Host wiring / external credentials |
| `DeterministicShotProvider.estimate_cost` | CNY 0.08/second fixture estimate | `deterministic_preview_cost` | Local preview | Complete |
| `DeterministicShotProvider.generate` | Deterministic bounded MP4 fixture | `LegacyPreviewService.render` | Preview asset/media records | Complete |
| `provider_for_route` | Route to configured provider | `ProviderCatalog.resolve`; `ProviderExecutionService.route_adapter`; `create_routed_from_catalog` | Routed execution | Complete |
| `ProviderExecutionService.capabilities` | Runtime provider capabilities | Same-named MoonBit method | Config endpoint | Complete |
| `ProviderExecutionService.get/list` | Durable provider job queries | `load_job/list_jobs` | Provider GET/list handlers | Complete |
| `ProviderExecutionService.attempt_projection` | Attempt history | `attempt_projection` | Job projection | Complete |
| `ProviderExecutionService.authorize` | Named actor, config digest, plan digest, cost and retry authority | Same-named MoonBit method plus `execution.reduce_provider_command` | Immutable provider-job record | Complete |
| `ProviderExecutionService.cancel` | Authorized cancellation | Same-named MoonBit method | Provider action handler and provider events | Complete |
| `ProviderExecutionService.execute` | Retryable transport, normalize response, content-address artifacts | Same-named MoonBit method | Provider events, attempt phases, host-effect receipts | Complete |
| `ProviderExecutionService.recover` | Restart recovery | `recover_interrupted` | Interrupted running jobs become retryable/failed | Complete |
| `RoutedExecutionService.list/get` | Project-scoped routed queries | `list_routed_executions/load_routed_execution` | Routed list/get handlers | Complete |
| `RoutedExecutionService.create` | Expand exact route into one authorized job per shot | `create_routed_from_catalog/create_routed_execution`; `execution.plan_routed_execution` | Routed create handler and durable routed record | Complete |
| `RoutedExecutionService.action` | Execute/resume/cancel a bound shot | `routed_action`; `routed_state` | Routed action handler | Complete |

## Long-form composition, preview assets, and runtime

| Retired reference | Public behavior | Exact MoonBit replacement | Durable/API replacement | Status |
|---|---|---|---|---|
| `longform.generate_shot_assets` | G3-authorized, route/cost-bounded shot generation and project ingest | `create_routed_from_catalog`; provider job content addressing; `ProductionPipelineService.routed_action_and_ingest` | Routed execution/job records and generation attempts | Complete |
| `longform.assemble_master` | G4, exact shot lineage, concat, SRT, audio/subtitle/duration QC, provenance | `LongformProductionService.assemble_master`; `master_domain_record` | Assemble handler; master MP4/SRT/provenance store | Complete |
| `longform.prepare_delivery` | G5 exact accepted package materialization | `LongformProductionService.prepare_delivery` | Prepared-delivery immutable record | Complete |
| `render.RenderError` | Typed user-facing rendering failures | `PreviewApplicationError`; `LongformApplicationError` | HTTP handlers translate failures without leaking process output | Complete |
| `render.render_video` | Render/reuse 1–12 second rights-confirmed, safety-bounded, visibly labeled MP4 | `normalize_preview_brief`; `LegacyPreviewService.render`; `probe` | `POST /api/generate`; preview metadata and media | Complete |
| `store.AssetStore.get` | Asset metadata, latest human review, inert publication projection | `LegacyPreviewService.get_asset/reviews/get_projection` | Asset GET handler | Complete |
| `store.AssetStore.list_assets` | Asset list with review/publication projection | `LegacyPreviewService.list_assets/list_projections` | Asset list handler | Complete |
| `store.AssetStore.review` | Named decision bound to exact SHA | `LegacyPreviewService.review` | Review endpoint and immutable review record | Complete |
| `runtime.resolve_ffmpeg` | Resolve ffmpeg/ffprobe | Constructor-injected executable paths plus `runtime_readiness`; `ProductionRuntimeReadiness` | `/api/config` and `/health` expose readiness; no alternate application host | Complete |
| Retired pinned auto-download branch | Download and unpack binaries | Intentionally a deployment/bootstrap responsibility, never application behavior | Host installs/configures executable paths; application never performs network bootstrap | Host wiring |

## Delivery factory

| Retired `DeliveryFactory` behavior | Exact MoonBit replacement | Durable/API replacement | Status |
|---|---|---|---|
| construction and restart recovery | `DeliveryFactoryService.new/recover_interrupted` | Typed state/output stores | Complete |
| `create` and profile normalization | `DeliveryBuildRequest` requires exact G5/client acceptance and an editor master-promotion digest; `DeliveryBuildProfile`; `DeliveryFactoryService.create`; `execution.reduce_delivery_command` | Delivery create endpoint and queued build record | Complete |
| `list/get` | `DeliveryFactoryService.list/load` | Delivery list/get handlers | Complete |
| stale build invalidation | `invalidate_if_stale`; reducer action `invalidate` | `build-invalidated` state transition | Complete |
| `cancel` | `DeliveryFactoryService.cancel` | Delivery action handler | Complete |
| `retry` | `DeliveryFactoryService.retry` | Delivery action handler | Complete |
| `build` | Exact profile, argv-only ffmpeg, content-addressed artifacts, manifest, zip | `DeliveryFactoryService.build`; `DeliveryArtifactManifest` | Build endpoint and durable artifact/archive records | Complete |
| `download` | Only exact accepted archive | `accepted_archive`; `delivery_download_handler` | Download endpoint | Complete |
| build acceptance/publication preparation | `record_acceptance/acceptance/accepted_build/publication_authority_request` | Acceptance record and inert publication-authority request | Complete |

## Commercial intake, client portal, billing, and repeat orders

| Retired reference | Public behavior | Exact MoonBit replacement | API/store replacement | Status |
|---|---|---|---|---|
| `CommercialIntakeService.dashboard` | Complete commercial state | `CommercialApplicationService.dashboard_json/load` | Commercial dashboard handler | Complete |
| `get_lead/get_quote` | Latest exact version | `CommercialApplicationService.lead/quote` | Lead/quote GET handlers | Complete |
| `create_lead/qualify_lead` | Lead intake and qualification | `QualifiedLead`; `LeadQualificationDecision`; `lead_is_qualified`; commercial reducer actions | Lead create/qualification descriptors and audit receipts | Complete |
| `create_quote/revise_quote` | Versioned scoped quote and forecast | `ScopedQuote`; `MarginForecast`; `quote_terms_valid`; commercial reducer | Quote create/revise descriptors | Complete |
| `decide_quote/accept_quote` | Internal and client exact-version decisions | `QuoteDecision`; `quote_is_internally_approved`; `quote_is_client_accepted` | Quote decision/acceptance descriptors | Complete |
| `create_resource/create_reservation` | Capacity resource and reservation | `CapacityResource`; `CapacityReservation`; commercial reducer | Capacity endpoints | Complete |
| `reschedule` | Exact-version reservation replacement | `reschedule_reservation` | Reschedule handler/descriptor | Complete |
| `capacity_board` | Workday allocation and conflicts | `calculate_capacity`; `CommercialApplicationService.capacity_board` | Global/quote capacity handlers | Complete |
| `convert` | Accepted quote to governed project binding | `QuoteConversion`; commercial reducer | Conversion descriptor and audit receipt | Complete |
| `CommercialPortalService.create_portal` | Opaque token returned once; digest only persisted | `create_client_portal`; `ClientPortalAccess/Creation` | Portal create handler/descriptor | Complete |
| `list_portals/control_portal` | Project portals, revoke, expire | `portals_for_project`; `control_portal` | Portal list/control descriptors and handlers | Complete |
| `projection` | Safe client projection | `client_portal_for_token/client_projection`; `portal_current` | Client projection handler | Complete |
| portal access audit | Immutable observation of project-summary access | `ClientPortalObservation`; `record_client_observation/client_observations` | `portal.accessed`; client-observation list descriptor/handler | Complete |
| `master` | Exact portal-bound master | `client_master_handler`; long-form provenance/blob query | Client master endpoint | Complete |
| master stream audit | Immutable observation bound to exact master bytes | `record_client_observation` | `master.streamed` | Complete |
| `annotate` | Exact timecoded annotation | `append_annotation`; `CommercialApplicationService.annotate` | Annotation handler | Complete |
| `decide` | Exact client decision and bounded revision rounds | `append_client_decision`; `record_client_decision` | Decision handler | Complete |
| `download` | Accepted exact delivery archive | `client_download_handler`; `DeliveryFactoryService.accepted_archive` | Client download endpoint | Complete |
| annotation, decision, and download audit | Preserve client-operation observations without payment/publication authority | `record_client_observation` | `annotation.created`, `delivery.decided`, `delivery.downloaded` | Complete |
| `billing/create_billing/update_billing` | Milestone billing records and legal state transitions without payment effect | `MilestoneBillingEntry`; `transition_billing`; billing queries/handler; commercial reducer | Billing descriptors/audit receipts | Complete |
| `repeat_order` | New proposal without carrying approval/publication authority | `RepeatOrderProposal`; `repeat_order_safe`; commercial reducer/query | Repeat-order descriptor | Complete |

## MC-8 outbound evidence and external Bookkeeper boundary

The former pack-local Bookkeeper and MoonFlow bridge are not migrated into
Mooncast. MoonBook owns Bookkeeper; MoonFlow owns orchestration. Mooncast has no
finalization, Three-Gap classification, learning, capability proposal, ability
update, disposition, evaluation, adoption, or due-action service.

| Mooncast-owned behavior | MoonBit contract/application | Durable/API replacement | Status |
|---|---|---|---|
| Freeze exact completed-production evidence | `FinalDeliverableEvidence`; `OutboundHandoffService.record_final_deliverable_evidence` | `application/handoff-outbox`; `POST /api/handoffs/final-deliverables` | Complete |
| Record exact production outcome evidence without gap inference | `ProductionOutcomeEvidence`; `record_production_outcome_evidence` | `application/handoff-outbox`; `POST /api/handoffs/outcomes` | Complete |
| Prepare an opaque MoonFlow request destined for MoonBook | `ExternalHandoffRequest`; `moonbook_handoff_request`; `prepare_request` | `POST /api/handoffs/requests`; no external effect | Complete |
| Retain an exact external receipt pointer | `ExternalHandoffReceiptReference`; `record_receipt_reference` | `POST /api/handoffs/receipt-references`; issuer payload remains authoritative | Complete |
| Read accepted MC-7 records for explicit migration | `LegacyBookkeeperReadOnlyAdapter` returning opaque JSON/envelopes | Old roots are never mounted as mutation routes and remain byte-identical | Read-only migration only |

The obsolete Bookkeeper/MoonFlow schemas, reducers, mutable application service,
routes, schedule, and Mooncast Bookkeeper UI are removed. Canonical MoonBook
import decides whether an exact legacy payload is admissible; Mooncast never
rewrites or reclassifies it.

## Project store and codecs

| Retired reference | Exact MoonBit replacement | Store/event replacement | Status |
|---|---|---|---|
| `ProjectStore.create/get/list` | `ProjectRepository.create/get/list` | Atomic project snapshots plus `project.created` | Complete |
| `ProjectStore.save` | `ProjectRepository.handle` for domain changes; `replace` for exact import/recovery | Domain events first, then snapshot, then repository receipt | Complete |
| `ProjectStore.events/record_event` | `ProjectRepository.events/record_repository_event` | Append-only project repository events | Complete |
| temporary-file recovery | `ProjectRepository.recover_temporary_files`; atomic store cleanup | Removes abandoned store-owned temporary keys only | Complete |
| project JSON codecs | `kernel.evaluate_json`, `snapshot_to_json/from_json`, `event_to_json/from_json`; application request codecs | Versioned v2 contracts | Complete |
| execution JSON codecs | `execution.provider_command_json/delivery_command_json`; application provider/delivery request codecs | Versioned execution contracts | Complete |
| commercial JSON codecs | `commercial_command_json`, `commercial_snapshot_json/from_json` | Versioned commercial contracts | Complete |
| handoff JSON codecs | `FinalDeliverableEvidence`, `ProductionOutcomeEvidence`, `ExternalHandoffRequest`, and `ExternalHandoffReceiptReference` | Pack-owned evidence and opaque external references only; legacy codecs are migration-only | Complete under MC-8 boundary |

## HTTP route coverage

`application/http_contracts.all_application_routes` combines every host-neutral descriptor. `legacy_routes`, `production_routes`, `execution_routes`, `commercial_routes`, and `handoff_routes` cover the complete non-editor endpoint families from the retired server:

- `/health`, `/api/config`, `/api/generate`, `/api/assets`, asset review, and preview media;
- project CRUD/events, creative artifacts, gate advance, generation, assembly, provenance, delivery, analytics, and all governance records;
- provider jobs, routed executions, delivery builds/actions/acceptance/download;
- commercial lead/quote/capacity/conversion, client portals and access observations, billing, repeat orders, client master/annotations/decision/download;
- Mooncast final-deliverable/outcome evidence, opaque outbound requests, and external receipt references under `/api/handoffs/**`.

Handlers in `application/http_contracts/handlers.mbt` implement request decoding and response projection without registering global routes. Binding those descriptors to the native host is intentionally left to host composition; no domain branch is required in the core router.

## Durable event coverage

The legacy event names are preserved semantically through typed events rather than string-driven project mutation:

| Retired store event family | MoonBit durable replacement |
|---|---|
| `project.created` and generic `ProjectStore.record_event` | `ProjectRepositoryEvent`; `ProjectRepository.create/record_repository_event/events` |
| creative artifact/decision and G0–G2 gate mutations | `creative-artifact-recorded`, `creative-decision-recorded`, `gate-advanced` `ProjectEvent` records |
| routing, shot attempt, QC, master, delivery package/acceptance, publication, and performance mutations | `routing-plan-recorded`, `routing-decision-recorded`, `generation-attempt-recorded`, `qc-finding-recorded`, `qc-decision-recorded`, `master-recorded`, `master-decision-recorded`, `delivery-package-recorded`, `delivery-acceptance-recorded`, `publication-authorization-recorded`, `publication-observation-recorded`, and `performance-review-recorded` |
| `provider.assets.ingested` | `execution-ingested` `ProviderExecutionEvent` plus `generation-attempt-recorded` and the project-ingest digest |
| `routed-execution.created/execute/resume/cancel` | `RoutedExecutionRecord`, its exact `ShotJobBinding` set, and the underlying provider execution event stream |
| `delivery-build.queued/completed/cancelled` | queued `DeliveryBuild` plus `build-started`, `build-completed`, `build-cancelled`, `build-failed`, `build-retried`, `build-invalidated`, and `build-recovered` events |
| commercial lead/quote/capacity/conversion audits | typed `CommercialEvent` plus one `CommercialAuditReceipt` for each accepted command |
| `client-portal.created/revoked/expired` | `client-portal-recorded` versions and commercial audit receipts |
| `portal.accessed`, `master.streamed`, `annotation.created`, `delivery.decided`, `delivery.downloaded` | immutable `ClientPortalObservation` records; annotation and decision remain exact portal versions |
| `billing.entry-created/state-recorded` | immutable versions through `billing-recorded`; `payment_effect_performed=false` |
| `repeat-order.created/seeded` | `repeat-order-recorded` plus the fresh-authority `RepeatOrderProposal` |
| Outbound handoff evidence | `FinalDeliverableEvidence`, `ProductionOutcomeEvidence`, `ExternalHandoffRequest`, `ExternalHandoffReceiptReference` stored as immutable envelopes |

| Event family | Typed MoonBit events / receipts | Persistence |
|---|---|---|
| Production | `ProjectEvent`, `GateReceipt`, `ProjectRepositoryEvent` | Project snapshot, domain event, repository event |
| Provider | `ProviderExecutionEvent`, `ProviderAttemptPhase`, `ProviderHostEffectReceipt` | Provider job and content-addressed artifact stores |
| Routed execution | `RoutedExecutionRecord` plus underlying provider events | Routed record and job records |
| Delivery | `DeliveryBuildEvent`, `DeliveryAcceptanceRecord`, `DeliveryArtifactManifest`, `PublicationAuthorityRequest` | Delivery state, outputs, manifest, archive, acceptance |
| Commercial | `CommercialEvent`, `CommercialAuditReceipt` | Commercial snapshot and one audit receipt per accepted command |
| External handoff | Mooncast evidence/request/reference envelopes only | `application/handoff-outbox`; legacy MC-7 roots are read-only migration evidence |
| Preview/long-form | `PreviewAsset`, `PreviewReview`, `MasterProvenance`, `PreparedDeliveryRecord` | Content-addressed media plus immutable metadata/provenance |

All reducers explicitly report no payment, publication, deployment, or automatic-adoption authority. Actual network calls and subprocess executions occur only in the application layer through typed native-host ports and are recorded in host-effect receipts or provenance.
