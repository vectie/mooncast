///|
fn complete_readiness() -> ProductionReadiness {
  {
    brief_complete: true,
    rights_cleared: true,
    bible_locked: true,
    script_approved: true,
    storyboard_approved: true,
    animatic_approved: true,
    route_authorized: true,
    budget_authorized: true,
    shots_complete: true,
    provenance_complete: true,
    qc_approved: true,
    editorial_approved: true,
    client_accepted: true,
    delivery_planned: true,
  }
}

///|
test "systematic gates fail closed on rights and budget" {
  let readiness = complete_readiness()
  assert_true(production_gate_ready(G1RightsBible, readiness))
  assert_false(
    production_gate_ready(G1RightsBible, { ..readiness, rights_cleared: false }),
  )
  let receipts = production_gate_sequence().map(gate => GateReceipt::{
    gate,
    actor: "operator",
    evidence_digest: "sha256",
    decided_at: "2026-07-16T00:00:00Z",
  })
  let summary : ProductionProjectSummary = {
    project_id: "systematic-fixture",
    stage: DeliveryAuthorized,
    target_duration_seconds: 180,
    episode_count: 1,
    scene_count: 5,
    shot_count: 15,
    budget_cny: 20.0,
    spent_cny: 4.8,
    gate_receipts: receipts,
  }
  assert_true(systematic_delivery_ready(summary, readiness))
  assert_false(
    systematic_delivery_ready({ ..summary, spent_cny: 20.1 }, readiness),
  )
}

///|
test "next gate preserves G0 through G7 order" {
  assert_true(next_production_gate([]) is Some(G0Brief))
  let first : GateReceipt = {
    gate: G0Brief,
    actor: "producer",
    evidence_digest: "digest",
    decided_at: "now",
  }
  assert_true(next_production_gate([first]) is Some(G1RightsBible))
}
