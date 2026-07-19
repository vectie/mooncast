///|
pub(all) struct AnalyzerRunRequest {
  expected_task_version : Int
  expected_task_digest : String
  actor : String
  human_confirmed : Bool
  network_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
struct ProbeStream {
  codec_type : String
  codec_name : String?
} derive(Debug, FromJson)

///|
struct ProbeFormat {
  duration : String?
} derive(Debug, FromJson)

///|
struct ProbeDocument {
  streams : Array[ProbeStream]
  format : ProbeFormat
} derive(Debug, FromJson)

///|
struct SemanticResult {
  contract : String
  score : Double
  threshold : Double
  status : String
  note : String
} derive(Debug, FromJson)

///|
pub suberror AnalyzerApplicationError {
  AnalyzerInvalid(String)
  AnalyzerConflict(String)
  AnalyzerSourceInvalid(String)
} derive(Debug)

///|
pub struct AnalyzerService {
  store : @store.AtomicStore
  media : @store.AtomicStore
  execution : @execution_app.ProviderExecutionService
  ffmpeg_executable : String
  ffprobe_executable : String
}

///|
pub fn AnalyzerService::new(
  root : String,
  execution : @execution_app.ProviderExecutionService,
  ffmpeg_executable : String,
  ffprobe_executable : String,
) -> AnalyzerService {
  {
    store: @store.AtomicStore::new(root + "/state"),
    media: @store.AtomicStore::new(root + "/media"),
    execution,
    ffmpeg_executable,
    ffprobe_executable,
  }
}

///|
fn digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn task_key(project_id : String, version : Int) -> String {
  "qc-analyzer-task-" + project_id + "-v" + version.to_string() + ".json"
}

///|
fn receipt_key(project_id : String, analyzer : String, version : Int) -> String {
  "qc-analyzer-receipt-" + project_id + "-" + analyzer + "-v" + version.to_string() + ".json"
}

///|
pub async fn AnalyzerService::record_task(
  self : AnalyzerService,
  task : @qc_domain.AnalyzerTask,
) -> @qc_domain.AnalyzerTask {
  let errors = @qc_domain.task_errors(task)
  guard errors.is_empty() else { raise AnalyzerInvalid(errors.join("; ")) }
  let key = task_key(task.project_id, task.reference.version)
  match self.store.get_json(key) {
    Some(value) => {
      let prior : @qc_domain.AnalyzerTask = @json.from_json(value)
      guard prior == task else { raise AnalyzerConflict("task version conflict") }
      prior
    }
    None => { ignore(self.store.put_json(key, task.to_json())); task }
  }
}

///|
pub async fn AnalyzerService::list_tasks(
  self : AnalyzerService,
  project_id : String,
) -> Array[@qc_domain.AnalyzerTask] {
  let values : Array[@qc_domain.AnalyzerTask] = []
  for key in self.store.list_keys(prefix="qc-analyzer-task-" + project_id + "-v", suffix=".json") {
    match self.store.get_json(key) { Some(value) => values.push(@json.from_json(value)); None => () }
  }
  values
}

///|
fn measurement(
  task : @qc_domain.AnalyzerTask,
  metric : String,
  value : Double,
  unit : String,
  comparator : String,
  threshold : Double,
  passed : Bool,
) -> @qc_domain.AnalyzerMeasurement {
  {
    metric, value, unit, comparator, threshold,
    status: if passed { "pass" } else { "fail" },
    evidence_digest: digest(task.reference.digest + ":" + metric + ":" + value.to_string()),
  }
}

///|
fn parse_max_volume(stderr : String) -> Double? {
  guard stderr.find("max_volume:") is Some(index) else { return None }
  let rest = stderr[index + 11:]
  guard rest.find(" dB") is Some(end) else { return None }
  let value = rest[:end].trim()
  Some(@string.parse_double(value) catch { _ => return None })
}

///|
async fn AnalyzerService::probe(
  self : AnalyzerService,
  task : @qc_domain.AnalyzerTask,
  bytes : Bytes,
) -> (ProbeDocument, String) {
  guard self.ffprobe_executable != "" && self.ffmpeg_executable != "" && !bytes.is_empty() else {
    raise AnalyzerSourceInvalid("configured local media tools and source bytes are required")
  }
  let key = "source-" + task.source_artifact_digest.replace(old=":", new="-") + ".media"
  ignore(self.media.put_blob(key, bytes))
  let path = self.media.owned_path(key)
  let result = @host_process.run_capture({
    executable: self.ffprobe_executable,
    arguments: ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", path],
    working_directory: None, timeout_ms: 30000, max_output_bytes: 1048576,
  })
  guard result.exit_code == Some(0) && !result.timed_out && !result.output_truncated else {
    raise AnalyzerSourceInvalid("ffprobe could not inspect the exact source artifact")
  }
  let document : ProbeDocument = @json.from_json(@json.parse(@utf8.decode(result.stdout))) catch {
    _ => raise AnalyzerSourceInvalid("ffprobe returned invalid JSON")
  }
  (document, path)
}

///|
async fn AnalyzerService::run_local(
  self : AnalyzerService,
  task : @qc_domain.AnalyzerTask,
  bytes : Bytes,
) -> (@qc_domain.AnalyzerMeasurement, String) {
  let (probe, path) = self.probe(task, bytes)
  let duration = match probe.format.duration {
    Some(value) => @string.parse_double(value) catch { _ => 0.0 }
    None => 0.0
  }
  let video = probe.streams.filter(stream => stream.codec_type == "video")
  let audio = probe.streams.any(stream => stream.codec_type == "audio")
  match task.analyzer {
    "codec" => {
      let supported = video.any(stream => match stream.codec_name {
        Some(value) => ["h264", "hevc", "vp9", "av1"].contains(value)
        None => false
      })
      (measurement(task, "supported_video_codec", if supported { 1.0 } else { 0.0 }, "boolean", "eq", 1.0, supported), "ffprobe codec inspection")
    }
    "duration" => {
      let actual_ms = duration * 1000.0
      let delta = (actual_ms - task.expected_duration_ms.to_double()).abs()
      (measurement(task, "duration_delta", delta, "ms", "lte", task.duration_tolerance_ms.to_double(), delta <= task.duration_tolerance_ms.to_double()), "ffprobe duration against exact shot timing")
    }
    "audio-level" => {
      guard audio else {
        return (measurement(task, "maximum_audio_level", -100.0, "dBFS", "gte", -40.0, false), "ffprobe found no audio stream")
      }
      let result = @host_process.run_capture({
        executable: self.ffmpeg_executable,
        arguments: ["-hide_banner", "-nostdin", "-i", path, "-af", "volumedetect", "-vn", "-f", "null", "-"],
        working_directory: None, timeout_ms: 60000, max_output_bytes: 1048576,
      })
      guard result.exit_code == Some(0) && !result.timed_out &&
        parse_max_volume(@utf8.decode(result.stderr)) is Some(level) else {
        raise AnalyzerSourceInvalid("ffmpeg audio-level analysis failed")
      }
      (measurement(task, "maximum_audio_level", level, "dBFS", "gte", -40.0, level >= -40.0), "ffmpeg volumedetect maximum level")
    }
    "blank-frames" => {
      let result = @host_process.run_capture({
        executable: self.ffmpeg_executable,
        arguments: ["-hide_banner", "-nostdin", "-i", path, "-vf", "blackdetect=d=0.20:pix_th=0.10", "-an", "-f", "null", "-"],
        working_directory: None, timeout_ms: 60000, max_output_bytes: 1048576,
      })
      guard result.exit_code == Some(0) && !result.timed_out else {
        raise AnalyzerSourceInvalid("ffmpeg blank-frame analysis failed")
      }
      let blank = @utf8.decode(result.stderr).contains("black_start:")
      (measurement(task, "blank_segment_detected", if blank { 1.0 } else { 0.0 }, "boolean", "eq", 0.0, !blank), "ffmpeg blackdetect with a 200ms bound")
    }
    "subtitle-timing" => {
      let passed = task.subtitle_cue_count > 0 &&
        task.subtitle_last_end_ms <= task.expected_duration_ms
      (measurement(task, "subtitle_last_end", task.subtitle_last_end_ms.to_double(), "ms", "lte", task.expected_duration_ms.to_double(), passed), "exact subtitle track timing against shot duration")
    }
    "safe-area" => {
      let passed = task.subtitle_safe_area_ratio >= 0.8
      (measurement(task, "subtitle_safe_area_ratio", task.subtitle_safe_area_ratio, "ratio", "gte", 0.8, passed), "subtitle layout safe-area receipt")
    }
    _ => raise AnalyzerInvalid("semantic analyzer cannot run on the local port")
  }
}

///|
async fn AnalyzerService::run_external(
  self : AnalyzerService,
  task : @qc_domain.AnalyzerTask,
  request : AnalyzerRunRequest,
) -> (@qc_domain.AnalyzerMeasurement, String, String, Double, Bool) {
  let adapter = task.provider_adapter_id.unwrap_or("")
  let provider = task.provider.unwrap_or("")
  let model = task.model.unwrap_or("")
  let capability = "qc-" + task.analyzer
  let job = self.execution.authorize_asset_from_catalog({
    contract: "mooncast.asset-provider-request.v1",
    request_id: "qc:" + task.reference.id + ":" + task.reference.version.to_string(),
    project_id: task.project_id, project_revision: task.project_revision,
    asset_id: task.project_id + "-" + task.shot_id + "-" + task.analyzer,
    asset_version: task.reference.version, variant: 1, kind: "qc-analysis",
    capability, intent_ref: task.reference.digest,
    prompt_digest: digest(task.analyzer + ":" + task.reference.digest),
    source_asset_refs: [task.source_artifact_digest], rights_refs: task.rights_refs,
    continuity_key: task.shot_id + ":" + task.continuity_refs.join("|"),
    adapter_id: adapter, provider, model,
    permitted_data_class: task.permitted_data_class,
    cost_ceiling_cny: task.cost_ceiling_cny, retry_limit: task.retry_limit,
    parameters: task.to_json(), publication_authority: false,
  }, request.actor, request.network_authority)
  let executed = if job.job.state == "completed" { job } else { self.execution.execute(job.job.job_id) }
  guard executed.job.state == "completed" && executed.job.artifacts.length() == 1 else {
    raise AnalyzerConflict("semantic provider analysis is retryable or failed")
  }
  let artifact = executed.job.artifacts[0]
  guard self.execution.artifact_bytes(artifact.artifact_digest) is Some(bytes) else {
    raise AnalyzerSourceInvalid("semantic provider artifact bytes are unavailable")
  }
  let result : SemanticResult = @json.from_json(@json.parse(@utf8.decode(bytes))) catch {
    _ => raise AnalyzerSourceInvalid("semantic provider must return the typed score contract")
  }
  guard result.contract == "mooncast.qc-semantic-result.v1" &&
    ["pass", "fail"].contains(result.status) else {
    raise AnalyzerSourceInvalid("semantic provider result contract is invalid")
  }
  let measured : @qc_domain.AnalyzerMeasurement = {
    metric: task.analyzer + "_score", value: result.score, unit: "ratio",
    comparator: "gte", threshold: result.threshold, status: result.status,
    evidence_digest: artifact.artifact_digest,
  }
  (
    measured, result.note, executed.job.job_id, executed.job.spent_cny,
    executed.host_effect_receipts.any(value => value.network_effect_performed),
  )
}

///|
pub async fn AnalyzerService::run(
  self : AnalyzerService,
  task : @qc_domain.AnalyzerTask,
  source_bytes : Bytes?,
  request : AnalyzerRunRequest,
) -> @qc_domain.AnalyzerReceipt {
  guard request.expected_task_version == task.reference.version &&
    request.expected_task_digest == task.reference.digest && request.actor != "" &&
    request.human_confirmed else {
    raise AnalyzerConflict("analysis requires the exact task and a named observer")
  }
  let key = receipt_key(task.project_id, task.analyzer, task.reference.version)
  match self.store.get_json(key) {
    Some(value) => return @json.from_json(value)
    None => ()
  }
  let (measured, note, provider_job_id, cost, network) = if task.execution_mode == "local-technical" {
    guard source_bytes is Some(bytes) else { raise AnalyzerSourceInvalid("local analyzer source is unavailable") }
    let (measurement, note) = self.run_local(task, bytes)
    (measurement, note, None, 0.0, false)
  } else {
    let (measurement, note, job_id, cost, network) = self.run_external(task, request)
    (measurement, note, Some(job_id), cost, network)
  }
  let evidence = digest(task.reference.digest + ":" + measured.evidence_digest + ":" + measured.status)
  let finding_core : @qc_domain.AnalyzerFinding = {
    contract: "mooncast.qc-analyzer-finding.v1",
    finding: { id: task.reference.id + "-finding", version: 1, digest: "" },
    task: task.reference, shot_id: task.shot_id, attempt_digest: task.attempt_digest,
    analyzer: task.analyzer,
    governance_dimension: @qc_domain.governance_dimension(task.analyzer),
    status: measured.status, measurements: [measured], evidence_digest: evidence,
    note, human_decision_required: true, publication_authority: false, immutable: true,
  }
  let finding = { ..finding_core, finding: { ..finding_core.finding, digest: digest(finding_core.to_json().stringify()) } }
  let receipt_core : @qc_domain.AnalyzerReceipt = {
    contract: "mooncast.qc-analyzer-receipt.v1",
    receipt: { id: task.reference.id + "-receipt", version: 1, digest: "" },
    task: task.reference, provider_job_id,
    source_artifact_digest: task.source_artifact_digest,
    analyzer: task.analyzer, execution_mode: task.execution_mode, finding,
    cost_cny: cost, completed_at: @async.now().to_string(),
    network_effect_performed: network, human_decision_performed: false,
    publication_authority: false, immutable: true,
  }
  let receipt = { ..receipt_core, receipt: { ..receipt_core.receipt, digest: digest(receipt_core.to_json().stringify()) } }
  ignore(self.store.put_json(key, receipt.to_json()))
  receipt
}

///|
pub async fn AnalyzerService::workspace(
  self : AnalyzerService,
  project_id : String,
) -> @qc_domain.AnalyzerWorkspace {
  let tasks = self.list_tasks(project_id)
  let receipts : Array[@qc_domain.AnalyzerReceipt] = []
  for key in self.store.list_keys(prefix="qc-analyzer-receipt-" + project_id + "-", suffix=".json") {
    match self.store.get_json(key) { Some(value) => receipts.push(@json.from_json(value)); None => () }
  }
  {
    tasks, receipts, findings: receipts.map(value => value.finding),
    total_cost_cny: receipts.fold(init=0.0, (sum, value) => sum + value.cost_cny),
    human_decisions: 0, provider_execution_authority: false,
    publication_authority: false,
  }
}
