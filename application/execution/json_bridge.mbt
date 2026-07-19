///|
pub fn provider_catalog_from_json(input : StringView) -> ProviderCatalog raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn provider_plan_from_json(input : StringView) -> ProviderHttpPlan raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn provider_authority_from_json(
  input : StringView,
) -> ProviderAuthorityReceipt raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn delivery_build_request_from_json(
  input : StringView,
) -> DeliveryBuildRequest raise {
  @json.from_json(@json.parse(input))
}
