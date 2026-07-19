///|
async test "legacy Studio create is atomic qualified and immediately listable" {
  let root = "/tmp/mooncast-studio-contract-" + @async.now().to_string()
  let service = StudioService::new(root)
  let body =
    #|{"project_id":"ui-contract-episode","title":"UI contract episode","objective":"Deliver an accepted 3–8 minute episode","audience":"design partner","channels":["review-only"],"rights_owner":"named-owner","rights_confirmed":true,"target_duration_seconds":180,"max_budget_cny":20000}
  let created = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/v2/projects",
    query: None,
    headers: { "content-type": "application/json" },
    body: @utf8.encode(body),
  })
  assert_eq(created.status, 201)
  let created_json = @utf8.decode(created.body)
  assert_true(created_json.contains("\"brief\""))
  assert_false(created_json.contains(":null"))
  let durable = service.get_project("ui-contract-episode")
  assert_true(durable.snapshot.qualification is Some(_))
  assert_eq(durable.snapshot.creative_artifacts.length(), 7)

  let listed = service.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/v2/projects",
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(listed.status, 200)
  let listed_json = @utf8.decode(listed.body)
  assert_true(listed_json.contains("\"projects\""))
  assert_true(listed_json.contains("ui-contract-episode"))
  assert_false(listed_json.contains("request_invalid"))
}
