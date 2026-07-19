///|
struct AnimaticPlanRecordRequest {
  plan : @animatic.AnimaticPlan
} derive(FromJson)

///|
async fn StudioService::approved_rendered_animatic(
  self : StudioService,
  project_id : String,
) -> @animatic.RenderedAnimaticApproval? {
  let record = self.get_project(project_id)
  @animatic.exact_approved_render(
    current_creative(record.snapshot, @creative.Animatic),
    record.snapshot.creative_decisions,
    record.snapshot.creative_artifacts,
    record.snapshot.graph,
  )
}

///|
async fn StudioService::record_animatic_plan(
  self : StudioService,
  project_id : String,
  input : AnimaticPlanRecordRequest,
) -> @animatic.AnimaticPlan {
  let canonical = self.get_project(project_id)
  guard gate_recorded(canonical.snapshot, "G2") else {
    raise Conflict(
      code="animatic_g2_required",
      message="approved bible, script, claims, and rights are required before rendering",
    )
  }
  let workspace = self.asset_factory.workspace(project_id)
  let exact_assets = workspace.approved_assets.map(value => value.reference)
  guard !input.plan.approved_assets.is_empty() &&
    input.plan.approved_assets.all(asset => exact_assets.contains(asset)) else {
    raise Conflict(
      code="animatic_asset_approval_required",
      message="animatic panels and temporary audio must use exact approved reusable asset versions",
    )
  }
  let base = {
    ..input.plan,
    project_id,
    project_revision: canonical.snapshot.revision,
    reference: { ..input.plan.reference, digest: "" },
    process_authority: false,
    publication_authority: false,
  }
  let exact = {
    ..base,
    reference: { ..base.reference, digest: @animatic.plan_digest(base) },
  }
  self.animatic.record_plan(
    exact,
    canonical.snapshot.graph,
    canonical.snapshot.creative_artifacts,
  )
}

///|
async fn StudioService::approve_rendered_animatic(
  self : StudioService,
  project_id : String,
  input : @animatic_app.AnimaticApprovalRequest,
) -> Json {
  let approval = self.animatic.approve(project_id, input)
  let canonical = self.get_project(project_id)
  guard current_creative(canonical.snapshot, @creative.Animatic)
    is Some(current) &&
    current_creative(canonical.snapshot, @creative.IpBible) is Some(bible) &&
    current_creative(canonical.snapshot, @creative.Script) is Some(script) &&
    current_creative(canonical.snapshot, @creative.Storyboard)
    is Some(storyboard) &&
    approval.rendered.bible == bible.reference &&
    approval.rendered.script == script.reference &&
    approval.rendered.storyboard == storyboard.reference else {
    raise Conflict(
      code="animatic_creative_lineage_stale",
      message="rendered animatic no longer binds the current bible, script, and storyboard",
    )
  }
  let content = approval.to_json().stringify()
  let next_version = current.reference.version + 1
  let artifact_digest = "sha256:" +
    sha256_text(
      project_id +
      ":rendered-animatic:" +
      next_version.to_string() +
      ":" +
      content,
    )
  let dependencies : Array[String] = [
    bible.reference.digest,
    script.reference.digest,
    storyboard.reference.digest,
  ]
  let artifact : @creative.CreativeArtifact = {
    reference: {
      id: current.reference.id,
      version: next_version,
      digest: artifact_digest,
    },
    kind: @creative.Animatic,
    dependency_digests: dependencies,
    duration_seconds: Some(approval.rendered.duration_seconds),
    expected_cost_cny: Some(approval.rendered.budget.actual_cny),
    rights_cleared: true,
    content,
  }
  let revised = self.record_creative_artifact(project_id, {
    expected_revision: canonical.snapshot.revision,
    command_id: "rendered-animatic-" + artifact_digest[7:31].to_owned(),
    recorded_at: input.approved_at,
    evidence_digest: approval.approval_digest,
    artifact,
  })
  guard revised.result.ok else {
    raise Conflict(
      code="animatic_project_revision_conflict",
      message="rendered animatic could not become the canonical creative version",
    )
  }
  let decision : @creative.CreativeDecision = {
    artifact: artifact.reference,
    decision: "approved",
    actor: input.actor,
    role: input.actor_role,
    decided_at: input.approved_at,
    note: input.note,
  }
  let decided = self.record_creative_decision(project_id, {
    expected_revision: revised.project.snapshot.revision,
    command_id: "rendered-animatic-approval-" +
    approval.approval_digest[7:31].to_owned(),
    recorded_at: input.approved_at,
    evidence_digest: approval.approval_digest,
    decision,
  })
  guard decided.result.ok else {
    raise Conflict(
      code="animatic_approval_conflict",
      message="render approval could not bind the canonical creative version",
    )
  }
  Json::object({
    "approval": approval.to_json(),
    "project": self.studio_project_projection(decided.project),
    "publication_authority": false.to_json(),
  })
}

///|
async fn StudioService::dispatch_animatic_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (Get, ["api", "v2", "projects", project_id, "animatic-workspace"]) => {
      ignore(self.get_project(project_id))
      Some(json_value_response(200, self.animatic.workspace(project_id)))
    }
    (Post, ["api", "v2", "projects", project_id, "animatic-workspace", "plans"]) => {
      let input : AnimaticPlanRecordRequest = decode_body(request)
      Some(
        json_value_response(201, self.record_animatic_plan(project_id, input)),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "animatic-workspace", "render"]
    ) => {
      let input : @animatic_app.AnimaticRenderRequest = decode_body(request)
      Some(json_value_response(201, self.animatic.render(project_id, input)))
    }
    (
      Post,
      ["api", "v2", "projects", project_id, "animatic-workspace", "approve"],
    ) => {
      let input : @animatic_app.AnimaticApprovalRequest = decode_body(request)
      Some(
        json_value_response(
          201,
          self.approve_rendered_animatic(project_id, input),
        ),
      )
    }
    (
      Get
      | Head,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "animatic-workspace",
        "renders",
        version,
        kind,
      ],
    ) => {
      let parsed = @string.parse_int(version) catch { _ => -1 }
      guard parsed > 0 && (kind == "sheet" || kind == "video") else {
        raise NotFound(entity="animatic_media", id=version + ":" + kind)
      }
      let blob = self.animatic.media(project_id, parsed, kind)
      let range = request.headers.get("range")
      let if_none_match = request.headers.get("if-none-match")
      let response = @host_http.static_response(
        "sha256:" + blob.sha256,
        blob.bytes,
        range?,
        if_none_match?,
      )
      response.headers["Content-Type"] = if kind == "sheet" {
        "image/png"
      } else {
        "video/mp4"
      }
      Some(response)
    }
    _ => None
  }
}

///|
pub fn StudioService::register_animatic_routes(self : StudioService) -> Unit {
  self.register_route_extension(
    RouteExtension::new("/api/v2/projects", async fn(request) {
      self.dispatch_animatic_http(request)
    }),
  )
}
