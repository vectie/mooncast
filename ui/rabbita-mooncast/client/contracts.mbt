///|
/// Client-safe projection for an immutable review portal. This deliberately
/// excludes provider prompts, credentials, internal production files, and any
/// publication authority.
struct ClientBrand {
  name : String
  accent : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientPortalSummary {
  portal_id : String
  expires_at : String
  scopes : Array[String]
  status : String?
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientEpisodeSummary {
  episode_id : String
  title : String
  scene_count : Int
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientProjectSummary {
  project_id : String
  title : String
  objective : String
  target_duration_seconds : Double
  episodes : Array[ClientEpisodeSummary]
} derive(FromJson)

///|
struct ExactBuildBinding {
  master_sha256 : String
  delivery_digest : String
  build_id : String
  build_digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientAnnotation {
  contract : String
  annotation_id : String
  portal_id : String
  master_sha256 : String
  build_digest : String
  timecode_seconds : Double
  body : String
  author : String
  created_at : String
  digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientDecisionReceipt {
  contract : String
  portal_id : String
  decision : String
  master_sha256 : String
  build_digest : String
  governance_receipt_digest : String
  project_revision : Int
  decided_at : String
  digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct RevisionPolicy {
  maximum : Int
  used : Int
  remaining : Int
} derive(FromJson)

///|
struct DeliveryArtifact {
  name : String
  kind : String
  sha256 : String
  size_bytes : Int
} derive(FromJson)

///|
struct ClientDelivery {
  accepted : Bool
  download_url : String?
  archive_name : String?
  artifacts : Array[DeliveryArtifact]
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientProjection {
  contract : String
  brand : ClientBrand
  portal : ClientPortalSummary
  project : ClientProjectSummary
  binding : ExactBuildBinding
  review_master_url : String
  annotations : Array[ClientAnnotation]
  decisions : Array[ClientDecisionReceipt]
  revision_policy : RevisionPolicy
  delivery : ClientDelivery
  provider_data_included : Bool
  publication_authority : Bool
} derive(FromJson)

///|
struct AnnotationRequest {
  expected_master_sha256 : String
  expected_build_digest : String
  timecode_seconds : Double
  author : String
  body : String
} derive(ToJson)

///|
struct DecisionRequest {
  expected_master_sha256 : String
  expected_build_digest : String
  human_confirmed : Bool
  actor : String
  decision : String
  note : String
} derive(ToJson)
