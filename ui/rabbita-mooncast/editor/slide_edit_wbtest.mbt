///|
test "slide UI previews signed edit and sends one canonical mutation with guards" {
  let original = {
    ..roll_ui_model(),
    selected_clip_ids: ["b"],
    slide_offset_frames: "12",
  }
  let plan = selected_slide_plan(original).unwrap()
  assert_eq(plan.start_tick, 2480)
  assert_eq(plan.end_tick, 4480)
  let body = make_command_body(original, "group_trim", plan.payload)
  guard body is Object(fields) else { fail("command body") }
  assert_eq(fields["expected_revision"], Json::number(7))
  assert_eq(fields["idempotency_key"], Json::string("rabbita-group_trim-1"))
  let edited = update(_ => @rabbita.none, SetSlideOffset("2"), original).1
  assert_eq(edited.slide_offset_frames, "2")
  let next = update(_ => @rabbita.none, SlideSelection, original).1
  assert_true(next.busy)
  assert_eq(next.request_sequence, 1)
  assert_eq(clips(next)[1].start_tick, 2000)
  assert_eq(next.undo_stack.length(), 0)
  let again = update(_ => @rabbita.none, SlideSelection, next).1
  assert_eq(again.request_sequence, 1)
  assert_true(again.error.contains("Wait"))
  assert_eq(
    update(_ => @rabbita.none, SetSlideOffset("99"), next).1.slide_offset_frames,
    "12",
  )
  for
    model in [
      { ..original, project_id: "other", },
      { ..original, loading: true, },
      { ..original, selected_clip_ids: [], },
      { ..original, slide_offset_frames: "1.5", },
      { ..original, slide_offset_frames: "2147483648", },
      { ..original, slide_offset_frames: "0", },
      {
        ..original,
        workspace: Some({ ..original.workspace.unwrap(), take_variants: None, }),
      },
    ] {
    assert_true(selected_slide_plan(model) is Err(_))
    assert_eq(
      update(_ => @rabbita.none, SlideSelection, model).1.request_sequence,
      0,
    )
  }
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(slide_edit_controls(_ => @rabbita.none, original)),
  )
  assert_true(html.contains("Slide shot"))
  assert_true(html.contains("2480–4480"))
  assert_true(html.contains("Same track only"))
  assert_false(html.contains("disabled"))
  let workspace = original.workspace.unwrap()
  let variants = workspace.take_variants.unwrap()
  let conflict = {
    ..original,
    workspace: Some({
      ..workspace,
      take_variants: Some(variants + [{ ..variants[0], duration_ticks: 2999, }]),
    }),
  }
  assert_true(selected_slide_plan(conflict) is Err(_))
}
