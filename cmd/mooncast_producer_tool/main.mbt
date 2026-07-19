///|
const MAX_BODY_BYTES = 1048576

///|
/// Long-running routed generation is bounded at ten minutes per HTTP action.
const REQUEST_TIMEOUT_MS = 600000

///|
const MAX_RESPONSE_BYTES = 8388608

///|
struct ProducerCall {
  request_method : @transport.JsonMethod
  path : String
  body : Json?
}

///|
fn usage() -> String {
  "usage: moon run cmd/mooncast_producer_tool -- <tool-id> [resource ids ...] [JSON body or @body-file]"
}

///|
fn portable_id(value : String) -> Bool {
  if value.is_empty() || value == "." || value == ".." {
    return false
  }
  for char in value {
    match char {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' => ()
      _ => return false
    }
  }
  true
}

///|
fn required_id(
  args : Array[String],
  index : Int,
  label : String,
) -> String raise {
  guard args.length() > index && portable_id(args[index]) else {
    fail("missing or invalid " + label + "; " + usage())
  }
  args[index]
}

///|
async fn bounded_body(value : String) -> Json {
  let text = if value.has_prefix("@") {
    let path = value[1:].to_owned()
    guard !path.is_empty() && @fs.exists(path) && @fs.kind(path) is Regular else {
      fail("JSON body file does not exist or is not a regular file")
    }
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    let size = file.size()
    guard size >= 0L && size <= MAX_BODY_BYTES.to_int64() else {
      fail("JSON body file exceeds the 1 MiB limit")
    }
    @utf8.decode(file.read_exactly_at(size.to_int(), position=0))
  } else {
    guard @utf8.encode(value).length() <= MAX_BODY_BYTES else {
      fail("inline JSON body exceeds the 1 MiB limit")
    }
    value
  }
  @json.parse(text) catch {
    _ => fail("request body must be valid JSON")
  }
}

///|
async fn required_body(args : Array[String], index : Int) -> Json {
  guard args.length() == index + 1 else {
    fail("JSON body required; " + usage())
  }
  bounded_body(args[index])
}

///|
async fn optional_body(args : Array[String], index : Int) -> Json {
  if args.length() == index {
    @json.parse("{}")
  } else {
    required_body(args, index)
  }
}

///|
async fn project_call(tool : String, args : Array[String]) -> ProducerCall {
  let project_id = required_id(args, 2, "project id")
  let root = "/api/v2/projects/" + project_id
  match tool {
    "project.get" => {
      guard args.length() == 3 else { fail(usage()) }
      { request_method: Get, path: root, body: None }
    }
    "project.events" => {
      guard args.length() == 3 else { fail(usage()) }
      { request_method: Get, path: root + "/events", body: None }
    }
    "project.governance" => {
      guard args.length() == 3 else { fail(usage()) }
      { request_method: Get, path: root + "/governance", body: None }
    }
    "project.advance" => {
      let body = required_body(args, 3)
      { request_method: Post, path: root + "/advance", body: Some(body) }
    }
    "routed-execution.list" => {
      guard args.length() == 3 else { fail(usage()) }
      { request_method: Get, path: root + "/routed-executions", body: None }
    }
    "routed-execution.create" => {
      let body = required_body(args, 3)
      {
        request_method: Post,
        path: root + "/routed-executions",
        body: Some(body),
      }
    }
    "production-coordinator.confirm-qc" => {
      let body = required_body(args, 3)
      {
        request_method: Post,
        path: root + "/production-coordinator/qc-batches",
        body: Some(body),
      }
    }
    "editor.production-import" => {
      let body = optional_body(args, 3)
      {
        request_method: Post,
        path: "/api/editor/projects/" + project_id + "/production-import",
        body: Some(body),
      }
    }
    "editor.get" => {
      guard args.length() == 3 else { fail(usage()) }
      {
        request_method: Get,
        path: "/api/editor/projects/" + project_id,
        body: None,
      }
    }
    "editor.export.create" => {
      let body = required_body(args, 3)
      {
        request_method: Post,
        path: "/api/editor/projects/" + project_id + "/exports",
        body: Some(body),
      }
    }
    "delivery-build.list" => {
      guard args.length() == 3 else { fail(usage()) }
      { request_method: Get, path: root + "/delivery-builds", body: None }
    }
    "delivery-build.create" => {
      let body = required_body(args, 3)
      {
        request_method: Post,
        path: root + "/delivery-builds",
        body: Some(body),
      }
    }
    _ => fail("unknown project tool id: " + tool)
  }
}

///|
async fn resource_call(tool : String, args : Array[String]) -> ProducerCall {
  let project_id = required_id(args, 2, "project id")
  let resource_id = required_id(args, 3, "resource id")
  let project_root = "/api/v2/projects/" + project_id
  match tool {
    "routed-execution.get" => {
      guard args.length() == 4 else { fail(usage()) }
      {
        request_method: Get,
        path: project_root + "/routed-executions/" + resource_id,
        body: None,
      }
    }
    "production-coordinator.run-pending" => {
      let body = required_body(args, 4)
      {
        request_method: Post,
        path: project_root +
        "/production-coordinator/routed-executions/" +
        resource_id +
        "/run-pending",
        body: Some(body),
      }
    }
    "editor.export.get" => {
      guard args.length() == 4 else { fail(usage()) }
      {
        request_method: Get,
        path: "/api/editor/projects/" + project_id + "/exports/" + resource_id,
        body: None,
      }
    }
    "editor.export.promote-master" => {
      let body = required_body(args, 4)
      {
        request_method: Post,
        path: "/api/editor/projects/" +
        project_id +
        "/exports/" +
        resource_id +
        "/promote-master",
        body: Some(body),
      }
    }
    "delivery-build.get" => {
      guard args.length() == 4 else { fail(usage()) }
      {
        request_method: Get,
        path: project_root + "/delivery-builds/" + resource_id,
        body: None,
      }
    }
    "delivery-build.build" | "delivery-build.retry" | "delivery-build.accept" => {
      let body = required_body(args, 4)
      let action = match tool {
        "delivery-build.build" => "build"
        "delivery-build.retry" => "retry"
        _ => "acceptance"
      }
      {
        request_method: Post,
        path: project_root + "/delivery-builds/" + resource_id + "/" + action,
        body: Some(body),
      }
    }
    _ => fail("unknown resource tool id: " + tool)
  }
}

///|
async fn resolve_call(args : Array[String]) -> ProducerCall {
  guard args.length() >= 2 else { fail(usage()) }
  let tool = args[1]
  match tool {
    "health" => {
      guard args.length() == 2 else { fail(usage()) }
      { request_method: Get, path: "/health", body: None }
    }
    "project.list" => {
      guard args.length() == 2 else { fail(usage()) }
      { request_method: Get, path: "/api/v2/projects", body: None }
    }
    "project.get"
    | "project.events"
    | "project.governance"
    | "project.advance"
    | "routed-execution.list"
    | "routed-execution.create"
    | "production-coordinator.confirm-qc"
    | "editor.production-import"
    | "editor.get"
    | "editor.export.create"
    | "delivery-build.list"
    | "delivery-build.create" => project_call(tool, args)
    "routed-execution.get"
    | "production-coordinator.run-pending"
    | "editor.export.get"
    | "editor.export.promote-master"
    | "delivery-build.get"
    | "delivery-build.build"
    | "delivery-build.retry"
    | "delivery-build.accept" => resource_call(tool, args)
    _ => fail("unknown tool id: " + tool)
  }
}

///|
async fn main {
  let result : Result[Unit, Error] = try {
    let args = @env.args()
    let base_url = @env.get_env_var("MOONCAST_STUDIO_URL")
      .unwrap_or("http://127.0.0.1:8765")
      .trim()
      .trim_end(chars="/")
      .to_owned()
    let call = resolve_call(args)
    let response = @transport.send_loopback_json({
      request_method: call.request_method,
      url: base_url + call.path,
      headers: {},
      body: call.body,
      timeout_ms: REQUEST_TIMEOUT_MS,
      max_response_bytes: MAX_RESPONSE_BYTES,
    })
    @stdio.stdout.write(response.body.stringify(indent=2) + "\n")
    if response.status < 200 || response.status >= 300 {
      fail("Mooncast Studio returned HTTP " + response.status.to_string())
    }
    Ok(())
  } catch {
    error => Err(error)
  }
  match result {
    Ok(_) => ()
    Err(error) => {
      @stdio.stderr.write("mooncast-producer-tool: \{to_repr(error)}\n")
      @sys.exit(1)
    }
  }
}
