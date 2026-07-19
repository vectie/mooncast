///|
pub(all) enum Gate {
  G0
  G1
  G2
  G3
  G4
  G5
  G6
  G7
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Gate::to_string(self : Gate) -> String {
  match self {
    G0 => "G0"
    G1 => "G1"
    G2 => "G2"
    G3 => "G3"
    G4 => "G4"
    G5 => "G5"
    G6 => "G6"
    G7 => "G7"
  }
}

///|
pub fn Gate::parse(value : String) -> Gate? {
  match value {
    "G0" => Some(G0)
    "G1" => Some(G1)
    "G2" => Some(G2)
    "G3" => Some(G3)
    "G4" => Some(G4)
    "G5" => Some(G5)
    "G6" => Some(G6)
    "G7" => Some(G7)
    _ => None
  }
}

///|
pub fn gate_sequence() -> Array[Gate] {
  [G0, G1, G2, G3, G4, G5, G6, G7]
}

///|
pub(all) struct GateReceipt {
  gate : Gate
  actor : String
  role : String
  evidence_digest : String
  snapshot_revision : Int
  decided_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AuthorityBoundary {
  external_effect_performed : Bool
  filesystem_authorized : Bool
  provider_transport_authorized : Bool
  secret_access_authorized : Bool
  payment_authorized : Bool
  publication_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn no_external_authority() -> AuthorityBoundary {
  {
    external_effect_performed: false,
    filesystem_authorized: false,
    provider_transport_authorized: false,
    secret_access_authorized: false,
    payment_authorized: false,
    publication_performed: false,
  }
}

///|
/// Evidence that the production has a payable, repeatable customer scenario.
pub(all) struct ClientQualification {
  reference : @project.VersionRef
  customer_id : String
  payable_problem : String
  acceptance_method : String
  distribution_channel : String
  payment_path : String
  repeat_purchase_hypothesis : String
  accepted : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn qualification_valid(qualification : ClientQualification) -> Bool {
  qualification.reference.id != "" &&
  qualification.reference.version >= 1 &&
  qualification.reference.digest != "" &&
  qualification.customer_id != "" &&
  qualification.payable_problem != "" &&
  qualification.acceptance_method != "" &&
  qualification.distribution_channel != "" &&
  qualification.payment_path != "" &&
  qualification.repeat_purchase_hypothesis != ""
}
