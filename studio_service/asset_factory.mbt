///|
struct AssetPlanRecordRequest {
  plan : @asset_factory.AssetFactoryPlan
} derive(FromJson)

///|
struct AssetBindingRequest {
  project_revision : Int
  bound_at : String
  human_confirmed : Bool
} derive(FromJson)

///|
async fn StudioService::approved_asset_map(
  self : StudioService,
  project_id : String,
  project_revision : Int,
) -> Map[String, Array[@project.Asset]] {
  let result : Map[String, Array[@project.Asset]] = Map([])
  match self.asset_factory.current_plan(project_id) {
    None => result
    Some(plan) => {
      let canonical = self.get_project(project_id)
      let current_shot_ids = @project.flattened_shots(canonical.snapshot.graph).map(shot => {
          shot.shot_id
        },
      )
      guard plan.project_revision <= project_revision &&
        canonical.snapshot.revision == project_revision &&
        plan.specs.all(spec => {
          spec.dependent_shot_ids.all(shot_id => {
            current_shot_ids.contains(shot_id)
          })
        }) else {
        raise Conflict(
          code="asset_factory_plan_stale",
          message="the reusable asset plan does not bind the current project graph",
        )
      }
      let workspace = self.asset_factory.workspace(project_id)
      let decisions = workspace.plan_decisions.filter(value => {
        value.plan == plan.plan
      })
      guard !decisions.is_empty() else {
        raise Conflict(
          code="asset_factory_approval_required",
          message="the exact reusable asset plan needs named-human approval",
        )
      }
      let mut latest = decisions[0]
      for decision in decisions {
        if decision.decided_at > latest.decided_at {
          latest = decision
        }
      }
      guard latest.decision == "approve" else {
        raise Conflict(
          code="asset_factory_approval_required",
          message="the current reusable asset plan is not approved",
        )
      }
      let dependent_shots : Array[String] = []
      for spec in plan.specs {
        for shot_id in spec.dependent_shot_ids {
          if !dependent_shots.contains(shot_id) {
            dependent_shots.push(shot_id)
          }
        }
      }
      for shot_id in dependent_shots {
        guard self.asset_factory.shot_assets(
            project_id,
            plan.project_revision,
            shot_id,
          )
          is Some(assets) else {
          raise Conflict(
            code="asset_factory_binding_required",
            message="each dependent shot must bind exact approved reusable asset versions",
          )
        }
        result[shot_id] = assets
      }
      result
    }
  }
}

///|
async fn StudioService::dispatch_asset_factory_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (Get, ["api", "v2", "projects", project_id, "asset-factory"]) => {
      ignore(self.get_project(project_id))
      Some(json_value_response(200, self.asset_factory.workspace(project_id)))
    }
    (Post, ["api", "v2", "projects", project_id, "asset-factory", "plans"]) => {
      let canonical = self.get_project(project_id)
      guard gate_recorded(canonical.snapshot, "G2") else {
        raise Conflict(
          code="asset_factory_g2_required",
          message="approved bible and script are required before reusable asset planning",
        )
      }
      let input : AssetPlanRecordRequest = decode_body(request)
      let base = {
        ..input.plan,
        project_id,
        project_revision: canonical.snapshot.revision,
        plan: { ..input.plan.plan, digest: "" },
        publication_authority: false,
        provider_execution_authority: false,
      }
      let exact = {
        ..base,
        plan: { ..base.plan, digest: @asset_factory.plan_digest(base) },
      }
      Some(
        json_value_response(
          201,
          self.asset_factory.record_plan(
            exact,
            canonical.snapshot.graph,
            canonical.snapshot.revision,
          ),
        ),
      )
    }
    (
      Post,
      ["api", "v2", "projects", project_id, "asset-factory", "plan-decisions"],
    ) => {
      let input : @asset_factory_app.PlanDecisionRequest = decode_body(request)
      Some(
        json_value_response(
          201,
          self.asset_factory.decide_plan(project_id, input),
        ),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "asset-factory", "authorize"]) => {
      let input : @asset_factory_app.FactoryExecutionRequest = decode_body(
        request,
      )
      Some(
        json_value_response(
          201,
          self.asset_factory.authorize_variants(project_id, input),
        ),
      )
    }
    (Post, ["api", "v2", "projects", project_id, "asset-factory", "run-pending"]
    ) => {
      let input : @asset_factory_app.FactoryExecutionRequest = decode_body(
        request,
      )
      Some(
        json_value_response(
          200,
          self.asset_factory.run_pending(project_id, input),
        ),
      )
    }
    (Post, ["api", "v2", "projects", _project_id, "asset-factory", "findings"]) => {
      let input : @asset_factory_app.FindingRequest = decode_body(request)
      Some(json_value_response(201, self.asset_factory.record_finding(input)))
    }
    (Post, ["api", "v2", "projects", _project_id, "asset-factory", "approvals"]) => {
      let input : @asset_factory_app.AssetApprovalRequest = decode_body(request)
      Some(json_value_response(201, self.asset_factory.approve_asset(input)))
    }
    (Post, ["api", "v2", "projects", project_id, "asset-factory", "bind-shots"]) => {
      let input : AssetBindingRequest = decode_body(request)
      let canonical = self.get_project(project_id)
      guard input.human_confirmed &&
        input.project_revision == canonical.snapshot.revision else {
        raise Conflict(
          code="asset_factory_binding_confirmation_required",
          message="shot binding must be confirmed against the exact current project revision",
        )
      }
      Some(
        json_value_response(
          201,
          self.asset_factory.bind_approved_assets(
            project_id,
            input.project_revision,
            @project.flattened_shots(canonical.snapshot.graph).map(shot => {
              shot.shot_id
            }),
            input.bound_at,
          ),
        ),
      )
    }
    _ => None
  }
}

///|
pub fn StudioService::register_asset_factory_routes(
  self : StudioService,
) -> Unit {
  self.register_route_extension(
    RouteExtension::new("/api/v2/projects", async fn(request) {
      self.dispatch_asset_factory_http(request)
    }),
  )
}
