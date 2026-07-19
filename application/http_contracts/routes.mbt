///|
/// Host-neutral route metadata. Template matching remains in the global host.
pub(all) struct ApplicationRouteDescriptor {
  request_method : String
  path_template : String
  operation : String
  request_contract : String?
  response_contract : String
  performs_network : Bool
  performs_process : Bool
  performs_payment : Bool
  performs_publication : Bool
  performs_deployment : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn inert_route(
  request_method : String,
  path : String,
  operation : String,
  request_contract : String?,
  response_contract : String,
) -> ApplicationRouteDescriptor {
  {
    request_method,
    path_template: path,
    operation,
    request_contract,
    response_contract,
    performs_network: false,
    performs_process: false,
    performs_payment: false,
    performs_publication: false,
    performs_deployment: false,
  }
}

///|
pub fn legacy_routes() -> Array[ApplicationRouteDescriptor] {
  let routes = [
    inert_route("GET", "/health", "health", None, "mooncast.health.v1"),
    inert_route(
      "GET",
      "/api/config",
      "legacy_config",
      None,
      "mooncast.production-runtime-readiness.v1",
    ),
    inert_route(
      "GET",
      "/api/assets",
      "preview_asset_list",
      None,
      "mooncast.preview-asset-list.v1",
    ),
    inert_route(
      "GET",
      "/api/assets/{asset_id}",
      "preview_asset_get",
      None,
      "mooncast.preview-asset.v1",
    ),
    inert_route(
      "GET",
      "/media/{asset_file}",
      "preview_media",
      None,
      "video/mp4",
    ),
    inert_route(
      "POST",
      "/api/assets/{asset_id}/review",
      "preview_asset_review",
      Some("mooncast.preview-review-request.v1"),
      "mooncast.preview-review.v1",
    ),
  ]
  routes.push({
    ..inert_route(
      "POST",
      "/api/generate",
      "preview_generate",
      Some("mooncast.preview-brief.v1"),
      "mooncast.preview-render-result.v1",
    ),
    performs_process: true,
  })
  routes
}

///|
pub fn production_routes() -> Array[ApplicationRouteDescriptor] {
  let routes = [
    inert_route(
      "GET",
      "/api/v2/projects",
      "production_project_list",
      None,
      "mooncast.project-snapshot-list.v2",
    ),
    inert_route(
      "POST",
      "/api/v2/projects",
      "production_project_create",
      Some("mooncast.new-production-request.v2"),
      "mooncast.project-snapshot.v2",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}",
      "production_project_get",
      None,
      "mooncast.project-snapshot.v2",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/events",
      "production_project_events",
      None,
      "mooncast.project-event-list.v2",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/advance",
      "production_advance_gate",
      Some("mooncast.gate-advance-request.v2"),
      "mooncast.command-result.v2",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/governance",
      "production_governance",
      None,
      "mooncast.project-snapshot.v2",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/master/provenance",
      "production_master_provenance",
      None,
      "mooncast.master-provenance.v2",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/delivery-plan",
      "production_delivery_plan",
      Some("mooncast.delivery-package.v3"),
      "mooncast.command-result.v2",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/review",
      "production_compatibility_review",
      Some("mooncast.master-decision.v1"),
      "mooncast.command-result.v2",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/deliver",
      "production_prepare_delivery",
      None,
      "mooncast.prepared-delivery.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/analytics",
      "production_record_analytics",
      Some("mooncast.analytics-observation.v1"),
      "mooncast.analytics-observation.v1",
    ),
  ]
  for
    artifact in [
      "brief", "rights-ledger", "ip-bible", "script", "claims-ledger", "storyboard",
      "animatic",
    ] {
    routes.push(
      inert_route(
        "GET",
        "/api/v2/projects/{id}/creative/" + artifact,
        "creative_get_" + artifact,
        None,
        "mooncast.creative-artifact.v1",
      ),
    )
    routes.push(
      inert_route(
        "POST",
        "/api/v2/projects/{id}/creative/" + artifact + "/revise",
        "creative_revise_" + artifact,
        Some("mooncast.creative-revision-request.v2"),
        "mooncast.command-result.v2",
      ),
    )
    routes.push(
      inert_route(
        "POST",
        "/api/v2/projects/{id}/creative/" + artifact + "/decision",
        "creative_decide_" + artifact,
        Some("mooncast.creative-decision-request.v2"),
        "mooncast.command-result.v2",
      ),
    )
  }
  routes.push(
    inert_route(
      "POST",
      "/api/v2/projects/{id}/governance/model-routing/revise",
      "routing_revise",
      Some("mooncast.model-routing-plan.v1"),
      "mooncast.command-result.v2",
    ),
  )
  routes.push(
    inert_route(
      "POST",
      "/api/v2/projects/{id}/governance/model-routing/decision",
      "routing_decide",
      Some("mooncast.model-routing-decision.v1"),
      "mooncast.command-result.v2",
    ),
  )
  routes.push(
    inert_route(
      "POST",
      "/api/v2/projects/{id}/governance/shots/{shot_id}/attempts",
      "generation_attempt",
      Some("mooncast.generation-attempt-v2.v1"),
      "mooncast.command-result.v2",
    ),
  )
  for dimension in ["technical", "continuity", "safety", "claims", "rights"] {
    routes.push(
      inert_route(
        "POST",
        "/api/v2/projects/{id}/governance/shots/{shot_id}/qc/" +
        dimension +
        "/findings",
        "qc_finding_" + dimension,
        Some("mooncast.shot-qc-finding.v1"),
        "mooncast.command-result.v2",
      ),
    )
    routes.push(
      inert_route(
        "POST",
        "/api/v2/projects/{id}/governance/shots/{shot_id}/qc/" +
        dimension +
        "/decision",
        "qc_decision_" + dimension,
        Some("mooncast.shot-qc-decision.v1"),
        "mooncast.command-result.v2",
      ),
    )
  }
  for
    kind in ["technical-qc", "creative-director", "rights-compliance", "client"] {
    routes.push(
      inert_route(
        "POST",
        "/api/v2/projects/{id}/governance/master/" + kind,
        "master_decision_" + kind,
        Some("mooncast.master-decision.v1"),
        "mooncast.command-result.v2",
      ),
    )
  }
  for
    pair in [
      ("delivery-package", "mooncast.delivery-package.v3"),
      ("delivery-milestone", "mooncast.delivery-milestone-acceptance.v1"),
      ("publication-authorizations", "mooncast.publication-authorization.v1"),
      ("publication-receipts", "mooncast.publication-observation.v1"),
      ("performance-review", "mooncast.performance-economics-review.v1"),
    ] {
    routes.push(
      inert_route(
        "POST",
        "/api/v2/projects/{id}/governance/" + pair.0,
        "governance_" + pair.0,
        Some(pair.1),
        "mooncast.command-result.v2",
      ),
    )
  }
  routes.push({
    ..inert_route(
      "POST",
      "/api/v2/projects/{id}/generate",
      "production_generate_shots",
      Some("mooncast.routed-execution-create.v1"),
      "mooncast.routed-execution.v1",
    ),
    performs_network: true,
  })
  routes.push({
    ..inert_route(
      "POST",
      "/api/v2/projects/{id}/assemble",
      "production_assemble_master",
      Some("mooncast.master-assembly-request.v1"),
      "mooncast.master-provenance.v2",
    ),
    performs_process: true,
  })
  routes
}

///|
pub fn execution_routes() -> Array[ApplicationRouteDescriptor] {
  let routes = [
    inert_route(
      "GET",
      "/api/provider-executions/config",
      "provider_config",
      None,
      "mooncast.provider-execution-capabilities.v1",
    ),
    inert_route(
      "GET",
      "/api/provider-executions",
      "provider_list",
      None,
      "mooncast.provider-execution-list.v1",
    ),
    inert_route(
      "GET",
      "/api/provider-executions/{job_id}",
      "provider_get",
      None,
      "mooncast.provider-execution-job.v1",
    ),
    inert_route(
      "POST",
      "/api/provider-executions",
      "provider_authorize",
      Some("mooncast.provider-authorization-http.v1"),
      "mooncast.provider-execution-job.v1",
    ),
    inert_route(
      "POST",
      "/api/provider-executions/{job_id}/cancel",
      "provider_cancel",
      Some("mooncast.provider-cancel-http.v1"),
      "mooncast.provider-execution-job.v1",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/routed-executions",
      "routed_list",
      None,
      "mooncast.routed-execution-list.v1",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/routed-executions/{execution_id}",
      "routed_get",
      None,
      "mooncast.routed-execution.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/routed-executions",
      "routed_create",
      Some("mooncast.routed-execution-create.v1"),
      "mooncast.routed-execution.v1",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/delivery-builds",
      "delivery_build_list",
      None,
      "mooncast.delivery-build-list.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/delivery-builds",
      "delivery_build_create",
      Some("mooncast.delivery-build-request.v1"),
      "mooncast.delivery-build.v1",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/delivery-builds/{build_id}",
      "delivery_build_get",
      None,
      "mooncast.delivery-build.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/delivery-builds/{build_id}/acceptance",
      "delivery_build_acceptance",
      Some("mooncast.delivery-build-acceptance.v1"),
      "mooncast.delivery-build-acceptance-receipt.v1",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/delivery-builds/{build_id}/download",
      "delivery_build_download",
      None,
      "application/zip",
    ),
  ]
  routes.push({
    ..inert_route(
      "POST",
      "/api/provider-executions/{job_id}/execute",
      "provider_execute",
      None,
      "mooncast.provider-execution-job.v1",
    ),
    performs_network: true,
  })
  routes.push({
    ..inert_route(
      "POST",
      "/api/provider-executions/{job_id}/resume",
      "provider_resume",
      None,
      "mooncast.provider-execution-job.v1",
    ),
    performs_network: true,
  })
  for action in ["execute", "resume"] {
    routes.push({
      ..inert_route(
        "POST",
        "/api/v2/projects/{id}/routed-executions/{execution_id}/shots/{shot_id}/" +
        action,
        "routed_" + action,
        None,
        "mooncast.routed-execution.v1",
      ),
      performs_network: true,
    })
  }
  routes.push(
    inert_route(
      "POST",
      "/api/v2/projects/{id}/routed-executions/{execution_id}/shots/{shot_id}/cancel",
      "routed_cancel",
      Some("mooncast.routed-execution-action.v1"),
      "mooncast.routed-execution.v1",
    ),
  )
  for action in ["build", "retry", "cancel"] {
    routes.push({
      ..inert_route(
        "POST",
        "/api/v2/projects/{id}/delivery-builds/{build_id}/" + action,
        "delivery_" + action,
        Some("mooncast.delivery-build-action.v1"),
        "mooncast.delivery-build.v1",
      ),
      performs_process: action == "build" || action == "retry",
    })
  }
  routes
}

///|
pub fn commercial_routes() -> Array[ApplicationRouteDescriptor] {
  [
    inert_route(
      "GET",
      "/api/commercial-intake",
      "commercial_dashboard",
      None,
      "mooncast.commercial-intake-dashboard.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/leads",
      "lead_create",
      Some("mooncast.qualified-lead.v1"),
      "mooncast.qualified-lead.v1",
    ),
    inert_route(
      "GET",
      "/api/commercial-intake/leads/{lead_id}",
      "lead_get",
      None,
      "mooncast.qualified-lead.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/leads/{lead_id}/qualification",
      "lead_qualify",
      Some("mooncast.lead-qualification-decision.v1"),
      "mooncast.qualified-lead.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/leads/{lead_id}/quotes",
      "quote_create",
      Some("mooncast.scoped-quote.v1"),
      "mooncast.scoped-quote.v1",
    ),
    inert_route(
      "GET",
      "/api/commercial-intake/quotes/{quote_id}",
      "quote_get",
      None,
      "mooncast.scoped-quote.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/quotes/{quote_id}/revisions",
      "quote_revise",
      Some("mooncast.scoped-quote.v1"),
      "mooncast.scoped-quote.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/quotes/{quote_id}/internal-decisions",
      "quote_internal_decision",
      Some("mooncast.quote-internal-decision.v1"),
      "mooncast.scoped-quote.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/quotes/{quote_id}/client-acceptance",
      "quote_client_acceptance",
      Some("mooncast.quote-client-acceptance.v1"),
      "mooncast.scoped-quote.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/capacity/resources",
      "capacity_resource",
      Some("mooncast.capacity-resource.v1"),
      "mooncast.capacity-resource.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/capacity/reservations",
      "capacity_reservation",
      Some("mooncast.capacity-reservation.v1"),
      "mooncast.capacity-reservation.v1",
    ),
    inert_route(
      "GET",
      "/api/commercial-intake/capacity-board",
      "capacity_board",
      None,
      "mooncast.capacity-board.v1",
    ),
    inert_route(
      "GET",
      "/api/commercial-intake/quotes/{quote_id}/capacity-board",
      "quote_capacity_board",
      None,
      "mooncast.capacity-board.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/capacity/reservations/{reservation_id}/reschedule",
      "capacity_reschedule",
      Some("mooncast.capacity-reservation.v1"),
      "mooncast.capacity-reservation.v1",
    ),
    inert_route(
      "POST",
      "/api/commercial-intake/quotes/{quote_id}/conversion",
      "quote_conversion",
      Some("mooncast.quote-conversion.v1"),
      "mooncast.quote-conversion.v1",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/client-portals",
      "client_portal_list",
      None,
      "mooncast.client-portal-list.v1",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/client-observations",
      "client_observation_list",
      None,
      "mooncast.client-portal-observation-list.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/client-portals",
      "client_portal_create",
      Some("mooncast.client-portal-create.v1"),
      "mooncast.client-portal-create-result.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/client-portals/{portal_id}/revoke",
      "client_portal_revoke",
      Some("mooncast.client-portal-control.v1"),
      "mooncast.client-portal.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/client-portals/{portal_id}/expire",
      "client_portal_expire",
      Some("mooncast.client-portal-control.v1"),
      "mooncast.client-portal.v1",
    ),
    inert_route(
      "GET",
      "/api/v2/projects/{id}/billing",
      "billing_list",
      None,
      "mooncast.milestone-billing-list.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/billing",
      "billing_create",
      Some("mooncast.milestone-billing-create.v1"),
      "mooncast.milestone-billing-entry.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/billing/{billing_id}/state",
      "billing_state",
      Some("mooncast.milestone-billing-action.v1"),
      "mooncast.milestone-billing-entry.v1",
    ),
    inert_route(
      "POST",
      "/api/v2/projects/{id}/repeat-orders",
      "repeat_order",
      Some("mooncast.repeat-order-request.v1"),
      "mooncast.repeat-order-proposal.v1",
    ),
    inert_route(
      "GET",
      "/api/client/{token}",
      "client_projection",
      None,
      "mooncast.client-portal-projection.v1",
    ),
    inert_route(
      "GET",
      "/api/client/{token}/master",
      "client_master",
      None,
      "video/mp4",
    ),
    inert_route(
      "POST",
      "/api/client/{token}/annotations",
      "client_annotation",
      Some("mooncast.client-annotation-request.v1"),
      "mooncast.client-annotation.v1",
    ),
    inert_route(
      "POST",
      "/api/client/{token}/decision",
      "client_decision",
      Some("mooncast.client-decision-request.v1"),
      "mooncast.client-decision-receipt.v1",
    ),
    inert_route(
      "GET",
      "/api/client/{token}/download",
      "client_download",
      None,
      "application/zip",
    ),
  ]
}

///|
pub fn handoff_routes() -> Array[ApplicationRouteDescriptor] {
  [
    inert_route(
      "POST",
      "/api/handoffs/final-deliverables",
      "final_deliverable_evidence",
      Some("mooncast.final-deliverable-evidence.v1"),
      "mooncast.immutable-record-envelope.v1",
    ),
    inert_route(
      "POST",
      "/api/handoffs/outcomes",
      "production_outcome_evidence",
      Some("mooncast.production-outcome-evidence.v1"),
      "mooncast.immutable-record-envelope.v1",
    ),
    inert_route(
      "POST",
      "/api/handoffs/requests",
      "external_handoff_request",
      Some("mooncast.external-handoff-request.v1"),
      "mooncast.immutable-record-envelope.v1",
    ),
    inert_route(
      "POST",
      "/api/handoffs/receipt-references",
      "external_handoff_receipt_reference",
      Some("mooncast.external-handoff-receipt-reference.v1"),
      "mooncast.immutable-record-envelope.v1",
    ),
    inert_route(
      "GET",
      "/api/handoffs/{record_type}/{record_id}",
      "external_handoff_record",
      None,
      "mooncast.immutable-record-envelope.v1",
    ),
  ]
}

///|
pub fn all_application_routes() -> Array[ApplicationRouteDescriptor] {
  let routes : Array[ApplicationRouteDescriptor] = []
  for route in legacy_routes() {
    routes.push(route)
  }
  for route in production_routes() {
    routes.push(route)
  }
  for route in execution_routes() {
    routes.push(route)
  }
  for route in commercial_routes() {
    routes.push(route)
  }
  for route in handoff_routes() {
    routes.push(route)
  }
  routes
}
