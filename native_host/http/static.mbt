///|
pub(all) struct ByteRange {
  start : Int
  end_inclusive : Int
} derive(Debug, Eq)

///|
/// Split a request target once; fragments are never part of an HTTP target.
pub fn split_target(target : String) -> (String, String?) {
  match target.find("?") {
    None => (target, None)
    Some(index) =>
      (target[:index].to_owned(), Some(target[index + 1:].to_owned()))
  }
}

///|
/// Convert a URL path to a path relative to a configured static root.
/// Percent-encoded paths are rejected because decoding must precede policy.
pub fn safe_static_path(path : String) -> String? {
  guard path.has_prefix("/") && !path.contains("%") else { return None }
  let pieces = path.split("/").to_array()
  let clean : Array[String] = []
  for piece in pieces {
    let value = piece.to_owned()
    match value {
      "" | "." => ()
      ".." => return None
      part if part.contains("\\") || part.contains("\u0000") => return None
      part => clean.push(part)
    }
  }
  if clean.is_empty() {
    Some("index.html")
  } else {
    Some(clean.join("/"))
  }
}

///|
pub fn content_type(path : String) -> String {
  let normalized = path.to_lower()
  if normalized.has_suffix(".html") {
    "text/html; charset=utf-8"
  } else if normalized.has_suffix(".css") {
    "text/css; charset=utf-8"
  } else if normalized.has_suffix(".js") || normalized.has_suffix(".mjs") {
    "text/javascript; charset=utf-8"
  } else if normalized.has_suffix(".json") || normalized.has_suffix(".map") {
    "application/json; charset=utf-8"
  } else if normalized.has_suffix(".wasm") {
    "application/wasm"
  } else if normalized.has_suffix(".svg") {
    "image/svg+xml"
  } else if normalized.has_suffix(".png") {
    "image/png"
  } else if normalized.has_suffix(".jpg") || normalized.has_suffix(".jpeg") {
    "image/jpeg"
  } else if normalized.has_suffix(".webp") {
    "image/webp"
  } else if normalized.has_suffix(".mp4") {
    "video/mp4"
  } else if normalized.has_suffix(".webm") {
    "video/webm"
  } else if normalized.has_suffix(".wav") {
    "audio/wav"
  } else if normalized.has_suffix(".mp3") {
    "audio/mpeg"
  } else if normalized.has_suffix(".woff") {
    "font/woff"
  } else if normalized.has_suffix(".woff2") {
    "font/woff2"
  } else if normalized.has_suffix(".vtt") {
    "text/vtt; charset=utf-8"
  } else {
    "application/octet-stream"
  }
}

///|
pub fn etag(bytes : Bytes) -> String {
  let digest = @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
  "\"sha256-" + digest + "\""
}

///|
pub fn parse_range(value : String, size : Int) -> ByteRange? {
  guard size > 0 && value.has_prefix("bytes=") else { return None }
  let spec = value[6:].to_owned()
  guard !spec.contains(",") else { return None }
  let halves = spec.split("-").to_array()
  guard halves.length() == 2 else { return None }
  let left = halves[0].trim().to_owned()
  let right = halves[1].trim().to_owned()
  if left is "" {
    let suffix = @string.parse_int(right) catch { _ => return None }
    guard suffix > 0 else { return None }
    let start = if suffix >= size { 0 } else { size - suffix }
    return Some({ start, end_inclusive: size - 1 })
  }
  let start = @string.parse_int(left) catch { _ => return None }
  guard start >= 0 && start < size else { return None }
  let end_inclusive = if right is "" {
    size - 1
  } else {
    @string.parse_int(right) catch {
      _ => return None
    }
  }
  guard end_inclusive >= start else { return None }
  let bounded_end = if end_inclusive < size { end_inclusive } else { size - 1 }
  Some({ start, end_inclusive: bounded_end })
}

///|
pub fn static_response(
  path : String,
  bytes : Bytes,
  range? : String,
  if_none_match? : String,
) -> Response {
  let tag = etag(bytes)
  let headers = {
    "ETag": tag,
    "Accept-Ranges": "bytes",
    "Cross-Origin-Resource-Policy": "same-origin",
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-cache",
  }
  if if_none_match is Some(value) && value == tag {
    return response(
      304,
      "Not Modified",
      b"",
      content_type=content_type(path),
      headers~,
    )
  }
  match range {
    Some(value) =>
      match parse_range(value, bytes.length()) {
        None => {
          headers["Content-Range"] = "bytes */" + bytes.length().to_string()
          response(
            416,
            "Range Not Satisfiable",
            b"",
            content_type=content_type(path),
            headers~,
          )
        }
        Some(span) => {
          headers["Content-Range"] = "bytes " +
            span.start.to_string() +
            "-" +
            span.end_inclusive.to_string() +
            "/" +
            bytes.length().to_string()
          let body = bytes[span.start:span.end_inclusive + 1].to_owned()
          response(
            206,
            "Partial Content",
            body,
            content_type=content_type(path),
            headers~,
          )
        }
      }
    None =>
      response(200, "OK", bytes, content_type=content_type(path), headers~)
  }
}
