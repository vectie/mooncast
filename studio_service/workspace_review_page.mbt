///|
fn workspace_html_escape(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
async fn StudioService::workspace_review_content(
  self : StudioService,
  access : WorkspaceShareAccessProjection,
) -> String {
  match access.target_kind {
    @workspace.GraphTarget => {
      let graph = self.get_workspace_graph(access.project_id, access.target_id)
      let nodes = graph.nodes
        .map(node => {
          "<li><strong>" +
          workspace_html_escape(node.title) +
          "</strong><span>" +
          workspace_html_escape(node.definition_id) +
          "</span></li>"
        })
        .join("")
      "<h2>Graph revision " +
      graph.revision.to_string() +
      "</h2><p>" +
      workspace_html_escape(graph.title) +
      "</p><ul>" +
      nodes +
      "</ul>"
    }
    @workspace.RunTarget => {
      let run = self.get_workspace_run(access.target_id)
      let nodes = run.nodes
        .map(node => {
          let latest = node.attempts.last()
          "<li><strong>" +
          workspace_html_escape(node.node_id) +
          "</strong><span>" +
          workspace_html_escape(node.state.to_json().stringify()) +
          "</span>" +
          latest
          .map(attempt => {
            if attempt.error_code.is_blank() {
              if attempt.output_ref.is_blank() {
                ""
              } else {
                "<small>Output: " +
                workspace_html_escape(attempt.output_ref) +
                "</small>"
              }
            } else {
              "<small>" +
              workspace_html_escape(
                attempt.error_code + " · " + attempt.error_message,
              ) +
              "</small>"
            }
          })
          .unwrap_or("") +
          "</li>"
        })
        .join("")
      "<h2>Run evidence</h2><p>" +
      workspace_html_escape(
        run.run_id + " · " + run.state.to_json().stringify(),
      ) +
      "</p><ul>" +
      nodes +
      "</ul>"
    }
    @workspace.ArtifactTarget => {
      let artifacts = self.list_workspace_artifacts(
        project_id=access.project_id,
      )
      guard artifacts.artifacts
        .iter()
        .find_first(artifact => artifact.artifact_id == access.target_id)
        is Some(artifact) else {
        raise NotFound(entity="workspace_artifact", id=access.target_id)
      }
      "<h2>Immutable artifact</h2><dl><dt>ID</dt><dd>" +
      workspace_html_escape(artifact.artifact_id) +
      " v" +
      artifact.version.to_string() +
      "</dd><dt>Digest</dt><dd>" +
      workspace_html_escape(artifact.digest) +
      "</dd><dt>Rights</dt><dd>" +
      workspace_html_escape(artifact.rights_state) +
      "</dd><dt>QC</dt><dd>" +
      workspace_html_escape(artifact.qc_state) +
      "</dd></dl>"
    }
    @workspace.NodeTarget =>
      "<h2>Node review</h2><p>" +
      workspace_html_escape(access.target_id) +
      "</p>"
  }
}

///|
pub async fn StudioService::workspace_review_page(
  self : StudioService,
  share_id : String,
  token : String,
) -> @host_http.Response {
  let access = self.access_workspace_share(share_id, token)
  let content = self.workspace_review_content(access)
  let html = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Mooncast review</title><style>body{margin:0;background:#101416;color:#eef3f1;font:16px system-ui}main{max-width:900px;margin:auto;padding:48px 24px}header{border-bottom:1px solid #34413f;margin-bottom:28px}h1{font-size:2rem}h2{margin-top:28px}ul{list-style:none;padding:0;display:grid;gap:10px}li,dl{border:1px solid #34413f;border-radius:12px;padding:14px;background:#171d1f;display:grid;gap:6px}small,span,dt{color:#a9bab5}dd{margin:0 0 12px;overflow-wrap:anywhere}.pill{display:inline-block;padding:5px 9px;border-radius:999px;background:#24433c;color:#9de1cf}</style></head><body><main><header><span class=\"pill\">Read-only client review</span><h1>Mooncast evidence</h1><p>Project " +
    workspace_html_escape(access.project_id) +
    " · expires " +
    workspace_html_escape(access.expires_at) +
    "</p></header>" +
    content +
    "<footer><p>This link grants review visibility only. It cannot publish, execute providers, or approve work.</p></footer></main></body></html>"
  @host_http.text_response(
    200,
    "OK",
    html,
    content_type="text/html; charset=utf-8",
  )
}
