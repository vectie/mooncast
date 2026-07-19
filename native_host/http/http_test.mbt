///|
test "safe static paths stay below their root" {
  debug_inspect(safe_static_path("/"), content="Some(\"index.html\")")
  debug_inspect(safe_static_path("/editor.js"), content="Some(\"editor.js\")")
  debug_inspect(safe_static_path("/../secret"), content="None")
  debug_inspect(safe_static_path("/%2e%2e/secret"), content="None")
}

///|
test "range parsing is bounded" {
  debug_inspect(
    parse_range("bytes=2-5", 10),
    content="Some({ start: 2, end_inclusive: 5 })",
  )
  debug_inspect(
    parse_range("bytes=-3", 10),
    content="Some({ start: 7, end_inclusive: 9 })",
  )
  debug_inspect(parse_range("bytes=20-", 10), content="None")
  debug_inspect(parse_range("bytes=0-1,4-5", 10), content="None")
}

///|
test "static responses use browser-safe MIME types" {
  inspect(content_type("index.html"), content="text/html; charset=utf-8")
  inspect(
    content_type("assets/app.js"),
    content="text/javascript; charset=utf-8",
  )
  inspect(content_type("assets/app.css"), content="text/css; charset=utf-8")
  let response = static_response("index.html", b"<!doctype html>")
  assert_true(
    response.headers.get("Content-Type") == Some("text/html; charset=utf-8"),
  )
}

///|
test "router dispatches exact typed routes" {
  let router = Router::new()
  router.add(Get, "/health", _ => text_response(200, "OK", "healthy"))
  let request : Request = {
    request_method: Get,
    path: "/health",
    query: None,
    headers: {},
    body: b"",
  }
  debug_inspect(router.dispatch(request).status, content="200")
}
