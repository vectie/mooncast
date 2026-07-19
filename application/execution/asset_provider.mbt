///|
pub(all) struct AssetProviderRequest {
  contract : String
  request_id : String
  project_id : String
  project_revision : Int
  asset_id : String
  asset_version : Int
  variant : Int
  kind : String
  capability : String
  intent_ref : String
  prompt_digest : String
  source_asset_refs : Array[String]
  rights_refs : Array[String]
  continuity_key : String
  adapter_id : String
  provider : String
  model : String
  permitted_data_class : String
  cost_ceiling_cny : Double
  retry_limit : Int
  parameters : Json
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub async fn ProviderExecutionService::authorize_asset_from_catalog(
  self : ProviderExecutionService,
  request : AssetProviderRequest,
  actor_id : String,
  network_authority : Bool,
) -> ProviderJobRecord {
  guard request.contract == "mooncast.asset-provider-request.v1" &&
    request.request_id != "" &&
    request.project_id != "" &&
    request.project_revision >= 0 &&
    request.asset_id != "" &&
    request.asset_version > 0 &&
    request.variant > 0 &&
    request.kind != "" &&
    request.capability != "" &&
    request.intent_ref != "" &&
    request.prompt_digest != "" &&
    !request.rights_refs.is_empty() &&
    request.continuity_key != "" &&
    request.retry_limit > 0 &&
    request.retry_limit <= 5 &&
    request.cost_ceiling_cny >= 0.0 &&
    !request.publication_authority &&
    network_authority else {
    raise InvalidPlan("asset provider request or authority is invalid")
  }
  guard self.catalog.find(request.adapter_id, request.capability)
    is Some(config) &&
    config.provider == request.provider &&
    config.model == request.model else {
    raise AdapterUnavailable(request.adapter_id + ":" + request.capability)
  }
  let plan = config
    .request_plan(
      request.request_id,
      request.to_json(),
      request.cost_ceiling_cny,
    )
    .unwrap_or_else(() => {
      raise InvalidPlan("provider catalog could not materialize asset request")
    })
  let granted_at = now()
  let authority : ProviderAuthorityReceipt = {
    contract: "mooncast.provider-execution-authority.v1",
    receipt_id: "asset-provider-authority:" + request.request_id,
    actor_id,
    decision: "authorize",
    plan_digest: plan.plan_digest,
    config_digest: config_digest(config),
    cost_ceiling_cny: request.cost_ceiling_cny,
    max_attempts: request.retry_limit,
    network_authority: true,
    publication_authority: false,
    granted_at,
    receipt_digest: "",
  }
  let exact = {
    ..authority,
    receipt_digest: provider_authority_receipt_digest(authority),
  }
  self.authorize(plan, exact)
}
