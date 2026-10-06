///|
test "delivery caption preview follows the selected project without stale links" {
  let first = fixture_project("caption-project-A", 3)
  let model = {
    ..initial_model(),
    selected_project_id: first.id,
    project: Some(first),
  }
  let html = rendered(render_delivery(_ => @rabbita.none, model, Some(first)))
  assert_true(
    html.contains("/api/v2/projects/caption-project-A/delivery-captions/view"),
  )
  assert_true(html.contains("Preview selected captions and download SRT"))
  assert_true(html.contains("Missing or changed captions"))
  let second = fixture_project("caption-project-B", 4)
  let switched = rendered(
    render_delivery(
      _ => @rabbita.none,
      { ..model, selected_project_id: second.id, project: Some(second), },
      Some(second),
    ),
  )
  assert_true(
    switched.contains(
      "/api/v2/projects/caption-project-B/delivery-captions/view",
    ),
  )
  assert_false(switched.contains("caption-project-A/delivery-captions"))
}
