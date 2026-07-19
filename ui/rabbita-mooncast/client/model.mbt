///|
/// The portal has an explicit lifecycle so expired, revoked, completed, and
/// unavailable links cannot be mistaken for an active review session.
enum PortalAvailability {
  Loading
  Active
  Expired
  Revoked
  Closed(String)
  Unavailable
} derive(Eq)

///|
struct AnnotationDraft {
  timecode : String
  author : String
  body : String
}

///|
struct DecisionDraft {
  actor : String
  decision : String
  note : String
  human_confirmed : Bool
}

///|
struct Model {
  /// Browser location is application state. The opaque portal token is
  /// derived from its final path segment and is never maintained separately.
  url : @url.Url?
  projection : ClientProjection?
  availability : PortalAvailability
  busy : Bool
  playhead_seconds : Double
  annotation : AnnotationDraft
  decision : DecisionDraft
  status_message : String
  api_error : @api.ApiErrorBody?
}

///|
enum Msg {
  UrlChanged(@url.Url)
  Reload
  ProjectionLoaded(Result[ClientProjection, Error])
  MediaTimeChanged(Double)
  CaptureTimecode
  AnnotationTimecodeChanged(String)
  AnnotationAuthorChanged(String)
  AnnotationBodyChanged(String)
  SubmitAnnotation
  AnnotationSaved(Result[ClientAnnotation, Error])
  DecisionActorChanged(String)
  DecisionNoteChanged(String)
  SelectDecision(String)
  ToggleDecisionConfirmation
  SubmitDecision
  DecisionSaved(String, Result[ClientDecisionReceipt, Error])
  ClearError
}

///|
fn token_from_url(url : @url.Url?) -> String {
  guard url is Some(value) else { "" }
  let mut token = ""
  let mut previous = ""
  for segment in value.path.split("/") {
    if previous == "client" && !segment.is_empty() {
      token = segment.to_owned()
    }
    previous = segment.to_owned()
  }
  token
}

///|
fn pad_two(value : Int) -> String {
  if value < 10 {
    "0\{value}"
  } else {
    value.to_string()
  }
}

///|
fn pad_three(value : Int) -> String {
  if value < 10 {
    "00\{value}"
  } else if value < 100 {
    "0\{value}"
  } else {
    value.to_string()
  }
}

///|
fn format_timecode(value : Double) -> String {
  let total_milliseconds = (Double::max(0.0, value) * 1000.0).to_int()
  let total_seconds = total_milliseconds / 1000
  let minutes = total_seconds / 60
  let seconds = total_seconds % 60
  let milliseconds = total_milliseconds % 1000
  "\{pad_two(minutes)}:\{pad_two(seconds)}.\{pad_three(milliseconds)}"
}

///|
fn format_seconds_input(value : Double) -> String {
  let milliseconds = (Double::max(0.0, value) * 1000.0).to_int()
  "\{milliseconds / 1000}.\{pad_three(milliseconds % 1000)}"
}

///|
/// Keep server timestamps explicit about their timezone instead of silently
/// applying browser locale rules that vary between client reviewers.
fn format_local_datetime(value : String) -> String {
  let readable = value.replace(old="T", new=" ")
  if readable.has_suffix("Z") {
    "\{readable[:readable.length() - 1].to_owned()} UTC"
  } else {
    readable
  }
}

///|
fn decimal_bytes(value : Int, unit : Int, suffix : String) -> String {
  let whole = value / unit
  let tenths = value % unit * 10 / unit
  "\{whole}.\{tenths} \{suffix}"
}

///|
fn human_bytes(value : Int) -> String {
  let bytes = Int::max(0, value)
  if bytes < 1024 {
    "\{bytes} B"
  } else if bytes < 1024 * 1024 {
    decimal_bytes(bytes, 1024, "KB")
  } else if bytes < 1024 * 1024 * 1024 {
    decimal_bytes(bytes, 1024 * 1024, "MB")
  } else {
    decimal_bytes(bytes, 1024 * 1024 * 1024, "GB")
  }
}

///|
fn review_video_time() -> Double? {
  guard @dom.document().get_element_by_id("client-video").to_option()
    is Some(element) else {
    return None
  }
  element.to_html_video_element().map(video => video.get_current_time())
}

///|
fn initial_model(url : @url.Url?) -> Model {
  let has_token = token_from_url(url) != ""
  {
    url,
    projection: None,
    availability: if has_token {
      Loading
    } else {
      Unavailable
    },
    busy: false,
    playhead_seconds: 0.0,
    annotation: { timecode: "0.000", author: "", body: "" },
    decision: {
      actor: "",
      decision: "accept",
      note: "",
      human_confirmed: false,
    },
    status_message: if has_token {
      "Opening secure client review…"
    } else {
      "This client review URL does not contain a portal token."
    },
    api_error: None,
  }
}

///|
fn api_base(model : Model) -> String {
  "/api/client/\{token_from_url(model.url)}"
}

///|
fn resolve_url(model : Model, path : String) -> String {
  if path.has_prefix("http://") || path.has_prefix("https://") {
    path
  } else {
    let clean = if path.has_prefix("/") { path[1:].to_owned() } else { path }
    "\{api_base(model)}/\{clean}"
  }
}

///|
fn short_digest(value : String) -> String {
  if value.length() <= 20 {
    value
  } else {
    "\{value[:12].to_owned()}…\{value[value.length() - 4:].to_owned()}"
  }
}

///|
fn parse_timecode(value : String) -> Double? {
  let cleaned = value.trim().to_owned()
  guard cleaned != "" else { None }
  Some(@string.parse_double(cleaned)) catch {
    _ => None
  }
}

///|
fn error_body(code : String, message : String) -> @api.ApiErrorBody {
  { code, message }
}

///|
fn availability_from_projection(value : ClientProjection) -> PortalAvailability {
  match value.portal.status {
    Some("expired") => Expired
    Some("revoked") => Revoked
    Some("closed") => Closed("This exact-build review has been closed.")
    _ if value.decisions.any(receipt => receipt.decision != "accept") =>
      Closed(
        "A final change or rejection decision has closed this exact-build review.",
      )
    _ => Active
  }
}

///|
fn unavailable_from_error(message : String) -> PortalAvailability {
  let lower = message.to_lower()
  if lower.contains("expired") {
    Expired
  } else if lower.contains("revoked") {
    Revoked
  } else {
    Unavailable
  }
}

///|
fn active_projection(model : Model) -> ClientProjection? {
  if model.availability == Active {
    model.projection
  } else {
    None
  }
}
