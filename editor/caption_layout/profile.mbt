///|
/// Editorial preferences, not an accessibility certification or delivery gate.
pub(all) struct Profile {
  contract : String
  max_line_chars : Int
  max_lines : Int
  min_duration_ms : Int
  max_chars_per_second : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A starting point for manual review; adapt it to the language and audience.
pub fn default_profile() -> Profile {
  {
    contract: "mooncast.caption-layout-profile.v1",
    max_line_chars: 42,
    max_lines: 2,
    min_duration_ms: 1000,
    max_chars_per_second: 20,
  }
}

///|
pub fn Profile::validate(self : Profile) -> Unit raise {
  guard self.contract == "mooncast.caption-layout-profile.v1" else {
    fail("unsupported caption layout profile contract")
  }
  guard self.max_line_chars >= 8 && self.max_line_chars <= 120 else {
    fail("max_line_chars must be between 8 and 120")
  }
  guard self.max_lines >= 1 && self.max_lines <= 4 else {
    fail("max_lines must be between 1 and 4")
  }
  guard self.min_duration_ms >= 1 && self.min_duration_ms <= 10000 else {
    fail("min_duration_ms must be between 1 and 10000")
  }
  guard self.max_chars_per_second >= 1 && self.max_chars_per_second <= 100 else {
    fail("max_chars_per_second must be between 1 and 100")
  }
}

///|
pub fn read_profile(text : String) -> Profile raise {
  let profile : Profile = @json.from_json(@json.parse(text))
  profile.validate()
  profile
}
