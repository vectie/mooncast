///|
pub(all) struct ProviderRequestPlan {
  contract : String
  request_id : String
  adapter_id : String
  capability : String
  provider : String
  endpoint : String
  request_method : String
  model : String
  timeout_seconds : Int
  max_attempts : Int
  cost_ceiling_cny : Double
  secret_refs : Array[String]
  input_digest : String
  plan_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderExecutionAuthority {
  actor_id : String
  authority_receipt_digest : String
  network_authority : Bool
  publication_authority : Bool
  external_effect_performed_by_reducer : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderAttemptPhase {
  attempt_id : String
  phase : String
  state : String
  start_timestamp : String?
  end_timestamp : String?
  error_code : String?
  error_message : String?
  phase_digest : String
  usage_cost_receipt_digest : String?
  attachment_receipt_digest : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderResultArtifact {
  artifact_id : String
  kind : String
  artifact_digest : String
  media_type : String
  bytes : Int
  rights_refs : Array[String]
  provider_receipt_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderExecutionJob {
  contract : String
  job_id : String
  state : String
  revision : Int
  plan : ProviderRequestPlan
  plan_digest : String
  config_digest : String
  binding_digest : String
  authority : ProviderExecutionAuthority
  attempt_count : Int
  max_attempts : Int
  attempt_history : Array[ProviderAttemptPhase]
  artifacts : Array[ProviderResultArtifact]
  spent_cny : Double
  last_error_code : String?
  last_error_message : String?
  project_ingest_digest : String?
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderExecutionEvent {
  contract : String
  event_id : String
  kind : String
  recorded_at : String
  evidence_digest : String
  attempt : ProviderAttemptPhase?
  artifacts : Array[ProviderResultArtifact]
  cost_cny : Double?
  project_ingest_digest : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderExecutionCommand {
  contract : String
  command_id : String
  action : String
  actor_id : String
  recorded_at : String
  evidence_digest : String
  expected_revision : Int
  job : ProviderExecutionJob
  attempt : ProviderAttemptPhase?
  artifacts : Array[ProviderResultArtifact]
  cost_cny : Double?
  project_ingest_digest : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderExecutionResult {
  contract : String
  command_id : String
  ok : Bool
  error_code : String?
  job : ProviderExecutionJob
  events : Array[ProviderExecutionEvent]
  external_effect_performed : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)
