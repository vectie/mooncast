///|
test "control tower date math rejects impossible dates" {
  assert_eq(iso_date_delta("2026-03-01", "2026-02-28"), Some(1))
  assert_eq(iso_date_delta("2024-03-01", "2024-02-29"), Some(1))
  assert_eq(iso_date_ordinal("2026-02-29"), None)
  assert_eq(iso_date_ordinal("2026-04-31"), None)
}

///|
test "control tower never turns missing operating evidence into zero" {
  let provider = provider_cost_breakdown(10.0, 2.0, 1.0, 3.0, 4.0, None)
  assert_eq(provider.operational_total_cny, 20.0)
  assert_eq(provider.evidence_state, "operational-records-only")
  let actual = spend_actual(provider, None)
  assert_eq(actual.labor_cny, None)
  assert_eq(actual.other_cny, None)
  assert_eq(actual.direct_cny, None)
  assert_eq(actual.revenue_cny, None)
}

///|
test "control tower exposes revision overage and named forecast drift" {
  let revisions = revision_burden(Some(2), 4)
  assert_eq(revisions.state, "overage")
  assert_eq(revisions.overage_rounds, Some(2))
  let remaining : RemainingWork = {
    total_shots: 10,
    shots_without_output: 2,
    shots_awaiting_qc: 1,
    creative_approvals_remaining: 0,
    routing_approval_remaining: false,
    master_work_remaining: true,
    client_acceptance_remaining: true,
    delivery_work_remaining: true,
    performance_review_remaining: true,
    work_units_total: 20,
    work_units_complete: 12,
    completion_rate: 0.6,
    next_actions: ["Generate remaining shots"],
  }
  let schedule = schedule_health(
    "2026-07-31",
    Some("2026-07-20"),
    Some("2026-08-02"),
    Some("2026-08-05"),
    remaining,
    false,
  )
  assert_eq(schedule.risk, "high")
  assert_eq(schedule.days_to_delivery, Some(2))
  assert_eq(schedule.drift_days, Some(3))
}
