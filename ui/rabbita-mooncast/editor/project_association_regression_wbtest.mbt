///|
fn regression_two_project_model() -> Model {
  let base = initial_model()
  let projects = decode_project_response([
    {
      "project_id": "A",
      "revision": 1,
      "timeline_id": "a",
      "duration_ticks": 1000,
      "updated_at": "fixture",
    },
    {
      "project_id": "B",
      "revision": 1,
      "timeline_id": "b",
      "duration_ticks": 1000,
      "updated_at": "fixture",
    },
  ]).unwrap()
  {
    ..base,
    projects,
    catalog_state: CatalogReady,
    project_id: "A",
    export_state: {
      ..base.export_state,
      job_id: "master",
      download_url: "/A/master.mp4",
      promoted: true,
    },
  }
}

///|
test "regression selecting B must not relabel A before explicit Open" {
  let selected = update(
      _ => @rabbita.none,
      SelectProject("B"),
      regression_two_project_model(),
    ).1
  assert_eq(selected.project_id, "A")
}

///|
test "regression opening B must remove A completed export" {
  let selected = update(
      _ => @rabbita.none,
      SelectProject("B"),
      regression_two_project_model(),
    ).1
  let opened = update(_ => @rabbita.none, OpenProject, selected).1
  assert_eq(opened.project_id, "B")
  assert_eq(opened.export_state.download_url, "")
  assert_false(opened.export_state.promoted)
}
