///|
fn association_step(model : Model, message : Msg) -> Model {
  update(_ => @rabbita.none, message, model).1
}

///|
fn association_projects() -> Array[@api.ProjectSummary] {
  decode_project_response([
    {
      "project_id": "A",
      "revision": 1,
      "timeline_id": "a",
      "duration_ticks": 1000,
      "updated_at": "fixture",
    },
    {
      "project_id": "B",
      "revision": 1,
      "timeline_id": "b",
      "duration_ticks": 1000,
      "updated_at": "fixture",
    },
  ]).unwrap()
}

///|
fn association_workspace(id : String) -> Json {
  { "ok": true, "conflict": false, "data": { "project_id": id, "revision": 1 } }
}

///|
fn association_model() -> Model {
  let base = initial_model()
  {
    ..base,
    project_id: "A",
    catalog_state: CatalogReady,
    projects: association_projects(),
    workspace: decode_workspace_response(association_workspace("A")),
    open_generation: 1,
    review_comment: "A unsent marker",
    workspace_comment: "A graph comment",
    export_state: {
      ..base.export_state,
      job_id: "master",
      download_url: "/A/master.mp4",
      receipt_state: "succeeded",
      promoted: true,
    },
  }
}

///|
fn association_graph(id : String) -> WorkspaceGraphSummary {
  {
    contract: "mooncast.workspace.graph.v1",
    graph_id: "combine-videos",
    project_id: id,
    revision: 1,
    title: id + " draft",
    nodes: [],
    edges: [],
    output_node_ids: [],
    created_by: "fixture",
    created_at: "fixture",
  }
}

///|
test "project selection leaves the current result and action target visibly associated until Open" {
  let a = association_model()
  let selected = association_step(a, SelectProject("B"))
  assert_eq(selected.project_id, "A")
  assert_eq(chosen_project(selected), "B")
  assert_eq(selected.export_state.download_url, "/A/master.mp4")
  assert_eq(selected.workspace.bind(value => value.project_id), Some("A"))
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(project_header(_ => @rabbita.none, selected)),
  )
  assert_true(html.contains("Working in: A"))
  assert_true(html.contains("B selected; use Open to switch"))
  assert_true(html.contains("Open selected project"))
}

///|
test "opening empty B hides A results and returning to A restores only its own drafts and resume key" {
  let a = {
    ..association_model(),
    workspace_graph: Some(association_graph("A")),
    workspace_graph_dirty: true,
  }
  let b = association_step(association_step(a, SelectProject("B")), OpenProject)
  assert_eq(b.project_id, "B")
  assert_true(b.workspace is None)
  assert_true(b.workspace_graph is None)
  assert_eq(b.export_state.download_url, "")
  assert_eq(b.export_state.job_id, "")
  assert_false(b.export_state.promoted)
  assert_eq(b.review_comment, "")
  let b = association_step(
    b,
    SnapshotLoaded(b.open_generation, Ok(association_workspace("B"))),
  )
  assert_eq(b.workspace.bind(value => value.project_id), Some("B"))
  assert_eq(b.export_state.download_url, "")
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(production_handoff_view(_ => @rabbita.none, b)),
  )
  assert_false(html.contains("/A/master.mp4"))
  assert_true(html.contains("No verified export loaded for B"))
  let b = association_step(b, ReviewCommentChanged("B unsent marker"))
  let a = association_step(association_step(b, SelectProject("A")), OpenProject)
  assert_eq(a.review_comment, "A unsent marker")
  assert_eq(a.workspace_comment, "A graph comment")
  assert_eq(a.export_state.job_id, "master")
  assert_eq(a.export_state.download_url, "/A/master.mp4")
  assert_false(a.export_state.promoted)
  assert_eq(a.workspace_graph.map(value => value.title), Some("A draft"))
  let a = association_step(
    a,
    WorkspaceGraphLoaded(Ok(association_graph("A").to_json())),
  )
  assert_true(a.workspace_graph_dirty)
  let b = association_step(association_step(a, SelectProject("B")), OpenProject)
  assert_eq(b.review_comment, "B unsent marker")
  assert_eq(b.export_state.download_url, "")
}

///|
test "late project callbacks cannot repopulate B or a later A visit" {
  let a = association_model()
  let b = association_step(association_step(a, SelectProject("B")), OpenProject)
  let old = ProjectReply(
    "A",
    1,
    WorkspaceGraphLoaded(Ok(association_graph("A").to_json())),
  )
  let b = association_step(b, old)
  assert_true(b.workspace_graph is None)
  let a = association_step(association_step(b, SelectProject("A")), OpenProject)
  let a = association_step(a, old)
  assert_true(a.workspace_graph is None)
  let a = association_step(
    a,
    ProjectReply(
      "B",
      2,
      WorkspaceActionFinished("comment", Err(CatalogTestError)),
    ),
  )
  assert_eq(a.error, "")
  assert_true(a.loading)
}

///|
test "export key selection clears completed result and ownership flags" {
  let a = association_step(
    association_model(),
    ExportChanged("job_id", "new-master"),
  )
  assert_eq(a.export_state.job_id, "new-master")
  assert_eq(a.export_state.download_url, "")
  assert_eq(a.export_state.receipt_state, "idle")
  assert_false(a.export_state.promoted)
  let a = association_step(
    a,
    ExportReply("master", 0, ExportPolled(Err(CatalogTestError))),
  )
  assert_eq(a.error, "")
}

///|
test "in-flight action stays bound to A while B is selected and Open remains explicit" {
  let a = { ..association_model(), busy: true, }
  let chosen = association_step(a, SelectProject("B"))
  let not_opened = association_step(chosen, OpenProject)
  assert_eq(not_opened.project_id, "A")
  assert_eq(chosen_project(not_opened), "B")
  let completed = association_step(
    not_opened,
    ProjectReply("A", 1, WorkspaceActionFinished("tag", Ok({}))),
  )
  assert_false(completed.busy)
  assert_eq(completed.project_id, "A")
  let opened = association_step(completed, OpenProject)
  assert_eq(opened.project_id, "B")
  assert_eq(opened.export_state.download_url, "")
}

///|
extern "js" fn association_dom_fixture(enable : Bool) -> Unit =
  #| enable => {
  #|   if (enable) { globalThis.__castAssociationOldDocument = globalThis.document; globalThis.document = { getElementById: () => null }; }
  #|   else { globalThis.document = globalThis.__castAssociationOldDocument; delete globalThis.__castAssociationOldDocument; }
  #| }

///|
test "actual open HTTP callbacks remain scoped through B then A with reversed replies" {
  install_catalog_http_fixture()
  association_dom_fixture(true)
  defer restore_catalog_http_fixture()
  defer association_dom_fixture(false)
  let scheduler = CatalogTestScheduler::{
    hooks: { url_request: None, url_changed: None, },
  }
  let cell = Ref(association_model())
  fn dispatch(message : Msg) -> @rabbita.Cmd {
    let (command, next) = update(dispatch, message, cell.val)
    cell.val = next
    @cmd.Scheduler::add(scheduler, command)
    @rabbita.none
  }
  ignore(dispatch(SelectProject("B")))
  ignore(dispatch(OpenProject))
  ignore(dispatch(SelectProject("A")))
  ignore(dispatch(OpenProject))
  assert_eq(cell.val.project_id, "A")
  assert_eq(cell.val.open_generation, 3)
  catalog_fixture_reply(0, association_workspace("B").stringify(), false)
  catalog_fixture_reply(4, association_graph("B").to_json().stringify(), false)
  assert_true(cell.val.workspace is None)
  assert_true(cell.val.workspace_graph is None)
  catalog_fixture_reply(8, association_workspace("A").stringify(), false)
  assert_eq(cell.val.workspace.bind(value => value.project_id), Some("A"))
  catalog_fixture_reply(16, association_workspace("A").stringify(), false)
  catalog_fixture_reply(0, "", true)
  assert_eq(cell.val.error, "")
  assert_eq(cell.val.export_state.download_url, "/A/master.mp4")
}

///|
fn association_export(job : String, state : String) -> String {
  let digest = "sha256:" + "a".repeat(64)
  let plan = "sha256:" + "b".repeat(64)
  let url = "/A/" + job + ".mp4"
  (
    {
      "job_id": job,
      "state": state,
      "output_digest": digest,
      "media_url": url,
      "result": {
        "export_receipt": {
          "digest": digest,
          "plan_digest": plan,
          "output_ref": url,
        },
      },
    } : Json).stringify()
}

///|
test "legacy response cannot hide another project in its canonical snapshot" {
  let snapshot : @api.WorkspaceSnapshot = @json.from_json({
    "revision": 1,
    "snapshot": {
      "project_id": "A",
      "revision": 1,
      "timeline": {
        "timeline_id": "a",
        "revision": 1,
        "timebase": { "ticks_per_second": 1000 },
        "tracks": [],
        "transitions": [],
      },
    },
  })
  assert_true(workspace_matches_project(snapshot, "A"))
  assert_false(workspace_matches_project(snapshot, "B"))
}

///|
test "actual export readback ignores duplicate old receipts after changing the resume key" {
  install_catalog_http_fixture()
  defer restore_catalog_http_fixture()
  let scheduler = CatalogTestScheduler::{
    hooks: { url_request: None, url_changed: None, },
  }
  let cell = Ref(association_model())
  fn dispatch(message : Msg) -> @rabbita.Cmd {
    let (command, next) = update(dispatch, message, cell.val)
    cell.val = next
    @cmd.Scheduler::add(scheduler, command)
    @rabbita.none
  }
  ignore(dispatch(PollExport))
  ignore(dispatch(SelectProject("B")))
  catalog_fixture_reply(0, association_export("master", "succeeded"), false)
  assert_eq(cell.val.project_id, "A")
  assert_eq(cell.val.export_state.download_url, "/A/master.mp4")
  ignore(dispatch(ExportChanged("job_id", "new-master")))
  ignore(dispatch(PollExport))
  catalog_fixture_reply(0, association_export("master", "succeeded"), false)
  assert_eq(cell.val.export_state.download_url, "")
  assert_true(cell.val.busy)
  catalog_fixture_reply(1, association_export("new-master", "succeeded"), false)
  assert_false(cell.val.busy)
  assert_eq(cell.val.export_state.download_url, "/A/new-master.mp4")
  ignore(dispatch(OpenProject))
  assert_eq(cell.val.project_id, "B")
  catalog_fixture_reply(1, association_export("new-master", "succeeded"), false)
  assert_eq(cell.val.export_state.download_url, "")
}
