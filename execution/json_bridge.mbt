///|
pub fn provider_command_json(input : StringView) -> String raise {
  let command : ProviderExecutionCommand = @json.from_json(@json.parse(input))
  reduce_provider_command(command).to_json().stringify()
}

///|
pub fn delivery_command_json(input : StringView) -> String raise {
  let command : DeliveryBuildCommand = @json.from_json(@json.parse(input))
  reduce_delivery_command(command).to_json().stringify()
}
