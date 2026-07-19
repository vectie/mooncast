///|
fn sha256_bytes(bytes : Bytes) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
pub struct MediaRegistry {
  objects : @host_store.AtomicStore
  records : @host_store.AtomicStore
  analyses : @host_store.AtomicStore
}

///|
pub fn MediaRegistry::new(root : String) -> MediaRegistry {
  {
    objects: @host_store.AtomicStore::new(
      root + "/objects",
      max_read_bytes=1073741824,
    ),
    records: @host_store.AtomicStore::new(root + "/records"),
    analyses: @host_store.AtomicStore::new(root + "/analyses"),
  }
}

///|
fn analysis_key(digest : String) -> String {
  "analysis-" + digest_key(digest) + ".json"
}

///|
fn analysis_digest(value : MediaAnalysis) -> String {
  let unsigned = { ..value, analysis_digest: None }
  "sha256:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(unsigned.to_json().stringify())),
  )
}

///|
fn append_ref(values : Array[String], value : String) -> Array[String] {
  let result = values.copy()
  result.push(value)
  result
}

///|
pub async fn MediaRegistry::save_analysis(
  self : MediaRegistry,
  value : MediaAnalysis,
) -> MediaAnalysis {
  guard value.source_digest.has_prefix("sha256:") && value.state == "available" else {
    fail("available media analysis is required")
  }
  let completed = { ..value, analysis_digest: Some(analysis_digest(value)) }
  ignore(
    self.analyses.put_json(
      analysis_key(value.source_digest),
      completed.to_json(),
    ),
  )
  completed
}

///|
pub async fn MediaRegistry::analysis(
  self : MediaRegistry,
  source_digest : String,
) -> MediaAnalysis? {
  match self.analyses.get_json(analysis_key(source_digest)) {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
/// Materializes bounded thumbnail and waveform artifacts and binds them to probe metadata.
pub async fn MediaRegistry::complete_analysis(
  self : MediaRegistry,
  probed : MediaAnalysis,
  thumbnail_bytes : Bytes?,
  thumbnail_mime : String?,
  thumbnail_width : Int?,
  thumbnail_height : Int?,
  raw_pcm_s16le : Bytes?,
  created_at : String,
) -> MediaAnalysis {
  guard self.get(probed.source_digest) is Some(original) else {
    fail("analysis source is not registered")
  }
  let mut thumbnail = probed.thumbnail
  if thumbnail_bytes is Some(bytes) {
    guard thumbnail_mime is Some(mime) &&
      thumbnail_width is Some(width) &&
      thumbnail_height is Some(height) &&
      width > 0 &&
      height > 0 else {
      fail("thumbnail metadata is incomplete")
    }
    let record = self.ingest(
      bytes,
      mime,
      None,
      "analysis-thumbnail",
      Some(probed.source_digest),
      original.source_refs,
      append_ref(original.provenance_refs, "editor-analysis:thumbnail"),
      original.rights_refs,
      created_at,
    )
    thumbnail = {
      state: "available",
      digest: Some(record.digest),
      mime: Some(record.mime),
      width: Some(width),
      height: Some(height),
    }
  }
  let mut waveform = probed.waveform
  if raw_pcm_s16le is Some(pcm) {
    let peaks = waveform_peaks(pcm)
    let svg = waveform_svg(peaks, probed.source_digest)
    let record = self.ingest(
      svg,
      "image/svg+xml",
      None,
      "analysis-waveform",
      Some(probed.source_digest),
      original.source_refs,
      append_ref(original.provenance_refs, "editor-analysis:waveform"),
      original.rights_refs,
      created_at,
    )
    waveform = {
      state: "available",
      peak_count: peaks.length(),
      peaks,
      digest: Some(record.digest),
    }
  }
  self.save_analysis({ ..probed, thumbnail, waveform })
}

///|
pub async fn MediaRegistry::analysis_thumbnail(
  self : MediaRegistry,
  source_digest : String,
) -> MediaByteDescriptor? {
  guard self.analysis(source_digest) is Some(value) &&
    value.thumbnail.digest is Some(digest) else {
    return None
  }
  guard self.get(digest) is Some(record) else { return None }
  self.describe_range(digest, 0, record.size)
}

///|
fn digest_key(digest : String) -> String {
  if digest.has_prefix("sha256:") {
    digest[7:].to_owned()
  } else {
    digest
  }
}

///|
pub async fn MediaRegistry::ingest(
  self : MediaRegistry,
  bytes : Bytes,
  mime : String,
  duration : Double?,
  role : String,
  original_digest : String?,
  source_refs : Array[String],
  provenance_refs : Array[String],
  rights_refs : Array[String],
  created_at : String,
) -> MediaObjectRecord {
  let digest = sha256_bytes(bytes)
  let original = match original_digest {
    Some(value) => value
    None => digest
  }
  if role == "original" && original != digest {
    fail("original media digest mismatch")
  }
  if role == "proxy" && original == digest {
    fail("proxy must bind a distinct original digest")
  }
  let key = "media-" + digest_key(digest)
  let hex = digest_key(digest)
  ignore(self.objects.put_blob(key, bytes))
  let record : MediaObjectRecord = {
    contract: "mooncast.editor-media-registry.v1",
    digest,
    size: bytes.length(),
    mime,
    duration,
    role,
    original_digest: original,
    locator: "objects/sha256/" + hex[:2].to_owned() + "/" + hex,
    source_refs,
    provenance_refs,
    rights_refs,
    created_at,
  }
  ignore(self.records.put_json(key + ".json", record.to_json()))
  record
}

///|
pub async fn MediaRegistry::get(
  self : MediaRegistry,
  digest : String,
) -> MediaObjectRecord? {
  match self.records.get_json("media-" + digest_key(digest) + ".json") {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
pub async fn MediaRegistry::list_proxies(
  self : MediaRegistry,
  original_digest : String,
) -> Array[MediaObjectRecord] {
  let keys = self.records.list_keys(prefix="media-", suffix=".json")
  let result : Array[MediaObjectRecord] = []
  for key in keys {
    if self.records.get_json(key) is Some(value) {
      let record : MediaObjectRecord = @json.from_json(value)
      if record.role == "proxy" && record.original_digest == original_digest {
        result.push(record)
      }
    }
  }
  result
}

///|
pub async fn MediaRegistry::bytes(
  self : MediaRegistry,
  digest : String,
) -> Bytes? {
  match self.objects.get_blob("media-" + digest_key(digest)) {
    None => None
    Some(value) => {
      if "sha256:" + value.sha256 != digest {
        fail("stored media digest mismatch")
      }
      Some(value.bytes)
    }
  }
}

///|
pub async fn MediaRegistry::resolve(
  self : MediaRegistry,
  digest : String,
) -> MediaResolution {
  guard self.get(digest) is Some(record) else {
    return {
      record: None,
      findings: [
        {
          code: "missing_record",
          digest,
          locator: "",
          detail: "registry record is absent",
        },
      ],
    }
  }
  match self.objects.get_blob("media-" + digest_key(digest)) {
    None =>
      {
        record: Some(record),
        findings: [
          {
            code: "missing_media",
            digest,
            locator: record.locator,
            detail: "media object is absent",
          },
        ],
      }
    Some(blob) => {
      let findings : Array[MediaFinding] = []
      if blob.bytes.length() != record.size {
        findings.push({
          code: "size_mismatch",
          digest,
          locator: record.locator,
          detail: "object size differs from record",
        })
      }
      if "sha256:" + blob.sha256 != digest {
        findings.push({
          code: "digest_mismatch",
          digest,
          locator: record.locator,
          detail: "object digest differs from identity",
        })
      }
      { record: Some(record), findings }
    }
  }
}

///|
pub async fn MediaRegistry::availability(
  self : MediaRegistry,
  digest : String,
) -> MediaAvailability {
  let resolution = self.resolve(digest)
  match resolution.record {
    None =>
      {
        state: "missing",
        digest,
        mime: None,
        size: None,
        source_descriptor: None,
      }
    Some(record) => {
      let ready = resolution.findings.is_empty()
      let descriptor = if ready && record.size > 0 {
        self.describe_range(digest, 0, record.size)
      } else {
        None
      }
      {
        state: if ready {
          "available"
        } else {
          "unavailable"
        },
        digest,
        mime: Some(record.mime),
        size: Some(record.size),
        source_descriptor: descriptor,
      }
    }
  }
}

///|
/// Audits every registry declaration and separates regenerable derivatives from originals.
pub async fn MediaRegistry::recovery_plan(
  self : MediaRegistry,
) -> MediaRecoveryPlan {
  let findings : Array[MediaFinding] = []
  let regenerate : Array[String] = []
  let restore : Array[String] = []
  for key in self.records.list_keys(prefix="media-", suffix=".json") {
    if self.records.get_json(key) is Some(value) {
      let record : MediaObjectRecord = @json.from_json(value)
      let resolution = self.resolve(record.digest)
      findings.append(resolution.findings)
      if !resolution.findings.is_empty() {
        if record.role == "original" {
          restore.push(record.digest)
        } else {
          regenerate.push(record.digest)
        }
      }
    }
  }
  {
    contract: "mooncast.editor-media-recovery-plan.v1",
    findings,
    regenerate_digests: regenerate,
    restore_original_digests: restore,
    publication_authority: false,
  }
}

///|
pub async fn MediaRegistry::describe_range(
  self : MediaRegistry,
  digest : String,
  start : Int,
  requested : Int,
) -> MediaByteDescriptor? {
  guard self.get(digest) is Some(record) else { return None }
  guard start >= 0 && start < record.size else {
    fail("invalid media byte range")
  }
  let remaining = record.size - start
  let length = if requested <= 0 || requested > remaining {
    remaining
  } else {
    requested
  }
  Some({
    digest,
    object_key: "media-" + digest_key(digest),
    mime: record.mime,
    range: { start, length, total: record.size },
    etag: digest,
    immutable: true,
  })
}
