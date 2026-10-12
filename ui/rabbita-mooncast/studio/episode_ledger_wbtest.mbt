///|
test "episode cards link the exact selected project and episode ledger" {
  let project = {
    ..fixture_project("project-A", 3),
    episodes: [
      { id: "episode-one", title: "First episode", scenes: [], },
      { id: "episode-two", title: "Second episode", scenes: [], },
    ],
  }
  let model = {
    ..initial_model(),
    selected_project_id: project.id,
    project: Some(project),
  }
  let html = rendered(render_app(_ => @rabbita.none, model))
  assert_true(html.contains("Open episode ledger and actual costs"))
  assert_true(
    html.contains("/api/v2/projects/project-A/episodes/episode-one/ledger/view"),
  )
  assert_true(
    html.contains("/api/v2/projects/project-A/episodes/episode-two/ledger/view"),
  )
  let other = { ..fixture_project("project-B", 1), episodes: [], }
  let other_html = rendered(
    render_app(_ => @rabbita.none, {
      ..model,
      selected_project_id: other.id,
      project: Some(other),
    }),
  )
  assert_false(other_html.contains("project-A/episodes"))
}
