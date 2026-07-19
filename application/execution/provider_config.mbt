///|
pub(all) struct ProviderAdapterConfig {
  adapter_id : String
  capability : String
  provider : String
  endpoint : String
  model : String
  api_style : String
  secret_refs : Map[String, String]
  timeout_seconds : Int
  max_response_bytes : Int
  default_parameters : Json
  commercial_use : String
  network_authority : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProviderCatalog {
  contract : String
  adapters : Array[ProviderAdapterConfig]
  authority_actors : Array[String]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProviderAdapterReadiness {
  adapter_id : String
  configured : Bool
  endpoint_https : Bool
  secret_reference_count : Int
  secrets_available : Bool
  commercial_use_recorded : Bool
  ready : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn env_name(reference : String) -> String? {
  guard reference.has_prefix("host-secret:") else { return None }
  let name = reference[12:].to_owned()
  if name.contains(":") ||
    name.contains("/") ||
    name.contains("-") ||
    name.contains(".") {
    return None
  }
  Some(name)
}

///|
fn adapter_ready(config : ProviderAdapterConfig) -> ProviderAdapterReadiness {
  let deterministic_fixture = config.api_style ==
    "mooncast-deterministic-ffmpeg-v1"
  let mut secrets_available = deterministic_fixture ||
    config.secret_refs.length() > 0
  for _, reference in config.secret_refs {
    match env_name(reference) {
      None => secrets_available = false
      Some(name) =>
        match @runtime.SecretRef::from_env(name) {
          None => secrets_available = false
          Some(secret) =>
            if secret.resolve() is None {
              secrets_available = false
            }
        }
    }
  }
  let endpoint_https = config.endpoint.has_prefix("https://")
  {
    adapter_id: config.adapter_id,
    configured: config.adapter_id != "" &&
    config.provider != "" &&
    config.model != "",
    endpoint_https,
    secret_reference_count: config.secret_refs.length(),
    secrets_available,
    commercial_use_recorded: config.commercial_use != "",
    ready: endpoint_https &&
    secrets_available &&
    config.timeout_seconds > 0 &&
    config.max_response_bytes > 0 &&
    !config.network_authority &&
    (!deterministic_fixture || config.secret_refs.is_empty()),
    publication_authority: false,
  }
}

///|
pub fn ProviderCatalog::readiness(
  self : ProviderCatalog,
) -> Array[ProviderAdapterReadiness] {
  self.adapters.map(adapter_ready)
}

///|
pub fn ProviderCatalog::find(
  self : ProviderCatalog,
  adapter_id : String,
  capability : String,
) -> ProviderAdapterConfig? {
  for adapter in self.adapters {
    if adapter.adapter_id == adapter_id && adapter.capability == capability {
      return Some(adapter)
    }
  }
  None
}

///|
pub fn ProviderCatalog::resolve(
  self : ProviderCatalog,
  adapter_id : String,
  capability? : String,
) -> ProviderAdapterConfig? {
  for adapter in self.adapters {
    let capability_matches = match capability {
      None => true
      Some(value) => adapter.capability == value
    }
    if adapter.adapter_id == adapter_id && capability_matches {
      return Some(adapter)
    }
  }
  None
}

///|
pub fn ProviderAdapterConfig::public_readiness(
  self : ProviderAdapterConfig,
) -> ProviderAdapterReadiness {
  adapter_ready(self)
}

///|
pub fn provider_plan_digest(plan : ProviderHttpPlan) -> String {
  let core = plan.request_id +
    ":" +
    plan.adapter_id +
    ":" +
    plan.capability +
    ":" +
    plan.endpoint +
    ":" +
    plan.model +
    ":" +
    plan.body.stringify() +
    ":" +
    plan.cost_ceiling_cny.to_string()
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(core)))
}

///|
pub fn ProviderAdapterConfig::request_plan(
  self : ProviderAdapterConfig,
  request_id : String,
  body : Json,
  cost_ceiling_cny : Double,
) -> ProviderHttpPlan? {
  if request_id == "" ||
    cost_ceiling_cny < 0.0 ||
    self.network_authority ||
    !self.endpoint.has_prefix("https://") {
    return None
  }
  let core = request_id +
    ":" +
    self.adapter_id +
    ":" +
    self.capability +
    ":" +
    self.endpoint +
    ":" +
    self.model +
    ":" +
    body.stringify() +
    ":" +
    cost_ceiling_cny.to_string()
  Some({
    contract: "mooncast.provider-request-plan.v1",
    request_id,
    adapter_id: self.adapter_id,
    capability: self.capability,
    provider: self.provider,
    endpoint: self.endpoint,
    request_method: "POST",
    model: self.model,
    api_style: self.api_style,
    secret_refs: self.secret_refs,
    timeout_seconds: self.timeout_seconds,
    body,
    cost_ceiling_cny,
    network_authority: false,
    publication_authority: false,
    plan_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(core))),
  })
}
