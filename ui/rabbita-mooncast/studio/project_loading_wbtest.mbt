///|
suberror ProjectLoadTestError {
  ProjectLoadTestError(String)
}

///|
fn step(model : Model, msg : Msg) -> Model {
  update(@cmd.Emit(_ => @rabbita.none), msg, model).1
}

///|
fn fixture_project(id : String, revision : Int) -> ProjectProjection {
  let artifact : ArtifactProjection = {
    artifact_id: id + "-brief",
    artifact_type: "brief",
    version: revision,
    digest: "digest-\{revision}",
    status: "draft",
    content: { "project": id, "version": revision },
    latest_decision: None,
  }
  {
    contract: "fixture",
    id,
    title: id,
    objective: "Fixture",
    audience: "Fixture",
    channels: [],
    target_duration_seconds: 180,
    revision,
    stage: "draft",
    current_gate: Some("G0"),
    gates: {},
    brief: Some(artifact),
    rights: None,
    bible: Some({ ..artifact, artifact_type: "bible", }),
    script: None,
    claims_ledger: None,
    storyboard: None,
    animatic: None,
    episodes: [],
    shots: [],
    budget: { currency: "CNY", maximum: 100, reserved: 0, spent: 0, },
    model_routing_plan: None,
    generation_attempts: {},
    master: None,
    delivery_package: None,
    delivery_milestone_acceptances: [],
    publication_authorizations: [],
    publication_receipts: [],
    performance_reviews: [],
    outcome_handoff: {
      contract: "fixture",
      eligible_final_deliverables: [],
      production_outcomes: [],
      external_handoff_requests: [],
      publication_authority: false,
      payment_authority: false,
      external_effect_authorized: false,
    },
    governance_invalidations: [],
    economics: {
      provider_cost_cny: 0,
      recognized_revenue_cny: 0,
      gross_margin_cny: 0,
    },
  }
}

///|
fn fixture_billing(id : String) -> BillingListProjection {
  {
    entries: [
      {
        contract: "fixture",
        billing_id: id + "-bill",
        project_id: id,
        kind: "deposit",
        currency: "CNY",
        amount: 1,
        reference: id,
        state: "quoted",
        quoted_at: "fixture",
        due_at: None,
        paid_at: None,
        waived_at: None,
        revision: 1,
        record_digest: id,
        payment_effect_performed: false,
      },
    ],
    payment_effect_performed: false,
  }
}

///|
fn fixture_assets(amount : Double) -> AssetFactoryWorkspaceProjection {
  {
    plans: [],
    plan_decisions: [],
    variants: [],
    findings: [],
    approved_assets: [],
    shot_bindings: [],
    total_spent_cny: amount,
    publication_authority: false,
    provider_execution_authority: false,
  }
}

///|
fn fixture_replies(request : ProjectRequest, marker : Double) -> Array[Msg] {
  [
    LoadedRouted(
      request,
      Ok({
        executions: [
          {
            execution_id: request.project_id,
            revision: 1,
            state: "fixture",
            record_digest: "fixture",
            shots: [],
          },
        ],
        publication_authority: false,
      }),
    ),
    LoadedDeliveries(
      request,
      Ok({
        builds: [
          {
            build_id: request.project_id,
            build_digest: "fixture",
            state: "fixture",
            revision: 1,
            attempt_count: 0,
            recovery_count: 0,
            master_sha256: "fixture",
            delivery_digest: "fixture",
            download_url: None,
            last_error: None,
            record_digest: "fixture",
            publication_authority: false,
          },
        ],
        publication_authority: false,
      }),
    ),
    LoadedPortals(
      request,
      Ok({
        portals: [
          {
            contract: "fixture",
            portal_id: request.project_id,
            project_id: request.project_id,
            master_sha256: "fixture",
            delivery_digest: "fixture",
            build_id: "fixture",
            build_digest: "fixture",
            client_name: "fixture",
            brand: { name: "fixture", accent: "fixture", },
            scopes: [],
            expires_at: "fixture",
            status: "fixture",
            revision: 1,
            created_by: "fixture",
            created_by_role: "fixture",
            created_at: "fixture",
            updated_at: "fixture",
            record_digest: "fixture",
          },
        ],
        publication_authority: false,
      }),
    ),
    LoadedBilling(request, Ok(fixture_billing(request.project_id))),
    LoadedAssetFactory(request, Ok(fixture_assets(marker))),
    LoadedAnimaticWorkspace(
      request,
      Ok({
        plans: [request.project_id.to_json()],
        attempts: [],
        renders: [],
        approvals: [],
        publication_authority: false,
      }),
    ),
    LoadedPostprocessWorkspace(
      request,
      Ok({
        tasks: [],
        outputs: [],
        bindings: [],
        total_cost_cny: marker,
        publication_authority: false,
        provider_execution_authority: false,
      }),
    ),
    LoadedAnalyzerWorkspace(
      request,
      Ok({
        tasks: [],
        receipts: [],
        findings: [],
        total_cost_cny: marker,
        human_decisions: 0,
        provider_execution_authority: false,
        publication_authority: false,
      }),
    ),
  ]
}

///|
fn fixture_errors(request : ProjectRequest) -> Array[Msg] {
  let error = ProjectLoadTestError("unavailable")
  [
    LoadedProject(request, Err(error)),
    LoadedRouted(request, Err(error)),
    LoadedDeliveries(request, Err(error)),
    LoadedPortals(request, Err(error)),
    LoadedBilling(request, Err(error)),
    LoadedAssetFactory(request, Err(error)),
    LoadedAnimaticWorkspace(request, Err(error)),
    LoadedPostprocessWorkspace(request, Err(error)),
    LoadedAnalyzerWorkspace(request, Err(error)),
    CreatedClientPortal(request, Err(error)),
  ]
}

///|
fn loaded_fixture(id : String) -> Model {
  let selected = step(initial_model(), SelectProject(id))
  step(
    selected,
    LoadedProject(project_request(selected), Ok(fixture_project(id, 1))),
  )
}

///|
test "project selection ignores A completing after B and an index refresh" {
  let a = step(initial_model(), SelectProject("A"))
  let b = step(a, SelectProject("B"))
  let b = step(b, LoadedProjects(Ok({ projects: [], })))
  assert_true(b.loading)
  let b = step(
    b,
    LoadedProject(project_request(b), Ok(fixture_project("B", 2))),
  )
  let late = step(
    b,
    LoadedProject(project_request(a), Ok(fixture_project("A", 1))),
  )
  assert_eq(late.selected_project_id, "B")
  assert_eq(late.project.map(p => p.id), Some("B"))
  assert_eq(late.project.map(p => p.revision), Some(2))
  assert_eq(late.project_pending.length(), 8)
  assert_true(late.loading)
}

///|
test "switching clears A evidence immediately and rejects all old subordinate successes" {
  let mut a = loaded_fixture("A")
  let request_a = project_request(a)
  for reply in fixture_replies(request_a, 11) {
    a = step(a, reply)
  }
  assert_false(a.loading)
  let mut b = step(a, SelectProject("B"))
  assert_true(b.project is None)
  assert_true(b.billing_entries.is_empty())
  assert_true(b.routed.is_empty())
  assert_true(b.asset_factory is None)
  assert_true(b.animatic_workspace is None)
  assert_true(b.postprocess_workspace is None)
  assert_true(b.analyzer_workspace is None)
  let request_b = project_request(b)
  b = step(b, LoadedProject(request_b, Ok(fixture_project("B", 1))))
  for reply in fixture_replies(request_b, 22).rev() {
    b = step(b, reply)
  }
  for reply in fixture_replies(request_a, 11).rev() {
    b = step(b, reply)
  }
  assert_false(b.loading)
  assert_eq(b.routed[0].execution_id, "B")
  assert_eq(b.delivery_builds[0].build_id, "B")
  assert_eq(b.client_portals[0].project_id, "B")
  assert_eq(b.billing_entries[0].project_id, "B")
  assert_eq(b.asset_factory.map(p => p.total_spent_cny), Some(22.0))
  assert_eq(b.animatic_workspace.map(p => p.plans[0]), Some("B".to_json()))
  assert_eq(b.postprocess_workspace.map(p => p.total_cost_cny), Some(22.0))
  assert_eq(b.analyzer_workspace.map(p => p.total_cost_cny), Some(22.0))
}

///|
test "all stale errors leave the current project's status and progress unchanged" {
  let a = loaded_fixture("A")
  let mut b = step(a, SelectProject("B"))
  let status = b.status
  for reply in fixture_errors(project_request(a)) {
    b = step(b, reply)
  }
  assert_eq(b.status, status)
  assert_true(b.loading)
  assert_true(b.error is None)
  assert_true(b.project_load_errors.is_empty())
  assert_eq(b.project_pending, ["Project"])
}

///|
test "same-project repeated refreshes reject old project sidecars and errors" {
  let original = loaded_fixture("A")
  let first = step(original, RefreshProject)
  let second = step(first, RefreshProject)
  assert_true(second.project_generation > first.project_generation)
  let mut latest = step(
    second,
    LoadedProject(project_request(second), Ok(fixture_project("A", 3))),
  )
  for reply in fixture_replies(project_request(second), 33) {
    latest = step(latest, reply)
  }
  latest = step(
    latest,
    LoadedProject(project_request(first), Ok(fixture_project("A", 2))),
  )
  for reply in fixture_replies(project_request(original), 11) {
    latest = step(latest, reply)
  }
  for reply in fixture_errors(project_request(first)) {
    latest = step(latest, reply)
  }
  assert_eq(latest.project.map(p => p.revision), Some(3))
  assert_eq(latest.asset_factory.map(p => p.total_spent_cny), Some(33.0))
  assert_false(latest.loading)
  assert_true(latest.project_load_errors.is_empty())
}

///|
test "dirty artifact drafts survive canonical refresh project return and artifact switches" {
  let a = loaded_fixture("A")
  let a = step(a, SetArtifactDraft("{\"local\":\"A brief\"}"))
  let a = step(a, SelectArtifact("bible"))
  let a = step(a, SetArtifactDraft("A bible incomplete JSON"))
  let a = step(a, SelectArtifact("brief"))
  assert_eq(a.artifact_draft, "{\"local\":\"A brief\"}")
  let refresh = step(a, RefreshProject)
  let refresh = step(
    refresh,
    LoadedProject(project_request(refresh), Ok(fixture_project("A", 2))),
  )
  assert_eq(refresh.artifact_draft, "{\"local\":\"A brief\"}")
  assert_true(artifact_draft_is_dirty(refresh))
  let b = step(refresh, SelectProject("B"))
  let b = step(
    b,
    LoadedProject(project_request(b), Ok(fixture_project("B", 1))),
  )
  assert_false(artifact_draft_is_dirty(b))
  let b = step(b, SetArtifactDraft("B brief"))
  let a = step(b, SelectProject("A"))
  let a = step(
    a,
    LoadedProject(project_request(a), Ok(fixture_project("A", 3))),
  )
  assert_eq(a.artifact_draft, "{\"local\":\"A brief\"}")
  assert_eq(
    step(a, SelectArtifact("bible")).artifact_draft,
    "A bible incomplete JSON",
  )
}

///|
test "clean drafts follow canonical refresh and confirmed saves retire only matching local text" {
  let a = loaded_fixture("A")
  let refresh = step(a, RefreshProject)
  let refreshed = step(
    refresh,
    LoadedProject(project_request(refresh), Ok(fixture_project("A", 2))),
  )
  assert_eq(
    refreshed.artifact_draft,
    fixture_project("A", 2).brief.unwrap().content.stringify(),
  )
  let saved_text = fixture_project("A", 3).brief.unwrap().content.stringify()
  let edited = step(refreshed, SetArtifactDraft(saved_text))
  let refresh = step(edited, RefreshProject)
  let saved = step(
    refresh,
    LoadedProject(project_request(refresh), Ok(fixture_project("A", 3))),
  )
  assert_false(artifact_draft_is_dirty(saved))
  assert_true(saved.artifact_drafts.is_empty())
  let newer = step(saved, SetArtifactDraft("newer local edit"))
  let refresh = step(newer, RefreshProject)
  let newer = step(
    refresh,
    LoadedProject(project_request(refresh), Ok(fixture_project("A", 3))),
  )
  assert_eq(newer.artifact_draft, "newer local edit")
}

///|
test "failed current sidecars remain explicit until a retry succeeds" {
  let mut a = loaded_fixture("A")
  let request = project_request(a)
  a = step(a, LoadedBilling(request, Err(ProjectLoadTestError("offline"))))
  assert_true(a.loading)
  assert_eq(a.project_load_errors.length(), 1)
  for reply in fixture_replies(request, 1) {
    a = step(a, reply)
  }
  assert_false(a.loading)
  assert_true(a.billing_entries.is_empty())
  assert_eq(a.project_load_errors[0].0, "Billing ledger")
  let retry = step(a, RefreshProject)
  assert_true(retry.project_load_errors.is_empty())
  let mut retry = step(
    retry,
    LoadedProject(project_request(retry), Ok(fixture_project("A", 2))),
  )
  for reply in fixture_replies(project_request(retry), 2) {
    retry = step(retry, reply)
  }
  assert_false(retry.loading)
  assert_true(retry.project_load_errors.is_empty())
  assert_eq(retry.billing_entries[0].project_id, "A")
}

///|
test "navigation cancellation invalidates pending replies and prevents index auto-open" {
  let a = loaded_fixture("A")
  let mut cancelled = step(a, SelectProject(""))
  cancelled = step(
    cancelled,
    LoadedProject(project_request(a), Ok(fixture_project("A", 1))),
  )
  for reply in fixture_replies(project_request(a), 1) {
    cancelled = step(cancelled, reply)
  }
  for reply in fixture_errors(project_request(a)) {
    cancelled = step(cancelled, reply)
  }
  cancelled = step(
    cancelled,
    LoadedProjects(
      Ok({
        projects: [
          {
            project_id: "A",
            title: "A",
            revision: 1,
            stage: "draft",
            current_gate: None,
            next_gate: None,
            updated_at: "fixture",
          },
        ],
      }),
    ),
  )
  assert_eq(cancelled.selected_project_id, "")
  assert_true(cancelled.project is None)
  assert_false(cancelled.loading)
  assert_true(cancelled.project_pending.is_empty())
  assert_true(cancelled.project_load_errors.is_empty())
}

///|
test "wrong project identity becomes a retryable error without accepting its data" {
  let selected = step(initial_model(), SelectProject("B"))
  let result = step(
    selected,
    LoadedProject(project_request(selected), Ok(fixture_project("A", 1))),
  )
  assert_true(result.project is None)
  assert_eq(result.selected_project_id, "B")
  assert_false(result.loading)
  assert_eq(result.project_load_errors.length(), 1)
}

///|
test "failed same-project refresh retains the last successful project and draft" {
  let original = loaded_fixture("A")
  let edited = step(original, SetArtifactDraft("retained local draft"))
  let refreshing = step(edited, RefreshProject)
  let failed = step(
    refreshing,
    LoadedProject(
      project_request(refreshing),
      Err(ProjectLoadTestError("offline")),
    ),
  )
  assert_eq(failed.project.map(p => p.id), Some("A"))
  assert_eq(failed.project.map(p => p.revision), Some(1))
  assert_eq(failed.artifact_draft, "retained local draft")
  assert_false(failed.loading)
  assert_eq(failed.project_load_errors[0].0, "Project")
  assert_true(failed.status.contains("last successful load"))
}

///|
test "command refresh starts a new generation without erasing local drafts" {
  let original = loaded_fixture("A")
  let edited = step(original, SetArtifactDraft("in progress"))
  let refreshed = step(
    edited,
    ActionCompleted(project_request(edited), "Creative revision", Ok({})),
  )
  assert_true(refreshed.project_generation > edited.project_generation)
  assert_eq(refreshed.project_pending, ["Project"])
  assert_eq(refreshed.artifact_draft, "in progress")
  let refreshed = step(
    refreshed,
    LoadedProject(project_request(edited), Ok(fixture_project("A", 99))),
  )
  assert_eq(refreshed.project.map(p => p.revision), Some(1))
  assert_eq(refreshed.artifact_draft, "in progress")
}

///|
#warnings("-alert_unstable")
fn rendered(html : @rabbita.Html) -> String {
  @rabbita.render_to_string(@rabbita.static_cell(html))
}

///|
fn fixture_created_portal(id : String) -> ClientPortalCreatedProjection {
  {
    portal: {
      contract: "fixture",
      portal_id: id,
      project_id: id,
      master_sha256: "fixture",
      delivery_digest: "fixture",
      build_id: "fixture",
      build_digest: "fixture",
      client_name: "fixture",
      brand: { name: "fixture", accent: "fixture", },
      scopes: [],
      expires_at: "fixture",
      status: "fixture",
      revision: 1,
      created_by: "fixture",
      created_by_role: "fixture",
      created_at: "fixture",
      updated_at: "fixture",
      record_digest: "fixture",
    },
    client_url: "/client/fixture-" + id,
    raw_token_returned_once: true,
    external_effect_performed: false,
    publication_authority: false,
  }
}

///|
test "late mutation successes and failures preserve B state and expose A outcomes separately" {
  let a = { ..loaded_fixture("A"), busy: true, }
  let request = project_request(a)
  let b = step(a, SelectProject("B"))
  assert_false(b.busy)
  let b = step(
    b,
    LoadedProject(project_request(b), Ok(fixture_project("B", 2))),
  )
  let b = step(b, SetArtifactDraft("B local edit"))
  let b = {
    ..b,
    busy: true,
    status: "B command in flight",
    error: Some("B existing error"),
  }
  let replies = [
    ActionCompleted(request, "Creative revision", Ok({})),
    ActionCompleted(request, "Creative revision", Ok({ "error": "A rejected" })),
    ActionCompleted(
      request,
      "Creative revision",
      Err(ProjectLoadTestError("A offline")),
    ),
    CreatedProject(request, Ok(fixture_project("new-A", 1))),
    CreatedProject(request, Err(ProjectLoadTestError("A create failed"))),
    CreatedClientPortal(request, Ok(fixture_created_portal("A"))),
    CreatedClientPortal(request, Err(ProjectLoadTestError("A portal failed"))),
  ]
  let mut result = b
  for reply in replies {
    result = step(result, reply)
  }
  assert_eq(result.selected_project_id, "B")
  assert_eq(result.project.map(p => p.id), Some("B"))
  assert_eq(result.project_generation, b.project_generation)
  assert_eq(result.project_selection_generation, b.project_selection_generation)
  assert_eq(result.status, "B command in flight")
  assert_eq(result.error, Some("B existing error"))
  assert_true(result.busy)
  assert_eq(result.artifact_draft, "B local edit")
  assert_eq(result.command_notices.length(), 7)
  assert_true(
    result.command_notices[0].contains("Project A: Creative revision recorded"),
  )
  assert_true(result.command_notices[1].contains("A rejected"))
  assert_true(result.command_notices[3].contains("new-A created"))
  assert_true(result.latest_client_url is None)
  assert_eq(result.client_urls.get("A"), Some("/client/fixture-A"))
  assert_false(rendered(render_status(result)).contains("/client/fixture-A"))
  let returned = step(result, SelectProject("A"))
  assert_eq(returned.latest_client_url, Some("/client/fixture-A"))
}

///|
test "same-project read refresh retains command ownership until its delayed outcome arrives" {
  let a = { ..loaded_fixture("A"), busy: true, }
  let request = project_request(a)
  let refresh = step(a, RefreshProject)
  assert_eq(
    refresh.project_selection_generation,
    a.project_selection_generation,
  )
  assert_true(refresh.project_generation > a.project_generation)
  let refresh = step(
    refresh,
    LoadedProject(project_request(refresh), Ok(fixture_project("A", 2))),
  )
  assert_true(refresh.busy)
  let completed = step(
    refresh,
    ActionCompleted(request, "Creative revision", Ok({})),
  )
  assert_false(completed.busy)
  assert_true(completed.project_generation > refresh.project_generation)
  assert_true(completed.command_notices.is_empty())
  assert_true(completed.status.contains("Creative revision recorded"))
  let rejected = step(
    refresh,
    ActionCompleted(
      request,
      "Creative revision",
      Ok({ "error": "rejected fixture" }),
    ),
  )
  assert_false(rejected.busy)
  assert_eq(rejected.error, Some("Creative revision: rejected fixture"))
  let failed = step(
    refresh,
    ActionCompleted(
      request,
      "Creative revision",
      Err(ProjectLoadTestError("offline")),
    ),
  )
  assert_false(failed.busy)
  assert_true(failed.error is Some(_))
}

///|
test "same-selection portal result survives refresh and is retained by project" {
  let a = { ..loaded_fixture("A"), busy: true, }
  let request = project_request(a)
  let refresh = step(a, RefreshProject)
  let completed = step(
    refresh,
    CreatedClientPortal(request, Ok(fixture_created_portal("A"))),
  )
  assert_eq(completed.latest_client_url, Some("/client/fixture-A"))
  assert_eq(completed.client_urls.get("A"), Some("/client/fixture-A"))
  assert_false(completed.busy)
  assert_true(completed.command_notices.is_empty())
  let b = step(completed, SelectProject("B"))
  assert_true(b.latest_client_url is None)
  assert_eq(
    step(b, SelectProject("A")).latest_client_url,
    Some("/client/fixture-A"),
  )
  let failure = step(
    refresh,
    CreatedClientPortal(request, Err(ProjectLoadTestError("offline"))),
  )
  assert_false(failure.busy)
  assert_true(failure.error is Some(_))
}

///|
test "A B A navigation rejects old mutation focus and state changes" {
  let a = loaded_fixture("A")
  let old = project_request(a)
  let b = step(a, SelectProject("B"))
  let returned = step(b, SelectProject("A"))
  assert_true(
    returned.project_selection_generation > a.project_selection_generation,
  )
  let returned = { ..returned, busy: true, status: "new A context", }
  let result = step(returned, ActionCompleted(old, "Creative revision", Ok({})))
  let result = step(
    result,
    CreatedProject(old, Ok(fixture_project("new-project", 1))),
  )
  assert_eq(result.selected_project_id, "A")
  assert_eq(result.project_generation, returned.project_generation)
  assert_eq(result.status, "new A context")
  assert_true(result.busy)
  assert_eq(result.command_notices.length(), 2)
}

///|
test "empty-selection cancellation rejects delayed creation without losing its outcome" {
  let initial = initial_model()
  let cancelled = step(initial, SelectProject(""))
  let result = step(
    cancelled,
    CreatedProject(
      project_request(initial),
      Ok(fixture_project("new-project", 1)),
    ),
  )
  assert_eq(result.selected_project_id, "")
  assert_true(result.project is None)
  assert_true(result.tab == Overview)
  assert_true(result.command_notices[0].contains("new-project created"))
  let current = step(
    initial,
    CreatedProject(
      project_request(initial),
      Ok(fixture_project("new-project", 1)),
    ),
  )
  assert_eq(current.selected_project_id, "new-project")
  assert_true(current.tab == Creative)
  assert_true(current.loading)
}

///|
test "same-project refresh accepts delayed creation success and error" {
  let a = { ..loaded_fixture("A"), busy: true, }
  let request = project_request(a)
  let refresh = step(a, RefreshProject)
  let created = step(
    refresh,
    CreatedProject(request, Ok(fixture_project("new-project", 1))),
  )
  assert_eq(created.selected_project_id, "new-project")
  assert_true(created.tab == Creative)
  assert_false(created.busy)
  assert_true(created.command_notices.is_empty())
  let failed = step(
    refresh,
    CreatedProject(request, Err(ProjectLoadTestError("offline"))),
  )
  assert_eq(failed.selected_project_id, "A")
  assert_false(failed.busy)
  assert_true(failed.error is Some(_))
  assert_true(failed.command_notices.is_empty())
}

///|
test "an in-flight read cannot clear a newer command rejection" {
  let a = { ..loaded_fixture("A"), busy: true, }
  let request = project_request(a)
  let refresh = step(a, RefreshProject)
  let rejected = step(
    refresh,
    ActionCompleted(
      request,
      "Creative revision",
      Ok({ "error": "reject fixture" }),
    ),
  )
  let loaded = step(
    rejected,
    LoadedProject(project_request(rejected), Ok(fixture_project("A", 2))),
  )
  assert_eq(loaded.error, Some("Creative revision: reject fixture"))
  assert_false(loaded.busy)
}

///|
test "creation completion preserves a newer explicit tab and reports its outcome" {
  let a = { ..loaded_fixture("A"), busy: true, tab: Overview, }
  let request = project_request(a)
  let navigated = step(a, SelectTab(ControlTower))
  assert_true(navigated.tab_generation > a.tab_generation)
  let created = step(
    navigated,
    CreatedProject(request, Ok(fixture_project("new-project", 1))),
  )
  assert_true(created.tab == ControlTower)
  assert_eq(created.selected_project_id, "A")
  assert_eq(created.project_generation, navigated.project_generation)
  assert_false(created.busy)
  assert_true(created.command_notices[0].contains("new-project created"))
  let failed = step(
    navigated,
    CreatedProject(request, Err(ProjectLoadTestError("offline"))),
  )
  assert_true(failed.tab == ControlTower)
  assert_eq(failed.selected_project_id, "A")
  assert_false(failed.busy)
  assert_eq(failed.command_notices.length(), 1)
  let returned = step(navigated, SelectTab(Overview))
  let result = step(
    returned,
    CreatedProject(request, Ok(fixture_project("new-project", 1))),
  )
  assert_true(result.tab == Overview)
  assert_eq(result.selected_project_id, "A")
}

///|
test "creation index refresh cannot auto-select after explicit initial tab navigation" {
  let initial = { ..initial_model(), busy: true, }
  let navigated = step(initial, SelectTab(ControlTower))
  let created = step(
    navigated,
    CreatedProject(
      project_request(initial),
      Ok(fixture_project("new-project", 1)),
    ),
  )
  let indexed = step(
    created,
    LoadedProjects(
      Ok({
        projects: [
          {
            project_id: "new-project",
            title: "New project",
            revision: 1,
            stage: "draft",
            current_gate: None,
            next_gate: None,
            updated_at: "fixture",
          },
        ],
      }),
    ),
  )
  assert_eq(indexed.selected_project_id, "")
  assert_true(indexed.tab == ControlTower)
  assert_false(indexed.busy)
  assert_true(indexed.project is None)
}

///|
test "late A portal after A B A navigation is recoverable by same-project refresh" {
  let a = loaded_fixture("A")
  let old = project_request(a)
  let b = step(a, SelectProject("B"))
  let returned = step(b, SelectProject("A"))
  let returned = step(
    returned,
    LoadedProject(project_request(returned), Ok(fixture_project("A", 2))),
  )
  let late = step(
    returned,
    CreatedClientPortal(old, Ok(fixture_created_portal("A"))),
  )
  assert_eq(late.selected_project_id, "A")
  assert_true(late.latest_client_url is None)
  assert_eq(late.client_urls.get("A"), Some("/client/fixture-A"))
  let refreshing = step(late, RefreshProject)
  assert_eq(refreshing.latest_client_url, Some("/client/fixture-A"))
  let failed = step(
    refreshing,
    LoadedProject(
      project_request(refreshing),
      Err(ProjectLoadTestError("offline")),
    ),
  )
  assert_eq(failed.latest_client_url, Some("/client/fixture-A"))
  assert_eq(step(failed, SelectProject("B")).latest_client_url, None)
}

///|
test "rendered loading failure retry and draft states describe the selected project" {
  let emit : @rabbita.Emit[Msg] = @cmd.Emit(_ => @rabbita.none)
  let selected = step(initial_model(), SelectProject("B"))
  let loading = rendered(render_surface(emit, selected))
  assert_true(loading.contains("Loading selected project"))
  assert_true(loading.contains("Selected project: B"))
  assert_false(loading.contains("Create production project"))
  let failed = step(
    selected,
    LoadedProject(
      project_request(selected),
      Err(ProjectLoadTestError("offline")),
    ),
  )
  assert_true(
    rendered(render_surface(emit, failed)).contains(
      "Project could not be loaded",
    ),
  )
  assert_true(rendered(render_header(emit, failed)).contains("Retry"))
  assert_true(
    rendered(render_status(failed)).contains(
      "Project: " + failed.project_load_errors[0].1,
    ),
  )
  let edited = step(loaded_fixture("B"), SetArtifactDraft("local edit"))
  assert_true(
    rendered(render_creative(emit, edited, edited.project)).contains(
      "Unsaved creative edits retained",
    ),
  )
  assert_true(rendered(render_status(edited)).contains("Still loading:"))
}
