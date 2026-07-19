///|
#cfg(not(platform="windows"))
pub let platform_name : String = "posix-macos-linux"

///|
#cfg(platform="windows")
pub let platform_name : String = "windows-unsupported"

///|
/// A reference to a host environment variable. It deliberately has no Debug
/// derivation so resolved secret material is not rendered accidentally.
pub struct SecretRef {
  env_name : String
}

///|
pub fn SecretRef::from_env(env_name : String) -> SecretRef? {
  guard !env_name.is_empty() else { return None }
  for index, char in env_name {
    let valid = match char {
      'A'..='Z' | '0'..='9' | '_' => true
      _ => false
    }
    if !valid || (index == 0 && char is ('0'..='9')) {
      return None
    }
  }
  Some({ env_name, })
}

///|
pub fn SecretRef::name(self : SecretRef) -> String {
  self.env_name
}

///|
pub fn SecretRef::resolve(self : SecretRef) -> String? {
  @env.get_env_var(self.env_name)
}

///|
pub fn wall_clock_ms() -> Int64 {
  @clock.epoch.now().ms()
}

///|
/// Generate a non-semantic identifier from the OS CSPRNG. No model, process,
/// hostname, or secret is incorporated into the identifier.
#warnings("-alert_internal")
pub fn new_id(prefix? : String = "mc") -> String raise {
  let random = @tls.rand_bytes(16)
  prefix +
  "_" +
  @crypto.bytes_to_hex_string(@crypto.sha256(random))[:32].to_owned()
}

///|
pub fn is_supported_platform() -> Bool {
  platform_name == "posix-macos-linux"
}

///|
pub fn runtime_json() -> String {
  let supported = if is_supported_platform() { "true" } else { "false" }
  "{\"runtime\":\"moonbit-native\",\"platform\":\"" +
  platform_name +
  "\",\"supported\":" +
  supported +
  ",\"capabilities\":[\"http\",\"rabbita-release-host\",\"static-range\",\"atomic-store\",\"subprocess\",\"https-json\",\"canonical-project-api\",\"g3-g7-governance\",\"editor-workspaces\",\"media-analysis\",\"preview-export\",\"provider-execution\",\"delivery-factory\",\"commercial-portal\",\"outbound-handoff-evidence\"]}"
}
