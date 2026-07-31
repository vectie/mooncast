///|
let max_request_body : Int = 1048576

///|
let max_editor_media_body : Int = 67108864

///|
let max_static_asset : Int = 536870912

///|
fn request_method(http_method : @async_http.RequestMethod) -> @host_http.Method {
  match http_method {
    @async_http.Get => @host_http.Get
    @async_http.Head => @host_http.Head
    @async_http.Post => @host_http.Post
    @async_http.Put => @host_http.Put
    @async_http.Delete => @host_http.Delete
    @async_http.Patch => @host_http.Patch
    @async_http.Options => @host_http.Options
    @async_http.Connect => @host_http.Other("CONNECT")
    @async_http.Trace => @host_http.Other("TRACE")
  }
}

///|
fn header(headers : Map[String, String], name : String) -> String? {
  headers.get(name.to_lower())
}

///|
fn direct_mount_path(path : String) -> String {
  let prefix = "/apps/mooncast"
  if path.has_prefix(prefix + "/") {
    path[prefix.length():].to_owned()
  } else {
    path
  }
}

///|
async fn read_bounded_body(reader : &@io.Reader, limit : Int) -> Bytes? {
  let output : Array[Byte] = []
  for ;; {
    let remaining = limit - output.length()
    guard remaining >= 0 else { return None }
    match
      reader.read_some(
        max_len=if remaining < 65536 { remaining + 1 } else { 65536 },
      ) {
      None => break
      Some(chunk) => {
        guard chunk.length() <= remaining else { return None }
        for byte in chunk {
          output.push(byte)
        }
      }
    }
  }
  Some(Bytes::from_array(output))
}

///|
async fn send_response(
  conn : @async_http.ServerConnection,
  response : @host_http.Response,
  head_only : Bool,
) -> Unit noraise {
  let headers = response.headers
  headers["Cross-Origin-Resource-Policy"] = match
    headers.get("Cross-Origin-Resource-Policy") {
    Some(value) => value
    None => "same-origin"
  }
  headers["X-Content-Type-Options"] = "nosniff"
  try {
    conn.send_response(response.status, response.reason, extra_headers=headers)
    if !head_only && !response.body.is_empty() {
      conn.write(response.body)
    }
    conn.end_response()
  } catch {
    _ => println("native host client disconnected while sending response")
  } noraise {
    _ => ()
  }
}

///|
async fn serve_static(
  raw_path : String,
  headers : Map[String, String],
  release_root : String,
  rabbita_root : String,
  conn : @async_http.ServerConnection,
  head_only : Bool,
) -> Unit {
  let mounted_path = if raw_path.has_prefix("/apps/mooncast/") {
    raw_path["/apps/mooncast".length():].to_owned()
  } else {
    raw_path
  }
  let requested = match @host_http.safe_static_path(mounted_path) {
    Some(value) => value
    None => {
      send_response(conn, @host_http.not_found(), head_only)
      return
    }
  }
  let direct_root = if requested.has_prefix("target/") {
    rabbita_root
  } else {
    release_root
  }
  let direct_candidate = direct_root + "/" + requested
  let mut selected : (String, String)? = None
  if mounted_path != "/" &&
    @fs.exists(direct_candidate) &&
    @fs.kind(direct_candidate) is Regular {
    selected = Some((direct_root, requested))
  } else if !requested.contains(".") {
    let entry_candidates : Array[String] = if mounted_path == "/client" ||
      mounted_path.has_prefix("/client/") {
      ["client/index.html", "client.html", "index.html"]
    } else if mounted_path == "/editor" || mounted_path.has_prefix("/editor/") {
      ["editor/index.html", "editor.html", "index.html"]
    } else {
      ["studio/index.html", "studio.html", "index.html"]
    }
    for entry in entry_candidates {
      if selected is None &&
        @fs.exists(release_root + "/" + entry) &&
        @fs.kind(release_root + "/" + entry) is Regular {
        selected = Some((release_root, entry))
      }
    }
  }
  guard selected is Some((root, relative)) else {
    send_response(conn, @host_http.not_found(), head_only)
    return
  }
  let candidate = root + "/" + relative
  let resolved = @fs.realpath(candidate)
  guard resolved.has_prefix(root + "/") && @fs.kind(resolved) is Regular else {
    send_response(conn, @host_http.not_found(), head_only)
    return
  }
  let file = @fs.open(resolved, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size <= max_static_asset.to_int64() else {
    send_response(
      conn,
      @host_http.json_response(
        413, "Payload Too Large", "{\"error\":\"static_asset_too_large\"}",
      ),
      head_only,
    )
    return
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0)
  let range = header(headers, "range")
  let if_none_match = header(headers, "if-none-match")
  let response = @host_http.static_response(
    relative,
    bytes,
    range?,
    if_none_match?,
  )
  send_response(conn, response, head_only)
}

///|
fn build_router() -> @host_http.Router {
  let router = @host_http.Router::new()
  router.add(@host_http.Get, "/health", _ => {
    @host_http.json_response(
      200, "OK", "{\"status\":\"ok\",\"runtime\":\"moonbit-native\"}",
    )
  })
  router.add(@host_http.Get, "/api/runtime", _ => {
    @host_http.json_response(200, "OK", @runtime.runtime_json())
  })
  router
}

///|
fn provider_catalog() -> @execution_app.ProviderCatalog {
  let empty : @execution_app.ProviderCatalog = {
    contract: "mooncast.provider-catalog.v1",
    adapters: [],
    authority_actors: ["studio-operator"],
  }
  match @env.get_env_var("MOONCAST_PROVIDER_CATALOG_JSON") {
    None => empty
    Some(raw) => @json.from_json(@json.parse(raw)) catch { _ => empty }
  }
}

///|
async fn handle_request(
  request : @async_http.Request,
  body_reader : &@io.Reader,
  conn : @async_http.ServerConnection,
  router : @host_http.Router,
  service : @studio_service.StudioService,
  release_root : String,
  rabbita_root : String,
) -> Unit {
  let (raw_path, query) = @host_http.split_target(request.path)
  let path = direct_mount_path(raw_path)
  let http_method = request_method(request.meth)
  let head_only = http_method is @host_http.Head
  if http_method is (@host_http.Get | @host_http.Head) &&
    !path.has_prefix("/api/") &&
    !path.has_prefix("/media/") &&
    path != "/health" {
    serve_static(
      raw_path,
      request.headers,
      release_root,
      rabbita_root,
      conn,
      head_only,
    )
    return
  }
  let body_limit = if (
      path.has_prefix("/api/editor/projects/") &&
      path.contains("/media-intakes/") &&
      path.has_suffix("/content")
    ) ||
    (
      path.has_prefix("/api/editor/utility-concats/") &&
      path.contains("/inputs/")
    ) {
    max_editor_media_body
  } else {
    max_request_body
  }
  let body = match read_bounded_body(body_reader, body_limit) {
    None => {
      send_response(conn, @host_http.payload_too_large(), head_only)
      return
    }
    Some(bytes) => bytes
  }
  let typed : @host_http.Request = {
    request_method: http_method,
    path,
    query,
    headers: request.headers,
    body,
  }
  let response = if path == "/health" || path == "/api/runtime" {
    router.dispatch(typed)
  } else {
    service.dispatch_http(typed)
  }
  send_response(conn, response, head_only)
}

///|
fn main {
  @async.run_async_main(async fn() {
    guard @runtime.is_supported_platform() else {
      println(
        "Mooncast Studio native host is unsupported on " +
        @runtime.platform_name,
      )
      return
    }
    let host = @env.get_env_var("MOONCAST_HOST").unwrap_or("127.0.0.1")
    let port = match @env.get_env_var("MOONCAST_PORT") {
      None => 8765
      Some(value) => @string.parse_int(value) catch { _ => 8765 }
    }
    let configured_rabbita_root = @env.get_env_var("MOONCAST_RABBITA_ROOT").unwrap_or(
      "ui/rabbita-mooncast",
    )
    let configured_release_root = @env.get_env_var("MOONCAST_RABBITA_DIST").unwrap_or(
      configured_rabbita_root + "/dist",
    )
    guard @fs.exists(configured_rabbita_root) &&
      @fs.exists(configured_release_root) else {
      println(
        "Mooncast Rabbita release assets are missing; build ui/rabbita-mooncast before starting the native host",
      )
      return
    }
    let rabbita_root = @fs.realpath(configured_rabbita_root)
    let release_root = @fs.realpath(configured_release_root)
    let data_root = match @env.get_env_var("MOONCAST_DATA_ROOT") {
      Some(root) => root
      None =>
        match @env.get_env_var("LEPUSA_APP_DATA_DIR") {
          Some(app_data) => app_data + "/mooncast"
          None => "var/native"
        }
    }
    let server = @async_http.Server::new(
      @socket.Addr::parse(host + ":" + port.to_string()),
      reuse_addr=true,
    )
    let router = build_router()
    let service = @studio_service.StudioService::new(
      data_root,
      provider_catalog=provider_catalog(),
    )
    println(
      "Mooncast Studio (MoonBit native) listening on http://" +
      host +
      ":" +
      port.to_string(),
    )
    println("Rabbita release root: " + release_root)
    server.run_forever((request, body, conn) => {
      handle_request(
        request, body, conn, router, service, release_root, rabbita_root,
      ) catch {
        error => {
          // Transport failures are consumed by send_response, so reaching this
          // branch means application handling failed before a response began.
          let response = @host_http.json_response(
            500, "Internal Server Error", "{\"error\":\"native_host_failure\"}",
          )
          send_response(conn, response, false)
          let _ = error
          println("native host request failed")
        }
      }
    })
  })
}
