///|
let supported_lepusa_version : String = "0.1.4"

///|
let studio_port : Int = 4302

///|
let studio_path : String = "/apps/mooncast/studio"

///|
let studio_readiness_path : String = "/health"

///|
let studio_executable : String = "mooncast-studio"

///|
let studio_release_source : String = "_build/native/release/build/cmd/studio/studio.exe"

///|
let rabbita_release_source : String = "ui/rabbita-mooncast/dist"

///|
let ffmpeg_release_source : String = ".tools/ffmpeg/darwin_arm64/ffmpeg"

///|
let ffmpeg_release_path : String = "tools/ffmpeg/darwin_arm64/ffmpeg"

///|
let ffprobe_release_source : String = ".tools/ffmpeg/darwin_arm64/ffprobe"

///|
let ffprobe_release_path : String = "tools/ffmpeg/darwin_arm64/ffprobe"

///|
fn json_object(text : String, context~ : String) -> Map[String, Json] {
  match (try! @json.parse(text)) {
    Object(object) => object
    _ => abort("\{context} must be a JSON object")
  }
}

///|
fn required_object(
  object : Map[String, Json],
  key : String,
) -> Map[String, Json] {
  match object.get(key) {
    Some(Object(value)) => value
    _ => abort("required JSON object is missing: \{key}")
  }
}

///|
fn required_array(object : Map[String, Json], key : String) -> Array[Json] {
  match object.get(key) {
    Some(Array(value)) => value
    _ => abort("required JSON array is missing: \{key}")
  }
}

///|
fn required_string(object : Map[String, Json], key : String) -> String {
  match object.get(key) {
    Some(String(value)) => value
    _ => abort("required JSON string is missing: \{key}")
  }
}

///|
fn required_int(object : Map[String, Json], key : String) -> Int {
  match object.get(key) {
    Some(value) => try! @json.from_json(value)
    None => abort("required JSON integer is missing: \{key}")
  }
}

///|
fn required_bool(object : Map[String, Json], key : String) -> Bool {
  match object.get(key) {
    Some(True) => true
    Some(False) => false
    _ => abort("required JSON boolean is missing: \{key}")
  }
}

///|
fn named_object(items : Array[Json], name : String) -> Map[String, Json] {
  for item in items {
    match item {
      Object(object) =>
        if object.get("name") is Some(String(found)) && found == name {
          return object
        }
      _ => ()
    }
  }
  abort("required named JSON object is missing: \{name}")
}

///|
fn string_array(object : Map[String, Json], key : String) -> Array[String] {
  required_array(object, key).map(fn(item) {
    match item {
      String(value) => value
      _ => abort("JSON array must contain only strings: \{key}")
    }
  })
}

///|
async fn release_inputs() -> (String, Map[String, Json], Map[String, Json]) {
  let lepusa_text = @fs.read_file("lepusa.json").text()
  let pack_text = @fs.read_file("pack.json").text()
  (
    lepusa_text,
    json_object(lepusa_text, context="lepusa.json"),
    json_object(pack_text, context="pack.json"),
  )
}

///|
async test "Lepusa release version is locked to the Mooncast pack" {
  let (_, release, pack) = release_inputs()
  assert_eq(
    required_string(release, "version"),
    required_string(pack, "version"),
  )
  assert_eq(supported_lepusa_version, "0.1.4")
  assert_eq(required_string(release, "identifier"), "dev.vectie.mooncast")
}

///|
async test "Studio uses the fixed loopback route and readiness contract" {
  let (_, release, _) = release_inputs()
  let window = required_object(release, "window")
  assert_eq(required_string(window, "label"), "studio")
  let localhost = required_object(
    required_object(window, "source"),
    "localhost",
  )
  assert_eq(required_string(localhost, "host"), "127.0.0.1")
  assert_eq(required_int(localhost, "port"), studio_port)
  assert_eq(required_string(localhost, "path"), studio_path)
  assert_eq(required_string(localhost, "readinessPath"), studio_readiness_path)
  let command = string_array(localhost, "command")
  assert_eq(command.length(), 1)
  assert_eq(command[0], studio_executable)
}

///|
async test "release grants only localhost and file-dialog access to Studio" {
  let (_, release, _) = release_inputs()
  let plugins = required_array(release, "plugins")
  ignore(named_object(plugins, "localhost"))
  ignore(named_object(plugins, "fileDialog"))
  assert_eq(plugins.length(), 2)
  let capability = named_object(
    required_array(release, "capabilities"),
    "studio",
  )
  let windows = string_array(capability, "windows")
  assert_eq(windows.length(), 1)
  assert_eq(windows[0], "studio")
  let permissions = string_array(capability, "permissions")
  assert_true(permissions.contains("localhost"))
  assert_true(permissions.contains("file-dialog"))
  assert_eq(permissions.length(), 2)
}

///|
async test "release carries a portable native Studio sidecar resource" {
  let (text, release, _) = release_inputs()
  let resources = required_array(release, "bundleResources")
  assert_eq(resources.length(), 4)
  guard resources[0] is Object(resource) else {
    fail("bundleResources entry must be an object")
  }
  assert_eq(required_string(resource, "source"), studio_release_source)
  assert_eq(required_string(resource, "path"), studio_executable)
  assert_true(required_bool(resource, "executable"))
  assert_false(text.contains("/Users/"))
  assert_false(text.contains("../lepusa"))
  assert_false(text.contains(".mooncakes/"))
  assert_false(text.contains("moon run"))
}

///|
async test "release carries the UI and executable media tools" {
  let (_, release, _) = release_inputs()
  let resources = required_array(release, "bundleResources")
  guard resources[1] is Object(rabbita) &&
    resources[2] is Object(ffmpeg) &&
    resources[3] is Object(ffprobe) else {
    fail("runtime bundle resources must be objects")
  }
  assert_eq(required_string(rabbita, "source"), rabbita_release_source)
  assert_eq(required_string(rabbita, "path"), rabbita_release_source)
  assert_eq(required_string(ffmpeg, "source"), ffmpeg_release_source)
  assert_eq(required_string(ffmpeg, "path"), ffmpeg_release_path)
  assert_true(required_bool(ffmpeg, "executable"))
  assert_eq(required_string(ffprobe, "source"), ffprobe_release_source)
  assert_eq(required_string(ffprobe, "path"), ffprobe_release_path)
  assert_true(required_bool(ffprobe, "executable"))
}

///|
async test "release baseline uses explicit ad-hoc signing for strict local gates" {
  let (_, release, _) = release_inputs()
  assert_eq(
    required_string(required_object(release, "signing"), "identity"),
    "-",
  )
}
