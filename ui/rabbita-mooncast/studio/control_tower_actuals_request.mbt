///|
/// Match the native derived DTO: absent options are omitted, present values
/// are bare scalars. Invalid text must never become invented zero evidence.
fn control_tower_actuals_body(
  model : Model,
  project_revision : Int,
  actuals_version : Int?,
  actuals_digest : String?,
) -> Result[Json, String] {
  let form = model.control_tower_actuals_form
  let fields : Map[String, Json] = {
    "command_id": ("tower-actuals-" + (model.command_sequence + 1).to_string()).to_json(),
    "expected_project_revision": project_revision.to_json(),
    "provider_cost_reconciled": form.provider_cost_reconciled.to_json(),
    "evidence_refs": split_lines(form.evidence_refs).to_json(),
    "actor": model.operator.actor.to_json(),
    "actor_role": model.operator.role.to_json(),
    "observed_at": model.operator.recorded_at.to_json(),
    "human_confirmed": model.operator.human_confirmed.to_json(),
  }
  match actuals_version {
    Some(value) => fields["expected_actuals_version"] = value.to_json()
    None => ()
  }
  match actuals_digest {
    Some(value) => fields["expected_actuals_digest"] = value.to_json()
    None => ()
  }
  for
    (key, text) in [
      ("provider_cost_confirmed_cny", form.provider_cost_confirmed_cny),
      ("labor_cost_cny", form.labor_cost_cny),
      ("other_cost_cny", form.other_cost_cny),
      ("recognized_revenue_cny", form.recognized_revenue_cny),
      ("founder_hours", form.founder_hours),
      ("completed_labor_hours", form.completed_labor_hours),
    ] {
    if text.trim() == "" {
      continue
    }
    let number = @string.parse_double(text.trim()) catch {
      _ =>
        return Err(
          key + ": enter a finite nonnegative number or leave it blank.",
        )
    }
    if !(number >= 0.0 && number <= 1.7976931348623157e308) {
      return Err(key + ": enter a finite nonnegative number or leave it blank.")
    }
    fields[key] = number.to_json()
  }
  if form.forecast_completion_date.trim() != "" {
    fields["forecast_completion_date"] = form.forecast_completion_date.to_json()
  }
  Ok(Json::object(fields))
}
