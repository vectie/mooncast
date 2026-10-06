///|
fn ledger_text(
  value : Json,
  key : String,
  fallback? : String = "Unknown",
) -> String {
  match json_member(value, key) {
    Some(String(text)) => text
    Some(Number(number, ..)) => number.to_string()
    Some(True) => "Recorded"
    Some(False) => "Not recorded"
    _ => fallback
  }
}

///|
fn ledger_list(value : Json, key : String) -> Array[Json] {
  match json_member(value, key) {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn ledger_detail(label : String, value : Json) -> String {
  "<details><summary>" +
  workspace_html_escape(label) +
  "</summary><pre>" +
  workspace_html_escape(value.stringify(indent=2)) +
  "</pre></details>"
}

///|
/// An internal producer view. It is deliberately not a public client portal,
/// and contains no access token or link that bypasses the existing portal.
pub async fn StudioService::episode_ledger_page(
  self : StudioService,
  project_id : String,
  episode_id : String,
) -> @host_http.Response {
  let ledger = self.episode_ledger(project_id, episode_id)
  let escape = workspace_html_escape
  let media = match json_member(ledger, "master_url") {
    Some(String(url)) =>
      "<p><a href=\"" +
      escape(url) +
      "\">Open verified master</a></p><video controls preload=\"metadata\" aria-label=\"Exact promoted episode master\" src=\"" +
      escape(url) +
      "\"></video>"
    _ =>
      "<p>No currently verified master is available for this episode. Historical master evidence is retained below.</p>"
  }
  let blockers = ledger_list(ledger, "blockers")
    .map(item => {
      "<li>" +
      escape(
        match item {
          String(text) => text
          _ => item.stringify()
        },
      ) +
      "</li>"
    })
    .join("")
  let gates = ledger_list(ledger, "gates")
    .map(gate => {
      "<li><strong>" +
      escape(ledger_text(gate, "gate")) +
      "</strong><span>" +
      (if json_member(gate, "current_ready") == Some(true.to_json()) {
        "Current evidence ready"
      } else {
        "Evidence needs attention"
      }) +
      " · " +
      ledger_list(gate, "receipts").length().to_string() +
      " recorded receipts</span>" +
      ledger_detail("Reasons and retained receipts", gate) +
      "</li>"
    })
    .join("")
  let shots = ledger_list(ledger, "shots")
    .map(shot => {
      let identity = json_member(shot, "shot").unwrap_or(Json::null())
      "<li><strong>" +
      escape(ledger_text(identity, "shot_id")) +
      "</strong><span>" +
      (if json_member(shot, "latest_attempt_qc_passed") == Some(true.to_json()) {
        "Latest attempt QC recorded"
      } else {
        "Latest attempt needs output or QC"
      }) +
      "</span>" +
      ledger_detail("Source assets, attempts and reviews", shot) +
      "</li>"
    })
    .join("")
  let builds = ledger_list(ledger, "delivery_builds")
    .map(item => {
      let build = json_member(item, "build").unwrap_or(Json::null())
      let download = match json_member(item, "download_url") {
        Some(String(url)) =>
          "<p><a href=\"" +
          escape(url) +
          "\">Download verified accepted package</a></p>"
        _ =>
          "<p>Download unavailable. The exact build must have its own acceptance and intact archive.</p>"
      }
      "<li><strong>" +
      escape(ledger_text(build, "build_id")) +
      "</strong><span>" +
      escape(ledger_text(build, "state")) +
      " · " +
      (if json_member(item, "current_for_episode") == Some(true.to_json()) {
        "Bound to this current episode"
      } else {
        "Historical or unverified for this episode"
      }) +
      "</span>" +
      download +
      ledger_detail("Package manifest and binding", item) +
      "</li>"
    })
    .join("")
  let costs = [
      ("Provider cost (CNY)", "actual_provider_cost_cny"),
      ("Labor cost (CNY)", "actual_labor_cost_cny"),
      ("Other cost (CNY)", "actual_other_cost_cny"),
      ("Founder hours", "actual_founder_hours"),
    ]
    .map(pair => {
      "<div><dt>" +
      escape(pair.0) +
      "</dt><dd>" +
      escape(ledger_text(ledger, pair.1)) +
      "</dd></div>"
    })
    .join("")
  let quote = json_member(ledger, "quote_evidence").unwrap_or(Json::null())
  let html = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Episode ledger · MoonCast</title><style>body{background:#101619;color:#e7f1ef;font:16px system-ui;line-height:1.5;margin:0}main{max-width:1100px;margin:auto;padding:32px 24px}a{color:#a2e9cd}a:focus-visible,summary:focus-visible{outline:3px solid #ffce70;outline-offset:5px}header,section{padding:24px 0;border-bottom:1px solid #425256}h1{font-size:2.5rem;margin:.3em 0}h2{font-size:1.4rem}.next{border:1px solid #81bda8;background:#1a3029;border-radius:14px;padding:20px}ul{list-style:none;padding:0;display:grid;gap:12px}li,details{padding:14px;background:#192328;border-radius:8px}li>span{display:block;color:#b8ccc5}details{margin:10px 0}summary{cursor:pointer}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:.85rem}dl{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}dt{color:#b8ccc5}dd{margin:4px 0;font-size:1.35rem}video{max-width:100%;width:720px}small{color:#b8ccc5}</style></head><body><main><header><small>MoonCast · Internal producer view · read only</small><h1>" +
    escape(ledger_text(ledger, "title")) +
    "</h1><p>Project " +
    escape(project_id) +
    " · Episode " +
    escape(episode_id) +
    " · Revision " +
    escape(ledger_text(ledger, "project_revision")) +
    "</p><p><a href=\"/studio\">Return to Studio</a> · <a href=\"../ledger\">Open ledger JSON</a></p></header><section class=\"next\"><h2>Next step</h2><p>" +
    escape(ledger_text(ledger, "next_action")) +
    "</p><p>In Studio, select project <strong>" +
    escape(project_id) +
    "</strong>. This page records no approval or external action.</p><ul>" +
    blockers +
    "</ul></section><section><h2>Master and review</h2>" +
    media +
    "<p>Client acceptance: <strong>" +
    escape(ledger_text(ledger, "client_acceptance_recorded")) +
    "</strong>. Payment evidence: <strong>" +
    escape(ledger_text(ledger, "payment_evidence_recorded")) +
    "</strong>.</p><p>Client access must be verified separately. Existing raw review tokens are never reconstructed here. Publication requires its own existing authorization.</p>" +
    ledger_detail(
      "Client responses and previous review versions",
      json_member(ledger, "client_reviews").unwrap_or(Json::null()),
    ) +
    ledger_detail(
      "Master decisions and version",
      Json::object({
        "master": json_member(ledger, "master").unwrap_or(Json::null()),
        "decisions": json_member(ledger, "master_decisions").unwrap_or(
          Json::null(),
        ),
      }),
    ) +
    ledger_detail(
      "Retained master, gate and revision history",
      json_member(ledger, "production_history").unwrap_or(Json::null()),
    ) +
    "</section><section><h2>Quote, capacity and actual costs</h2><p>Commercial amounts belong to the whole project and are not allocated across episodes. A forecast is not actual cost. Missing actuals stay unknown; no margin is inferred.</p><dl>" +
    costs +
    "</dl><p>Actuals match the current project revision: " +
    (if json_member(ledger, "actuals_current_revision") == Some(true.to_json()) {
      "Yes"
    } else {
      "No current record; any displayed values are last reported evidence"
    }) +
    "</p>" +
    ledger_detail("Exact quote, named decisions and conversion capacity", quote) +
    ledger_detail(
      "Actual cost evidence",
      json_member(ledger, "actuals").unwrap_or(Json::null()),
    ) +
    ledger_detail(
      "Separate billing and payment references",
      json_member(ledger, "billing_records").unwrap_or(Json::null()),
    ) +
    "</section><section><h2>Delivery packages</h2><ul>" +
    (if builds == "" {
      "<li>No delivery build recorded yet</li>"
    } else {
      builds
    }) +
    "</ul></section><section><h2>Production gates</h2><p>Readiness and retained receipts are shown independently. This view does not advance G0–G7.</p><ul>" +
    gates +
    "</ul></section><section><h2>Episode shots and asset lineage</h2><ul>" +
    shots +
    "</ul>" +
    ledger_detail(
      "Creative and rights revision history",
      json_member(ledger, "creative_history").unwrap_or(Json::null()),
    ) +
    "</section><footer><p>Producer-only local evidence. No client identity, paid production, recipient access, payment, or publication is established by opening this page.</p></footer></main></body></html>"
  @host_http.response(
    200,
    "OK",
    @utf8.encode(html),
    content_type="text/html; charset=utf-8",
    headers={
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; media-src 'self'; base-uri 'none'; frame-ancestors 'none'",
    },
  )
}
