///|
suberror CatalogTestError {
  CatalogTestError
}

///|
fn catalog_step(model : Model, message : Msg) -> Model {
  update(_ => @rabbita.none, message, model).1
}

///|
fn catalog_fixture(id : String) -> Json {
  [
    {
      "project_id": id,
      "revision": 1,
      "timeline_id": "timeline",
      "duration_ticks": 1000,
      "updated_at": "fixture",
    },
  ]
}

///|
test "catalog network and malformed failures expose their own recoverable read" {
  let loading = catalog_step(initial_model(), Bootstrap)
  assert_eq(loading.catalog_state, CatalogLoading)
  assert_eq(loading.catalog_generation, 1)
  let failed = catalog_step(loading, ProjectsLoaded(1, Err(CatalogTestError)))
  assert_eq(failed.catalog_state, CatalogFailed)
  assert_true(failed.retry is Some(RetryCatalog))
  assert_false(failed.loading)
  let retry = catalog_step(failed, RetryPending)
  assert_eq(retry.catalog_generation, 2)
  assert_false(retry.catalog_auto_open)
  let malformed = catalog_step(retry, ProjectsLoaded(2, Ok({ "wrong": true })))
  assert_true(malformed.retry is Some(RetryCatalog))
  assert_eq(malformed.catalog_state, CatalogFailed)
  let next = catalog_step(malformed, RetryPending)
  let loaded = catalog_step(
    next,
    ProjectsLoaded(3, Ok(catalog_fixture("real-project"))),
  )
  assert_eq(chosen_project(loaded), "real-project")
  assert_eq(loaded.project_id, "project-mc3a")
  assert_eq(loaded.catalog_state, CatalogReady)
  assert_false(loaded.loading)
  assert_true(loaded.retry is None)
}

///|
test "catalog duplicate requests and stale callbacks cannot replace newer results" {
  let first = catalog_step(initial_model(), Bootstrap)
  let duplicate = catalog_step(first, ReloadProjects)
  assert_eq(duplicate.catalog_generation, 1)
  let failed = catalog_step(first, ProjectsLoaded(1, Err(CatalogTestError)))
  let second = catalog_step(failed, RetryPending)
  let duplicate = catalog_step(second, RetryPending)
  assert_eq(duplicate.catalog_generation, 2)
  let stale = catalog_step(
    second,
    ProjectsLoaded(1, Ok(catalog_fixture("old"))),
  )
  assert_eq(stale.catalog_state, CatalogLoading)
  assert_true(stale.projects.is_empty())
  let current = catalog_step(
    stale,
    ProjectsLoaded(2, Ok(catalog_fixture("new"))),
  )
  let stale = catalog_step(current, ProjectsLoaded(1, Err(CatalogTestError)))
  let repeated = catalog_step(
    stale,
    ProjectsLoaded(2, Ok(catalog_fixture("duplicate"))),
  )
  assert_eq(chosen_project(repeated), "new")
  assert_eq(repeated.project_id, "project-mc3a")
  assert_eq(repeated.error, "")
  assert_true(repeated.retry is None)
}

///|
test "catalog recovery empty state waits for explicit creative workspace open" {
  let failed = catalog_step(
    catalog_step(initial_model(), Bootstrap),
    ProjectsLoaded(1, Err(CatalogTestError)),
  )
  let retry = catalog_step(failed, RetryPending)
  let empty = catalog_step(retry, ProjectsLoaded(2, Ok([])))
  assert_eq(empty.catalog_state, CatalogEmpty)
  assert_false(empty.loading)
  assert_true(empty.status.contains("Open the creative workspace"))
  assert_true(empty.retry is None)
  let explicit = catalog_step(empty, OpenProject)
  assert_true(explicit.loading)
}

///|
test "unknown project cannot be opened from a failed catalog" {
  let failed = catalog_step(
    catalog_step(initial_model(), Bootstrap),
    ProjectsLoaded(1, Err(CatalogTestError)),
  )
  let opened = catalog_step(failed, OpenProject)
  assert_false(opened.loading)
  assert_eq(opened.open_generation, 0)
  assert_true(opened.retry is Some(RetryCatalog))
}

///|
test "newly imported production retains its explicit open retry before catalog refresh" {
  let base = {
    ..initial_model(),
    catalog_state: CatalogEmpty,
    production_project_id: "new-import",
  }
  let imported = catalog_step(base, ProductionImported(Ok({})))
  assert_eq(imported.catalog_state, CatalogReady)
  let failed = catalog_step(
    imported,
    WorkspaceOpened(imported.open_generation, Err(CatalogTestError)),
  )
  assert_true(failed.retry is Some(RetryOpen("new-import")))
  let retry = catalog_step(failed, RetryPending)
  assert_eq(retry.project_id, "new-import")
  assert_eq(retry.open_generation, imported.open_generation + 1)
  assert_true(retry.loading)
}

///|
struct CatalogTestScheduler {
  hooks : @cmd.Hooks
}

///|
impl @cmd.Scheduler for CatalogTestScheduler with fn run_effect(
  self,
  _kind,
  effect,
) {
  effect(self)
}

///|
impl @cmd.Scheduler for CatalogTestScheduler with fn queue_message(
  _self,
  _id,
  send,
) {
  send()
}

///|
impl @cmd.Scheduler for CatalogTestScheduler with fn drain_message(_self) {
  ()
}

///|
impl @cmd.Scheduler for CatalogTestScheduler with fn hooks(self) {
  self.hooks
}

///|
extern "js" fn install_catalog_http_fixture() -> Unit =
  #| () => {
  #|   globalThis.__castCatalogFixture = { oldFetch: globalThis.fetch, requests: [], callbacks: [] };
  #|   globalThis.fetch = (url, options) => {
  #|     const state = globalThis.__castCatalogFixture;
  #|     state.requests.push({url, method: options.method});
  #|     const pending = { success: null, failure: null };
  #|     state.callbacks.push(pending);
  #|     const chain = { then(fn) { pending.success = fn; return chain; }, catch(fn) { pending.failure = fn; return chain; } };
  #|     return chain;
  #|   };
  #| }

///|
extern "js" fn catalog_fixture_reply(
  index : Int,
  body : String,
  fail : Bool,
) -> Unit =
  #| (index, body, fail) => {
  #|   const pending = globalThis.__castCatalogFixture.callbacks[index];
  #|   if (fail) pending.failure(new Error('offline fixture'));
  #|   else pending.success({text() { return {then(fn) { fn(body); }}; }});
  #| }

///|
extern "js" fn catalog_fixture_requests() -> String = "() => JSON.stringify(globalThis.__castCatalogFixture.requests)"

///|
extern "js" fn restore_catalog_http_fixture() -> Unit = "() => { globalThis.fetch = globalThis.__castCatalogFixture.oldFetch; delete globalThis.__castCatalogFixture; }"

///|
test "actual catalog Retry remains read only through success empty malformed and stale responses" {
  install_catalog_http_fixture()
  defer restore_catalog_http_fixture()
  let scheduler = CatalogTestScheduler::{
    hooks: { url_request: None, url_changed: None, },
  }
  let cell = Ref(initial_model())
  fn dispatch(message : Msg) -> @rabbita.Cmd {
    let (command, next) = update(dispatch, message, cell.val)
    cell.val = next
    @cmd.Scheduler::add(scheduler, command)
    @rabbita.none
  }
  ignore(dispatch(Bootstrap))
  catalog_fixture_reply(0, "", true)
  ignore(dispatch(RetryPending))
  ignore(dispatch(RetryPending))
  ignore(dispatch(ReloadProjects))
  catalog_fixture_reply(1, "{}", false)
  assert_true(cell.val.retry is Some(RetryCatalog))
  ignore(dispatch(RetryPending))
  catalog_fixture_reply(2, catalog_fixture("real-project").stringify(), false)
  catalog_fixture_reply(0, catalog_fixture("late-default").stringify(), false)
  assert_eq(chosen_project(cell.val), "real-project")
  assert_eq(cell.val.project_id, "project-mc3a")
  assert_eq(cell.val.open_generation, 0)
  ignore(dispatch(ReloadProjects))
  catalog_fixture_reply(3, "[]", false)
  assert_eq(cell.val.catalog_state, CatalogEmpty)
  let requests = @json.parse(catalog_fixture_requests())
  guard requests is Array(items) else { fail("Missing HTTP fixture log") }
  assert_eq(items.length(), 4)
  for item in items {
    assert_eq(item, { "url": "/api/editor/projects", "method": "GET" })
  }
  ignore(dispatch(OpenProject))
  guard @json.parse(catalog_fixture_requests()) is Array(opened) else {
    fail("Missing explicit open log")
  }
  assert_eq(opened.length(), 11)
  assert_eq(opened.filter(item => item is { "method": "POST", .. }).length(), 1)
}

///|
test "recovered real project uses its existing explicit open path" {
  install_catalog_http_fixture()
  defer restore_catalog_http_fixture()
  let scheduler = CatalogTestScheduler::{
    hooks: { url_request: None, url_changed: None, },
  }
  let recovered = catalog_step(
    catalog_step(initial_model(), ReloadProjects),
    ProjectsLoaded(1, Ok(catalog_fixture("real-project"))),
  )
  let (command, opening) = update(_ => @rabbita.none, OpenProject, recovered)
  @cmd.Scheduler::add(scheduler, command)
  assert_eq(opening.open_generation, 1)
  guard @json.parse(catalog_fixture_requests()) is Array(items) else {
    fail("Missing open log")
  }
  assert_eq(items.length(), 8)
  assert_eq(items[0], {
    "url": "/api/editor/projects/real-project",
    "method": "GET",
  })
  assert_false(catalog_fixture_requests().contains("project-mc3a"))
}

///|
test "documented initial bootstrap still initializes the project-free creative workspace once" {
  install_catalog_http_fixture()
  defer restore_catalog_http_fixture()
  let scheduler = CatalogTestScheduler::{
    hooks: { url_request: None, url_changed: None, },
  }
  let cell = Ref(initial_model())
  fn dispatch(message : Msg) -> @rabbita.Cmd {
    let (command, next) = update(dispatch, message, cell.val)
    cell.val = next
    @cmd.Scheduler::add(scheduler, command)
    @rabbita.none
  }
  ignore(dispatch(Bootstrap))
  catalog_fixture_reply(0, "[]", false)
  catalog_fixture_reply(0, "[]", false)
  ignore(dispatch(Bootstrap))
  assert_eq(cell.val.catalog_state, CatalogEmpty)
  guard @json.parse(catalog_fixture_requests()) is Array(items) else {
    fail("Missing bootstrap requests")
  }
  assert_eq(items.length(), 8)
  assert_eq(items.filter(item => item is { "method": "POST", .. }).length(), 1)
}

///|
test "catalog loading error dismissed error and empty states render distinct recovery actions" {
  let loading = catalog_step(initial_model(), Bootstrap)
  let failed = catalog_step(loading, ProjectsLoaded(1, Err(CatalogTestError)))
  let dismissed = catalog_step(failed, ClearError)
  let empty = catalog_step(
    catalog_step(failed, RetryPending),
    ProjectsLoaded(2, Ok([])),
  )
  for
    (model, label) in [
      (loading, "Loading projects…"),
      (failed, "Retry project catalog"),
      (dismissed, "Retry project catalog"),
      (empty, "Open creative workspace"),
    ] {
    let html = @rabbita.render_to_string(
      @rabbita.static_cell(view(_ => @rabbita.none, model)),
    )
    assert_true(html.contains(label), msg=label)
  }
  let retry = catalog_step(dismissed, ReloadProjects)
  assert_eq(retry.catalog_state, CatalogLoading)
  assert_false(retry.catalog_auto_open)
}
