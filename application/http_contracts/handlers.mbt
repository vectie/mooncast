///|
pub(all) struct ProviderAuthorizationHttpRequest {
  plan : @execution_app.ProviderHttpPlan
  authority : @execution_app.ProviderAuthorityReceipt
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct PreviewReviewHttpRequest {
  decision : String
  actor : String
  note : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnalyticsHttpRequest {
  expected_project_revision : Int
  source : String
  views : Int
  completion_rate : Double
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RoutedActionHttpRequest {
  expected_revision : Int
  actor_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RoutedCreateHttpRequest {
  expected_project_revision : Int
  actor_id : String
  binding_digest : String
  network_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReservationRescheduleHttpRequest {
  expected : @commerce.CapacityReservation
  updated : @commerce.CapacityReservation
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PortalControlHttpRequest {
  expected_revision : Int
  actor : String
  observed_at : String
  record_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BillingStateHttpRequest {
  expected_revision : Int
  state : String
  actor : String
  actor_role : String
  reference : String
  recorded_at : String
  record_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderCancelHttpRequest {
  actor_id : String
  note : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn invalid_request(message : String) -> @http.Response {
  @http.json_response(
    400,
    "Bad Request",
    "{\"error\":\"invalid_request\",\"message\":" +
    message.to_json().stringify() +
    "}",
  )
}

///|
pub fn health_handler(
  preview : @production_app.LegacyPreviewService,
) -> @http.Response {
  @http.json_response(
    200,
    "OK",
    preview.runtime_readiness().to_json().stringify(),
  )
}

///|
pub fn preview_config_handler(
  preview : @production_app.LegacyPreviewService,
) -> @http.Response {
  @http.json_response(
    200,
    "OK",
    preview.runtime_readiness().to_json().stringify(),
  )
}

///|
pub async fn preview_generate_handler(
  preview : @production_app.LegacyPreviewService,
  request : @http.Request,
) -> @http.Response {
  let brief : @production_app.PreviewBrief = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("bounded preview brief is required")
  }
  try {
    let result = preview.render(brief)
    @http.json_response(
      if result.created {
        201
      } else {
        200
      },
      if result.created {
        "Created"
      } else {
        "OK"
      },
      result.to_json().stringify(),
    )
  } catch {
    _ =>
      @http.json_response(
        422, "Unprocessable Entity", "{\"error\":\"preview_generation_rejected\"}",
      )
  }
}

///|
pub async fn preview_asset_list_handler(
  preview : @production_app.LegacyPreviewService,
) -> @http.Response {
  @http.json_response(
    200,
    "OK",
    preview.list_projections().to_json().stringify(),
  )
}

///|
pub async fn preview_asset_get_handler(
  preview : @production_app.LegacyPreviewService,
  asset_id : String,
) -> @http.Response {
  match preview.get_projection(asset_id) {
    None => @http.not_found()
    Some(asset) => @http.json_response(200, "OK", asset.to_json().stringify())
  }
}

///|
pub async fn preview_media_handler(
  preview : @production_app.LegacyPreviewService,
  asset_id : String,
) -> @http.Response {
  match preview.media_blob(asset_id) {
    None => @http.not_found()
    Some(blob) =>
      @http.response(200, "OK", blob.bytes, content_type="video/mp4", headers={
        "ETag": "\"" + blob.sha256 + "\"",
      })
  }
}

///|
pub async fn preview_review_handler(
  preview : @production_app.LegacyPreviewService,
  asset_id : String,
  request : @http.Request,
) -> @http.Response {
  let payload : PreviewReviewHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("preview review request is invalid")
  }
  try {
    ignore(
      preview.review(asset_id, payload.decision, payload.actor, payload.note),
    )
    match preview.get_projection(asset_id) {
      Some(value) =>
        @http.json_response(201, "Created", value.to_json().stringify())
      None => @http.not_found()
    }
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"preview_review_rejected\"}",
      )
  }
}

///|
pub async fn production_project_create_handler(
  repository : @production_app.ProjectRepository,
  request : @http.Request,
) -> @http.Response {
  let payload : @production_app.NewProductionRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("new production request is invalid")
  }
  match @production_app.new_production_snapshot(payload) {
    None => invalid_request("new production request violates project policy")
    Some(snapshot) =>
      try {
        let created = repository.create(snapshot)
        @http.json_response(201, "Created", created.to_json().stringify())
      } catch {
        _ =>
          @http.json_response(
            409, "Conflict", "{\"error\":\"project_create_rejected\"}",
          )
      }
  }
}

///|
pub async fn production_project_list_handler(
  repository : @production_app.ProjectRepository,
) -> @http.Response {
  @http.json_response(200, "OK", repository.list().to_json().stringify())
}

///|
pub async fn production_project_get_handler(
  repository : @production_app.ProjectRepository,
  project_id : String,
) -> @http.Response {
  match repository.get(project_id) {
    None => @http.not_found()
    Some(snapshot) =>
      @http.json_response(200, "OK", snapshot.to_json().stringify())
  }
}

///|
pub async fn production_project_events_handler(
  repository : @production_app.ProjectRepository,
  project_id : String,
) -> @http.Response {
  @http.json_response(
    200,
    "OK",
    repository.events(project_id).to_json().stringify(),
  )
}

///|
pub async fn production_command_handler(
  repository : @production_app.ProjectRepository,
  request : @http.Request,
) -> @http.Response {
  let command : @kernel.ProjectCommand = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("typed project command is required")
  }
  try {
    let result = repository.handle(command)
    @http.json_response(200, "OK", result.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"project_command_rejected\"}",
      )
  }
}

///|
pub async fn creative_artifact_get_handler(
  repository : @production_app.ProjectRepository,
  project_id : String,
  kind : @creative.ArtifactKind,
) -> @http.Response {
  match repository.get(project_id) {
    None => @http.not_found()
    Some(snapshot) =>
      match @creative.current_artifact(snapshot.creative_artifacts, kind) {
        None => @http.not_found()
        Some(artifact) =>
          @http.json_response(200, "OK", artifact.to_json().stringify())
      }
  }
}

///|
pub async fn master_assemble_handler(
  repository : @production_app.ProjectRepository,
  service : @production_app.LongformProductionService,
  project_id : String,
  request : @http.Request,
) -> @http.Response {
  let payload : @production_app.MasterAssemblyRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("master assembly request is invalid")
  }
  match repository.get(project_id) {
    None => @http.not_found()
    Some(snapshot) =>
      try {
        let provenance = service.assemble_master(snapshot, payload)
        @http.json_response(201, "Created", provenance.to_json().stringify())
      } catch {
        _ =>
          @http.json_response(
            409, "Conflict", "{\"error\":\"master_assembly_rejected\"}",
          )
      }
  }
}

///|
pub async fn master_provenance_handler(
  service : @production_app.LongformProductionService,
  project_id : String,
) -> @http.Response {
  match service.provenance_for_project(project_id) {
    None => @http.not_found()
    Some(record) => @http.json_response(200, "OK", record.to_json().stringify())
  }
}

///|
pub async fn prepare_delivery_handler(
  repository : @production_app.ProjectRepository,
  service : @production_app.LongformProductionService,
  project_id : String,
) -> @http.Response {
  match repository.get(project_id) {
    None => @http.not_found()
    Some(snapshot) =>
      try {
        let record = service.prepare_delivery(snapshot)
        @http.json_response(201, "Created", record.to_json().stringify())
      } catch {
        _ =>
          @http.json_response(
            409, "Conflict", "{\"error\":\"delivery_prepare_rejected\"}",
          )
      }
  }
}

///|
pub async fn production_analytics_handler(
  repository : @production_app.ProjectRepository,
  project_id : String,
  request : @http.Request,
) -> @http.Response {
  let payload : AnalyticsHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("analytics observation is invalid")
  }
  try {
    let observation = repository.record_analytics(
      project_id,
      payload.expected_project_revision,
      payload.source,
      payload.views,
      payload.completion_rate,
      payload.recorded_at,
    )
    @http.json_response(201, "Created", observation.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(409, "Conflict", "{\"error\":\"analytics_rejected\"}")
  }
}

///|
pub fn provider_config_handler(
  service : @execution_app.ProviderExecutionService,
) -> @http.Response {
  @http.json_response(200, "OK", service.capabilities().to_json().stringify())
}

///|
pub async fn provider_list_handler(
  service : @execution_app.ProviderExecutionService,
) -> @http.Response {
  @http.json_response(200, "OK", service.list_jobs().to_json().stringify())
}

///|
pub async fn provider_get_handler(
  service : @execution_app.ProviderExecutionService,
  job_id : String,
) -> @http.Response {
  match service.load_job(job_id) {
    Some(record) =>
      @http.json_response(200, "OK", record.job.to_json().stringify())
    None => @http.not_found()
  }
}

///|
pub async fn provider_authorize_handler(
  service : @execution_app.ProviderExecutionService,
  request : @http.Request,
) -> @http.Response {
  let payload : ProviderAuthorizationHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("provider plan and authority are required")
  }
  try {
    let record = service.authorize(payload.plan, payload.authority)
    @http.json_response(201, "Created", record.job.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"provider_authorization_rejected\"}",
      )
  }
}

///|
pub async fn provider_action_handler(
  service : @execution_app.ProviderExecutionService,
  job_id : String,
  action : String,
  request : @http.Request,
) -> @http.Response {
  try {
    let record = match action {
      "execute" => service.execute(job_id)
      "resume" => service.resume_job(job_id)
      "cancel" => {
        let payload : ProviderCancelHttpRequest = @json.from_json(
          @json.parse(@utf8.decode(request.body)),
        )
        service.cancel(job_id, payload.actor_id)
      }
      _ => return @http.not_found()
    }
    @http.json_response(200, "OK", record.job.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"provider_action_rejected\"}",
      )
  }
}

///|
pub async fn routed_list_handler(
  service : @execution_app.ProviderExecutionService,
  project_id : String,
) -> @http.Response {
  @http.json_response(
    200,
    "OK",
    service.list_routed_executions(project_id).to_json().stringify(),
  )
}

///|
pub async fn routed_create_handler(
  repository : @production_app.ProjectRepository,
  service : @execution_app.ProviderExecutionService,
  project_id : String,
  request : @http.Request,
) -> @http.Response {
  let payload : RoutedCreateHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("routed execution request is invalid")
  }
  match repository.get(project_id) {
    None => @http.not_found()
    Some(snapshot) => {
      if snapshot.revision != payload.expected_project_revision {
        return @http.json_response(
          409, "Conflict", "{\"error\":\"project_revision_conflict\"}",
        )
      }
      let routing = match snapshot.routing_plan {
        None =>
          return @http.json_response(
            409, "Conflict", "{\"error\":\"routing_plan_required\"}",
          )
        Some(value) => value
      }
      try {
        let record = service.create_routed_from_catalog(
          snapshot.graph,
          routing,
          payload.actor_id,
          payload.binding_digest,
          payload.network_authority,
        )
        @http.json_response(
          201,
          "Created",
          record.execution.to_json().stringify(),
        )
      } catch {
        _ =>
          @http.json_response(
            409, "Conflict", "{\"error\":\"routed_execution_rejected\"}",
          )
      }
    }
  }
}

///|
pub async fn routed_get_handler(
  service : @execution_app.ProviderExecutionService,
  project_id : String,
  execution_id : String,
) -> @http.Response {
  match service.load_routed_execution(execution_id) {
    Some(record) if record.execution.project_id == project_id =>
      @http.json_response(200, "OK", record.execution.to_json().stringify())
    _ => @http.not_found()
  }
}

///|
pub async fn routed_action_handler(
  service : @execution_app.ProviderExecutionService,
  execution_id : String,
  shot_id : String,
  action : String,
  request : @http.Request,
) -> @http.Response {
  let payload : RoutedActionHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("routed action request is invalid")
  }
  try {
    let record = service.routed_action(
      execution_id,
      shot_id,
      action,
      payload.expected_revision,
      payload.actor_id,
    )
    @http.json_response(200, "OK", record.execution.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"routed_action_rejected\"}",
      )
  }
}

///|
pub async fn pipeline_routed_action_handler(
  service : @pipeline_app.ProductionPipelineService,
  project_id : String,
  execution_id : String,
  shot_id : String,
  action : String,
  request : @http.Request,
) -> @http.Response {
  let payload : RoutedActionHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("routed action request is invalid")
  }
  try {
    let result = service.routed_action_and_ingest(
      project_id,
      execution_id,
      shot_id,
      action,
      payload.expected_revision,
      payload.actor_id,
    )
    @http.json_response(200, "OK", result.execution.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"routed_pipeline_action_rejected\"}",
      )
  }
}

///|
pub async fn commercial_command_handler(
  service : @commerce_app.CommercialApplicationService,
  request : @http.Request,
) -> @http.Response {
  let command : @commerce.CommercialCommand = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("typed commercial command is required")
  }
  try {
    let result = service.submit(command)
    @http.json_response(200, "OK", result.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"commercial_command_rejected\"}",
      )
  }
}

///|
pub async fn commercial_dashboard_handler(
  service : @commerce_app.CommercialApplicationService,
) -> @http.Response {
  @http.json_response(200, "OK", service.dashboard_json())
}

///|
pub async fn commercial_lead_get_handler(
  service : @commerce_app.CommercialApplicationService,
  lead_id : String,
) -> @http.Response {
  match service.lead(lead_id) {
    None => @http.not_found()
    Some(lead) => @http.json_response(200, "OK", lead.to_json().stringify())
  }
}

///|
pub async fn commercial_quote_get_handler(
  service : @commerce_app.CommercialApplicationService,
  quote_id : String,
) -> @http.Response {
  match service.quote(quote_id) {
    None => @http.not_found()
    Some(quote) => @http.json_response(200, "OK", quote.to_json().stringify())
  }
}

///|
pub async fn commercial_capacity_handler(
  service : @commerce_app.CommercialApplicationService,
  quote_id? : String,
) -> @http.Response {
  match service.capacity_board(quote_id?) {
    None => @http.json_response(200, "OK", "null")
    Some(board) => @http.json_response(200, "OK", board.to_json().stringify())
  }
}

///|
pub async fn commercial_reschedule_handler(
  service : @commerce_app.CommercialApplicationService,
  request : @http.Request,
) -> @http.Response {
  let payload : ReservationRescheduleHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("capacity reschedule request is invalid")
  }
  try {
    let reservation = service.reschedule_reservation(
      payload.expected,
      payload.updated,
    )
    @http.json_response(200, "OK", reservation.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"capacity_reschedule_rejected\"}",
      )
  }
}

///|
pub async fn client_portal_create_handler(
  service : @commerce_app.CommercialApplicationService,
  request : @http.Request,
) -> @http.Response {
  let command : @commerce.CommercialCommand = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("typed client portal command is required")
  }
  try {
    let result = service.create_client_portal(command)
    @http.json_response(201, "Created", result.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"client_portal_create_rejected\"}",
      )
  }
}

///|
pub async fn client_portal_list_handler(
  service : @commerce_app.CommercialApplicationService,
  project_id : String,
) -> @http.Response {
  @http.json_response(
    200,
    "OK",
    service.portals_for_project(project_id).to_json().stringify(),
  )
}

///|
pub async fn client_portal_control_handler(
  service : @commerce_app.CommercialApplicationService,
  portal_id : String,
  action : String,
  request : @http.Request,
) -> @http.Response {
  let payload : PortalControlHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("client portal control request is invalid")
  }
  try {
    let portal = service.control_portal(
      portal_id,
      payload.expected_revision,
      action,
      payload.actor,
      payload.observed_at,
      payload.record_digest,
    )
    @http.json_response(200, "OK", portal.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"client_portal_control_rejected\"}",
      )
  }
}

///|
pub async fn billing_list_handler(
  service : @commerce_app.CommercialApplicationService,
  project_id : String,
) -> @http.Response {
  @http.json_response(
    200,
    "OK",
    service.billing_for_project(project_id).to_json().stringify(),
  )
}

///|
pub async fn billing_state_handler(
  service : @commerce_app.CommercialApplicationService,
  billing_id : String,
  request : @http.Request,
) -> @http.Response {
  let payload : BillingStateHttpRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("billing state request is invalid")
  }
  try {
    let entry = service.transition_billing(
      billing_id,
      payload.expected_revision,
      payload.state,
      payload.actor,
      payload.actor_role,
      payload.reference,
      payload.recorded_at,
      payload.record_digest,
    )
    @http.json_response(200, "OK", entry.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"billing_transition_rejected\"}",
      )
  }
}

///|
pub async fn final_deliverable_evidence_handler(
  service : @handoff_app.OutboundHandoffService,
  request : @http.Request,
) -> @http.Response {
  let value : @handoff.FinalDeliverableEvidence = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("typed final-deliverable evidence is required")
  }
  try {
    let result = service.record_final_deliverable_evidence(value)
    @http.json_response(
      if result.created {
        201
      } else {
        200
      },
      if result.created {
        "Created"
      } else {
        "OK"
      },
      result.to_json().stringify(),
    )
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"final_deliverable_evidence_rejected\"}",
      )
  }
}

///|
pub async fn production_outcome_evidence_handler(
  service : @handoff_app.OutboundHandoffService,
  request : @http.Request,
) -> @http.Response {
  let value : @handoff.ProductionOutcomeEvidence = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("typed production-outcome evidence is required")
  }
  try {
    let result = service.record_production_outcome_evidence(value)
    @http.json_response(
      if result.created {
        201
      } else {
        200
      },
      if result.created {
        "Created"
      } else {
        "OK"
      },
      result.to_json().stringify(),
    )
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"production_outcome_evidence_rejected\"}",
      )
  }
}

///|
pub async fn outbound_handoff_request_handler(
  service : @handoff_app.OutboundHandoffService,
  request : @http.Request,
) -> @http.Response {
  let value : @handoff.ExternalHandoffRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("typed external handoff request is required")
  }
  try {
    let result = service.prepare_request(value)
    @http.json_response(
      if result.created {
        201
      } else {
        200
      },
      if result.created {
        "Created"
      } else {
        "OK"
      },
      result.to_json().stringify(),
    )
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"external_handoff_request_rejected\"}",
      )
  }
}

///|
pub async fn outbound_handoff_receipt_reference_handler(
  service : @handoff_app.OutboundHandoffService,
  request : @http.Request,
) -> @http.Response {
  let value : @handoff.ExternalHandoffReceiptReference = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("typed external receipt reference is required")
  }
  try {
    let result = service.record_receipt_reference(value)
    @http.json_response(
      if result.created {
        201
      } else {
        200
      },
      if result.created {
        "Created"
      } else {
        "OK"
      },
      result.to_json().stringify(),
    )
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"external_receipt_reference_rejected\"}",
      )
  }
}

///|
pub async fn outbound_handoff_record_handler(
  service : @handoff_app.OutboundHandoffService,
  record_type : String,
  record_id : String,
) -> @http.Response {
  match service.record_json(record_type, record_id) {
    Some(value) => @http.json_response(200, "OK", value.stringify())
    None => @http.not_found()
  }
}

///|
pub(all) struct DeliveryBuildHttpAction {
  expected_revision : Int
  expected_record_digest : String
  economics_receipt_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub async fn delivery_create_handler(
  service : @execution_app.DeliveryFactoryService,
  request : @http.Request,
) -> @http.Response {
  let payload : @execution_app.DeliveryBuildRequest = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("delivery build request is invalid")
  }
  try {
    let record = service.create(payload)
    @http.json_response(201, "Created", record.build.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"delivery_build_rejected\"}",
      )
  }
}

///|
pub async fn delivery_list_handler(
  service : @execution_app.DeliveryFactoryService,
  project_id : String,
) -> @http.Response {
  @http.json_response(200, "OK", service.list(project_id).to_json().stringify())
}

///|
pub async fn delivery_get_handler(
  service : @execution_app.DeliveryFactoryService,
  project_id : String,
  build_id : String,
) -> @http.Response {
  match service.load(build_id) {
    Some(record) if record.build.project_id == project_id =>
      @http.json_response(200, "OK", record.build.to_json().stringify())
    _ => @http.not_found()
  }
}

///|
pub async fn delivery_action_handler(
  service : @execution_app.DeliveryFactoryService,
  build_id : String,
  action : String,
  request : @http.Request,
) -> @http.Response {
  let payload : DeliveryBuildHttpAction = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("delivery action request is invalid")
  }
  try {
    let record = match action {
      "build" =>
        service.build(
          build_id,
          payload.expected_revision,
          payload.expected_record_digest,
          payload.economics_receipt_digest,
        )
      "retry" =>
        service.retry(
          build_id,
          payload.expected_revision,
          payload.expected_record_digest,
          payload.economics_receipt_digest,
        )
      "cancel" =>
        service.cancel(
          build_id,
          payload.expected_revision,
          payload.expected_record_digest,
        )
      _ => return @http.not_found()
    }
    @http.json_response(200, "OK", record.build.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"delivery_action_rejected\"}",
      )
  }
}

///|
pub async fn delivery_acceptance_handler(
  service : @execution_app.DeliveryFactoryService,
  build_id : String,
  request : @http.Request,
) -> @http.Response {
  let acceptance : @execution.DeliveryBuildAcceptance = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("delivery acceptance is invalid")
  }
  try {
    let record = service.record_acceptance(build_id, acceptance)
    @http.json_response(200, "OK", record.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"delivery_acceptance_rejected\"}",
      )
  }
}

///|
pub async fn delivery_download_handler(
  service : @execution_app.DeliveryFactoryService,
  build_id : String,
) -> @http.Response {
  match service.accepted_archive(build_id) {
    Some(blob) =>
      @http.response(200, "OK", blob.bytes, content_type="application/zip", headers={
        "ETag": "\"" + blob.sha256 + "\"",
      })
    None =>
      @http.json_response(
        403, "Forbidden", "{\"error\":\"accepted_delivery_required\"}",
      )
  }
}

///|
pub async fn client_projection_handler(
  service : @commerce_app.CommercialApplicationService,
  raw_token : String,
  observed_at : String,
  master_sha256 : String,
  delivery_digest : String,
  build : @execution.DeliveryBuild,
) -> @http.Response {
  try {
    let portal = service.client_portal_for_token(raw_token, observed_at)
    let projection = service.client_projection(
      raw_token, observed_at, master_sha256, delivery_digest, build,
    )
    ignore(
      service.record_client_observation(
        portal,
        "portal.accessed",
        build.record_digest,
        observed_at,
      ),
    )
    @http.json_response(200, "OK", projection.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        410, "Gone", "{\"error\":\"client_portal_unavailable\"}",
      )
  }
}

///|
pub async fn client_annotation_handler(
  service : @commerce_app.CommercialApplicationService,
  raw_token : String,
  observed_at : String,
  master_duration_seconds : Double,
  request : @http.Request,
) -> @http.Response {
  let annotation : @commerce.ClientAnnotation = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("client annotation is invalid")
  }
  try {
    let result = service.annotate(
      raw_token,
      observed_at,
      annotation,
      master_duration_seconds,
      annotation.digest,
    )
    @http.json_response(201, "Created", result.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"client_annotation_rejected\"}",
      )
  }
}

///|
pub async fn client_decision_handler(
  service : @commerce_app.CommercialApplicationService,
  raw_token : String,
  observed_at : String,
  request : @http.Request,
) -> @http.Response {
  let decision : @commerce.ClientDecisionReceipt = @json.from_json(
    @json.parse(@utf8.decode(request.body)),
  ) catch {
    _ => return invalid_request("client decision is invalid")
  }
  try {
    let result = service.record_client_decision(
      raw_token,
      observed_at,
      decision,
      decision.digest,
    )
    @http.json_response(200, "OK", result.to_json().stringify())
  } catch {
    _ =>
      @http.json_response(
        409, "Conflict", "{\"error\":\"client_decision_rejected\"}",
      )
  }
}

///|
pub async fn client_master_handler(
  commerce_service : @commerce_app.CommercialApplicationService,
  production_service : @production_app.LongformProductionService,
  raw_token : String,
  observed_at : String,
) -> @http.Response {
  try {
    let portal = commerce_service.client_portal_for_token(
      raw_token, observed_at,
    )
    let provenance = match
      production_service.provenance_for_project(portal.project_id) {
      None => return @http.not_found()
      Some(value) => value
    }
    if provenance.sha256 != portal.master_sha256 &&
      "sha256:" + provenance.sha256 != portal.master_sha256 {
      return @http.json_response(
        409, "Conflict", "{\"error\":\"client_master_stale\"}",
      )
    }
    match production_service.master_blob(provenance.master_id) {
      None => @http.not_found()
      Some(blob) => {
        ignore(
          commerce_service.record_client_observation(
            portal,
            "master.streamed",
            "sha256:" + blob.sha256,
            observed_at,
          ),
        )
        @http.response(200, "OK", blob.bytes, content_type="video/mp4", headers={
          "ETag": "\"" + blob.sha256 + "\"",
        })
      }
    }
  } catch {
    _ =>
      @http.json_response(
        410, "Gone", "{\"error\":\"client_portal_unavailable\"}",
      )
  }
}

///|
pub async fn client_download_handler(
  commerce_service : @commerce_app.CommercialApplicationService,
  delivery_service : @execution_app.DeliveryFactoryService,
  raw_token : String,
  observed_at : String,
) -> @http.Response {
  try {
    let portal = commerce_service.client_portal_for_token(
      raw_token, observed_at,
    )
    if !portal.decisions.any(decision => decision.decision == "accept") {
      return @http.json_response(
        403, "Forbidden", "{\"error\":\"client_acceptance_required\"}",
      )
    }
    match delivery_service.accepted_archive(portal.build_id) {
      None =>
        @http.json_response(
          403, "Forbidden", "{\"error\":\"accepted_delivery_required\"}",
        )
      Some(blob) => {
        ignore(
          commerce_service.record_client_observation(
            portal,
            "delivery.downloaded",
            "sha256:" + blob.sha256,
            observed_at,
          ),
        )
        @http.response(200, "OK", blob.bytes, content_type="application/zip", headers={
          "ETag": "\"" + blob.sha256 + "\"",
        })
      }
    }
  } catch {
    _ =>
      @http.json_response(
        410, "Gone", "{\"error\":\"client_portal_unavailable\"}",
      )
  }
}

///|
pub async fn client_observation_list_handler(
  service : @commerce_app.CommercialApplicationService,
  project_id : String,
) -> @http.Response {
  @http.json_response(
    200,
    "OK",
    service.client_observations(project_id).to_json().stringify(),
  )
}
