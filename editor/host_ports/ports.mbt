///|
pub(open) trait EditorClock {
  fn now_rfc3339(Self) -> String
}

///|
pub(open) trait EditorIdSource {
  fn next_id(Self, scope~ : String) -> String
}

///|
pub(all) struct ResolvedContent {
  digest : String
  content_key : String
  safe_path : String
  size_bytes : Int
  mime_type : String
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(open) trait ContentPathResolver {
  fn resolve_content(Self, digest~ : String) -> ResolvedContent?
}

///|
pub(all) struct ContentWriteRequest {
  content_key : String
  expected_digest : String
  mime_type : String
  temporary_path : String
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ContentWriteReceipt {
  content_key : String
  digest : String
  size_bytes : Int
  safe_path : String
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(open) trait ContentMaterializer {
  fn materialize_content(Self, request~ : ContentWriteRequest) -> ContentWriteReceipt
}

///|
pub(all) struct FileReadRequest {
  safe_path : String
  maximum_bytes : Int
  expected_digest : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(open) trait EditorFileReader {
  fn read_file(Self, request~ : FileReadRequest) -> Bytes
}

///|
pub(all) struct MediaToolPort {
  ffmpeg : String
  ffprobe : String
  provider_ref : String
  provider_version : String
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct JobWakeRequest {
  project_id : String
  job_id : String
  kind : String
  observation_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(open) trait EditorWorkerWakePort {
  fn wake(Self, request~ : JobWakeRequest) -> Unit
}

///|
pub(all) struct EditorCliRequest {
  command : String
  payload_path : String
  output_root : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(open) trait EditorCliPort {
  fn submit_cli(Self, request~ : EditorCliRequest) -> Int
}

///|
pub(all) struct StreamDescriptor {
  transport : String
  path_template : String
  event_contract : String
  heartbeat_seconds : Int
  replay_cursor_parameter : String
} derive(Debug, Eq, ToJson, FromJson)
