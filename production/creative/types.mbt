///|
pub(all) enum ArtifactKind {
  Brief
  RightsLedger
  IpBible
  Script
  ClaimsLedger
  Storyboard
  Animatic
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn ArtifactKind::to_string(self : ArtifactKind) -> String {
  match self {
    Brief => "brief"
    RightsLedger => "rights-ledger"
    IpBible => "ip-bible"
    Script => "script"
    ClaimsLedger => "claims-ledger"
    Storyboard => "storyboard"
    Animatic => "animatic"
  }
}

///|
pub(all) struct CreativeArtifact {
  reference : @project.VersionRef
  kind : ArtifactKind
  dependency_digests : Array[String]
  duration_seconds : Int?
  expected_cost_cny : Double?
  rights_cleared : Bool
  content : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeDecision {
  artifact : @project.VersionRef
  decision : String
  actor : String
  role : String
  decided_at : String
  note : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DependencyInvalidation {
  changed : @project.VersionRef
  invalidated_kinds : Array[ArtifactKind]
  from_gate : String
  reason : String
} derive(Debug, Eq, ToJson, FromJson)
