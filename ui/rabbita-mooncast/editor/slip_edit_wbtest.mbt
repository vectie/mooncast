///|
test "slip controls bind selection revision and busy guard without optimistic mutation" {
  let original = { ..roll_ui_model(), selected_clip_ids: ["a"], }
  let payload = selected_slip_plan(original, 1).unwrap()
  let body = make_command_body(original, "trim", payload)
  guard body is Object(fields) else { fail("command body") }
  assert_eq(fields["expected_revision"], Json::number(7))
  assert_eq(fields["idempotency_key"], Json::string("rabbita-trim-1"))
  let next = update(_ => @rabbita.none, SlipSelection(1), original).1
  assert_true(next.busy)
  assert_eq(next.request_sequence, 1)
  assert_eq(clips(next)[0].source_in_tick, 1000)
  assert_eq(clips(next)[1].start_tick, 2000)
  assert_eq(next.undo_stack.length(), 0)
  let again = update(_ => @rabbita.none, SlipSelection(1), next).1
  assert_eq(again.request_sequence, 1)
  assert_true(again.error.contains("Wait"))
  for model in [
    { ..original, project_id: "other", }, { ..original, loading: true, },
    { ..original, selected_clip_ids: [], },
    { ..original, workspace: Some({ ..original.workspace.unwrap(), take_variants: None, }), },
  ] {
    assert_true(selected_slip_plan(model, 1) is Err(_))
    assert_eq(update(_ => @rabbita.none, SlipSelection(1), model).1.request_sequence, 0)
  }
  let html = @rabbita.render_to_string(@rabbita.static_cell(slip_edit_controls(_ => @rabbita.none, original)))
  assert_true(html.contains("Slip −1f"))
  assert_true(html.contains("Slip +1f"))
  assert_false(html.contains("disabled"))
}
