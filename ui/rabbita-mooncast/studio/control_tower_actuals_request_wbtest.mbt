///|
extern "js" fn export_actuals_fixture(name : String, payload : String) -> Unit =
  #| (name, payload) => {
  #|   const path = process.env.MOONCAST_ACTUALS_UI_PAYLOAD_ROOT;
  #|   if (path) process.getBuiltinModule("node:fs").writeFileSync(path + "/" + name + ".json", payload);
  #| }

///|
fn actuals_ui_fixture_model() -> Model {
  let model = initial_model()
  {
    ..model,
    operator: {
      ..model.operator,
      actor: "Synthetic UI producer",
      role: "producer",
      recorded_at: "2026-10-08T00:00:00Z",
      human_confirmed: true,
    },
  }
}

///|
test "actuals production builder omits unknown fields and preserves explicit zero" {
  let model = actuals_ui_fixture_model()
  let blank = control_tower_actuals_body(model, 8, None, None).unwrap()
  guard blank is Object(fields) else { fail("object required") }
  for
    key in [
      "expected_actuals_version", "expected_actuals_digest", "labor_cost_cny", "provider_cost_confirmed_cny",
      "founder_hours", "forecast_completion_date",
    ] {
    assert_false(fields.contains(key))
  }
  let model = {
    ..model,
    control_tower_actuals_form: {
      ..model.control_tower_actuals_form,
      labor_cost_cny: "20",
      other_cost_cny: "0",
      evidence_refs: "fixture://compiled-ui-actuals",
    },
  }
  let value = control_tower_actuals_body(model, 8, None, None).unwrap()
  guard value is Object(values) else { fail("object required") }
  assert_eq(values.get("labor_cost_cny"), Some(20.0.to_json()))
  assert_eq(values.get("other_cost_cny"), Some(0.0.to_json()))
  assert_false(values.contains("founder_hours"))
  export_actuals_fixture("actuals-ui-absent", value.stringify())
}

///|
test "actuals production builder preserves present optional bindings and values" {
  let initial = actuals_ui_fixture_model()
  let model = {
    ..initial,
    control_tower_actuals_form: {
      ..initial.control_tower_actuals_form,
      provider_cost_confirmed_cny: "1.25",
      labor_cost_cny: "2.5",
      other_cost_cny: "3",
      recognized_revenue_cny: "4",
      founder_hours: "5",
      completed_labor_hours: "6",
      forecast_completion_date: "2026-10-10",
      provider_cost_reconciled: true,
      evidence_refs: "fixture://present-ui-actuals",
    },
  }
  let payload = control_tower_actuals_body(
    model,
    8,
    Some(2),
    Some("sha256:observed"),
  ).unwrap()
  guard payload is Object(fields) else { fail("object required") }
  assert_eq(fields.get("expected_actuals_version"), Some((2).to_json()))
  assert_eq(
    fields.get("expected_actuals_digest"),
    Some("sha256:observed".to_json()),
  )
  assert_eq(fields.get("provider_cost_confirmed_cny"), Some(1.25.to_json()))
  assert_eq(
    fields.get("forecast_completion_date"),
    Some("2026-10-10".to_json()),
  )
  for _, value in fields {
    assert_true(value != Json::null())
  }
  export_actuals_fixture("actuals-ui-present", payload.stringify())
}

///|
test "actuals production builder rejects malformed negative and nonfinite input" {
  let initial = actuals_ui_fixture_model()
  for text in ["not a number", "-1", "NaN", "Infinity", "1e999"] {
    let model = {
      ..initial,
      control_tower_actuals_form: {
        ..initial.control_tower_actuals_form,
        labor_cost_cny: text,
      },
    }
    assert_true(control_tower_actuals_body(model, 8, None, None) is Err(_))
  }
}
