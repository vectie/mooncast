///|
pub(all) struct DeliveryOutputSpec {
  output_id : String
  kind : String
  container : String
  codec : String
  width : Int
  height : Int
  subtitle_mode : String
  metadata_digest : String
  source_output_id : String?
  orientation : String?
  framing_policy : String?
  in_seconds : Double?
  out_seconds : Double?
  timestamp_seconds : Double?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryBuildProfile {
  contract : String
  profile_version : Int
  profile_digest : String
  outputs : Array[DeliveryOutputSpec]
  include_provenance_manifest : Bool
  include_rights_ledger : Bool
  include_acceptance_receipt : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryBuildArtifact {
  artifact_id : String
  kind : String
  filename : String
  media_type : String
  bytes : Int
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryBuild {
  contract : String
  build_id : String
  build_digest : String
  project_id : String
  project_revision : Int
  master_sha256 : String
  delivery_version : Int
  delivery_digest : String
  profile : DeliveryBuildProfile
  state : String
  revision : Int
  attempt_count : Int
  recovery_count : Int
  artifacts : Array[DeliveryBuildArtifact]
  archive : DeliveryBuildArtifact?
  economics_receipt_digest : String?
  last_error_code : String?
  created_at : String
  updated_at : String
  publication_authority : Bool
  record_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryBuildAcceptance {
  contract : String
  build_digest : String
  build_record_digest : String
  decision : String
  actor : String
  actor_role : String
  note : String
  project_revision : Int
  decided_at : String
  receipt_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryBuildEvent {
  contract : String
  event_id : String
  kind : String
  recorded_at : String
  evidence_digest : String
  artifacts : Array[DeliveryBuildArtifact]
  archive : DeliveryBuildArtifact?
  economics_receipt_digest : String?
  error_code : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryBuildCommand {
  contract : String
  command_id : String
  action : String
  expected_revision : Int
  recorded_at : String
  evidence_digest : String
  build : DeliveryBuild
  artifacts : Array[DeliveryBuildArtifact]
  archive : DeliveryBuildArtifact?
  economics_receipt_digest : String?
  error_code : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryBuildResult {
  contract : String
  command_id : String
  ok : Bool
  error_code : String?
  build : DeliveryBuild
  events : Array[DeliveryBuildEvent]
  external_effect_performed : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PublicationAuthorityRequest {
  contract : String
  project_id : String
  build_digest : String
  acceptance_receipt_digest : String
  destination_id : String
  actor : String
  authorized_at : String
  external_effect_performed : Bool
  publication_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)
