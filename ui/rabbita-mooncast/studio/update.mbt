///|
fn api_error_message(value : Json) -> String? {
  fn error_message(error : Json) -> String? {
    match error {
      String(message) => Some(message)
      Object(fields) =>
        match fields.get("message") {
          Some(String(message)) => Some(message)
          _ => Some("The native host rejected the command.")
        }
      _ => None
    }
  }
  match value {
    Object(fields) =>
      match fields.get("error") {
        Some(error) => error_message(error)
        None =>
          match fields.get("result") {
            Some(Object(result)) if result.get("ok") == Some(false.to_json()) =>
              match result.get("error") {
                Some(error) => error_message(error)
                None => Some("The native host rejected the command.")
              }
            _ => None
          }
      }
    _ => None
  }
}

///|
fn optional_double_json(value : String) -> Json {
  if value.trim() == "" {
    Json::null()
  } else {
    (@string.parse_double(value) catch { _ => 0.0 }).to_json()
  }
}

///|
fn update(
  emit : @rabbita.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@rabbita.Cmd, Model) {
  match msg {
    Bootstrap => {
      let projects = @http.get("/api/v2/projects").expect_json(
        emit.map(fn(result) { LoadedProjects(result) }),
      )
      let commercial = @http.get("/api/commercial-intake").expect_json(
        emit.map(fn(result) { LoadedCommercial(result) }),
      )
      let needs = @http.get("/api/v2/needs-intakes").expect_json(
        emit.map(fn(result) { LoadedNeedsIntake(result) }),
      )
      let tower = @http.get("/api/control-tower").expect_json(
        emit.map(fn(result) { LoadedControlTower(result) }),
      )
      (
        @rabbita.batch([projects, commercial, needs, tower]),
        {
          ..model,
          loading: true,
          status: "Loading project and commercial ledgers…",
        },
      )
    }
    SelectTab(tab) =>
      if tab == ControlTower {
        (
          @http.get("/api/control-tower").expect_json(
            emit.map(fn(result) { LoadedControlTower(result) }),
          ),
          { ..model, tab, status: "Refreshing portfolio evidence…" },
        )
      } else {
        (@rabbita.none, { ..model, tab, })
      }
    SelectProject(project_id) => {
      let cmd = @http.get("/api/v2/projects/" + project_id).expect_json(
        emit.map(fn(result) { LoadedProject(result) }),
      )
      (
        cmd,
        {
          ..model,
          selected_project_id: project_id,
          loading: true,
          error: None,
          status: "Loading canonical project revision…",
        },
      )
    }
    RefreshProject =>
      if model.selected_project_id == "" {
        (@rabbita.none, model)
      } else {
        let cmd = @http.get("/api/v2/projects/" + model.selected_project_id).expect_json(
          emit.map(fn(result) { LoadedProject(result) }),
        )
        (cmd, { ..model, loading: true, error: None })
      }
    LoadedProjects(Ok(value)) => {
      let should_open = model.selected_project_id == "" &&
        !value.projects.is_empty()
      let selected = if should_open {
        value.projects[0].project_id
      } else {
        model.selected_project_id
      }
      let cmd = if should_open {
        @http.get("/api/v2/projects/" + selected).expect_json(
          emit.map(fn(result) { LoadedProject(result) }),
        )
      } else {
        @rabbita.none
      }
      (
        cmd,
        {
          ..model,
          projects: value.projects,
          selected_project_id: selected,
          loading: should_open,
          status: if value.projects.is_empty() {
            "No production project yet. Create one from a qualified scenario."
          } else {
            "Project index loaded."
          },
        },
      )
    }
    LoadedProjects(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          error: Some("Could not load projects: \{error}"),
        },
      )
    LoadedProject(Ok(project)) => {
      let routed = @http.get(
        "/api/v2/projects/" + project.id + "/routed-executions",
      ).expect_json(emit.map(fn(result) { LoadedRouted(result) }))
      let deliveries = @http.get(
        "/api/v2/projects/" + project.id + "/delivery-builds",
      ).expect_json(emit.map(fn(result) { LoadedDeliveries(result) }))
      let portals = @http.get(
        "/api/v2/projects/" + project.id + "/client-portals",
      ).expect_json(emit.map(fn(result) { LoadedPortals(result) }))
      let billing = @http.get("/api/v2/projects/" + project.id + "/billing").expect_json(
        emit.map(fn(result) { LoadedBilling(result) }),
      )
      let assets = @http.get(
        "/api/v2/projects/" + project.id + "/asset-factory",
      ).expect_json(emit.map(fn(result) { LoadedAssetFactory(result) }))
      let animatic = @http.get(
        "/api/v2/projects/" + project.id + "/animatic-workspace",
      ).expect_json(emit.map(fn(result) { LoadedAnimaticWorkspace(result) }))
      let postprocess = @http.get(
        "/api/v2/projects/" + project.id + "/postprocess-jobs",
      ).expect_json(emit.map(fn(result) { LoadedPostprocessWorkspace(result) }))
      let analyzers = @http.get(
        "/api/v2/projects/" + project.id + "/automated-qc",
      ).expect_json(emit.map(fn(result) { LoadedAnalyzerWorkspace(result) }))
      (
        @rabbita.batch([routed, deliveries, portals, billing, assets, animatic, postprocess, analyzers]),
        {
          ..model,
          project: Some(project),
          selected_project_id: project.id,
          loading: false,
          busy: false,
          error: None,
          status: "Canonical revision loaded. No external effect was performed.",
          artifact_draft: artifact_for(project, model.selected_artifact_kind)
          .map(item => item.content.stringify())
          .unwrap_or("{}"),
          asset_plan_draft: if model.asset_plan_draft == "" {
            starter_asset_factory_plan(project)
          } else {
            model.asset_plan_draft
          },
        },
      )
    }
    LoadedProject(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          busy: false,
          error: Some("Could not load project: \{error}"),
        },
      )
    LoadedRouted(Ok(value)) =>
      (@rabbita.none, { ..model, routed: value.executions })
    LoadedRouted(Err(error)) =>
      (@rabbita.none, { ..model, error: Some("Routed execution: \{error}") })
    LoadedDeliveries(Ok(value)) =>
      (@rabbita.none, { ..model, delivery_builds: value.builds })
    LoadedDeliveries(Err(error)) =>
      (@rabbita.none, { ..model, error: Some("Delivery factory: \{error}") })
    LoadedPortals(Ok(value)) =>
      (@rabbita.none, { ..model, client_portals: value.portals })
    LoadedPortals(Err(error)) =>
      (@rabbita.none, { ..model, error: Some("Client portals: \{error}") })
    LoadedBilling(Ok(value)) =>
      (@rabbita.none, { ..model, billing_entries: value.entries })
    LoadedBilling(Err(error)) =>
      (@rabbita.none, { ..model, error: Some("Billing ledger: \{error}") })
    CreatedClientPortal(Ok(value)) => {
      let portals = @http.get(
        "/api/v2/projects/" + value.portal.project_id + "/client-portals",
      ).expect_json(emit.map(fn(result) { LoadedPortals(result) }))
      (
        portals,
        {
          ..model,
          busy: false,
          latest_client_url: Some(value.client_url),
          status: "Client review URL created once; copy it before leaving this revision.",
          error: None,
        },
      )
    }
    CreatedClientPortal(Err(error)) =>
      (
        @rabbita.none,
        { ..model, busy: false, error: Some("Client portal: \{error}") },
      )
    LoadedCommercial(Ok(value)) => {
      let selected_lead_id = if model.selected_lead_id == "" &&
        !value.leads.is_empty() {
        value.leads[value.leads.length() - 1].lead_id
      } else {
        model.selected_lead_id
      }
      let selected_quote_id = if model.selected_quote_id == "" &&
        !value.quotes.is_empty() {
        value.quotes[value.quotes.length() - 1].quote_id
      } else {
        model.selected_quote_id
      }
      let cmd = if selected_quote_id != "" {
        @http.get(
          "/api/commercial-intake/quotes/" +
          selected_quote_id +
          "/capacity-board",
        ).expect_json(emit.map(fn(result) { LoadedCapacity(result) }))
      } else {
        @rabbita.none
      }
      (
        cmd,
        {
          ..model,
          commercial: Some(value),
          selected_lead_id,
          selected_quote_id,
        },
      )
    }
    LoadedCommercial(Err(error)) =>
      (@rabbita.none, { ..model, error: Some("Commercial intake: \{error}") })
    LoadedCapacity(Ok(value)) =>
      (@rabbita.none, { ..model, capacity_board: Some(value) })
    LoadedCapacity(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          capacity_board: None,
          error: Some("Capacity board: \{error}"),
        },
      )
    LoadedControlTower(Ok(value)) =>
      (
        @rabbita.none,
        {
          ..model,
          control_tower: Some(value),
          status: "Production control tower refreshed from canonical ledgers.",
        },
      )
    LoadedControlTower(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          error: Some("Production control tower: \{error}"),
        },
      )
    RefreshControlTower =>
      (
        @http.get("/api/control-tower").expect_json(
          emit.map(fn(result) { LoadedControlTower(result) }),
        ),
        { ..model, status: "Refreshing portfolio evidence…", error: None },
      )
    SetControlTowerActualsField(field, value) => {
      let form = match field {
        "provider" =>
          { ..model.control_tower_actuals_form, provider_cost_confirmed_cny: value }
        "labor" =>
          { ..model.control_tower_actuals_form, labor_cost_cny: value }
        "other" =>
          { ..model.control_tower_actuals_form, other_cost_cny: value }
        "revenue" =>
          { ..model.control_tower_actuals_form, recognized_revenue_cny: value }
        "founder" =>
          { ..model.control_tower_actuals_form, founder_hours: value }
        "labor_hours" =>
          { ..model.control_tower_actuals_form, completed_labor_hours: value }
        "forecast" =>
          { ..model.control_tower_actuals_form, forecast_completion_date: value }
        "evidence" =>
          { ..model.control_tower_actuals_form, evidence_refs: value }
        _ => model.control_tower_actuals_form
      }
      (@rabbita.none, { ..model, control_tower_actuals_form: form })
    }
    ToggleProviderCostReconciled =>
      (
        @rabbita.none,
        {
          ..model,
          control_tower_actuals_form: {
            ..model.control_tower_actuals_form,
            provider_cost_reconciled: !model
            .control_tower_actuals_form
            .provider_cost_reconciled,
          },
        },
      )
    RecordControlTowerActuals =>
      match model.control_tower {
        Some(tower) => {
          let candidates = tower.projects.filter(value => {
            value.project_id == model.selected_project_id
          })
          if candidates.length() != 1 {
            (
              @rabbita.none,
              { ..model, error: Some("Select one project in the project rail.") },
            )
          } else {
            let project = candidates[0]
            let form = model.control_tower_actuals_form
            let body : Json = {
              "command_id": "tower-actuals-" +
              (model.command_sequence + 1).to_string(),
              "expected_project_revision": project.project_revision,
              "expected_actuals_version": project.actuals_version
              .map(value => value.to_json())
              .unwrap_or(Json::null()),
              "expected_actuals_digest": project.actuals_digest
              .map(value => value.to_json())
              .unwrap_or(Json::null()),
              "provider_cost_confirmed_cny": optional_double_json(
                form.provider_cost_confirmed_cny,
              ),
              "labor_cost_cny": optional_double_json(form.labor_cost_cny),
              "other_cost_cny": optional_double_json(form.other_cost_cny),
              "recognized_revenue_cny": optional_double_json(
                form.recognized_revenue_cny,
              ),
              "founder_hours": optional_double_json(form.founder_hours),
              "completed_labor_hours": optional_double_json(
                form.completed_labor_hours,
              ),
              "forecast_completion_date": if form.forecast_completion_date.trim() == "" {
                Json::null()
              } else {
                form.forecast_completion_date.to_json()
              },
              "provider_cost_reconciled": form.provider_cost_reconciled,
              "evidence_refs": split_lines(form.evidence_refs),
              "actor": model.operator.actor,
              "actor_role": model.operator.role,
              "observed_at": model.operator.recorded_at,
              "human_confirmed": model.operator.human_confirmed,
            }
            let cmd = @http.post(
                "/api/control-tower/projects/" +
                project.project_id +
                "/actuals",
              )
              .with_json(body)
              .expect_json(
                emit.map(fn(result) {
                  ActionCompleted("Control-tower operating actuals", result)
                }),
              )
            (cmd, { ..model, busy: true, error: None })
          }
        }
        None => (@rabbita.none, model)
      }
    SetControlTowerOwnershipDue(value) =>
      (
        @rabbita.none,
        {
          ..model,
          control_tower_ownership_form: {
            action_due_date: value,
          },
        },
      )
    AssignControlTowerException(exception_id) =>
      match model.control_tower {
        Some(tower) => {
          let candidates = tower.exceptions.filter(value => {
            value.exception_id == exception_id
          })
          if candidates.length() != 1 {
            (@rabbita.none, model)
          } else {
            let exception = candidates[0]
            let assignment = exception.assignment
            let body : Json = {
              "command_id": "tower-owner-" +
              (model.command_sequence + 1).to_string(),
              "expected_exception_digest": exception.digest,
              "expected_assignment_version": assignment
              .map(value => value.version.to_json())
              .unwrap_or(Json::null()),
              "expected_assignment_digest": assignment
              .map(value => value.digest.to_json())
              .unwrap_or(Json::null()),
              "owner": model.operator.actor,
              "owner_role": model.operator.role,
              "action_due_date": model
              .control_tower_ownership_form
              .action_due_date,
              "note": model.operator.note,
              "assigned_by": model.operator.actor,
              "assigned_by_role": model.operator.role,
              "assigned_at": model.operator.recorded_at,
              "human_confirmed": model.operator.human_confirmed,
            }
            let cmd = @http.post(
                "/api/control-tower/exceptions/" +
                exception_id +
                "/assignment",
              )
              .with_json(body)
              .expect_json(
                emit.map(fn(result) {
                  ActionCompleted("Named exception ownership", result)
                }),
              )
            (cmd, { ..model, busy: true, error: None })
          }
        }
        None => (@rabbita.none, model)
      }
    LoadedNeedsIntake(Ok(value)) => {
      let selected = if model.selected_intake_id == "" &&
        !value.intakes.is_empty() {
        value.intakes[value.intakes.length() - 1].packet.packet_id
      } else {
        model.selected_intake_id
      }
      (
        @rabbita.none,
        {
          ..model,
          needs_intake: Some(value),
          selected_intake_id: selected,
        },
      )
    }
    LoadedNeedsIntake(Err(error)) =>
      (
        @rabbita.none,
        { ..model, error: Some("Needs / Strategy intake: \{error}") },
      )
    LoadedAssetFactory(Ok(value)) => {
      let draft = match model.project {
        Some(project) if model.animatic_plan_draft == "" ||
          model.animatic_plan_draft == "{}" ||
          model.asset_factory
          .map(previous => {
            previous.approved_assets.length() != value.approved_assets.length()
          })
          .unwrap_or(false) =>
          starter_animatic_plan(project, value, 1)
        _ => model.animatic_plan_draft
      }
      let postprocess_draft = match model.project {
        Some(project) if model.postprocess_task_draft == "" =>
          starter_postprocess_task(project, value)
        _ => model.postprocess_task_draft
      }
      (@rabbita.none, {
        ..model,
        asset_factory: Some(value),
        animatic_plan_draft: draft,
        postprocess_task_draft: postprocess_draft,
      })
    }
    LoadedAssetFactory(Err(error)) =>
      (
        @rabbita.none,
        { ..model, error: Some("Asset factory: \{error}") },
      )
    SetAssetPlanDraft(value) =>
      (@rabbita.none, { ..model, asset_plan_draft: value })
    RecordAssetPlan =>
      match model.project {
        None => (@rabbita.none, model)
        Some(project) => {
          let plan = @json.parse(model.asset_plan_draft) catch {
            _ =>
              return (
                @rabbita.none,
                { ..model, error: Some("Asset factory plan must be valid JSON.") },
              )
          }
          let body : Json = { "plan": plan }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/asset-factory/plans",
            )
            .with_json(body)
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Reusable asset plan", result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
      }
    DecideAssetPlan(decision) =>
      match (model.project, model.asset_factory) {
        (Some(project), Some(workspace)) if !workspace.plans.is_empty() => {
          let mut plan = workspace.plans[0]
          for candidate in workspace.plans {
            if candidate.plan.version > plan.plan.version {
              plan = candidate
            }
          }
          let body : Json = {
            "expected_plan_version": plan.plan.version,
            "expected_plan_digest": plan.plan.digest,
            "decision": decision,
            "actor": model.operator.actor,
            "actor_role": model.operator.role,
            "note": model.operator.note,
            "decided_at": model.operator.recorded_at,
            "human_confirmed": model.operator.human_confirmed,
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/asset-factory/plan-decisions",
            )
            .with_json(body)
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Reusable asset plan " + decision, result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
        _ => (@rabbita.none, { ..model, error: Some("Record an asset plan first.") })
      }
    RunAssetFactory =>
      match (model.project, model.asset_factory) {
        (Some(project), Some(workspace)) if !workspace.plans.is_empty() => {
          let mut plan = workspace.plans[0]
          for candidate in workspace.plans {
            if candidate.plan.version > plan.plan.version {
              plan = candidate
            }
          }
          let body : Json = {
            "expected_plan_version": plan.plan.version,
            "expected_plan_digest": plan.plan.digest,
            "actor": model.operator.actor,
            "human_confirmed": model.operator.human_confirmed,
            "network_authority": model.operator.human_confirmed,
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/asset-factory/run-pending",
            )
            .with_json(body)
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Bounded multimodal asset run", result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
        _ => (@rabbita.none, { ..model, error: Some("Approve an asset plan first.") })
      }
    RecordAssetVariantQc(variant_id) =>
      match model.project {
        None => (@rabbita.none, model)
        Some(project) => {
          let commands : Array[@rabbita.Cmd] = []
          for dimension in ["technical", "identity", "continuity", "rights", "safety"] {
            let body : Json = {
              "variant_id": variant_id,
              "dimension": dimension,
              "status": "pass",
              "evidence_digest": "review:" + variant_id + ":" + dimension,
              "reviewer": model.operator.actor,
              "reviewer_role": model.operator.role,
              "reviewed_at": model.operator.recorded_at,
              "human_confirmed": model.operator.human_confirmed,
            }
            commands.push(
              @http.post(
                  "/api/v2/projects/" + project.id + "/asset-factory/findings",
                )
                .with_json(body)
                .expect_json(emit.map(fn(result) {
                  ActionCompleted("Asset QC " + dimension, result)
                })),
            )
          }
          (@rabbita.batch(commands), { ..model, busy: true, error: None })
        }
      }
    ApproveAssetVariant(variant_id) =>
      match (model.project, model.asset_factory) {
        (Some(project), Some(workspace)) => {
          let matches = workspace.variants.filter(value => {
            value.variant_id == variant_id
          })
          if matches.is_empty() {
            (@rabbita.none, { ..model, error: Some("Variant is not current.") })
          } else {
            let variant = matches[0]
            let body : Json = {
              "asset_id": variant.asset_id,
              "asset_version": variant.asset_version,
              "variant_id": variant.variant_id,
              "actor": model.operator.actor,
              "actor_role": model.operator.role,
              "approved_at": model.operator.recorded_at,
              "human_confirmed": model.operator.human_confirmed,
            }
            let cmd = @http.post(
                "/api/v2/projects/" + project.id + "/asset-factory/approvals",
              )
              .with_json(body)
              .expect_json(emit.map(fn(result) {
                ActionCompleted("Immutable reusable asset approval", result)
              }))
            (cmd, { ..model, busy: true, error: None })
          }
        }
        _ => (@rabbita.none, model)
      }
    BindAssetFactoryShots =>
      match model.project {
        None => (@rabbita.none, model)
        Some(project) => {
          let body : Json = {
            "project_revision": project.revision,
            "bound_at": model.operator.recorded_at,
            "human_confirmed": model.operator.human_confirmed,
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/asset-factory/bind-shots",
            )
            .with_json(body)
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Exact approved shot asset bindings", result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
      }
    LoadedAnimaticWorkspace(Ok(value)) => {
      let draft = match (model.project, model.asset_factory) {
        (Some(project), Some(factory)) if model.animatic_plan_draft == "" ||
          model.animatic_plan_draft == "{}" =>
          starter_animatic_plan(project, factory, value.plans.length() + 1)
        _ => model.animatic_plan_draft
      }
      (@rabbita.none, { ..model, animatic_workspace: Some(value), animatic_plan_draft: draft })
    }
    LoadedAnimaticWorkspace(Err(error)) =>
      (@rabbita.none, { ..model, error: Some("Storyboard / Animatic: \{error}") })
    SetAnimaticPlanDraft(value) =>
      (@rabbita.none, { ..model, animatic_plan_draft: value })
    RecordAnimaticPlan =>
      match model.project {
        None => (@rabbita.none, model)
        Some(project) => {
          let plan = @json.parse(model.animatic_plan_draft) catch {
            _ => return (@rabbita.none, { ..model, error: Some("Animatic plan must be valid JSON.") })
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/animatic-workspace/plans",
            )
            .with_json({ "plan": plan })
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Exact storyboard / animatic plan", result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
      }
    RenderAnimatic =>
      match (model.project, model.animatic_workspace) {
        (Some(project), Some(workspace)) if !workspace.plans.is_empty() => {
          let plan = workspace.plans[workspace.plans.length() - 1]
          let reference = match plan {
            Object(fields) => fields.get("reference")
            _ => None
          }
          guard reference is Some(Object(fields)) &&
            fields.get("version") is Some(Number(version)) &&
            fields.get("digest") is Some(String(plan_digest)) else {
            return (@rabbita.none, { ..model, error: Some("Current animatic plan is malformed.") })
          }
          let body : Json = {
            "expected_plan_version": version.to_int(),
            "expected_plan_digest": plan_digest,
            "actor": model.operator.actor,
            "rendered_at": model.operator.recorded_at,
            "human_confirmed": model.operator.human_confirmed,
            "process_authority": model.operator.human_confirmed,
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/animatic-workspace/render",
            )
            .with_json(body)
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Rendered storyboard sheet and timed animatic", result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
        _ => (@rabbita.none, { ..model, error: Some("Record an animatic plan first.") })
      }
    ApproveRenderedAnimatic =>
      match (model.project, model.animatic_workspace) {
        (Some(project), Some(workspace)) if !workspace.renders.is_empty() => {
          let render = workspace.renders[workspace.renders.length() - 1]
          let body : Json = {
            "expected_render_version": render.reference.version,
            "expected_render_digest": render.reference.digest,
            "actor": model.operator.actor,
            "actor_role": model.operator.role,
            "note": model.operator.note,
            "approved_at": model.operator.recorded_at,
            "human_confirmed": model.operator.human_confirmed,
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/animatic-workspace/approve",
            )
            .with_json(body)
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Exact rendered animatic approval", result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
        _ => (@rabbita.none, { ..model, error: Some("Render an animatic first.") })
      }
    LoadedPostprocessWorkspace(Ok(value)) =>
      (@rabbita.none, { ..model, postprocess_workspace: Some(value) })
    LoadedPostprocessWorkspace(Err(error)) =>
      (@rabbita.none, { ..model, error: Some("Postprocess jobs: \{error}") })
    SetPostprocessTaskDraft(value) =>
      (@rabbita.none, { ..model, postprocess_task_draft: value })
    RecordPostprocessTask =>
      match model.project {
        None => (@rabbita.none, model)
        Some(project) => {
          let task = @json.parse(model.postprocess_task_draft) catch {
            _ => return (@rabbita.none, { ..model, error: Some("Postprocess task must be valid JSON.") })
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/postprocess-jobs/tasks",
            )
            .with_json({ "task": task })
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Exact multimodal postprocess task", result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
      }
    RunPostprocessTask =>
      match (model.project, model.postprocess_workspace) {
        (Some(project), Some(workspace)) if !workspace.tasks.is_empty() => {
          let task = workspace.tasks[workspace.tasks.length() - 1]
          let body : Json = {
            "expected_task_version": task.reference.version,
            "expected_task_digest": task.reference.digest,
            "actor": model.operator.actor,
            "human_confirmed": model.operator.human_confirmed,
            "network_authority": model.operator.human_confirmed,
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/postprocess-jobs/run",
            )
            .with_json(body)
            .expect_json(emit.map(fn(result) {
              ActionCompleted("Bounded postprocess provider job", result)
            }))
          (cmd, { ..model, busy: true, error: None })
        }
        _ => (@rabbita.none, { ..model, error: Some("Record a postprocess task first.") })
      }
    LoadedAnalyzerWorkspace(Ok(value)) => {
      let draft = match model.project {
        Some(project) if model.analyzer_task_draft == "" => starter_analyzer_task(project)
        _ => model.analyzer_task_draft
      }
      (@rabbita.none, { ..model, analyzer_workspace: Some(value), analyzer_task_draft: draft })
    }
    LoadedAnalyzerWorkspace(Err(error)) =>
      (@rabbita.none, { ..model, error: Some("Automated QC: \{error}") })
    SetAnalyzerTaskDraft(value) =>
      (@rabbita.none, { ..model, analyzer_task_draft: value })
    RecordAnalyzerTask =>
      match model.project {
        None => (@rabbita.none, model)
        Some(project) => {
          let task = @json.parse(model.analyzer_task_draft) catch {
            _ => return (@rabbita.none, { ..model, error: Some("Analyzer task must be valid JSON.") })
          }
          let cmd = @http.post("/api/v2/projects/" + project.id + "/automated-qc/tasks")
            .with_json({ "task": task })
            .expect_json(emit.map(fn(result) { ActionCompleted("Exact QC analyzer task", result) }))
          (cmd, { ..model, busy: true, error: None })
        }
      }
    RunAnalyzerTask =>
      match (model.project, model.analyzer_workspace) {
        (Some(project), Some(workspace)) if !workspace.tasks.is_empty() => {
          let task = workspace.tasks[workspace.tasks.length() - 1]
          let body : Json = {
              "expected_task_version": task.reference.version,
              "expected_task_digest": task.reference.digest,
              "actor": model.operator.actor,
              "human_confirmed": model.operator.human_confirmed,
              "network_authority": task.execution_mode == "external-semantic" && model.operator.human_confirmed,
            }
          let cmd = @http.post("/api/v2/projects/" + project.id + "/automated-qc/run")
            .with_json(body)
            .expect_json(emit.map(fn(result) { ActionCompleted("Automated QC evidence", result) }))
          (cmd, { ..model, busy: true, error: None })
        }
        _ => (@rabbita.none, { ..model, error: Some("Record an analyzer task first.") })
      }
    SelectIntake(value) =>
      (@rabbita.none, { ..model, selected_intake_id: value })
    SetIntakePacketDraft(value) =>
      (@rabbita.none, { ..model, intake_packet_draft: value })
    SetIntakeSeedProjectId(value) =>
      (@rabbita.none, { ..model, intake_seed_project_id: value })
    ImportNeedsPacket => {
      let packet = @json.parse(model.intake_packet_draft) catch {
        _ =>
          return (
            @rabbita.none,
            { ..model, error: Some("MoonWiki export packet must be valid JSON.") },
          )
      }
      let packet_id = match packet {
        Object(fields) =>
          match fields.get("packet_id") {
            Some(String(value)) => value
            _ => ""
          }
        _ => ""
      }
      if packet_id.trim().is_empty() {
        (
          @rabbita.none,
          { ..model, error: Some("MoonWiki packet_id is required.") },
        )
      } else {
        let body : Json = {
          "packet": packet,
          "imported_at": model.operator.recorded_at.to_json(),
        }
        let cmd = @http.post("/api/v2/needs-intakes")
          .with_json(body)
          .expect_json(emit.map(fn(result) {
            ActionCompleted("MoonWiki needs packet", result)
          }))
        (
          cmd,
          {
            ..model,
            busy: true,
            selected_intake_id: packet_id,
            error: None,
            status: "Importing immutable MoonWiki evidence for deterministic completeness review…",
          },
        )
      }
    }
    DecideNeedsIntake(decision) =>
      match model.needs_intake {
        Some(workspace) => {
          let matches = workspace.intakes.filter(value => {
            value.packet.packet_id == model.selected_intake_id
          })
          if matches.is_empty() {
            (@rabbita.none, { ..model, error: Some("Select an imported intake.") })
          } else if !model.operator.human_confirmed {
            (
              @rabbita.none,
              { ..model, error: Some("Named-human confirmation is required.") },
            )
          } else {
            let imported = matches[matches.length() - 1]
            let body : Json = {
              "packet_version": imported.packet.packet_version,
              "expected_provenance_digest": imported.validation.provenance_digest,
              "decision": decision,
              "actor": model.operator.actor,
              "actor_role": model.operator.role,
              "note": model.operator.note,
              "decided_at": model.operator.recorded_at,
              "human_confirmed": model.operator.human_confirmed,
            }
            let cmd = @http.post(
                "/api/v2/needs-intakes/" +
                imported.packet.packet_id +
                "/decisions",
              )
              .with_json(body)
              .expect_json(emit.map(fn(result) {
                ActionCompleted("Needs / Strategy decision", result)
              }))
            (
              cmd,
              {
                ..model,
                busy: true,
                error: None,
                status: "Recording an exact named-human intake decision…",
              },
            )
          }
        }
        None => (@rabbita.none, { ..model, error: Some("Intake ledger is not loaded.") })
      }
    SeedProjectFromIntake =>
      match model.needs_intake {
        Some(workspace) => {
          let matches = workspace.intakes.filter(value => {
            value.packet.packet_id == model.selected_intake_id
          })
          if matches.is_empty() || model.intake_seed_project_id.trim().is_empty() {
            (
              @rabbita.none,
              { ..model, error: Some("Select an intake and provide a project id.") },
            )
          } else {
            let imported = matches[matches.length() - 1]
            let body : Json = {
              "packet_version": imported.packet.packet_version.to_json(),
              "expected_provenance_digest": imported.validation.provenance_digest.to_json(),
              "project_id": model.intake_seed_project_id.to_json(),
              "recorded_at": model.operator.recorded_at.to_json(),
            }
            let cmd = @http.post(
                "/api/v2/needs-intakes/" +
                imported.packet.packet_id +
                "/seed-project",
              )
              .with_json(body)
              .expect_json(emit.map(fn(result) {
                ActionCompleted("Intake-bound production project", result)
              }))
            (
              cmd,
              {
                ..model,
                busy: true,
                selected_project_id: model.intake_seed_project_id,
                error: None,
                status: "Creating a project bound to approved MoonWiki evidence…",
              },
            )
          }
        }
        None => (@rabbita.none, { ..model, error: Some("Intake ledger is not loaded.") })
      }
    CreatedProject(Ok(project)) => {
      let index = @http.get("/api/v2/projects").expect_json(
        emit.map(fn(result) { LoadedProjects(result) }),
      )
      (
        index,
        {
          ..model,
          project: Some(project),
          selected_project_id: project.id,
          busy: false,
          loading: false,
          tab: Creative,
          status: "Project and seven governed creative drafts created.",
          error: None,
        },
      )
    }
    CreatedProject(Err(error)) =>
      (
        @rabbita.none,
        { ..model, busy: false, error: Some("Create project: \{error}") },
      )
    ActionCompleted(label, Ok(value)) =>
      match api_error_message(value) {
        Some(message) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: Some(label + ": " + message),
              status: "Command rejected; canonical state was not changed locally.",
            },
          )
        None => {
          let commands : Array[@rabbita.Cmd] = []
          commands.push(
            @http.get("/api/v2/projects").expect_json(
              emit.map(fn(result) { LoadedProjects(result) }),
            ),
          )
          if model.selected_project_id != "" {
            commands.push(
              @http.get("/api/v2/projects/" + model.selected_project_id).expect_json(
                emit.map(fn(result) { LoadedProject(result) }),
              ),
            )
            commands.push(
              @http.get(
                "/api/v2/projects/" + model.selected_project_id + "/postprocess-jobs",
              ).expect_json(emit.map(fn(result) { LoadedPostprocessWorkspace(result) })),
            )
            commands.push(
              @http.get(
                "/api/v2/projects/" + model.selected_project_id + "/animatic-workspace",
              ).expect_json(emit.map(fn(result) { LoadedAnimaticWorkspace(result) })),
            )
          }
          commands.push(
            @http.get("/api/commercial-intake").expect_json(
              emit.map(fn(result) { LoadedCommercial(result) }),
            ),
          )
          commands.push(
            @http.get("/api/control-tower").expect_json(
              emit.map(fn(result) { LoadedControlTower(result) }),
            ),
          )
          commands.push(
            @http.get("/api/v2/needs-intakes").expect_json(
              emit.map(fn(result) { LoadedNeedsIntake(result) }),
            ),
          )
          if model.selected_project_id != "" {
            commands.push(
              @http.get(
                "/api/v2/projects/" + model.selected_project_id + "/asset-factory",
              ).expect_json(emit.map(fn(result) { LoadedAssetFactory(result) })),
            )
          }
          (
            @rabbita.batch(commands),
            {
              ..model,
              busy: false,
              error: None,
              status: label + " recorded; refreshing exact server state.",
              command_sequence: model.command_sequence + 1,
            },
          )
        }
      }
    ActionCompleted(label, Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          busy: false,
          error: Some(label + ": \{error}"),
          status: "Command rejected; canonical state was not changed locally.",
        },
      )
    SetCreateField(field, value) => {
      let create = match field {
        "project_id" => { ..model.create, project_id: value }
        "title" => { ..model.create, title: value }
        "objective" => { ..model.create, objective: value }
        "audience" => { ..model.create, audience: value }
        "channels" => { ..model.create, channels: value }
        "rights_owner" => { ..model.create, rights_owner: value }
        "duration" => { ..model.create, duration_seconds: value }
        "budget" => { ..model.create, maximum_budget_cny: value }
        _ => model.create
      }
      (@rabbita.none, { ..model, create, })
    }
    SetRightsConfirmed(value) =>
      (
        @rabbita.none,
        { ..model, create: { ..model.create, rights_confirmed: value } },
      )
    CreateProject => {
      let duration = @string.parse_int(model.create.duration_seconds) catch {
        _ => 0
      }
      let budget = @string.parse_double(model.create.maximum_budget_cny) catch {
        _ => -1.0
      }
      if model.create.project_id.trim().is_empty() ||
        model.create.title.trim().is_empty() ||
        duration < 180 ||
        duration > 480 ||
        budget <= 0.0 {
        (
          @rabbita.none,
          {
            ..model,
            error: Some(
              "Project id/title, 180–480 seconds, and a positive budget are required.",
            ),
          },
        )
      } else {
        let body : Json = {
          "project_id": model.create.project_id,
          "title": model.create.title,
          "objective": model.create.objective,
          "audience": model.create.audience,
          "channels": split_csv(model.create.channels).to_json(),
          "rights_owner": model.create.rights_owner,
          "rights_confirmed": model.create.rights_confirmed,
          "target_duration_seconds": duration,
          "max_budget_cny": budget,
        }
        let cmd = @http.post("/api/v2/projects")
          .with_json(body)
          .expect_json(emit.map(fn(result) { CreatedProject(result) }))
        (
          cmd,
          {
            ..model,
            busy: true,
            error: None,
            status: "Creating project graph and version-one creative drafts…",
          },
        )
      }
    }
    SelectArtifact(kind) => {
      let draft = match model.project {
        Some(project) =>
          artifact_for(project, kind)
          .map(item => item.content.stringify())
          .unwrap_or("{}")
        None => "{}"
      }
      (
        @rabbita.none,
        { ..model, selected_artifact_kind: kind, artifact_draft: draft },
      )
    }
    SetArtifactDraft(value) =>
      (@rabbita.none, { ..model, artifact_draft: value })
    ReviseArtifact =>
      match model.project {
        Some(project) =>
          match artifact_for(project, model.selected_artifact_kind) {
            Some(artifact) => {
              let content = @json.parse(model.artifact_draft) catch {
                _ =>
                  return (
                    @rabbita.none,
                    {
                      ..model,
                      error: Some("Creative revision must be valid JSON."),
                    },
                  )
              }
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_artifact_version": artifact.version,
                "expected_artifact_digest": artifact.digest,
                "actor": model.operator.actor,
                "content": content,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/creative/" +
                  model.selected_artifact_kind +
                  "/revise",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Creative revision", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (@rabbita.none, { ..model, error: Some("Artifact is missing.") })
          }
        None => (@rabbita.none, model)
      }
    DecideArtifact(decision) =>
      match model.project {
        None => (@rabbita.none, model)
        Some(project) =>
          match artifact_for(project, model.selected_artifact_kind) {
            None =>
              (@rabbita.none, { ..model, error: Some("Artifact is missing.") })
            Some(artifact) => {
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_artifact_version": artifact.version,
                "expected_artifact_digest": artifact.digest,
                "actor": model.operator.actor,
                "actor_role": model.operator.role,
                "human_confirmed": model.operator.human_confirmed,
                "decision": if decision == "approved" {
                  "approve"
                } else {
                  "reject"
                },
                "note": model.operator.note,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/creative/" +
                  model.selected_artifact_kind +
                  "/decision",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Creative " + decision, result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
          }
      }
    AdvanceGate(gate) =>
      match model.project {
        None => (@rabbita.none, model)
        Some(project) => {
          let evidence = match gate {
            "G0" => project.brief.map(item => item.digest)
            "G1" => project.bible.map(item => item.digest)
            "G2" => project.animatic.map(item => item.digest)
            "G3" => project.model_routing_plan.map(item => item.digest)
            _ => None
          }
          match evidence {
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  error: Some(
                    "This gate is controlled by its dedicated downstream workspace.",
                  ),
                },
              )
            Some(digest) => {
              let sequence = model.command_sequence + 1
              let body : Json = {
                "expected_revision": project.revision,
                "command_id": "studio-gate-\{gate}-\{sequence}",
                "recorded_at": model.operator.recorded_at,
                "evidence_digest": digest,
                "gate": gate,
                "actor": model.operator.actor,
                "role": model.operator.role,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" + project.id + "/advance",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Gate " + gate, result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
          }
        }
      }
    SetRoutingField(field, value) => {
      let routing_form = match field {
        "route_id" => { ..model.routing_form, route_id: value }
        "provider" => { ..model.routing_form, provider: value }
        "model" => { ..model.routing_form, model: value }
        "model_version" => { ..model.routing_form, model_version: value }
        "data_class" => { ..model.routing_form, permitted_data_class: value }
        "cost" => { ..model.routing_form, cost_ceiling_cny: value }
        "total" => { ..model.routing_form, total_cost_ceiling_cny: value }
        "retry" => { ..model.routing_form, retry_limit: value }
        "fallback" => { ..model.routing_form, fallback_route_ids: value }
        _ => model.routing_form
      }
      (@rabbita.none, { ..model, routing_form, })
    }
    RecordRoutingPlan =>
      match model.project {
        Some(project) => {
          let form = model.routing_form
          let current = project.model_routing_plan
          let routes : Json = [
            {
              "route_id": form.route_id,
              "shot_ids": project.shots.map(shot => shot.id).to_json(),
              "asset_kind": "video",
              "provider": form.provider,
              "model": form.model,
              "model_version": form.model_version,
              "permitted_data_class": form.permitted_data_class,
              "cost_ceiling_cny": @string.parse_double(form.cost_ceiling_cny) catch {
                _ => 0.0
              },
              "fallback_route_ids": split_csv(form.fallback_route_ids).to_json(),
              "retry_limit": @string.parse_int(form.retry_limit) catch {
                _ => 0
              },
            },
          ]
          let total_cost_ceiling_cny = @string.parse_double(
            form.total_cost_ceiling_cny,
          ) catch {
            _ => 0.0
          }
          // MoonBit's derived `FromJson` treats an optional field as absent;
          // an explicit JSON null is not the same contract. Initial creation
          // therefore omits optimistic-lock fields entirely, while revisions
          // bind both fields to the exact current plan.
          let body : Json = match current {
            None =>
              {
                "expected_project_revision": project.revision,
                "routes": routes,
                "total_cost_ceiling_cny": total_cost_ceiling_cny,
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
              }
            Some(plan) =>
              {
                "expected_project_revision": project.revision,
                "expected_plan_version": plan.version,
                "expected_plan_digest": plan.digest,
                "routes": routes,
                "total_cost_ceiling_cny": total_cost_ceiling_cny,
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
              }
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/governance/model-routing",
            )
            .with_json(body)
            .expect_json(
              emit.map(fn(result) {
                ActionCompleted("Model routing plan", result)
              }),
            )
          (cmd, { ..model, busy: true, error: None })
        }
        None => (@rabbita.none, model)
      }
    DecideRouting(role, decision) =>
      match model.project {
        Some(project) =>
          match project.model_routing_plan {
            Some(plan) => {
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_plan_version": plan.version,
                "expected_plan_digest": plan.digest,
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
                "actor_role": role,
                "decision": decision,
                "note": model.operator.note,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/governance/model-routing/decisions",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Routing " + role + " decision", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (
                @rabbita.none,
                { ..model, error: Some("Record a routing plan first.") },
              )
          }
        None => (@rabbita.none, model)
      }
    SetQcField(field, value) => {
      let qc_form = match field {
        "shot_id" => { ..model.qc_form, shot_id: value }
        "attempt_id" => { ..model.qc_form, attempt_id: value }
        "route_id" => { ..model.qc_form, route_id: value }
        "prompt_digest" => { ..model.qc_form, prompt_digest: value }
        "sources" => { ..model.qc_form, source_asset_digests: value }
        "cost" => { ..model.qc_form, cost_cny: value }
        "output" => { ..model.qc_form, output_digest: value }
        "attempt_status" => { ..model.qc_form, attempt_status: value }
        "dimension" => { ..model.qc_form, dimension: value }
        "finding_status" => { ..model.qc_form, finding_status: value }
        "evidence" => { ..model.qc_form, evidence_digest: value }
        "finding_version" => { ..model.qc_form, finding_version: value }
        "finding_digest" => { ..model.qc_form, finding_digest: value }
        "note" => { ..model.qc_form, note: value }
        _ => model.qc_form
      }
      (@rabbita.none, { ..model, qc_form, })
    }
    SelectQcShot(shot_id) => {
      let shot = match model.project {
        Some(project) =>
          project.shots.iter().find_first(item => item.id == shot_id)
        None => None
      }
      let route_id = match model.project {
        Some(project) =>
          project.model_routing_plan
          .bind(plan => {
            plan.content.routes
            .iter()
            .find_first(route => route.asset_ids.contains(shot_id))
          })
          .map(route => route.route_id)
          .unwrap_or(model.qc_form.route_id)
        None => model.qc_form.route_id
      }
      let output = shot
        .bind(item => item.asset_id)
        .unwrap_or(model.qc_form.output_digest)
      (
        @rabbita.none,
        {
          ..model,
          qc_form: { ..model.qc_form, shot_id, route_id, output_digest: output },
        },
      )
    }
    RecordGenerationAttempt =>
      match model.project {
        Some(project) =>
          match project.model_routing_plan {
            Some(plan) => {
              let form = model.qc_form
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_routing_plan_version": plan.version,
                "expected_routing_plan_digest": plan.digest,
                "attempt_id": form.attempt_id,
                "route_id": form.route_id,
                "prompt_digest": form.prompt_digest,
                "source_asset_digests": split_csv(form.source_asset_digests).to_json(),
                "seed": Json::null(),
                "cost_cny": @string.parse_double(form.cost_cny) catch {
                  _ => 0.0
                },
                "output_digest": form.output_digest,
                "status": form.attempt_status,
                "actor": model.operator.actor,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/governance/shots/" +
                  form.shot_id +
                  "/attempts",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Generation attempt evidence", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (
                @rabbita.none,
                { ..model, error: Some("Routing plan is required.") },
              )
          }
        None => (@rabbita.none, model)
      }
    RecordQcFinding =>
      match model.project {
        Some(project) => {
          let form = model.qc_form
          let body : Json = {
            "expected_project_revision": project.revision,
            "expected_attempt_digest": form.output_digest,
            "expected_finding_version": if form.finding_digest == "" {
              Json::null()
            } else {
              (@string.parse_int(form.finding_version) catch { _ => 1 }).to_json()
            },
            "expected_finding_digest": if form.finding_digest == "" {
              Json::null()
            } else {
              form.finding_digest.to_json()
            },
            "status": form.finding_status,
            "evidence_digest": form.evidence_digest,
            "note": form.note,
            "reported_by": model.operator.actor,
          }
          let cmd = @http.post(
              "/api/v2/projects/" +
              project.id +
              "/governance/shots/" +
              form.shot_id +
              "/qc/" +
              form.dimension +
              "/findings",
            )
            .with_json(body)
            .expect_json(
              emit.map(fn(result) { ActionCompleted("QC finding", result) }),
            )
          (cmd, { ..model, busy: true, error: None })
        }
        None => (@rabbita.none, model)
      }
    DecideQc(decision) =>
      match model.project {
        Some(project) => {
          let form = model.qc_form
          let body : Json = {
            "expected_project_revision": project.revision,
            "expected_attempt_digest": form.output_digest,
            "expected_finding_version": @string.parse_int(form.finding_version) catch {
              _ => 1
            },
            "expected_finding_digest": form.finding_digest,
            "human_confirmed": model.operator.human_confirmed,
            "actor": model.operator.actor,
            "actor_role": model.operator.role,
            "decision": decision,
            "note": form.note,
          }
          let cmd = @http.post(
              "/api/v2/projects/" +
              project.id +
              "/governance/shots/" +
              form.shot_id +
              "/qc/" +
              form.dimension +
              "/decisions",
            )
            .with_json(body)
            .expect_json(
              emit.map(fn(result) {
                ActionCompleted("Independent QC decision", result)
              }),
            )
          (cmd, { ..model, busy: true, error: None })
        }
        None => (@rabbita.none, model)
      }
    SetDeliveryGovernanceField(field, value) => {
      let delivery_governance_form = match field {
        "video" => { ..model.delivery_governance_form, video_digest: value }
        "audio" => { ..model.delivery_governance_form, audio_digest: value }
        "subtitle" =>
          { ..model.delivery_governance_form, subtitle_digest: value }
        "provenance" =>
          { ..model.delivery_governance_form, provenance_digest: value }
        "ai_label" => { ..model.delivery_governance_form, ai_label: value }
        "destinations" =>
          { ..model.delivery_governance_form, destination_ids: value }
        "manifest" =>
          { ..model.delivery_governance_form, manifest_digest: value }
        "rights" =>
          { ..model.delivery_governance_form, rights_ledger_digest: value }
        "destination" =>
          { ..model.delivery_governance_form, destination_id: value }
        "scope" =>
          { ..model.delivery_governance_form, publication_scope: value }
        "expires" =>
          { ..model.delivery_governance_form, publication_expires_at: value }
        "receipt" =>
          {
            ..model.delivery_governance_form,
            publication_receipt_digest: value,
          }
        "authority_ref" =>
          { ..model.delivery_governance_form, publication_authority_ref: value }
        "performance_status" =>
          { ..model.delivery_governance_form, performance_status: value }
        "performance_evidence" =>
          {
            ..model.delivery_governance_form,
            performance_evidence_digest: value,
          }
        "reach" => { ..model.delivery_governance_form, reach: value }
        "completion" =>
          { ..model.delivery_governance_form, completion_rate: value }
        "conversion" =>
          { ..model.delivery_governance_form, conversion_rate: value }
        "revenue" => { ..model.delivery_governance_form, revenue_cny: value }
        "provider_cost" =>
          { ..model.delivery_governance_form, provider_cost_cny: value }
        "founder_hours" =>
          { ..model.delivery_governance_form, founder_hours: value }
        "repeat" =>
          { ..model.delivery_governance_form, repeat_purchase_status: value }
        _ => model.delivery_governance_form
      }
      (@rabbita.none, { ..model, delivery_governance_form, })
    }
    RecordMaster =>
      match model.project {
        Some(project) => {
          let form = model.delivery_governance_form
          let body : Json = {
            "expected_project_revision": project.revision,
            "expected_master_version": match project.master {
              Some(master) => master.version.to_json()
              None => Json::null()
            },
            "expected_master_digest": match project.master {
              Some(master) => master.digest.to_json()
              None => Json::null()
            },
            "duration_seconds": project.target_duration_seconds,
            "video_digest": form.video_digest,
            "audio_digest": form.audio_digest,
            "subtitle_digest": form.subtitle_digest,
            "provenance_digest": form.provenance_digest,
            "ai_label": form.ai_label,
            "human_confirmed": model.operator.human_confirmed,
            "actor": model.operator.actor,
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/governance/master",
            )
            .with_json(body)
            .expect_json(
              emit.map(fn(result) {
                ActionCompleted("Reviewed master record", result)
              }),
            )
          (cmd, { ..model, busy: true, error: None })
        }
        None => (@rabbita.none, model)
      }
    DecideMaster(kind, decision) =>
      match model.project {
        Some(project) =>
          match project.master {
            Some(master) => {
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_master_version": master.version,
                "expected_master_digest": master.digest,
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
                "actor_role": model.operator.role,
                "decision": decision,
                "note": model.operator.note,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/governance/master/" +
                  kind +
                  "/decisions",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Master " + kind + " decision", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (
                @rabbita.none,
                { ..model, error: Some("Record the exact master first.") },
              )
          }
        None => (@rabbita.none, model)
      }
    RecordDeliveryPackage =>
      match model.project {
        Some(project) =>
          match project.master {
            Some(master) => {
              let form = model.delivery_governance_form
              let body : Json = match project.delivery_package {
                None =>
                  {
                    "expected_project_revision": project.revision,
                    "expected_master_version": master.version,
                    "expected_master_digest": master.digest,
                    "destination_ids": split_csv(form.destination_ids).to_json(),
                    "manifest_digest": form.manifest_digest,
                    "rights_ledger_digest": form.rights_ledger_digest,
                    "human_confirmed": model.operator.human_confirmed,
                    "actor": model.operator.actor,
                  }
                Some(delivery) =>
                  {
                    "expected_project_revision": project.revision,
                    "expected_master_version": master.version,
                    "expected_master_digest": master.digest,
                    "expected_delivery_version": delivery.version,
                    "expected_delivery_digest": delivery.digest,
                    "destination_ids": split_csv(form.destination_ids).to_json(),
                    "manifest_digest": form.manifest_digest,
                    "rights_ledger_digest": form.rights_ledger_digest,
                    "human_confirmed": model.operator.human_confirmed,
                    "actor": model.operator.actor,
                  }
              }
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/governance/delivery-package",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Delivery package intent", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (@rabbita.none, { ..model, error: Some("Master is required.") })
          }
        None => (@rabbita.none, model)
      }
    RecordDeliveryMilestone(decision) =>
      match model.project {
        Some(project) =>
          match project.delivery_package {
            Some(delivery) => {
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_delivery_version": delivery.version,
                "expected_delivery_digest": delivery.digest,
                "milestone": "delivery-package",
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
                "actor_role": model.operator.role,
                "decision": decision,
                "note": model.operator.note,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/governance/delivery-milestones",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Delivery milestone " + decision, result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (
                @rabbita.none,
                { ..model, error: Some("Delivery package is required.") },
              )
          }
        None => (@rabbita.none, model)
      }
    AuthorizePublication(decision) =>
      match model.project {
        Some(project) =>
          match project.delivery_package {
            Some(delivery) => {
              let form = model.delivery_governance_form
              let body_fields : Map[String, Json] = {
                "expected_project_revision": project.revision,
                "expected_delivery_version": delivery.version,
                "expected_delivery_digest": delivery.digest,
                "destination_id": form.destination_id,
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
                "actor_role": model.operator.role,
                "decision": decision,
                "scope": form.publication_scope,
                "note": model.operator.note,
              }
              if form.publication_expires_at != "" {
                body_fields["expires_at"] = form.publication_expires_at.to_json()
              }
              let body = Json::object(body_fields)
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/governance/publication-authorizations",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Inert publication " + decision, result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (
                @rabbita.none,
                { ..model, error: Some("Delivery package is required.") },
              )
          }
        None => (@rabbita.none, model)
      }
    RecordPublicationObservation =>
      match model.project {
        Some(project) =>
          match project.delivery_package {
            Some(delivery) => {
              let form = model.delivery_governance_form
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_delivery_version": delivery.version,
                "expected_delivery_digest": delivery.digest,
                "destination_id": form.destination_id,
                "receipt_digest": form.publication_receipt_digest,
                "external_effect_authority_ref": form.publication_authority_ref,
                "observed_at": Json::null(),
                "actor": model.operator.actor,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/governance/publication-observations",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Publication observation", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None => (@rabbita.none, model)
          }
        None => (@rabbita.none, model)
      }
    RecordPerformanceReview =>
      match model.project {
        Some(project) =>
          match project.delivery_package {
            Some(delivery) => {
              let form = model.delivery_governance_form
              let body_fields : Map[String, Json] = {
                "expected_project_revision": project.revision,
                "expected_delivery_version": delivery.version,
                "expected_delivery_digest": delivery.digest,
                "status": form.performance_status,
                "evidence_digest": form.performance_evidence_digest,
                "metrics": {
                  "reach": @string.parse_int(form.reach) catch {
                    _ => 0
                  },
                  "completion_rate": @string.parse_double(form.completion_rate) catch {
                    _ => 0.0
                  },
                  "conversion_rate": @string.parse_double(form.conversion_rate) catch {
                    _ => 0.0
                  },
                },
                "economics": {
                  "revenue_cny": @string.parse_double(form.revenue_cny) catch {
                    _ => 0.0
                  },
                  "provider_cost_cny": @string.parse_double(
                    form.provider_cost_cny,
                  ) catch {
                    _ => 0.0
                  },
                  "founder_hours": @string.parse_double(form.founder_hours) catch {
                    _ => 0.0
                  },
                },
                "repeat_purchase_status": form.repeat_purchase_status,
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
                "actor_role": model.operator.role,
              }
              let body = Json::object(body_fields)
              let cmd = @http.post(
                  "/api/v2/projects/" +
                  project.id +
                  "/governance/performance-reviews",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Performance and economics review", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (
                @rabbita.none,
                { ..model, error: Some("Delivery package is required.") },
              )
          }
        None => (@rabbita.none, model)
      }
    PrepareOutcomeHandoff(final_deliverable_record_id) =>
      match model.project {
        Some(project) => {
          let body : Json = {
            "expected_project_revision": project.revision,
            "final_deliverable_record_id": final_deliverable_record_id,
            "human_confirmed": model.operator.human_confirmed,
            "actor": model.operator.actor,
            "actor_role": model.operator.role,
          }
          let cmd = @http.post(
              "/api/v2/projects/" + project.id + "/delivery/outcome-handoff",
            )
            .with_json(body)
            .expect_json(
              emit.map(fn(result) {
                ActionCompleted("Immutable G7 outcome handoff", result)
              }),
            )
          (cmd, { ..model, busy: true, error: None })
        }
        None => (@rabbita.none, model)
      }
    SetClientOpsField(field, value) => {
      let client_ops_form = match field {
        "client_name" => { ..model.client_ops_form, client_name: value }
        "brand_name" => { ..model.client_ops_form, brand_name: value }
        "brand_accent" => { ..model.client_ops_form, brand_accent: value }
        "expires_at" => { ..model.client_ops_form, expires_at: value }
        "billing_kind" => { ..model.client_ops_form, billing_kind: value }
        "billing_state" => { ..model.client_ops_form, billing_state: value }
        "billing_currency" =>
          { ..model.client_ops_form, billing_currency: value }
        "billing_amount" => { ..model.client_ops_form, billing_amount: value }
        "billing_due_at" => { ..model.client_ops_form, billing_due_at: value }
        "billing_reference" =>
          { ..model.client_ops_form, billing_reference: value }
        "repeat_project_id" =>
          { ..model.client_ops_form, repeat_project_id: value }
        "repeat_title" => { ..model.client_ops_form, repeat_title: value }
        "repeat_objective" =>
          { ..model.client_ops_form, repeat_objective: value }
        "repeat_audience" => { ..model.client_ops_form, repeat_audience: value }
        "repeat_rights_owner" =>
          { ..model.client_ops_form, repeat_rights_owner: value }
        "repeat_duration" =>
          { ..model.client_ops_form, repeat_duration_seconds: value }
        "repeat_budget" => { ..model.client_ops_form, repeat_budget_cny: value }
        _ => model.client_ops_form
      }
      (@rabbita.none, { ..model, client_ops_form, })
    }
    CreateClientPortal =>
      match model.project {
        Some(project) => {
          let builds = model.delivery_builds.filter(item => {
            item.state == "completed"
          })
          match (project.master, builds.length()) {
            (Some(master), count) if count > 0 => {
              let build = builds[count - 1]
              let form = model.client_ops_form
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_master_sha256": master.sha256,
                "build_id": build.build_id,
                "expected_build_digest": build.build_digest,
                "expected_build_record_digest": build.record_digest,
                "client_name": form.client_name,
                "brand_name": form.brand_name,
                "brand_accent": form.brand_accent,
                "expires_at": form.expires_at,
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
                "actor_role": model.operator.role,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" + project.id + "/client-portals",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) { CreatedClientPortal(result) }),
                )
              (
                cmd,
                { ..model, busy: true, error: None, latest_client_url: None },
              )
            }
            _ =>
              (
                @rabbita.none,
                {
                  ..model,
                  error: Some("Accepted completed delivery build is required."),
                },
              )
          }
        }
        None => (@rabbita.none, model)
      }
    ControlClientPortal(portal_id, action) => {
      let candidates = model.client_portals.filter(item => {
        item.portal_id == portal_id
      })
      if candidates.length() != 1 || model.selected_project_id == "" {
        (@rabbita.none, model)
      } else {
        let portal = candidates[0]
        let body : Json = {
          "expected_portal_revision": portal.revision,
          "expected_portal_digest": portal.record_digest,
          "human_confirmed": model.operator.human_confirmed,
          "actor": model.operator.actor,
          "actor_role": model.operator.role,
        }
        let cmd = @http.post(
            "/api/v2/projects/" +
            model.selected_project_id +
            "/client-portals/" +
            portal_id +
            "/" +
            action,
          )
          .with_json(body)
          .expect_json(
            emit.map(fn(result) {
              ActionCompleted("Client portal " + action, result)
            }),
          )
        (cmd, { ..model, busy: true, error: None })
      }
    }
    CreateBillingEntry =>
      match model.project {
        Some(project) => {
          let form = model.client_ops_form
          let body : Json = {
            "expected_project_revision": project.revision,
            "kind": form.billing_kind,
            "state": form.billing_state,
            "currency": form.billing_currency,
            "amount": @string.parse_double(form.billing_amount) catch {
              _ => 0.0
            },
            "due_at": if form.billing_due_at == "" {
              Json::null()
            } else {
              form.billing_due_at.to_json()
            },
            "reference": form.billing_reference,
            "human_confirmed": model.operator.human_confirmed,
            "actor": model.operator.actor,
            "actor_role": model.operator.role,
          }
          let cmd = @http.post("/api/v2/projects/" + project.id + "/billing")
            .with_json(body)
            .expect_json(
              emit.map(fn(result) {
                ActionCompleted("Billing milestone", result)
              }),
            )
          (cmd, { ..model, busy: true, error: None })
        }
        None => (@rabbita.none, model)
      }
    TransitionBilling(billing_id, state) => {
      let candidates = model.billing_entries.filter(item => {
        item.billing_id == billing_id
      })
      if candidates.length() != 1 || model.selected_project_id == "" {
        (@rabbita.none, model)
      } else {
        let entry = candidates[0]
        let body : Json = {
          "expected_billing_revision": entry.revision,
          "expected_billing_digest": entry.record_digest,
          "state": state,
          "human_confirmed": model.operator.human_confirmed,
          "actor": model.operator.actor,
          "actor_role": model.operator.role,
          "reference": model.client_ops_form.billing_reference,
        }
        let cmd = @http.post(
            "/api/v2/projects/" +
            model.selected_project_id +
            "/billing/" +
            billing_id +
            "/state",
          )
          .with_json(body)
          .expect_json(
            emit.map(fn(result) {
              ActionCompleted("Billing state " + state, result)
            }),
          )
        (cmd, { ..model, busy: true, error: None })
      }
    }
    CreateRepeatOrder =>
      match model.project {
        Some(project) => {
          let builds = model.delivery_builds.filter(item => {
            item.state == "completed"
          })
          match (project.bible, builds.length()) {
            (Some(bible), count) if count > 0 => {
              let build = builds[count - 1]
              let form = model.client_ops_form
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_bible_digest": bible.digest,
                "expected_build_digest": build.build_digest,
                "new_project_id": form.repeat_project_id,
                "title": form.repeat_title,
                "objective": form.repeat_objective,
                "audience": form.repeat_audience,
                "channels": project.channels.to_json(),
                "rights_owner": form.repeat_rights_owner,
                "rights_confirmed": true,
                "target_duration_seconds": @string.parse_int(
                  form.repeat_duration_seconds,
                ) catch {
                  _ => 0
                },
                "max_budget_cny": @string.parse_double(form.repeat_budget_cny) catch {
                  _ => 0.0
                },
                "reusable_asset_ids": [],
                "human_confirmed": model.operator.human_confirmed,
                "actor": model.operator.actor,
                "actor_role": model.operator.role,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" + project.id + "/repeat-orders",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Repeat-order draft", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            _ =>
              (
                @rabbita.none,
                {
                  ..model,
                  error: Some(
                    "Approved bible and accepted delivery build are required.",
                  ),
                },
              )
          }
        }
        None => (@rabbita.none, model)
      }
    CreateRoutedExecution =>
      match model.project {
        Some(project) =>
          match project.model_routing_plan {
            Some(plan) => {
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_routing_plan_version": plan.version,
                "expected_routing_plan_digest": plan.digest,
                "actor_id": model.operator.actor,
                "network_authority": model.operator.human_confirmed,
                "publication_authority": false,
              }
              let cmd = @http.post(
                  "/api/v2/projects/" + project.id + "/routed-executions",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Routed multi-shot execution", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            None =>
              (
                @rabbita.none,
                { ..model, error: Some("Approve a routing plan first.") },
              )
          }
        None => (@rabbita.none, model)
      }
    RunRoutedShot(execution_id, shot_id, action) => {
      let candidates = model.routed.filter(item => {
        item.execution_id == execution_id
      })
      if candidates.length() != 1 || model.selected_project_id == "" {
        (@rabbita.none, model)
      } else {
        let execution = candidates[0]
        let body : Json = {
          "expected_execution_revision": execution.revision,
          "expected_execution_digest": execution.record_digest,
          "actor_id": model.operator.actor,
        }
        let cmd = @http.post(
            "/api/v2/projects/" +
            model.selected_project_id +
            "/routed-executions/" +
            execution_id +
            "/shots/" +
            shot_id +
            "/" +
            action,
          )
          .with_json(body)
          .expect_json(
            emit.map(fn(result) {
              ActionCompleted("Shot " + shot_id + " " + action, result)
            }),
          )
        (cmd, { ..model, busy: true, error: None })
      }
    }
    RunAllPendingShots(execution_id) => {
      let candidates = model.routed.filter(item => {
        item.execution_id == execution_id
      })
      match (model.project, candidates.length()) {
        (Some(project), 1) => {
          let execution = candidates[0]
          let body : Json = {
            "expected_project_revision": project.revision,
            "expected_execution_revision": execution.revision,
            "expected_execution_digest": execution.record_digest,
            "actor_id": model.operator.actor,
            "human_confirmed": model.operator.human_confirmed,
          }
          let cmd = @http.post(
              "/api/v2/projects/" +
              project.id +
              "/production-coordinator/routed-executions/" +
              execution_id +
              "/run-pending",
            )
            .with_json(body)
            .expect_json(
              emit.map(fn(result) {
                ActionCompleted("Production coordinator run", result)
              }),
            )
          (cmd, { ..model, busy: true, error: None })
        }
        _ =>
          (
            @rabbita.none,
            { ..model, error: Some("Select one exact routed execution first.") },
          )
      }
    }
    ConfirmBatchQc =>
      match model.project {
        Some(project) =>
          match project.model_routing_plan {
            Some(plan) => {
              let complete = project.shots.all(shot => {
                shot.status == "generated" && shot.asset_id is Some(_)
              })
              if !complete {
                (
                  @rabbita.none,
                  {
                    ..model,
                    error: Some(
                      "Every current shot needs a successful canonical output before batch QC.",
                    ),
                  },
                )
              } else {
                let outputs : Array[Json] = project.shots.map(shot => {
                  "shot_id": shot.id,
                  "output_digest": shot.asset_id.unwrap_or(""),
                })
                let body : Json = {
                  "expected_project_revision": project.revision,
                  "expected_routing_plan_version": plan.version,
                  "expected_routing_plan_digest": plan.digest,
                  "shot_outputs": outputs,
                  "evidence_digest": model.qc_form.evidence_digest,
                  "note": model.qc_form.note,
                  "actor": model.operator.actor,
                  "actor_role": model.operator.role,
                  "human_confirmed": model.operator.human_confirmed,
                }
                let cmd = @http.post(
                    "/api/v2/projects/" +
                    project.id +
                    "/production-coordinator/qc-batches",
                  )
                  .with_json(body)
                  .expect_json(
                    emit.map(fn(result) {
                      ActionCompleted("Production coordinator batch QC", result)
                    }),
                  )
                (cmd, { ..model, busy: true, error: None })
              }
            }
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  error: Some("An approved routing plan is required."),
                },
              )
          }
        None => (@rabbita.none, model)
      }
    CreateDeliveryBuild =>
      match model.project {
        Some(project) =>
          match (project.master, project.delivery_package) {
            (Some(master), Some(delivery)) => {
              let body : Json = {
                "expected_project_revision": project.revision,
                "expected_master_sha256": master.sha256,
                "expected_delivery_version": delivery.version,
                "expected_delivery_digest": delivery.digest,
                "profile": {
                  "contract": "mooncast.delivery-build-profile.v1",
                  "version": 1,
                  "include_source_master": true,
                  "variants": [
                    {
                      "variant_id": "horizontal-1080p",
                      "orientation": "horizontal",
                      "width": 1920,
                      "height": 1080,
                      "policy": "scale",
                    },
                    {
                      "variant_id": "vertical-1080p",
                      "orientation": "vertical",
                      "width": 1080,
                      "height": 1920,
                      "policy": "crop",
                    },
                  ],
                  "cuts": [],
                  "covers": [],
                  "include_subtitles": true,
                  "include_metadata": true,
                  "include_provenance_rights_ai_manifest": true,
                },
              }
              let cmd = @http.post(
                  "/api/v2/projects/" + project.id + "/delivery-builds",
                )
                .with_json(body)
                .expect_json(
                  emit.map(fn(result) {
                    ActionCompleted("Delivery build", result)
                  }),
                )
              (cmd, { ..model, busy: true, error: None })
            }
            _ =>
              (
                @rabbita.none,
                {
                  ..model,
                  error: Some(
                    "Reviewed master and delivery package are required.",
                  ),
                },
              )
          }
        None => (@rabbita.none, model)
      }
    RunDeliveryAction(build_id, action) => {
      let candidates = model.delivery_builds.filter(item => {
        item.build_id == build_id
      })
      if candidates.length() != 1 || model.selected_project_id == "" {
        (@rabbita.none, model)
      } else {
        let build = candidates[0]
        let body : Json = {
          "expected_build_revision": build.revision,
          "expected_record_digest": build.record_digest,
          "actor": model.operator.actor,
        }
        let cmd = @http.post(
            "/api/v2/projects/" +
            model.selected_project_id +
            "/delivery-builds/" +
            build_id +
            "/" +
            action,
          )
          .with_json(body)
          .expect_json(
            emit.map(fn(result) {
              ActionCompleted("Delivery " + action, result)
            }),
          )
        (cmd, { ..model, busy: true, error: None })
      }
    }
    AcceptDelivery(build_id) => {
      let candidates = model.delivery_builds.filter(item => {
        item.build_id == build_id
      })
      match (model.project, candidates.length()) {
        (Some(project), 1) => {
          let build = candidates[0]
          let body : Json = {
            "expected_project_revision": project.revision,
            "expected_build_digest": build.build_digest,
            "expected_build_record_digest": build.record_digest,
            "human_confirmed": model.operator.human_confirmed,
            "actor": model.operator.actor,
            "actor_role": model.operator.role,
            "decision": "accept",
            "note": model.operator.note,
          }
          let cmd = @http.post(
              "/api/v2/projects/" +
              project.id +
              "/delivery-builds/" +
              build_id +
              "/acceptance",
            )
            .with_json(body)
            .expect_json(
              emit.map(fn(result) {
                ActionCompleted("Delivery acceptance", result)
              }),
            )
          (cmd, { ..model, busy: true, error: None })
        }
        _ => (@rabbita.none, model)
      }
    }
    SetOperatorField(field, value) => {
      let operator = match field {
        "actor" => { ..model.operator, actor: value, human_confirmed: false }
        "role" => { ..model.operator, role: value, human_confirmed: false }
        "recorded_at" =>
          { ..model.operator, recorded_at: value, human_confirmed: false }
        "note" => { ..model.operator, note: value, human_confirmed: false }
        _ => model.operator
      }
      (@rabbita.none, { ..model, operator, })
    }
    SetHumanConfirmed(value) =>
      (
        @rabbita.none,
        { ..model, operator: { ..model.operator, human_confirmed: value } },
      )
    SetCommercialField(field, value) => {
      let commercial_form = match field {
        "customer" => { ..model.commercial_form, customer: value }
        "contact" => { ..model.commercial_form, contact_ref: value }
        "problem" => { ..model.commercial_form, payable_problem: value }
        "baseline_cost" => { ..model.commercial_form, baseline_cost_cny: value }
        "baseline_hours" => { ..model.commercial_form, baseline_hours: value }
        "acceptance" =>
          { ..model.commercial_form, measurable_acceptance: value }
        "repeat" => { ..model.commercial_form, repeat_hypothesis: value }
        _ => model.commercial_form
      }
      (@rabbita.none, { ..model, commercial_form, })
    }
    CreateLead => {
      let form = model.commercial_form
      let body : Json = {
        "customer": form.customer,
        "customer_contact_ref": form.contact_ref,
        "payable_problem": form.payable_problem,
        "baseline_cost_cny": @string.parse_double(form.baseline_cost_cny) catch {
          _ => 0.0
        },
        "baseline_time_hours": @string.parse_double(form.baseline_hours) catch {
          _ => 0.0
        },
        "channels": ["review-only"],
        "measurable_acceptance": split_lines(form.measurable_acceptance).to_json(),
        "repeat_hypothesis": form.repeat_hypothesis,
      }
      let cmd = @http.post("/api/commercial-intake/leads")
        .with_json(body)
        .expect_json(
          emit.map(fn(result) { ActionCompleted("Commercial lead", result) }),
        )
      (cmd, { ..model, busy: true, error: None })
    }
    SelectLead(lead_id) =>
      (
        @rabbita.none,
        {
          ..model,
          selected_lead_id: lead_id,
          selected_quote_id: "",
          capacity_board: None,
        },
      )
    QualifyLead(decision) =>
      match model.commercial {
        Some(commercial) => {
          let candidates = commercial.leads.filter(item => {
            item.lead_id == model.selected_lead_id
          })
          if candidates.length() != 1 {
            (@rabbita.none, { ..model, error: Some("Select one lead.") })
          } else {
            let lead = candidates[0]
            let body : Json = {
              "expected_version": lead.version,
              "expected_digest": lead.digest,
              "decision": decision,
              "note": model.operator.note,
              "human_confirmed": model.operator.human_confirmed,
              "actor": model.operator.actor,
              "actor_role": model.operator.role,
            }
            let cmd = @http.post(
                "/api/commercial-intake/leads/" +
                lead.lead_id +
                "/qualification",
              )
              .with_json(body)
              .expect_json(
                emit.map(fn(result) {
                  ActionCompleted("Lead " + decision, result)
                }),
              )
            (cmd, { ..model, busy: true, error: None })
          }
        }
        None => (@rabbita.none, model)
      }
    SetQuoteField(field, value) => {
      let quote_form = match field {
        "project_id" => { ..model.quote_form, project_id: value }
        "title" => { ..model.quote_form, title: value }
        "objective" => { ..model.quote_form, objective: value }
        "audience" => { ..model.quote_form, audience: value }
        "rights_owner" => { ..model.quote_form, rights_owner: value }
        "duration" => { ..model.quote_form, duration_seconds: value }
        "budget" => { ..model.quote_form, production_budget_cny: value }
        "start" => { ..model.quote_form, start_date: value }
        "delivery" => { ..model.quote_form, delivery_date: value }
        "deliverables" => { ..model.quote_form, deliverables: value }
        "revenue" => { ..model.quote_form, quoted_revenue_cny: value }
        "provider_cost" => { ..model.quote_form, provider_cost_cny: value }
        "labor_cost" => { ..model.quote_form, labor_cost_cny: value }
        "other_cost" => { ..model.quote_form, other_cost_cny: value }
        "founder_hours" => { ..model.quote_form, founder_hours: value }
        "contingency" => { ..model.quote_form, contingency_percent: value }
        "deposit" => { ..model.quote_form, deposit_cny: value }
        "animatic" => { ..model.quote_form, animatic_cny: value }
        "master" => { ..model.quote_form, master_cny: value }
        _ => model.quote_form
      }
      (@rabbita.none, { ..model, quote_form, })
    }
    CreateOrReviseQuote =>
      match model.commercial {
        Some(commercial) => {
          let leads = commercial.leads.filter(item => {
            item.lead_id == model.selected_lead_id
          })
          if leads.length() != 1 {
            (
              @rabbita.none,
              { ..model, error: Some("Select a qualified lead.") },
            )
          } else {
            let lead = leads[0]
            let form = model.quote_form
            let quotes = commercial.quotes.filter(item => {
              item.quote_id == model.selected_quote_id
            })
            let revising = quotes.length() == 1 &&
              quotes[0].source_lead_id == lead.lead_id
            let body : Json = {
              "expected_lead_version": if revising {
                Json::null()
              } else {
                lead.version.to_json()
              },
              "expected_lead_digest": if revising {
                Json::null()
              } else {
                lead.digest.to_json()
              },
              "expected_version": if revising {
                quotes[0].version.to_json()
              } else {
                Json::null()
              },
              "expected_digest": if revising {
                quotes[0].digest.to_json()
              } else {
                Json::null()
              },
              "project_id": form.project_id,
              "title": form.title,
              "objective": form.objective,
              "audience": form.audience,
              "rights_owner": form.rights_owner,
              "target_duration_seconds": @string.parse_int(
                form.duration_seconds,
              ) catch {
                _ => 0
              },
              "production_budget_cny": @string.parse_double(
                form.production_budget_cny,
              ) catch {
                _ => 0.0
              },
              "start_date": form.start_date,
              "delivery_date": form.delivery_date,
              "revision_rounds": 2,
              "deliverables": split_lines(form.deliverables).to_json(),
              "provider_overage_policy": "Customer approval required before provider overage.",
              "rights_restrictions": ["Contract-defined rights only"],
              "model_restrictions": [
                "Only approved providers and model versions",
              ],
              "data_restrictions": [
                "No client-confidential data outside approved providers",
              ],
              "quoted_revenue_cny": @string.parse_double(
                form.quoted_revenue_cny,
              ) catch {
                _ => 0.0
              },
              "provider_cost_cny": @string.parse_double(form.provider_cost_cny) catch {
                _ => 0.0
              },
              "labor_cost_cny": @string.parse_double(form.labor_cost_cny) catch {
                _ => 0.0
              },
              "other_cost_cny": @string.parse_double(form.other_cost_cny) catch {
                _ => 0.0
              },
              "founder_hours": @string.parse_double(form.founder_hours) catch {
                _ => 0.0
              },
              "contingency_percent": @string.parse_double(
                form.contingency_percent,
              ) catch {
                _ => 0.0
              },
              "milestones": [
                {
                  "kind": "deposit",
                  "amount_cny": @string.parse_double(form.deposit_cny) catch {
                    _ => 0.0
                  },
                },
                {
                  "kind": "approved-animatic",
                  "amount_cny": @string.parse_double(form.animatic_cny) catch {
                    _ => 0.0
                  },
                },
                {
                  "kind": "accepted-master",
                  "amount_cny": @string.parse_double(form.master_cny) catch {
                    _ => 0.0
                  },
                },
              ],
            }
            let url = if revising {
              "/api/commercial-intake/quotes/" +
              quotes[0].quote_id +
              "/revisions"
            } else {
              "/api/commercial-intake/leads/" + lead.lead_id + "/quotes"
            }
            let cmd = @http.post(url)
              .with_json(body)
              .expect_json(
                emit.map(fn(result) {
                  ActionCompleted(
                    if revising {
                      "Quote revision"
                    } else {
                      "Scoped quote"
                    },
                    result,
                  )
                }),
              )
            (cmd, { ..model, busy: true, error: None })
          }
        }
        None => (@rabbita.none, model)
      }
    SelectQuote(quote_id) => {
      let cmd = @http.get(
        "/api/commercial-intake/quotes/" + quote_id + "/capacity-board",
      ).expect_json(emit.map(fn(result) { LoadedCapacity(result) }))
      (cmd, { ..model, selected_quote_id: quote_id, capacity_board: None })
    }
    DecideQuote(authority) =>
      match model.commercial {
        Some(commercial) => {
          let candidates = commercial.quotes.filter(item => {
            item.quote_id == model.selected_quote_id
          })
          if candidates.length() != 1 {
            (@rabbita.none, { ..model, error: Some("Select one quote.") })
          } else {
            let quote = candidates[0]
            let body : Json = {
              "expected_version": quote.version,
              "expected_digest": quote.digest,
              "authority": authority,
              "decision": if authority == "client" {
                "accept"
              } else {
                "approve"
              },
              "note": model.operator.note,
              "human_confirmed": model.operator.human_confirmed,
              "actor": model.operator.actor,
              "actor_role": model.operator.role,
            }
            let suffix = if authority == "client" {
              "client-acceptance"
            } else {
              "internal-decisions"
            }
            let cmd = @http.post(
                "/api/commercial-intake/quotes/" + quote.quote_id + "/" + suffix,
              )
              .with_json(body)
              .expect_json(
                emit.map(fn(result) {
                  ActionCompleted("Quote " + authority + " approval", result)
                }),
              )
            (cmd, { ..model, busy: true, error: None })
          }
        }
        None => (@rabbita.none, model)
      }
    SetCapacityField(field, value) => {
      let capacity_form = match field {
        "name" => { ..model.capacity_form, resource_name: value }
        "role" => { ..model.capacity_form, resource_role: value }
        "skills" => { ..model.capacity_form, resource_skills: value }
        "weekly_hours" => { ..model.capacity_form, weekly_hours: value }
        "available_from" => { ..model.capacity_form, available_from: value }
        "available_to" => { ..model.capacity_form, available_to: value }
        "resource_id" => { ..model.capacity_form, resource_id: value }
        "reservation_skills" =>
          { ..model.capacity_form, reservation_skills: value }
        "depends_on" => { ..model.capacity_form, depends_on: value }
        "reservation_start" =>
          { ..model.capacity_form, reservation_start: value }
        "reservation_end" => { ..model.capacity_form, reservation_end: value }
        "reservation_hours" =>
          { ..model.capacity_form, reservation_hours: value }
        _ => model.capacity_form
      }
      (@rabbita.none, { ..model, capacity_form, })
    }
    CreateResource => {
      let form = model.capacity_form
      let body : Json = {
        "name": form.resource_name,
        "role": form.resource_role,
        "skills": split_csv(form.resource_skills).to_json(),
        "weekly_hours": @string.parse_double(form.weekly_hours) catch {
          _ => 0.0
        },
        "available_from": form.available_from,
        "available_to": form.available_to,
        "human_confirmed": model.operator.human_confirmed,
        "actor": model.operator.actor,
        "actor_role": model.operator.role,
      }
      let cmd = @http.post("/api/commercial-intake/capacity/resources")
        .with_json(body)
        .expect_json(
          emit.map(fn(result) { ActionCompleted("Capacity resource", result) }),
        )
      (cmd, { ..model, busy: true, error: None })
    }
    CreateReservation =>
      match model.commercial {
        Some(commercial) => {
          let quotes = commercial.quotes.filter(item => {
            item.quote_id == model.selected_quote_id
          })
          if quotes.length() != 1 {
            (@rabbita.none, { ..model, error: Some("Select one quote.") })
          } else {
            let quote = quotes[0]
            let form = model.capacity_form
            let body : Json = {
              "quote_id": quote.quote_id,
              "quote_version": quote.version,
              "quote_digest": quote.digest,
              "resource_id": form.resource_id,
              "skills": split_csv(form.reservation_skills).to_json(),
              "depends_on": split_csv(form.depends_on).to_json(),
              "start_date": form.reservation_start,
              "end_date": form.reservation_end,
              "hours": @string.parse_double(form.reservation_hours) catch {
                _ => 0.0
              },
              "human_confirmed": model.operator.human_confirmed,
              "actor": model.operator.actor,
              "actor_role": model.operator.role,
            }
            let cmd = @http.post("/api/commercial-intake/capacity/reservations")
              .with_json(body)
              .expect_json(
                emit.map(fn(result) {
                  ActionCompleted("Capacity reservation", result)
                }),
              )
            (cmd, { ..model, busy: true, error: None })
          }
        }
        None => (@rabbita.none, model)
      }
    LoadCapacity =>
      if model.selected_quote_id == "" {
        (@rabbita.none, model)
      } else {
        let cmd = @http.get(
          "/api/commercial-intake/quotes/" +
          model.selected_quote_id +
          "/capacity-board",
        ).expect_json(emit.map(fn(result) { LoadedCapacity(result) }))
        (cmd, model)
      }
    ConvertQuote =>
      match (model.commercial, model.capacity_board) {
        (Some(commercial), Some(board)) => {
          let quotes = commercial.quotes.filter(item => {
            item.quote_id == model.selected_quote_id
          })
          if quotes.length() != 1 || !board.ready {
            (
              @rabbita.none,
              {
                ..model,
                error: Some(
                  "Accepted quote and conflict-free capacity are required.",
                ),
              },
            )
          } else {
            let quote = quotes[0]
            let body : Json = {
              "expected_version": quote.version,
              "expected_digest": quote.digest,
              "expected_capacity_digest": board.digest,
              "human_confirmed": model.operator.human_confirmed,
              "actor": model.operator.actor,
              "actor_role": model.operator.role,
            }
            let cmd = @http.post(
                "/api/commercial-intake/quotes/" +
                quote.quote_id +
                "/conversion",
              )
              .with_json(body)
              .expect_json(
                emit.map(fn(result) {
                  ActionCompleted("Quote conversion", result)
                }),
              )
            (cmd, { ..model, busy: true, error: None })
          }
        }
        _ =>
          (
            @rabbita.none,
            { ..model, error: Some("Load the quote capacity board first.") },
          )
      }
  }
}
