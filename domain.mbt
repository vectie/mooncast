///|
pub(all) enum CampaignStage {
  Brief
  RightsCleared
  Generated
  SafetyReviewed
  HumanApproved
  Packaged
  Published
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryGate {
  rights_cleared : Bool
  safety_passed : Bool
  human_approved : Bool
  provenance_complete : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn delivery_ready(gate : DeliveryGate) -> Bool {
  gate.rights_cleared &&
  gate.safety_passed &&
  gate.human_approved &&
  gate.provenance_complete
}

///|
pub fn publication_ready(stage : CampaignStage, gate : DeliveryGate) -> Bool {
  (stage == Packaged || stage == Published) && delivery_ready(gate)
}
