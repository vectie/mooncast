///|
struct MoonWikiImportRequest {
  packet : @intake.MoonWikiNeedsPacket
  imported_at : String
} derive(FromJson)

///|
struct SeedIntakeProjectRequest {
  packet_version : Int
  expected_provenance_digest : String
  project_id : String
  recorded_at : String
} derive(FromJson)

///|
async fn StudioService::seed_project_from_intake(
  self : StudioService,
  packet_id : String,
  input : SeedIntakeProjectRequest,
) -> Json {
  guard self.needs_intake.get_intake(
      packet_id,
      packet_version=input.packet_version,
    )
    is Some(imported) else {
    raise NotFound(entity="needs_intake", id=packet_id)
  }
  guard imported.validation.complete &&
    imported.validation.provenance_digest == input.expected_provenance_digest else {
    raise Conflict(
      code="needs_intake_conflict",
      message="project seed must bind the exact complete displayed intake",
    )
  }
  guard self.needs_intake.approved_decision(imported) is Some(_) else {
    raise Conflict(
      code="needs_intake_approval_required",
      message="named-human approval is required before project creation",
    )
  }
  let packet = imported.packet
  let graph = @production_app.episode_production_graph(
    input.project_id,
    packet.creative_strategy.project_title,
    packet.contract_boundary.target_duration_seconds,
    packet.contract_boundary.budget_ceiling_cny,
  )
  let created = self.create_project(graph, input.recorded_at)
  let experience : ProjectExperienceMetadata = {
    objective: packet.creative_strategy.objective,
    audience: packet.client_need.audience,
    channels: packet.client_need.channels,
    rights_owner: packet.constraints.rights_owner,
    rights_confirmed: packet.constraints.rights_confirmed,
  }
  self.save_project_experience(created.project_id, experience)
  let seeded = self.seed_initial_creative_drafts(
    created.project_id,
    experience,
    input.recorded_at,
    moonwiki_intake=packet,
  )
  let binding = self.needs_intake.bind_intake_to_project(packet_id, {
    packet_version: input.packet_version,
    expected_provenance_digest: input.expected_provenance_digest,
    project_id: created.project_id,
    project_revision: seeded.snapshot.revision,
    bound_at: input.recorded_at,
  })
  Json::object({
    "project": self.studio_project_projection(seeded),
    "binding": binding.to_json(),
    "publication_authority": false.to_json(),
    "provider_execution_authority": false.to_json(),
  })
}

///|
async fn StudioService::dispatch_needs_intake_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (Get, ["api", "v2", "needs-intakes"]) =>
      Some(json_value_response(200, self.needs_intake.workspace()))
    (Post, ["api", "v2", "needs-intakes"]) => {
      let input : MoonWikiImportRequest = decode_body(request)
      Some(
        json_value_response(
          201,
          self.needs_intake.import_packet(input.packet, input.imported_at),
        ),
      )
    }
    (Get, ["api", "v2", "needs-intakes", packet_id]) =>
      match self.needs_intake.get_intake(packet_id) {
        Some(record) => Some(json_value_response(200, record))
        None =>
          Some(
            api_error(
              404, "needs_intake_not_found", "MoonWiki intake was not found",
            ),
          )
      }
    (Post, ["api", "v2", "needs-intakes", packet_id, "decisions"]) => {
      let input : @intake_app.IntakeDecisionRequest = decode_body(request)
      Some(
        json_value_response(
          201,
          self.needs_intake.record_decision(packet_id, input),
        ),
      )
    }
    (Post, ["api", "v2", "needs-intakes", packet_id, "seed-project"]) => {
      let input : SeedIntakeProjectRequest = decode_body(request)
      Some(
        json_value_response(
          201,
          self.seed_project_from_intake(packet_id, input),
        ),
      )
    }
    _ => None
  }
}

///|
pub fn StudioService::register_needs_intake_routes(
  self : StudioService,
) -> Unit {
  self.register_route_extension(
    RouteExtension::new("/api/v2/needs-intakes", async fn(request) {
      self.dispatch_needs_intake_http(request)
    }),
  )
}
