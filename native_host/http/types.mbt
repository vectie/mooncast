///|
/// Domain-neutral methods understood by the native host router.
pub(all) enum Method {
  Get
  Head
  Post
  Put
  Delete
  Patch
  Options
  Other(String)
} derive(Debug, Eq)

///|
/// An owned, bounded request passed to pack-local domain handlers.
pub(all) struct Request {
  request_method : Method
  path : String
  query : String?
  headers : Map[String, String]
  body : Bytes
} derive(Debug)

///|
/// A complete response. The adapter adds Content-Length when it is sent.
pub(all) struct Response {
  status : Int
  reason : String
  headers : Map[String, String]
  body : Bytes
} derive(Debug)

///|
pub fn response(
  status : Int,
  reason : String,
  body : Bytes,
  content_type? : String = "application/octet-stream",
  headers? : Map[String, String] = {},
) -> Response {
  headers["Content-Type"] = content_type
  { status, reason, headers, body }
}

///|
pub fn text_response(
  status : Int,
  reason : String,
  body : String,
  content_type? : String = "text/plain; charset=utf-8",
) -> Response {
  response(status, reason, @utf8.encode(body), content_type~)
}

///|
pub fn json_response(status : Int, reason : String, body : String) -> Response {
  response(
    status,
    reason,
    @utf8.encode(body),
    content_type="application/json; charset=utf-8",
  )
}

///|
pub fn not_found() -> Response {
  json_response(404, "Not Found", "{\"error\":\"not_found\"}")
}

///|
pub fn payload_too_large() -> Response {
  json_response(413, "Payload Too Large", "{\"error\":\"payload_too_large\"}")
}
