///|
pub(all) struct DeliveryBuildRequest {
  contract : String
  project_id : String
  expected_project_revision : Int
  master_path : String
  master_sha256 : String
  master_promotion_digest : String
  master_duration_seconds : Double
  delivery_version : Int
  delivery_digest : String
  profile : @execution_domain.DeliveryBuildProfile
  subtitle_path : String?
  project_metadata : Json?
  provenance_manifest : Json?
  rights_ledger : Json?
  acceptance_receipt : Json?
  ai_label : String?
  g5_accepted : Bool
  client_accepted : Bool
  evidence_digest : String
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryFactoryRecord {
  contract : String
  build : @execution_domain.DeliveryBuild
  request : DeliveryBuildRequest
  manifest_key : String?
  updated_at : String
  process_effect_performed : Bool
  publication_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryArtifactManifest {
  contract : String
  build_id : String
  build_digest : String
  master_sha256 : String
  master_promotion_digest : String
  delivery_digest : String
  profile_digest : String
  artifacts : Array[@execution_domain.DeliveryBuildArtifact]
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CustomerDeliveryManifest {
  contract : String
  build_id : String
  build_digest : String
  project_id : String
  project_revision : Int
  master_sha256 : String
  master_promotion_digest : String
  delivery_digest : String
  profile_digest : String
  ai_label : String
  artifacts : Array[@execution_domain.DeliveryBuildArtifact]
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryAcceptanceRecord {
  contract : String
  acceptance : @execution_domain.DeliveryBuildAcceptance
  publication_authority : Bool
  external_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror DeliveryApplicationError {
  DeliveryRequestInvalid(String)
  DeliveryBuildNotFound(String)
  DeliveryBuildConflict(String)
  DeliveryProcessFailed(String)
  DeliveryArtifactMissing(String)
} derive(Debug)

///|
pub struct DeliveryFactoryService {
  state : @store.AtomicStore
  outputs : @store.AtomicStore
  output_root : String
  ffmpeg_executable : String
  zip_executable : String
}

///|
pub fn DeliveryFactoryService::new(
  state_root : String,
  output_root : String,
  ffmpeg_executable : String,
  zip_executable? : String = "zip",
) -> DeliveryFactoryService {
  {
    state: @store.AtomicStore::new(state_root, max_read_bytes=16777216),
    outputs: @store.AtomicStore::new(output_root),
    output_root,
    ffmpeg_executable,
    zip_executable,
  }
}

///|
fn delivery_key(build_id : String) -> String {
  "delivery-build-" + build_id + ".json"
}

///|
fn safe_output_id(value : String) -> Bool {
  if value == "" {
    return false
  }
  for char in value {
    match char {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' => ()
      _ => return false
    }
  }
  true
}

///|
fn output_kind_valid(output : @execution_domain.DeliveryOutputSpec) -> Bool {
  match output.kind {
    "source-master" =>
      output.container == "mp4" &&
      output.source_output_id == None &&
      output.in_seconds == None &&
      output.out_seconds == None &&
      output.timestamp_seconds == None
    "platform-variant" =>
      output.container == "mp4" &&
      output.width >= 240 &&
      output.width <= 3840 &&
      output.height >= 240 &&
      output.height <= 3840 &&
      output.width % 2 == 0 &&
      output.height % 2 == 0 &&
      (
        (
          output.orientation == Some("horizontal") &&
          output.width >= output.height
        ) ||
        (output.orientation == Some("vertical") && output.height > output.width)
      ) &&
      (
        output.framing_policy == Some("crop") ||
        output.framing_policy == Some("pad") ||
        output.framing_policy == Some("scale")
      ) &&
      output.source_output_id == None
    "channel-cut" =>
      output.container == "mp4" &&
      output.source_output_id != None &&
      (match (output.in_seconds, output.out_seconds) {
        (Some(start), Some(finish)) =>
          start >= 0.0 && finish > start && finish - start <= 180.0
        _ => false
      })
    "cover-frame" =>
      (output.container == "jpg" || output.container == "png") &&
      output.source_output_id != None &&
      (match output.timestamp_seconds {
        Some(value) => value >= 0.0
        None => false
      })
    _ => false
  }
}

///|
fn delivery_profile_valid(
  profile : @execution_domain.DeliveryBuildProfile,
  master_duration_seconds : Double,
) -> Bool {
  if profile.contract != "mooncast.delivery-build-profile.v1" ||
    profile.profile_version < 1 ||
    profile.profile_digest == "" ||
    profile.outputs.length() == 0 ||
    profile.outputs.length() > 29 ||
    !profile.include_provenance_manifest ||
    !profile.include_rights_ledger ||
    !profile.include_acceptance_receipt {
    return false
  }
  let ids : Array[String] = []
  let variant_ids : Array[String] = ["master"]
  let mut source_master_count = 0
  let mut variant_count = 0
  let mut cut_count = 0
  let mut cover_count = 0
  for output in profile.outputs {
    if output.kind == "platform-variant" {
      variant_ids.push(output.output_id)
    }
  }
  for output in profile.outputs {
    if !safe_output_id(output.output_id) ||
      ids.contains(output.output_id) ||
      !output_kind_valid(output) {
      return false
    }
    ids.push(output.output_id)
    match output.kind {
      "source-master" => source_master_count = source_master_count + 1
      "platform-variant" => variant_count = variant_count + 1
      "channel-cut" => {
        cut_count = cut_count + 1
        let source = output.source_output_id.unwrap_or("")
        if !variant_ids.contains(source) {
          return false
        }
        match output.out_seconds {
          Some(value) if value > master_duration_seconds => return false
          _ => ()
        }
      }
      "cover-frame" => {
        cover_count = cover_count + 1
        let source = output.source_output_id.unwrap_or("")
        if !variant_ids.contains(source) {
          return false
        }
        match output.timestamp_seconds {
          Some(value) if value > master_duration_seconds => return false
          _ => ()
        }
      }
      _ => return false
    }
  }
  source_master_count <= 1 &&
  variant_count <= 8 &&
  cut_count <= 12 &&
  cover_count <= 8
}

///|
fn normalized_sha256(value : String) -> String {
  if value.has_prefix("sha256:") {
    value[7:].to_owned()
  } else {
    value
  }
}

///|
fn seal_delivery_build(
  build : @execution_domain.DeliveryBuild,
) -> @execution_domain.DeliveryBuild {
  let unsealed = { ..build, record_digest: "" }
  {
    ..build,
    record_digest: sha256(@utf8.encode(unsealed.to_json().stringify())),
  }
}

///|
pub async fn DeliveryFactoryService::create(
  self : DeliveryFactoryService,
  request : DeliveryBuildRequest,
) -> DeliveryFactoryRecord {
  if request.contract != "mooncast.delivery-build-request.v1" ||
    request.project_id == "" ||
    request.expected_project_revision < 1 ||
    request.master_path == "" ||
    request.master_sha256 == "" ||
    request.master_promotion_digest == "" ||
    request.master_duration_seconds < 1.0 ||
    request.delivery_version < 1 ||
    request.delivery_digest == "" ||
    !delivery_profile_valid(request.profile, request.master_duration_seconds) ||
    request.provenance_manifest == None ||
    request.rights_ledger == None ||
    request.acceptance_receipt == None ||
    request.ai_label == None ||
    (
      request.profile.outputs.any(output => output.subtitle_mode == "sidecar") &&
      request.subtitle_path == None
    ) {
    raise DeliveryRequestInvalid(
      "exact accepted master, delivery, and bounded profile are required",
    )
  }
  let build_digest = sha256(
    @utf8.encode(
      request.project_id +
      ":" +
      request.master_sha256 +
      ":" +
      request.master_promotion_digest +
      ":" +
      request.delivery_digest +
      ":" +
      request.profile.profile_digest,
    ),
  )
  let build_id = "delivery-build-" + build_digest[7:31].to_owned()
  match self.load(build_id) {
    Some(existing) => {
      if existing.request != request {
        raise DeliveryBuildConflict(build_id)
      }
      return existing
    }
    None => ()
  }
  let unsealed_build : @execution_domain.DeliveryBuild = {
    contract: "mooncast.delivery-build.v1",
    build_id,
    build_digest,
    project_id: request.project_id,
    project_revision: request.expected_project_revision,
    master_sha256: request.master_sha256,
    delivery_version: request.delivery_version,
    delivery_digest: request.delivery_digest,
    profile: request.profile,
    state: "queued",
    revision: 1,
    attempt_count: 0,
    recovery_count: 0,
    artifacts: [],
    archive: None,
    economics_receipt_digest: None,
    last_error_code: None,
    created_at: request.created_at,
    updated_at: request.created_at,
    publication_authority: false,
    record_digest: "",
  }
  let build = seal_delivery_build(unsealed_build)
  let record : DeliveryFactoryRecord = {
    contract: "mooncast.delivery-factory-record.v1",
    build,
    request,
    manifest_key: None,
    updated_at: now(),
    process_effect_performed: false,
    publication_effect_performed: false,
  }
  ignore(self.state.put_json(delivery_key(build_id), record.to_json()))
  record
}

///|
pub async fn DeliveryFactoryService::load(
  self : DeliveryFactoryService,
  build_id : String,
) -> DeliveryFactoryRecord? {
  match self.state.get_json(delivery_key(build_id)) {
    None => None
    Some(value) => {
      let record : DeliveryFactoryRecord = @json.from_json(value) catch {
        _ => raise DeliveryBuildNotFound(build_id)
      }
      Some(record)
    }
  }
}

///|
pub async fn DeliveryFactoryService::invalidate_if_stale(
  self : DeliveryFactoryService,
  build_id : String,
  current_project_revision : Int,
  current_master_sha256 : String,
  current_delivery_version : Int,
  current_delivery_digest : String,
) -> DeliveryFactoryRecord {
  let record = match self.load(build_id) {
    None => raise DeliveryBuildNotFound(build_id)
    Some(value) => value
  }
  let stale = record.build.project_revision != current_project_revision ||
    record.build.master_sha256 != current_master_sha256 ||
    record.build.delivery_version != current_delivery_version ||
    record.build.delivery_digest != current_delivery_digest
  if !stale || record.build.state == "invalidated" {
    return record
  }
  let result = @execution_domain.reduce_delivery_command(
    delivery_command(record, "invalidate"),
  )
  if !result.ok {
    raise DeliveryBuildConflict(
      result.error_code.unwrap_or("delivery_invalidation_failed"),
    )
  }
  let durable = {
    ..record,
    build: seal_delivery_build(result.build),
    updated_at: now(),
  }
  self.save(durable)
  durable
}

///|
pub async fn DeliveryFactoryService::list(
  self : DeliveryFactoryService,
  project_id : String,
) -> Array[@execution_domain.DeliveryBuild] {
  let builds : Array[@execution_domain.DeliveryBuild] = []
  for key in self.state.list_keys(prefix="delivery-build-", suffix=".json") {
    match self.state.get_json(key) {
      Some(value) => {
        let record : DeliveryFactoryRecord = @json.from_json(value) catch {
          _ => continue
        }
        if record.build.project_id == project_id {
          builds.push(record.build)
        }
      }
      None => ()
    }
  }
  builds
}

///|
async fn DeliveryFactoryService::save(
  self : DeliveryFactoryService,
  record : DeliveryFactoryRecord,
) -> Unit {
  ignore(
    self.state.put_json(delivery_key(record.build.build_id), record.to_json()),
  )
}

///|
fn delivery_command(
  record : DeliveryFactoryRecord,
  action : String,
  artifacts? : Array[@execution_domain.DeliveryBuildArtifact] = [],
  archive? : @execution_domain.DeliveryBuildArtifact,
  economics_receipt_digest? : String,
  error_code? : String,
) -> @execution_domain.DeliveryBuildCommand raise {
  {
    contract: "mooncast.delivery-build-command.v1",
    command_id: @runtime.new_id(prefix="delivery-command"),
    action,
    expected_revision: record.build.revision,
    recorded_at: now(),
    evidence_digest: record.request.evidence_digest,
    build: record.build,
    artifacts,
    archive,
    economics_receipt_digest,
    error_code,
  }
}

///|
fn video_output_args(
  source_path : String,
  output_path : String,
  output : @execution_domain.DeliveryOutputSpec,
) -> Array[String] {
  let seek : Array[String] = match output.timestamp_seconds {
    Some(value) => ["-ss", value.to_string()]
    None =>
      match output.in_seconds {
        Some(value) => ["-ss", value.to_string()]
        None => []
      }
  }
  let duration : Array[String] = match (output.in_seconds, output.out_seconds) {
    (Some(start), Some(finish)) => ["-t", (finish - start).to_string()]
    _ => []
  }
  match output.kind {
    "source-master" =>
      ["-y", "-i", source_path, "-map", "0", "-c", "copy", output_path]
    "platform-variant" => {
      let size = output.width.to_string() + ":" + output.height.to_string()
      let filter = match output.framing_policy {
        Some("crop") =>
          "scale=" + size + ":force_original_aspect_ratio=increase,crop=" + size
        Some("pad") =>
          "scale=" +
          size +
          ":force_original_aspect_ratio=decrease,pad=" +
          size +
          ":(ow-iw)/2:(oh-ih)/2:black"
        _ => "scale=" + size
      }
      [
        "-y",
        "-i",
        source_path,
        "-map",
        "0:v:0",
        "-map",
        "0:a?",
        "-vf",
        filter,
        "-c:v",
        output.codec,
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-movflags",
        "+faststart",
        output_path,
      ]
    }
    "channel-cut" =>
      [
        "-y",
        ..seek,
        "-i",
        source_path,
        ..duration,
        "-map",
        "0:v:0",
        "-map",
        "0:a?",
        "-c:v",
        output.codec,
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-movflags",
        "+faststart",
        output_path,
      ]
    "cover-frame" =>
      ["-y", ..seek, "-i", source_path, "-frames:v", "1", output_path]
    _ => []
  }
}

///|
fn subtitle_copy_args(
  source_path : String,
  output_path : String,
) -> Array[String] {
  ["-y", "-i", source_path, "-map", "0:s:0", "-c:s", "copy", output_path]
}

///|
fn source_path_for(
  source_output_id : String?,
  master_path : String,
  sources : Array[(String, String)],
) -> String raise DeliveryApplicationError {
  let source_id = source_output_id.unwrap_or("master")
  if source_id == "master" {
    return master_path
  }
  for pair in sources {
    if pair.0 == source_id {
      return pair.1
    }
  }
  raise DeliveryRequestInvalid(
    "delivery output source is unavailable: " + source_id,
  )
}

///|
fn media_type_for_container(container : String) -> String {
  match container {
    "mp4" => "video/mp4"
    "jpg" => "image/jpeg"
    "png" => "image/png"
    _ => "application/octet-stream"
  }
}

///|
fn artifact_for_blob(
  output : @execution_domain.DeliveryOutputSpec,
  filename : String,
  blob : @store.StoredBlob,
) -> @execution_domain.DeliveryBuildArtifact {
  {
    artifact_id: output.output_id,
    kind: output.kind,
    filename,
    media_type: media_type_for_container(output.container),
    bytes: blob.bytes.length(),
    digest: "sha256:" + blob.sha256,
  }
}

///|
async fn run_delivery_process(
  executable : String,
  arguments : Array[String],
) -> Bool {
  let result = @host_process.run_capture({
    executable,
    arguments,
    working_directory: None,
    timeout_ms: 1800000,
    max_output_bytes: 1048576,
  })
  !result.timed_out && !result.output_truncated && result.exit_code == Some(0)
}

///|
fn support_artifact(
  artifact_id : String,
  kind : String,
  filename : String,
  media_type : String,
  blob : @store.StoredBlob,
) -> @execution_domain.DeliveryBuildArtifact {
  {
    artifact_id,
    kind,
    filename,
    media_type,
    bytes: blob.bytes.length(),
    digest: "sha256:" + blob.sha256,
  }
}

///|
async fn DeliveryFactoryService::put_support_json(
  self : DeliveryFactoryService,
  build_id : String,
  suffix : String,
  kind : String,
  value : Json,
) -> (@execution_domain.DeliveryBuildArtifact, String) {
  let filename = build_id + "-" + suffix + ".json"
  ignore(self.outputs.put_json(filename, value))
  let blob = match self.outputs.get_blob(filename) {
    Some(value) => value
    None => raise DeliveryArtifactMissing(filename)
  }
  (
    support_artifact(
      build_id + "-" + suffix,
      kind,
      filename,
      "application/json",
      blob,
    ),
    self.output_root + "/" + filename,
  )
}

///|
pub async fn DeliveryFactoryService::build(
  self : DeliveryFactoryService,
  build_id : String,
  expected_revision : Int,
  expected_record_digest : String,
  economics_receipt_digest : String,
) -> DeliveryFactoryRecord {
  let record = match self.load(build_id) {
    Some(value) => value
    None => raise DeliveryBuildNotFound(build_id)
  }
  if record.build.revision != expected_revision ||
    record.build.record_digest != expected_record_digest {
    raise DeliveryBuildConflict(build_id)
  }
  let started = @execution_domain.reduce_delivery_command(
    delivery_command(record, "start"),
  )
  if !started.ok {
    raise DeliveryBuildConflict(
      started.error_code.unwrap_or("delivery_start_invalid"),
    )
  }
  let building = {
    ..record,
    build: seal_delivery_build(started.build),
    updated_at: now(),
    process_effect_performed: true,
  }
  self.save(building)
  let artifacts : Array[@execution_domain.DeliveryBuildArtifact] = []
  let output_paths : Array[String] = []
  let output_sources : Array[(String, String)] = []
  for
    requested_kind in [
      "source-master", "platform-variant", "channel-cut", "cover-frame",
    ] {
    for output in building.request.profile.outputs {
      if output.kind != requested_kind {
        continue
      }
      let filename = build_id + "-" + output.output_id + "." + output.container
      let output_path = self.outputs.prepare_owned_path(filename)
      let input_path = source_path_for(
        output.source_output_id,
        building.request.master_path,
        output_sources,
      )
      if !run_delivery_process(
          self.ffmpeg_executable,
          video_output_args(input_path, output_path, output),
        ) {
        let failed = @execution_domain.reduce_delivery_command(
          delivery_command(
            building,
            "fail",
            error_code="ffmpeg_delivery_failed",
          ),
        )
        let durable = {
          ..building,
          build: seal_delivery_build(failed.build),
          updated_at: now(),
        }
        self.save(durable)
        return durable
      }
      let blob = match self.outputs.get_blob(filename) {
        Some(value) => value
        None => raise DeliveryArtifactMissing(filename)
      }
      artifacts.push(artifact_for_blob(output, filename, blob))
      output_paths.push(output_path)
      if output.kind == "platform-variant" {
        output_sources.push((output.output_id, output_path))
      }
    }
  }
  let metadata = building.request.project_metadata.unwrap_or(
    Json::object({
      "project_id": building.request.project_id.to_json(),
      "master_sha256": building.request.master_sha256.to_json(),
    }),
  )
  let (metadata_artifact, metadata_path) = self.put_support_json(
    build_id, "metadata", "delivery-metadata", metadata,
  )
  artifacts.push(metadata_artifact)
  output_paths.push(metadata_path)
  let provenance = building.request.provenance_manifest.unwrap_or(
    Json::object({
      "master_sha256": building.request.master_sha256.to_json(),
      "master_promotion_digest": building.request.master_promotion_digest.to_json(),
      "delivery_digest": building.request.delivery_digest.to_json(),
      "profile_digest": building.request.profile.profile_digest.to_json(),
    }),
  )
  let (provenance_artifact, provenance_path) = self.put_support_json(
    build_id, "provenance", "provenance-manifest", provenance,
  )
  artifacts.push(provenance_artifact)
  output_paths.push(provenance_path)
  let rights = building.request.rights_ledger.unwrap_or(
    Json::object({
      "delivery_digest": building.request.delivery_digest.to_json(),
      "rights_status": "bound-to-approved-delivery-package".to_json(),
    }),
  )
  let (rights_artifact, rights_path) = self.put_support_json(
    build_id, "rights-ledger", "rights-ledger", rights,
  )
  artifacts.push(rights_artifact)
  output_paths.push(rights_path)
  let (label_artifact, label_path) = self.put_support_json(
    build_id,
    "ai-label",
    "ai-label",
    Json::object({
      "label": building.request.ai_label
      .unwrap_or("AI-assisted production")
      .to_json(),
      "applies_to": building.request.profile.outputs
      .map(output => output.output_id)
      .to_json(),
    }),
  )
  artifacts.push(label_artifact)
  output_paths.push(label_path)
  if building.request.profile.outputs.any(output => {
      output.subtitle_mode == "sidecar"
    }) {
    let source_path = building.request.subtitle_path.unwrap()
    let subtitle_name = build_id + "-subtitles.srt"
    let copied_subtitle_path = self.outputs.prepare_owned_path(subtitle_name)
    if !run_delivery_process(
        self.ffmpeg_executable,
        subtitle_copy_args(source_path, copied_subtitle_path),
      ) {
      let failed = @execution_domain.reduce_delivery_command(
        delivery_command(
          building,
          "fail",
          error_code="delivery_subtitle_copy_failed",
        ),
      )
      let durable = {
        ..building,
        build: seal_delivery_build(failed.build),
        updated_at: now(),
      }
      self.save(durable)
      return durable
    }
    let subtitle_blob = match self.outputs.get_blob(subtitle_name) {
      Some(value) => value
      None => raise DeliveryArtifactMissing(subtitle_name)
    }
    artifacts.push(
      support_artifact(
        build_id + "-subtitles",
        "subtitle-sidecar",
        subtitle_name,
        "application/x-subrip",
        subtitle_blob,
      ),
    )
    output_paths.push(copied_subtitle_path)
  }
  if building.request.profile.outputs.any(output => {
      output.subtitle_mode != "none"
    }) {
    let (subtitle_artifact, subtitle_path) = self.put_support_json(
      build_id,
      "subtitles",
      "subtitle-manifest",
      Json::object({
        "source_path_bound": (building.request.subtitle_path is Some(_)).to_json(),
        "modes": building.request.profile.outputs
        .map(output => output.subtitle_mode)
        .to_json(),
        "master_sha256": building.request.master_sha256.to_json(),
        "burned_into_master": building.request.profile.outputs
        .any(output => output.subtitle_mode == "burned")
        .to_json(),
      }),
    )
    artifacts.push(subtitle_artifact)
    output_paths.push(subtitle_path)
  }
  let (acceptance_template, acceptance_template_path) = self.put_support_json(
    build_id,
    "acceptance-receipt",
    "acceptance-receipt-template",
    building.request.acceptance_receipt.unwrap_or(
      Json::object({
        "build_digest": building.build.build_digest.to_json(),
        "build_record_digest": building.build.record_digest.to_json(),
        "state": "awaiting-named-client-acceptance".to_json(),
        "publication_authority": false.to_json(),
      }),
    ),
  )
  artifacts.push(acceptance_template)
  output_paths.push(acceptance_template_path)
  let checksum_lines : Array[String] = artifacts.map(artifact => {
    normalized_sha256(artifact.digest) + "  " + artifact.filename
  })
  let checksum_name = build_id + "-checksums.sha256"
  ignore(
    self.outputs.put_blob(
      checksum_name,
      @utf8.encode(checksum_lines.join("\n") + "\n"),
    ),
  )
  let checksum_blob = match self.outputs.get_blob(checksum_name) {
    Some(value) => value
    None => raise DeliveryArtifactMissing(checksum_name)
  }
  artifacts.push(
    support_artifact(
      build_id + "-checksums",
      "checksum-manifest",
      checksum_name,
      "text/plain",
      checksum_blob,
    ),
  )
  output_paths.push(self.output_root + "/" + checksum_name)
  let manifest_key = build_id + "-manifest.json"
  let manifest : DeliveryArtifactManifest = {
    contract: "mooncast.delivery-artifact-manifest.v1",
    build_id,
    build_digest: building.build.build_digest,
    master_sha256: building.request.master_sha256,
    master_promotion_digest: building.request.master_promotion_digest,
    delivery_digest: building.request.delivery_digest,
    profile_digest: building.request.profile.profile_digest,
    artifacts,
    publication_authority: false,
  }
  ignore(self.outputs.put_json(manifest_key, manifest.to_json()))
  let manifest_blob = match self.outputs.get_blob(manifest_key) {
    Some(value) => value
    None => raise DeliveryArtifactMissing(manifest_key)
  }
  artifacts.push(
    support_artifact(
      build_id + "-manifest",
      "delivery-manifest",
      manifest_key,
      "application/json",
      manifest_blob,
    ),
  )
  output_paths.push(self.output_root + "/" + manifest_key)
  let archive_name = build_id + ".zip"
  let archive_path = self.outputs.prepare_owned_path(archive_name)
  let zip_args = ["-j", archive_path]
  for path in output_paths {
    zip_args.push(path)
  }
  let zip_result = @host_process.run_capture({
    executable: self.zip_executable,
    arguments: zip_args,
    working_directory: None,
    timeout_ms: 600000,
    max_output_bytes: 1048576,
  })
  if zip_result.timed_out ||
    zip_result.output_truncated ||
    zip_result.exit_code != Some(0) {
    let failed = @execution_domain.reduce_delivery_command(
      delivery_command(building, "fail", error_code="zip_delivery_failed"),
    )
    let durable = {
      ..building,
      build: seal_delivery_build(failed.build),
      manifest_key: Some(manifest_key),
      updated_at: now(),
    }
    self.save(durable)
    return durable
  }
  let archive_blob = match self.outputs.get_blob(archive_name) {
    Some(value) => value
    None => raise DeliveryArtifactMissing(archive_name)
  }
  let archive : @execution_domain.DeliveryBuildArtifact = {
    artifact_id: build_id + "-archive",
    kind: "delivery-archive",
    filename: archive_name,
    media_type: "application/zip",
    bytes: archive_blob.bytes.length(),
    digest: "sha256:" + archive_blob.sha256,
  }
  let completed = @execution_domain.reduce_delivery_command(
    delivery_command(
      building,
      "complete",
      artifacts~,
      archive~,
      economics_receipt_digest~,
    ),
  )
  let durable = {
    ..building,
    build: seal_delivery_build(completed.build),
    manifest_key: Some(manifest_key),
    updated_at: now(),
    publication_effect_performed: false,
  }
  self.save(durable)
  durable
}

///|
pub async fn DeliveryFactoryService::cancel(
  self : DeliveryFactoryService,
  build_id : String,
  expected_revision : Int,
  expected_record_digest : String,
) -> DeliveryFactoryRecord {
  let record = match self.load(build_id) {
    Some(value) => value
    None => raise DeliveryBuildNotFound(build_id)
  }
  if record.build.revision != expected_revision ||
    record.build.record_digest != expected_record_digest {
    raise DeliveryBuildConflict(build_id)
  }
  let result = @execution_domain.reduce_delivery_command(
    delivery_command(record, "cancel"),
  )
  if !result.ok {
    raise DeliveryBuildConflict(
      result.error_code.unwrap_or("delivery_cancel_invalid"),
    )
  }
  let durable = {
    ..record,
    build: seal_delivery_build(result.build),
    updated_at: now(),
  }
  self.save(durable)
  durable
}

///|
pub async fn DeliveryFactoryService::retry(
  self : DeliveryFactoryService,
  build_id : String,
  expected_revision : Int,
  expected_record_digest : String,
  economics_receipt_digest : String,
) -> DeliveryFactoryRecord {
  let record = match self.load(build_id) {
    Some(value) => value
    None => raise DeliveryBuildNotFound(build_id)
  }
  if record.build.revision != expected_revision ||
    record.build.record_digest != expected_record_digest {
    raise DeliveryBuildConflict(build_id)
  }
  let retried = @execution_domain.reduce_delivery_command(
    delivery_command(record, "retry"),
  )
  if !retried.ok {
    raise DeliveryBuildConflict(
      retried.error_code.unwrap_or("delivery_retry_invalid"),
    )
  }
  let queued = {
    ..record,
    build: seal_delivery_build(retried.build),
    updated_at: now(),
  }
  self.save(queued)
  self.build(
    build_id,
    queued.build.revision,
    queued.build.record_digest,
    economics_receipt_digest,
  )
}

///|
pub async fn DeliveryFactoryService::record_acceptance(
  self : DeliveryFactoryService,
  build_id : String,
  acceptance : @execution_domain.DeliveryBuildAcceptance,
) -> DeliveryAcceptanceRecord {
  let record = match self.load(build_id) {
    Some(value) => value
    None => raise DeliveryBuildNotFound(build_id)
  }
  if record.build.state != "completed" ||
    acceptance.build_digest != record.build.build_digest ||
    acceptance.build_record_digest != record.build.record_digest ||
    acceptance.project_revision != record.build.project_revision ||
    (
      acceptance.decision != "accept" &&
      acceptance.decision != "reject" &&
      acceptance.decision != "request-revision"
    ) ||
    acceptance.actor == "" ||
    acceptance.actor_role == "" {
    raise DeliveryBuildConflict(
      "acceptance does not bind exact completed build",
    )
  }
  let durable : DeliveryAcceptanceRecord = {
    contract: "mooncast.delivery-build-acceptance-record.v1",
    acceptance,
    publication_authority: false,
    external_effect_performed: false,
  }
  ignore(
    self.state.put_json(
      "delivery-acceptance-" + build_id + ".json",
      durable.to_json(),
    ),
  )
  if acceptance.decision == "accept" && record.build.archive is Some(archive) {
    let acceptance_name = build_id + "-accepted-receipt.json"
    ignore(self.outputs.put_json(acceptance_name, durable.to_json()))
    let zip_result = @host_process.run_capture({
      executable: self.zip_executable,
      arguments: [
        "-j",
        self.output_root + "/" + archive.filename,
        self.output_root + "/" + acceptance_name,
      ],
      working_directory: None,
      timeout_ms: 600000,
      max_output_bytes: 1048576,
    })
    if zip_result.timed_out ||
      zip_result.output_truncated ||
      zip_result.exit_code != Some(0) {
      raise DeliveryProcessFailed(
        "accepted receipt could not be added to the customer archive",
      )
    }
  }
  durable
}

///|
pub async fn DeliveryFactoryService::acceptance(
  self : DeliveryFactoryService,
  build_id : String,
) -> DeliveryAcceptanceRecord? {
  match self.state.get_json("delivery-acceptance-" + build_id + ".json") {
    None => None
    Some(value) => {
      let record : DeliveryAcceptanceRecord = @json.from_json(value) catch {
        _ => raise DeliveryBuildConflict("delivery acceptance is corrupt")
      }
      Some(record)
    }
  }
}

///|
pub async fn DeliveryFactoryService::accepted_build(
  self : DeliveryFactoryService,
  build_id : String,
) -> @execution_domain.DeliveryBuild? {
  let record = match self.load(build_id) {
    None => return None
    Some(value) => value
  }
  match self.acceptance(build_id) {
    Some(value) if value.acceptance.decision == "accept" &&
      value.acceptance.build_digest == record.build.build_digest &&
      value.acceptance.build_record_digest == record.build.record_digest =>
      Some(record.build)
    _ => None
  }
}

///|
pub async fn DeliveryFactoryService::accepted_archive(
  self : DeliveryFactoryService,
  build_id : String,
) -> @store.StoredBlob? {
  let record = match self.load(build_id) {
    Some(value) => value
    None => return None
  }
  let acceptance = match
    self.state.get_json("delivery-acceptance-" + build_id + ".json") {
    Some(value) => {
      let durable : DeliveryAcceptanceRecord = @json.from_json(value) catch {
        _ => return None
      }
      durable.acceptance
    }
    None => return None
  }
  if acceptance.decision != "accept" ||
    acceptance.build_digest != record.build.build_digest {
    return None
  }
  match record.build.archive {
    Some(archive) => self.outputs.get_blob(archive.filename)
    None => None
  }
}

///|
pub async fn DeliveryFactoryService::publication_authority_request(
  self : DeliveryFactoryService,
  build_id : String,
  destination_id : String,
  actor : String,
  authorized_at : String,
) -> @execution_domain.PublicationAuthorityRequest? {
  let record = match self.load(build_id) {
    Some(value) => value
    None => return None
  }
  let acceptance = match
    self.state.get_json("delivery-acceptance-" + build_id + ".json") {
    Some(value) => {
      let durable : DeliveryAcceptanceRecord = @json.from_json(value) catch {
        _ => return None
      }
      durable.acceptance
    }
    None => return None
  }
  let request = @execution_domain.authorize_publication(
    record.build,
    acceptance,
    destination_id,
    actor,
    authorized_at,
  )
  match request {
    Some(value) => {
      ignore(
        self.state.put_json(
          "publication-authority-" + build_id + "-" + destination_id + ".json",
          value.to_json(),
        ),
      )
      Some(value)
    }
    None => None
  }
}

///|
pub async fn DeliveryFactoryService::recover_interrupted(
  self : DeliveryFactoryService,
) -> Int {
  let mut recovered = 0
  for key in self.state.list_keys(prefix="delivery-build-", suffix=".json") {
    match self.state.get_json(key) {
      Some(value) => {
        let record : DeliveryFactoryRecord = @json.from_json(value) catch {
          _ => continue
        }
        if record.build.state == "building" {
          let result = @execution_domain.reduce_delivery_command(
            delivery_command(record, "recover"),
          )
          if result.ok {
            self.save({
              ..record,
              build: seal_delivery_build(result.build),
              updated_at: now(),
            })
            recovered = recovered + 1
          }
        }
      }
      None => ()
    }
  }
  recovered
}
