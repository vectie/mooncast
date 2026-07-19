///|
pub(all) struct ProviderHttpPlan {
  contract : String
  request_id : String
  adapter_id : String
  capability : String
  provider : String
  endpoint : String
  request_method : String
  model : String
  api_style : String
  secret_refs : Map[String, String]
  timeout_seconds : Int
  body : Json
  cost_ceiling_cny : Double
  network_authority : Bool
  publication_authority : Bool
  plan_digest : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProviderAuthorityReceipt {
  contract : String
  receipt_id : String
  actor_id : String
  decision : String
  plan_digest : String
  config_digest : String
  cost_ceiling_cny : Double
  max_attempts : Int
  network_authority : Bool
  publication_authority : Bool
  granted_at : String
  receipt_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderJobRecord {
  contract : String
  job : @execution_domain.ProviderExecutionJob
  http_plan : ProviderHttpPlan
  response_digest : String?
  host_effect_receipts : Array[ProviderHostEffectReceipt]
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProviderHostEffectReceipt {
  contract : String
  request_id : String
  attempt_id : String
  endpoint_origin_digest : String
  response_digest : String?
  state : String
  performed_at : String
  network_effect_performed : Bool
  publication_effect_performed : Bool
  secret_values_persisted : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderExecutionCapabilities {
  contract : String
  adapters : Array[ProviderAdapterReadiness]
  authority_actor_count : Int
  secret_resolver_connected : Bool
  json_post_transport_connected : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderWireArtifact {
  modality : String
  text : String?
  content_base64 : String?
  mime_type : String?
  duration_seconds : Double?
  source_refs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderWireCost {
  currency : String
  amount : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderWireResult {
  contract : String
  artifacts : Array[ProviderWireArtifact]
  usage : Json
  cost : ProviderWireCost
  provider_receipt : Json
} derive(Debug, ToJson, FromJson)

///|
pub suberror ProviderApplicationError {
  InvalidPlan(String)
  AuthorityDenied(String)
  AdapterUnavailable(String)
  JobNotFound(String)
  JobCorrupt(String)
  HostNotReady(String)
  ProviderResponseInvalid(String)
} derive(Debug)
