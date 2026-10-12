///|
fn attribution_category_label(category : String) -> String {
  match category {
    "provider_cny" => "Provider cost (CNY)"
    "labor_cny" => "Labor cost (CNY)"
    "other_cny" => "Other cost (CNY)"
    "founder_hours" => "Founder hours"
    _ => "Unknown category"
  }
}

///|
fn attribution_status_label(status : String) -> String {
  match status {
    "comparable" => "Comparable current evidence"
    "held-project-total-unknown" => "Held: project total unknown"
    "held-over-attributed" => "Held: attributed amount exceeds project total"
    "held-cross-project-evidence" =>
      "Held: project evidence belongs to another project"
    _ => "Held: project or actuals evidence basis changed"
  }
}

///|
fn attribution_field(
  name : String,
  label : String,
  value : String,
  hidden? : Bool = false,
) -> String {
  let escape = workspace_html_escape
  "<label" +
  (if hidden { " hidden" } else { "" }) +
  ">" +
  escape(label) +
  " <input type=\"" +
  (if hidden { "hidden" } else { "text" }) +
  "\" name=\"" +
  escape(name) +
  "\" value=\"" +
  escape(value) +
  "\"" +
  (if hidden { "" } else { " required" }) +
  "></label> "
}

///|
async fn StudioService::episode_attribution_section(
  self : StudioService,
  project_id : String,
  episode_id : String,
  correction : String,
) -> String {
  let view = self.episode_attribution_view(project_id, episode_id)
  let effective = ledger_list(view, "effective_records")
  let selected = effective
    .iter()
    .find_first(record => ledger_text(record, "record_id") == correction)
  guard correction == "" || selected is Some(_) else {
    raise Conflict(
      code="episode_attribution_correction_stale",
      message="This record is no longer effective. Reload the episode ledger and choose its current correction.",
    )
  }
  let input = selected
    .map(record => json_member(record, "input").unwrap_or(Json::null()))
    .unwrap_or(Json::null())
  let escape = workspace_html_escape
  let base = "/api/v2/projects/" +
    project_id +
    "/episodes/" +
    episode_id +
    "/ledger"
  let rows = ledger_list(view, "reconciliation")
    .map(row => {
      "<li><strong>" +
      escape(attribution_category_label(ledger_text(row, "category"))) +
      "</strong><p>This episode: " +
      escape(ledger_text(row, "episode_recorded_value")) +
      " · Project total: " +
      escape(ledger_text(row, "project_total")) +
      " · Recorded attribution across episodes: " +
      escape(ledger_text(row, "recorded_attributed_total")) +
      " · Unallocated remainder: " +
      escape(ledger_text(row, "unallocated_remainder")) +
      "</p><p>" +
      escape(attribution_status_label(ledger_text(row, "status"))) +
      "</p></li>"
    })
    .join("")
  let history = ledger_list(view, "history")
    .map(record => {
      let id = ledger_text(record, "record_id")
      let current = effective.any(item => ledger_text(item, "record_id") == id)
      "<li><strong>" +
      (if current { "Effective attribution" } else { "Superseded history" }) +
      "</strong>" +
      ledger_detail("Exact record, author and source evidence", record) +
      (if current {
        "<a href=\"" +
        escape(base + "/view?correct=" + id) +
        "#episode-attribution\">Correct this exact record</a>"
      } else {
        ""
      }) +
      "</li>"
    })
    .join("")
  let category = ledger_text(input, "category", fallback="labor_cny")
  let options = ["provider_cny", "labor_cny", "other_cny", "founder_hours"]
    .map(value => {
      "<option value=\"" +
      value +
      "\"" +
      (if value == category { " selected" } else { "" }) +
      ">" +
      attribution_category_label(value) +
      "</option>"
    })
    .join("")
  "<section id=\"episode-attribution\"><h2>Episode actual-cost attribution</h2><p>Explicit user-authored actual evidence only. Named authors are not verified identities. Project totals, forecasts, revenue, billing and media remain separate. No equal split, inferred margin, payment or provider action.</p><p>Unknown totals and stale or mixed evidence are held for reconciliation. A held category has no comparable remainder. Review project actuals, then explicitly correct affected attribution records against the current basis. Each evidence reference must identify a distinct cost or time line item.</p><ul>" +
  rows +
  "</ul><h3>" +
  (if correction == "" {
    "Record an actual attribution"
  } else {
    "Correct the exact selected record"
  }) +
  "</h3>" +
  selected
  .map(record => {
    ledger_detail("Record being superseded (retained permanently)", record)
  })
  .unwrap_or("") +
  "<form method=\"post\" action=\"" +
  escape(base + "/attributions/form") +
  "\">" +
  attribution_field(
    "expected_project_revision",
    "Project revision",
    ledger_text(view, "project_revision"),
    hidden=true,
  ) +
  attribution_field(
    "expected_ledger_revision",
    "Ledger revision",
    ledger_text(view, "ledger_revision"),
    hidden=true,
  ) +
  attribution_field(
    "expected_actuals_digest",
    "Actuals digest",
    ledger_text(view, "actuals_digest", fallback=""),
    hidden=true,
  ) +
  attribution_field("supersedes_id", "Supersedes", correction, hidden=true) +
  attribution_field(
    "supersedes_digest",
    "Predecessor digest",
    selected.map(record => ledger_text(record, "digest")).unwrap_or(""),
    hidden=true,
  ) +
  attribution_field(
    "command_id",
    "Command ID (retain unchanged for exact retry)",
    "episode-" +
    sha256_text(
      now_string() +
      project_id +
      episode_id +
      ledger_text(view, "ledger_revision"),
    ),
  ) +
  (if correction == "" {
    "<label>Category <select name=\"category\">" + options + "</select></label>"
  } else {
    "<p>Correction category: " +
    escape(attribution_category_label(category)) +
    "</p>" +
    attribution_field("category", "Category", category, hidden=true)
  }) +
  attribution_field(
    "value",
    "Actual amount CNY or founder hours (zero is explicit)",
    ledger_text(input, "value", fallback=""),
  ) +
  attribution_field(
    "evidence_ref",
    "Distinct evidence reference",
    ledger_text(input, "evidence_ref", fallback=""),
  ) +
  attribution_field("author", "Named author", "") +
  attribution_field("note", "Evidence explanation / correction reason", "") +
  "<p><label><input type=\"checkbox\" name=\"human_confirmed\" value=\"true\" required> I reviewed this episode, amount, evidence and any exact correction above.</label></p><button type=\"submit\">" +
  (if correction == "" {
    "Record actual attribution"
  } else {
    "Record superseding correction"
  }) +
  "</button> <a href=\"" +
  escape(base + "/view#episode-attribution") +
  "\">Cancel / reload current evidence</a></form><h3>Effective records and immutable correction history</h3><ul>" +
  (if history == "" {
    "<li>No episode actual attribution recorded. Unknown is not zero.</li>"
  } else {
    history
  }) +
  "</ul></section>"
}

///|
fn attribution_form_decode(value : String) -> String raise {
  let bytes = @utf8.encode(value)
  let output : Array[Byte] = []
  for index = 0; index < bytes.length(); {
    if bytes[index] == b'+' {
      output.push(b' ')
      continue index + 1
    }
    if bytes[index] == b'%' {
      guard index + 2 < bytes.length() else { fail("Incomplete form escape") }
      let hex = @utf8.decode(bytes[index + 1:index + 3])
      for char in hex {
        guard char is ('0'..='9' | 'a'..='f' | 'A'..='F') else {
          fail("Invalid form escape")
        }
      }
      let number = @string.parse_int(hex, base=16)
      output.push(number.to_byte())
      continue index + 3
    }
    output.push(bytes[index])
    continue index + 1
  }
  @utf8.decode(Bytes::from_array(output))
}

///|
fn attribution_form_input(body : Bytes) -> EpisodeAttributionInput raise {
  guard body.length() <= 16384 else { fail("Attribution form too large") }
  let fields : Map[String, String] = Map([])
  for pair in @utf8.decode(body).split("&") {
    let parts = pair.split("=").to_array()
    guard parts.length() == 2 else { fail("Malformed attribution form") }
    let key = attribution_form_decode(parts[0].to_owned())
    guard !fields.contains(key) else { fail("Duplicate attribution field") }
    fields[key] = attribution_form_decode(parts[1].to_owned())
  }
  fn field(key : String) -> String {
    fields.get(key).unwrap_or("")
  }
  fn optional(key : String) -> String? {
    let value = field(key)
    if value == "" {
      None
    } else {
      Some(value)
    }
  }
  {
    command_id: field("command_id"),
    expected_project_revision: @string.parse_int(
      field("expected_project_revision"),
    ),
    expected_ledger_revision: @string.parse_int(
      field("expected_ledger_revision"),
    ),
    expected_actuals_digest: optional("expected_actuals_digest"),
    category: field("category"),
    value: @string.parse_double(field("value")),
    evidence_ref: field("evidence_ref"),
    author: field("author"),
    note: field("note"),
    supersedes_id: optional("supersedes_id"),
    supersedes_digest: optional("supersedes_digest"),
    human_confirmed: field("human_confirmed") == "true",
  }
}

///|
async fn StudioService::submit_episode_attribution_form(
  self : StudioService,
  project_id : String,
  episode_id : String,
  request : @host_http.Request,
) -> @host_http.Response {
  let base = "/api/v2/projects/" +
    project_id +
    "/episodes/" +
    episode_id +
    "/ledger/view#episode-attribution"
  try {
    let input = attribution_form_input(request.body) catch {
      _ =>
        raise Invalid(
          code="episode_attribution_form_invalid",
          message="Enter complete valid fields; no attribution was recorded.",
        )
    }
    ignore(self.record_episode_attribution(project_id, episode_id, input))
  } catch {
    error => {
      let (status, message) = match error {
        Conflict(message~, ..) => (409, message)
        Invalid(message~, ..) => (422, message)
        NotFound(..) => (404, "Project or episode is unavailable.")
        _ =>
          (
            500, "Persistence was not confirmed. Reload history before retrying the same command ID.",
          )
      }
      return @host_http.response(
        status,
        "Attribution not confirmed",
        @utf8.encode(
          "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Attribution needs review</title><h1>Attribution not confirmed</h1><p>" +
          workspace_html_escape(message) +
          "</p><p>Use Back to recover entered fields. For a revision conflict, reload and review the current records before making a new command.</p><a href=\"" +
          workspace_html_escape(base) +
          "\">Reload episode history</a></html>",
        ),
        content_type="text/html; charset=utf-8",
        headers={ "Cache-Control": "no-store" },
      )
    }
  }
  @host_http.response(303, "See Other", b"", headers={
    "Location": base,
    "Cache-Control": "no-store",
  })
}
