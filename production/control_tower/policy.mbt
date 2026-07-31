///|
fn iso_digit(value : String, index : Int) -> Int? {
  guard index >= 0 && index < value.length() else { return None }
  let code = value[index].to_int()
  if code >= 48 && code <= 57 {
    Some(code - 48)
  } else {
    None
  }
}

///|
fn iso_component(
  value : String,
  first : Int,
  second : Int,
  third? : Int,
  fourth? : Int,
) -> Int? {
  guard iso_digit(value, first) is Some(a) &&
    iso_digit(value, second) is Some(b) else {
    return None
  }
  let mut result = a * 10 + b
  match third {
    Some(index) =>
      match iso_digit(value, index) {
        Some(digit) => result = result * 10 + digit
        None => return None
      }
    None => ()
  }
  match fourth {
    Some(index) =>
      match iso_digit(value, index) {
        Some(digit) => result = result * 10 + digit
        None => return None
      }
    None => ()
  }
  Some(result)
}

///|
/// Gregorian day ordinal for exact `YYYY-MM-DD` dates.
pub fn iso_date_ordinal(value : String) -> Int? {
  guard value.length() == 10 &&
    value[4] == '-' &&
    value[7] == '-' &&
    iso_component(value, 0, 1, third=2, fourth=3) is Some(year) &&
    iso_component(value, 5, 6) is Some(month) &&
    iso_component(value, 8, 9) is Some(day) &&
    month >= 1 &&
    month <= 12 &&
    day >= 1 else {
    return None
  }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let days_in_month = match month {
    2 => if leap { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
  guard day <= days_in_month else { return None }
  let adjusted_year = year - (if month <= 2 { 1 } else { 0 })
  let era = if adjusted_year >= 0 {
    adjusted_year / 400
  } else {
    (adjusted_year - 399) / 400
  }
  let year_of_era = adjusted_year - era * 400
  let shifted_month = month + (if month > 2 { -3 } else { 9 })
  let day_of_year = (153 * shifted_month + 2) / 5 + day - 1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  Some(era * 146097 + day_of_era)
}

///|
pub fn iso_date_delta(later : String, earlier : String) -> Int? {
  guard iso_date_ordinal(later) is Some(later_day) &&
    iso_date_ordinal(earlier) is Some(earlier_day) else {
    return None
  }
  Some(later_day - earlier_day)
}

///|
pub fn remaining_work(snapshot : @kernel.ProjectSnapshot) -> RemainingWork {
  let shots = @project.flattened_shots(snapshot.graph)
  let mut without_output = 0
  let mut awaiting_qc = 0
  for shot in shots {
    let succeeded = snapshot.generation_attempts.any(attempt => {
      attempt.shot_id == shot.shot_id && attempt.status == "succeeded"
    })
    if !succeeded {
      without_output = without_output + 1
    } else if !@governance.shot_passes_qc(
        shot.shot_id,
        snapshot.generation_attempts,
        snapshot.qc_findings,
        snapshot.qc_decisions,
      ) {
      awaiting_qc = awaiting_qc + 1
    }
  }
  let creative_kinds = [
    @creative.Brief,
    @creative.RightsLedger,
    @creative.IpBible,
    @creative.Script,
    @creative.ClaimsLedger,
    @creative.Storyboard,
    @creative.Animatic,
  ]
  let mut creative_remaining = 0
  for kind in creative_kinds {
    let current = @creative.current_artifact(snapshot.creative_artifacts, kind)
    if !@creative.exact_approval(current, snapshot.creative_decisions) {
      creative_remaining = creative_remaining + 1
    }
  }
  let routing_remaining = !@governance.routing_exact_approved(
    snapshot.routing_plan,
    snapshot.routing_decisions,
    snapshot.graph.maximum_budget_cny,
  )
  let master_remaining = !@governance.master_exact_approved(
    snapshot.master,
    snapshot.master_decisions,
  )
  let client_remaining = !@governance.delivery_exact_accepted(
    snapshot.delivery_package,
    snapshot.master,
    snapshot.delivery_acceptances,
  )
  let delivery_remaining = snapshot.delivery_package is None
  let performance_remaining = !@governance.performance_current(
    snapshot.delivery_package,
    snapshot.performance_reviews,
  )
  let total = creative_kinds.length() + 1 + shots.length() * 2 + 4
  let incomplete = creative_remaining +
    (if routing_remaining { 1 } else { 0 }) +
    without_output * 2 +
    awaiting_qc +
    (if master_remaining { 1 } else { 0 }) +
    (if delivery_remaining { 1 } else { 0 }) +
    (if client_remaining { 1 } else { 0 }) +
    (if performance_remaining { 1 } else { 0 })
  let complete = Int::max(0, total - incomplete)
  let next_actions : Array[String] = []
  if creative_remaining > 0 {
    next_actions.push(
      "Complete " + creative_remaining.to_string() + " creative approvals",
    )
  }
  if routing_remaining {
    next_actions.push("Approve the exact model-routing plan")
  }
  if without_output > 0 {
    next_actions.push(
      "Generate outputs for " + without_output.to_string() + " shots",
    )
  }
  if awaiting_qc > 0 {
    next_actions.push("Resolve QC for " + awaiting_qc.to_string() + " shots")
  }
  if master_remaining {
    next_actions.push("Assemble and approve the exact master")
  }
  if delivery_remaining {
    next_actions.push("Prepare the delivery package")
  }
  if client_remaining {
    next_actions.push("Obtain named client acceptance")
  }
  if performance_remaining {
    next_actions.push("Record the G7 performance and economics review")
  }
  {
    total_shots: shots.length(),
    shots_without_output: without_output,
    shots_awaiting_qc: awaiting_qc,
    creative_approvals_remaining: creative_remaining,
    routing_approval_remaining: routing_remaining,
    master_work_remaining: master_remaining,
    client_acceptance_remaining: client_remaining,
    delivery_work_remaining: delivery_remaining,
    performance_review_remaining: performance_remaining,
    work_units_total: total,
    work_units_complete: complete,
    completion_rate: if total == 0 {
      0.0
    } else {
      complete.to_double() / total.to_double()
    },
    next_actions,
  }
}

///|
pub fn provider_cost_breakdown(
  generation_attempts_cny : Double,
  asset_factory_cny : Double,
  animatic_cny : Double,
  postprocess_cny : Double,
  automated_qc_cny : Double,
  actuals : OperatingActuals?,
) -> ProviderCostBreakdown {
  let operational = generation_attempts_cny +
    asset_factory_cny +
    animatic_cny +
    postprocess_cny +
    automated_qc_cny
  let confirmed = match actuals {
    Some(value) => value.provider_cost_confirmed_cny
    None => None
  }
  {
    generation_attempts_cny,
    asset_factory_cny,
    animatic_cny,
    postprocess_cny,
    automated_qc_cny,
    operational_total_cny: operational,
    confirmed_total_cny: confirmed,
    discrepancy_cny: confirmed.map(value => value - operational),
    evidence_state: match (actuals, confirmed) {
      (Some(value), Some(_)) if value.provider_cost_reconciled =>
        "evidence-reconciled"
      (Some(_), Some(_)) => "confirmed-but-unreconciled"
      _ => "operational-records-only"
    },
  }
}

///|
pub fn spend_actual(
  provider : ProviderCostBreakdown,
  actuals : OperatingActuals?,
) -> SpendActual {
  let labor = match actuals {
    Some(value) => value.labor_cost_cny
    None => None
  }
  let other = match actuals {
    Some(value) => value.other_cost_cny
    None => None
  }
  let revenue = match actuals {
    Some(value) => value.recognized_revenue_cny
    None => None
  }
  let provider_total = provider.confirmed_total_cny.unwrap_or(
    provider.operational_total_cny,
  )
  let direct = match (labor, other) {
    (Some(labor), Some(other)) => Some(provider_total + labor + other)
    _ => None
  }
  let margin = match (revenue, direct) {
    (Some(revenue), Some(direct)) => Some(revenue - direct)
    _ => None
  }
  {
    provider,
    labor_cny: labor,
    other_cny: other,
    direct_cny: direct,
    revenue_cny: revenue,
    gross_margin_cny: margin,
    contribution_margin_cny: margin,
    founder_hours: match actuals {
      Some(value) => value.founder_hours
      None => None
    },
    completed_labor_hours: match actuals {
      Some(value) => value.completed_labor_hours
      None => None
    },
  }
}

///|
pub fn spend_variance(
  plan : SpendPlan?,
  actual : SpendActual,
) -> SpendVariance? {
  guard plan is Some(plan) else { return None }
  let actual_provider = actual.provider.confirmed_total_cny.unwrap_or(
    actual.provider.operational_total_cny,
  )
  Some({
    provider_cny: Some(actual_provider - plan.provider_cny),
    labor_cny: actual.labor_cny.map(value => value - plan.labor_cny),
    other_cny: actual.other_cny.map(value => value - plan.other_cny),
    direct_cny: actual.direct_cny.map(value => value - plan.direct_cny),
    revenue_cny: actual.revenue_cny.map(value => value - plan.revenue_cny),
    gross_margin_cny: actual.gross_margin_cny.map(value => {
      value - plan.gross_margin_cny
    }),
    contribution_margin_cny: actual.contribution_margin_cny.map(value => {
      value - plan.contribution_margin_cny
    }),
    founder_hours: actual.founder_hours.map(value => value - plan.founder_hours),
  })
}

///|
pub fn revision_burden(
  included_rounds : Int?,
  used_rounds : Int,
) -> RevisionBurden {
  let remaining = included_rounds.map(value => Int::max(0, value - used_rounds))
  let overage = included_rounds.map(value => Int::max(0, used_rounds - value))
  {
    included_rounds,
    used_rounds,
    remaining_rounds: remaining,
    overage_rounds: overage,
    state: match included_rounds {
      None => "missing-quote-policy"
      Some(value) if used_rounds > value => "overage"
      Some(value) if used_rounds == value => "limit-reached"
      Some(_) => "within-policy"
    },
  }
}

///|
pub fn schedule_health(
  as_of_date : String,
  start_date : String?,
  delivery_date : String?,
  forecast_completion_date : String?,
  remaining : RemainingWork,
  has_capacity_conflict : Bool,
) -> ScheduleHealth {
  let days_to_delivery = match delivery_date {
    Some(value) => iso_date_delta(value, as_of_date)
    None => None
  }
  let drift = match (forecast_completion_date, delivery_date) {
    (Some(forecast), Some(delivery)) => iso_date_delta(forecast, delivery)
    (None, Some(delivery)) if remaining.completion_rate < 1.0 =>
      iso_date_delta(as_of_date, delivery).map(value => Int::max(0, value))
    _ => None
  }
  let basis : Array[String] = []
  let risk = match delivery_date {
    None => {
      basis.push("No accepted quote schedule is bound to the project")
      "unknown"
    }
    Some(_) if remaining.completion_rate >= 1.0 => {
      basis.push("All tracked production work units are complete")
      "complete"
    }
    Some(_) if days_to_delivery.map(value => value < 0).unwrap_or(false) => {
      basis.push("Promised delivery date has passed with work remaining")
      "breached"
    }
    Some(_) if drift.map(value => value > 0).unwrap_or(false) => {
      basis.push("Named completion forecast is later than promised delivery")
      "high"
    }
    Some(_) if has_capacity_conflict => {
      basis.push("A finite-resource conflict affects the project")
      "high"
    }
    Some(_) if days_to_delivery.map(value => value <= 3).unwrap_or(false) => {
      basis.push("Three or fewer days remain with production work open")
      "high"
    }
    Some(_) if days_to_delivery.map(value => value <= 7).unwrap_or(false) => {
      basis.push("Seven or fewer days remain with production work open")
      "at-risk"
    }
    Some(_) if forecast_completion_date is None => {
      basis.push("No named completion forecast has been recorded")
      "watch"
    }
    Some(_) => {
      basis.push("Current forecast is within the promised delivery window")
      "on-track"
    }
  }
  {
    as_of_date,
    start_date,
    promised_delivery_date: delivery_date,
    forecast_completion_date,
    drift_days: drift,
    days_to_delivery,
    risk,
    basis,
  }
}
