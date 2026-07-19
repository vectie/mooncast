///|
/// Evidence gates for the systematic long-form production lifecycle.
pub(all) enum ProductionGate {
  G0Brief
  G1RightsBible
  G2Creative
  G3ProductionAuthorization
  G4Assets
  G5Master
  G6ClientAcceptance
  G7Delivery
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ProductionStage {
  Draft
  BriefReady
  RightsReady
  CreativeApproved
  ProductionAuthorized
  AssetsReady
  MasterApproved
  ClientAccepted
  DeliveryAuthorized
  Delivered
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GateReceipt {
  gate : ProductionGate
  actor : String
  evidence_digest : String
  decided_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionReadiness {
  brief_complete : Bool
  rights_cleared : Bool
  bible_locked : Bool
  script_approved : Bool
  storyboard_approved : Bool
  animatic_approved : Bool
  route_authorized : Bool
  budget_authorized : Bool
  shots_complete : Bool
  provenance_complete : Bool
  qc_approved : Bool
  editorial_approved : Bool
  client_accepted : Bool
  delivery_planned : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionProjectSummary {
  project_id : String
  stage : ProductionStage
  target_duration_seconds : Int
  episode_count : Int
  scene_count : Int
  shot_count : Int
  budget_cny : Double
  spent_cny : Double
  gate_receipts : Array[GateReceipt]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn production_gate_sequence() -> Array[ProductionGate] {
  [
    G0Brief,
    G1RightsBible,
    G2Creative,
    G3ProductionAuthorization,
    G4Assets,
    G5Master,
    G6ClientAcceptance,
    G7Delivery,
  ]
}

///|
pub fn production_gate_ready(
  gate : ProductionGate,
  readiness : ProductionReadiness,
) -> Bool {
  match gate {
    G0Brief => readiness.brief_complete
    G1RightsBible => readiness.rights_cleared && readiness.bible_locked
    G2Creative =>
      readiness.script_approved &&
      readiness.storyboard_approved &&
      readiness.animatic_approved
    G3ProductionAuthorization =>
      readiness.route_authorized && readiness.budget_authorized
    G4Assets => readiness.shots_complete && readiness.provenance_complete
    G5Master => readiness.qc_approved && readiness.editorial_approved
    G6ClientAcceptance => readiness.client_accepted
    G7Delivery => readiness.delivery_planned
  }
}

///|
pub fn next_production_gate(receipts : Array[GateReceipt]) -> ProductionGate? {
  for gate in production_gate_sequence() {
    if !receipts.any(receipt => receipt.gate == gate) {
      return Some(gate)
    }
  }
  None
}

///|
pub fn systematic_delivery_ready(
  summary : ProductionProjectSummary,
  readiness : ProductionReadiness,
) -> Bool {
  summary.target_duration_seconds >= 180 &&
  summary.target_duration_seconds <= 480 &&
  summary.shot_count > 0 &&
  summary.spent_cny <= summary.budget_cny &&
  production_gate_sequence().all(gate => production_gate_ready(gate, readiness)) &&
  next_production_gate(summary.gate_receipts) is None
}
