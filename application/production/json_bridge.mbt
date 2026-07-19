///|
pub fn new_production_request_from_json(
  input : StringView,
) -> NewProductionRequest raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn canonical_json_digest(value : Json) -> String {
  "sha256:" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value.stringify())))
}

///|
pub fn production_recorded_at() -> String {
  @runtime.wall_clock_ms().to_string()
}

///|
pub fn preview_brief_from_json(input : StringView) -> PreviewBrief raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn master_assembly_request_from_json(
  input : StringView,
) -> MasterAssemblyRequest raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn creative_revision_request_from_json(
  input : StringView,
) -> CreativeRevisionRequest raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn creative_decision_request_from_json(
  input : StringView,
) -> CreativeDecisionRequest raise {
  @json.from_json(@json.parse(input))
}

///|
pub fn master_provenance_to_json(value : MasterProvenance) -> String {
  value.to_json().stringify()
}

///|
pub fn preview_asset_to_json(value : PreviewAsset) -> String {
  value.to_json().stringify()
}
