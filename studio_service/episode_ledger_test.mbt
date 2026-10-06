///|
async test "public episode ledger API and view reopen the same persisted episode" {
  let root = "/tmp/mooncast-ledger-public-" + @async.now().to_string()
  let graph = @production_app.episode_production_graph(
    "ledger-public", "Synthetic public API fixture", 180, 5000.0,
  )
  let service = @studio_service.StudioService::new(root)
  ignore(service.create_project(graph, "2026-10-04T00:00:00Z"))
  let path = "/api/v2/projects/ledger-public/episodes/" +
    graph.episodes[0].episode_id +
    "/ledger"
  let reopened = @studio_service.StudioService::new(root)
  let response = reopened.dispatch_http({
    request_method: Get,
    path,
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(response.status, 200)
  let ledger = @json.parse(@utf8.decode(response.body))
  assert_eq(
    ledger,
    reopened.episode_ledger(graph.project_id, graph.episodes[0].episode_id),
  )
  let page = reopened.dispatch_http({
    request_method: Get,
    path: path + "/view",
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(page.status, 200)
  assert_true(@utf8.decode(page.body).contains("Next step"))
  assert_true(@utf8.decode(page.body).contains("Unknown"))
}
