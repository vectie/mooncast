///|
pub(all) enum JsonMethod {
  Get
  Post
  Put
  Patch
  Delete
} derive(Debug, Eq)

///|
pub(all) struct JsonRequest {
  request_method : JsonMethod
  url : String
  headers : Map[String, String]
  body : Json?
  timeout_ms : Int
  max_response_bytes : Int
} derive(Debug)

///|
pub(all) struct JsonResponse {
  status : Int
  headers : Map[String, String]
  body : Json
} derive(Debug)

///|
pub suberror TransportError {
  HttpsRequired
  InvalidUrl
  InvalidLimit
  ResponseTooLarge(Int)
  InvalidJsonResponse
} derive(Debug)

///|
fn split_https_url(url : String) -> (String, String) raise TransportError {
  guard url.has_prefix("https://") else { raise HttpsRequired }
  guard !url.contains("\r") && !url.contains("\n") && !url.contains("#") else {
    raise InvalidUrl
  }
  let rest = url[8:].to_owned()
  guard !rest.is_empty() else { raise InvalidUrl }
  match rest.find("/") {
    None => {
      guard !rest.contains("?") && !rest.contains("@") else { raise InvalidUrl }
      ("https://" + rest, "/")
    }
    Some(index) => {
      let authority = rest[:index].to_owned()
      let path = rest[index:].to_owned()
      guard !authority.is_empty() && !authority.contains("@") else {
        raise InvalidUrl
      }
      ("https://" + authority, path)
    }
  }
}

///|
fn decimal_port(value : StringView) -> Bool {
  if value.is_empty() {
    return false
  }
  for char in value {
    match char {
      '0'..='9' => ()
      _ => return false
    }
  }
  true
}

///|
fn loopback_authority(authority : String) -> Bool {
  if authority == "localhost" ||
    authority == "127.0.0.1" ||
    authority == "[::1]" {
    return true
  }
  for prefix in ["localhost:", "127.0.0.1:", "[::1]:"] {
    if authority.has_prefix(prefix) {
      return decimal_port(authority[prefix.length():])
    }
  }
  false
}

///|
fn split_loopback_http_url(
  url : String,
) -> (String, String) raise TransportError {
  guard url.has_prefix("http://") else { raise InvalidUrl }
  guard !url.contains("\r") && !url.contains("\n") && !url.contains("#") else {
    raise InvalidUrl
  }
  let rest = url[7:].to_owned()
  guard !rest.is_empty() else { raise InvalidUrl }
  let (authority, path) = match rest.find("/") {
    None => (rest, "/")
    Some(index) => (rest[:index].to_owned(), rest[index:].to_owned())
  }
  guard loopback_authority(authority) && !path.has_prefix("//") else {
    raise InvalidUrl
  }
  ("http://" + authority, path)
}

///|
fn valid_headers(headers : Map[String, String]) -> Bool {
  for name, value in headers {
    if name.is_empty() ||
      name.contains("\r") ||
      name.contains("\n") ||
      value.contains("\r") ||
      value.contains("\n") {
      return false
    }
  }
  true
}

///|
async fn read_bounded(reader : @http.Client, limit : Int) -> Bytes {
  let output : Array[Byte] = []
  for ;; {
    let remaining = limit - output.length()
    guard remaining > 0 else {
      if reader.read_some(max_len=1) is Some(_) {
        raise ResponseTooLarge(limit)
      }
      break
    }
    match
      reader.read_some(
        max_len=if remaining < 65536 { remaining } else { 65536 },
      ) {
      None => break
      Some(chunk) =>
        for byte in chunk {
          output.push(byte)
        }
    }
  }
  Bytes::from_array(output)
}

///|
/// Perform a certificate-verified HTTPS JSON request. Credentials are supplied
/// only through caller-owned headers; this package contains no secret values.
pub async fn send_json(request : JsonRequest) -> JsonResponse {
  guard request.timeout_ms > 0 && request.max_response_bytes > 0 else {
    raise InvalidLimit
  }
  guard valid_headers(request.headers) else { raise InvalidUrl }
  @async.with_timeout(request.timeout_ms, () => {
    let (origin, path) = split_https_url(request.url)
    let client = @http.Client(origin)
    defer client.close()
    let headers = request.headers
    headers["Accept"] = "application/json"
    if request.body is Some(_) {
      headers["Content-Type"] = "application/json"
    }
    client.request(
      match request.request_method {
        Get => @http.Get
        Post => @http.Post
        Put => @http.Put
        Patch => @http.Patch
        Delete => @http.Delete
      },
      path,
      extra_headers=headers,
    )
    match request.body {
      None => ()
      Some(body) => client.write(body.stringify())
    }
    let response = client.end_request()
    let bytes = read_bounded(client, request.max_response_bytes)
    let json = @json.parse(@utf8.decode(bytes)) catch {
      _ => raise InvalidJsonResponse
    }
    { status: response.code, headers: response.headers, body: json }
  })
}

///|
/// Perform a bounded JSON request to the local MoonSuite host. This is a
/// separate port from provider HTTPS: it accepts only literal loopback or
/// localhost HTTP authorities and never permits credentials or remote hosts.
pub async fn send_loopback_json(request : JsonRequest) -> JsonResponse {
  guard request.timeout_ms > 0 && request.max_response_bytes > 0 else {
    raise InvalidLimit
  }
  guard valid_headers(request.headers) else { raise InvalidUrl }
  @async.with_timeout(request.timeout_ms, () => {
    let (origin, path) = split_loopback_http_url(request.url)
    let client = @http.Client(origin)
    defer client.close()
    let headers = request.headers
    headers["Accept"] = "application/json"
    if request.body is Some(_) {
      headers["Content-Type"] = "application/json"
    }
    client.request(
      match request.request_method {
        Get => @http.Get
        Post => @http.Post
        Put => @http.Put
        Patch => @http.Patch
        Delete => @http.Delete
      },
      path,
      extra_headers=headers,
    )
    match request.body {
      None => ()
      Some(body) => client.write(body.stringify())
    }
    let response = client.end_request()
    let bytes = read_bounded(client, request.max_response_bytes)
    let json = @json.parse(@utf8.decode(bytes)) catch {
      _ => raise InvalidJsonResponse
    }
    { status: response.code, headers: response.headers, body: json }
  })
}
