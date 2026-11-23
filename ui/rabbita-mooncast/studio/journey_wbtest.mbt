///|
test "studio journey maps every gate to one clear workspace" {
  assert_eq(studio_journey_for(None, false, false).action, "Start episode")
  assert_eq(studio_journey_for(Some("G1"), false, true).tab == Creative, true)
  assert_eq(
    studio_journey_for(Some("G3"), false, true).tab == StoryboardAnimatic,
    true,
  )
  assert_eq(studio_journey_for(Some("G4"), false, true).tab == ShotBoard, true)
  assert_eq(studio_journey_for(Some("G7"), false, true).tab == Commercial, true)
  assert_eq(studio_journey_for(None, false, true).position, 8)
}

///|
test "ready governed gates expose the receipt action" {
  assert_eq(studio_journey_for(Some("G0"), true, true).action, "Record G0")
  assert_eq(studio_journey_for(Some("G2"), true, true).action, "Record G2")
  assert_eq(studio_journey_for(Some("G3"), true, true).action, "Record G3")
}

///|
test "new studio forms do not prefill historical decision or delivery dates" {
  let model = initial_model()
  assert_eq(model.operator.recorded_at, "")
  assert_eq(model.quote_form.start_date, "")
  assert_eq(model.quote_form.delivery_date, "")
  assert_eq(model.capacity_form.available_from, "")
  assert_eq(model.capacity_form.available_to, "")
  assert_eq(model.capacity_form.reservation_start, "")
  assert_eq(model.capacity_form.reservation_end, "")
  assert_eq(model.control_tower_actuals_form.forecast_completion_date, "")
  assert_eq(model.control_tower_ownership_form.action_due_date, "")
}

///|
test "empty production portfolio is not reported on track" {
  assert_eq(control_tower_portfolio_status(0, 0), "no projects")
  assert_eq(control_tower_portfolio_status(1, 0), "on-track")
  assert_eq(control_tower_portfolio_status(1, 1), "attention-required")
}

///|
test "commercial lead requires an observed positive baseline before recording" {
  let blank = initial_model().commercial_form
  assert_false(commercial_lead_form_ready(blank))
  let completed = {
    ..blank,
    customer: "Synthetic buyer",
    payable_problem: "Slow episode production",
    baseline_hours: "2",
  }
  assert_true(commercial_lead_form_ready(completed))
  assert_false(
    commercial_lead_form_ready({ ..completed, baseline_hours: "0", }),
  )
  assert_false(
    commercial_lead_form_ready({ ..completed, baseline_hours: "-1", }),
  )
  assert_false(
    commercial_lead_form_ready({ ..completed, baseline_hours: "abc", }),
  )
}
