///|
fn[T : ToJson] intake_digest(value : T) -> String {
  "sha256:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(value.to_json().stringify())),
  )
}

///|
fn safe_file_name(value : String) -> Bool {
  !value.is_blank() &&
  value.length() <= 255 &&
  !value.contains("/") &&
  !value.contains("\\")
}

///|
fn allowed_intake_mime(role : String, mime : String) -> Bool {
  match role {
    "voice" | "music" | "SFX" => mime.has_prefix("audio/")
    "subtitle" =>
      mime == "text/plain" ||
      mime == "text/vtt" ||
      mime == "application/x-subrip"
    "image" | "logo" =>
      mime == "image/png" || mime == "image/jpeg" || mime == "image/webp"
    _ => false
  }
}

///|
/// Freezes all source and rights evidence before the host accepts bytes.
pub fn prepare_intake(
  project : @domain.EditorProject,
  expected_revision : Int,
  idempotency_key : String,
  role : String,
  file_name : String,
  mime_type : String,
  size_bytes : Int,
  sha256 : String,
  duration_ticks : Int,
  identity : @domain.ProductionIdentity,
  rights : @domain.RightsAttestation,
  source : @domain.MediaSourceAttestation,
  created_by : String,
  created_at : String,
) -> PreparedIntake raise {
  guard project.revision == expected_revision else {
    fail("editor revision conflict")
  }
  guard !idempotency_key.is_blank() && idempotency_key.length() <= 160 else {
    fail("invalid intake idempotency key")
  }
  guard safe_file_name(file_name) && allowed_intake_mime(role, mime_type) else {
    fail("unsupported local media")
  }
  guard size_bytes > 0 && size_bytes <= 67108864 && duration_ticks > 0 else {
    fail("local media bounds are invalid")
  }
  guard sha256.has_prefix("sha256:") && sha256.length() == 71 else {
    fail("local media digest is invalid")
  }
  guard project.identity_graph.contains(identity) else {
    fail("local media identity is outside the project")
  }
  guard rights.confirmed &&
    !rights.rights_ref.is_blank() &&
    !rights.owner.is_blank() &&
    !rights.basis.is_blank() &&
    !rights.territory.is_blank() &&
    !rights.channels.is_empty() else {
    fail("local media rights are incomplete")
  }
  guard source.kind == "customer-owned" ||
    source.kind == "licensed" ||
    source.kind == "original" else {
    fail("local media source is unsupported")
  }
  guard !source.source_id.is_blank() && !created_by.is_blank() else {
    fail("local media source and actor are required")
  }
  let provisional : IntakeRequest = {
    contract: "mooncast.editor-local-media-intake.v1",
    project_id: project.project_id,
    expected_editor_revision: expected_revision,
    idempotency_key,
    role,
    file_name,
    mime_type,
    size_bytes,
    sha256,
    duration_ticks,
    identity,
    rights,
    source,
    created_by,
    created_at,
    request_digest: "",
  }
  let request = { ..provisional, request_digest: intake_digest(provisional) }
  let intake_id = "intake-" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(
        @utf8.encode(project.project_id + "\u{0000}" + idempotency_key),
      ),
    )[:20].to_owned()
  {
    contract: request.contract,
    intake_id,
    request,
    status: "awaiting-content",
    upload_path: "/api/editor/projects/" +
    project.project_id +
    "/media-intakes/" +
    intake_id +
    "/content",
    publication_authority: false,
    provider_authority: false,
  }
}

///|
pub async fn complete_intake(
  registry : MediaRegistry,
  request : IntakeRequest,
  bytes : Bytes,
  ticks_per_second : Int,
  intake_id : String,
  media_ref_id : String,
  receipt_digest : String,
) -> CompletedIntake {
  guard request.contract == "mooncast.editor-local-media-intake.v1" else {
    fail("unsupported local media intake contract")
  }
  guard request.rights.confirmed else { fail("rights attestation is required") }
  guard bytes.length() == request.size_bytes else {
    fail("local media size mismatch")
  }
  let record = registry.ingest(
    bytes,
    request.mime_type,
    Some(request.duration_ticks.to_double() / ticks_per_second.to_double()),
    "original",
    Some(request.sha256),
    [request.source.source_id],
    [request.request_digest, "local-intake:" + intake_id],
    [request.rights.rights_ref],
    request.created_at,
  )
  guard record.digest == request.sha256 else {
    fail("local media digest mismatch")
  }
  let track_kind = if request.role == "image" ||
    request.role == "logo" ||
    request.role == "subtitle" {
    "overlay"
  } else {
    "audio"
  }
  let receipt : @domain.LocalMediaReceipt = {
    contract: request.contract,
    intake_id,
    project_id: request.project_id,
    expected_editor_revision: request.expected_editor_revision,
    idempotency_key: request.idempotency_key,
    role: request.role,
    file_name: request.file_name,
    mime_type: request.mime_type,
    size_bytes: request.size_bytes,
    sha256: request.sha256,
    duration_ticks: request.duration_ticks,
    identity: request.identity,
    rights: request.rights,
    source: request.source,
    created_by: request.created_by,
    request_digest: request.request_digest,
    status: "completed",
    created_at: request.created_at,
    completed_at: request.created_at,
    media_ref_id,
    registry_digest: record.digest,
    track_id: "",
    track_kind,
    publication_authority: false,
    provider_authority: false,
  }
  let binding : @domain.LocalMediaBinding = {
    contract: "mooncast.editor-local-media-binding.v1",
    project_id: request.project_id,
    intake_id,
    intake_receipt_digest: receipt_digest,
    intake_receipt: receipt,
    request_digest: request.request_digest,
    role: request.role,
    rights_ref: request.rights.rights_ref,
    media_digest: record.digest,
    parser_version: "",
    cue_digest: "",
    cues: [],
    width: 0,
    height: 0,
    inspector_version: "",
  }
  let processed_binding = if request.role == "subtitle" {
    binding_with_subtitles(
      binding,
      parse_subtitles(
        bytes,
        request.mime_type,
        request.duration_ticks,
        ticks_per_second,
      ),
    )
  } else if request.role == "image" || request.role == "logo" {
    binding_with_visual(binding, inspect_visual(bytes, request.mime_type))
  } else {
    binding
  }
  let media_ref : @domain.MediaRef = {
    contract: "mooncast.editor-media-ref.v1",
    media_ref_id,
    locator: { kind: "pack-relative", uri: record.locator },
    metadata: {
      sha256: digest_key(record.digest),
      mime_type: record.mime,
      size_bytes: record.size,
      duration_ticks: request.duration_ticks,
    },
  }
  { receipt, binding: processed_binding, media_ref, media_record: record }
}
