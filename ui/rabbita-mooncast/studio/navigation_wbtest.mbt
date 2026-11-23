///|
test "workspace navigation groups every studio destination exactly once" {
  let groups = workspace_navigation_groups()
  assert_eq(groups.map(group => group.0), [
    "Direct", "Create", "Produce", "Operate",
  ])
  let destination_count = groups.fold(init=0, (count, group) => {
    count + group.1.length()
  })
  assert_eq(destination_count, 10)
  assert_true(groups[0].1[0] == Overview)
  assert_true(groups[3].1[0] == Commercial)
}

///|
test "workspace navigation keeps full human-readable labels" {
  assert_eq(tab_label(ControlTower), "Control tower")
  assert_eq(tab_label(NeedsStrategy), "Needs and strategy")
  assert_eq(tab_label(StoryboardAnimatic), "Storyboard and animatic")
  assert_eq(tab_label(Commercial), "Commercial")
}

///|
test "studio shell exposes accessible navigation and progressive authority" {
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(render_app(_ => @rabbita.none, initial_model())),
  )
  assert_true(html.contains("href=\"#studio-main\""))
  assert_true(html.contains("aria-label=\"Mooncast workspace navigation\""))
  assert_true(html.contains("aria-label=\"Mooncast workspaces\""))
  assert_true(html.contains("operator-disclosure"))
  assert_true(
    html.contains("Decisions bind the exact displayed revision and digest."),
  )
}
