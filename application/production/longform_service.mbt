///|
pub(all) struct ShotMediaBinding {
  shot_id : String
  source_key : String
  source_sha256 : String
  duration_ms : Int
  subtitle : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterTimelineEntry {
  order : Int
  shot_id : String
  source_key : String
  source_sha256 : String
  duration_ms : Int
  subtitle : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterMedia {
  duration_seconds : Double
  format_name : String
  video_codec : String
  width : Int?
  height : Int?
  has_audio : Bool
  has_subtitles : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterProvenance {
  contract : String
  master_id : String
  project_id : String
  project_revision : Int
  master_key : String
  subtitle_key : String
  provenance_key : String
  sha256 : String
  timeline_digest : String
  timeline : Array[MasterTimelineEntry]
  media : MasterMedia
  explicit_ai_label : String
  qc_checks : Array[String]
  created_at : String
  process_effect_performed : Bool
  publication_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterAssemblyRequest {
  contract : String
  expected_project_revision : Int
  evidence_digest : String
  shot_media : Array[ShotMediaBinding]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreparedDeliveryRecord {
  contract : String
  project_id : String
  project_revision : Int
  delivery_package : @governance.DeliveryPackage
  delivery_key : String
  package_digest : String
  prepared_at : String
  external_effect_performed : Bool
  publication_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror LongformApplicationError {
  LongformGateRequired(String)
  LongformRequestInvalid(String)
  LongformShotMissing(String)
  LongformSourceMissing(String)
  LongformCompositionFailed(String)
  LongformProbeFailed(String)
  LongformDeliveryNotReady(String)
} derive(Debug)

///|
pub struct LongformProductionService {
  source : @store.AtomicStore
  masters : @store.AtomicStore
  deliveries : @store.AtomicStore
  master_root : String
  ffmpeg_executable : String
  ffprobe_executable : String
}

///|
pub fn LongformProductionService::new(
  source_root : String,
  master_root : String,
  delivery_root : String,
  ffmpeg_executable : String,
  ffprobe_executable : String,
) -> LongformProductionService {
  {
    source: @store.AtomicStore::new(source_root),
    masters: @store.AtomicStore::new(master_root),
    deliveries: @store.AtomicStore::new(delivery_root, max_read_bytes=33554432),
    master_root,
    ffmpeg_executable,
    ffprobe_executable,
  }
}

///|
fn has_gate(
  snapshot : @kernel.ProjectSnapshot,
  gate : @governance.Gate,
) -> Bool {
  snapshot.gate_receipts.any(receipt => receipt.gate == gate)
}

///|
fn longform_digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn pad_left(value : Int, width : Int) -> String {
  let text = value.to_string()
  let mut output = text
  while output.length() < width {
    output = "0" + output
  }
  output
}

///|
fn srt_time(milliseconds : Int) -> String {
  let hours = milliseconds / 3600000
  let after_hours = milliseconds % 3600000
  let minutes = after_hours / 60000
  let after_minutes = after_hours % 60000
  let seconds = after_minutes / 1000
  let millis = after_minutes % 1000
  pad_left(hours, 2) +
  ":" +
  pad_left(minutes, 2) +
  ":" +
  pad_left(seconds, 2) +
  "," +
  pad_left(millis, 3)
}

///|
fn concat_escape(value : String) -> String {
  value.replace_all(old="'", new="'\\''")
}

///|
fn build_timeline(
  snapshot : @kernel.ProjectSnapshot,
  bindings : Array[ShotMediaBinding],
) -> Array[MasterTimelineEntry] raise LongformApplicationError {
  let shots = @project.flattened_shots(snapshot.graph)
  if shots.length() == 0 || bindings.length() != shots.length() {
    raise LongformRequestInvalid(
      "every graph shot requires exactly one media binding",
    )
  }
  let timeline : Array[MasterTimelineEntry] = []
  for shot in shots {
    let mut found : ShotMediaBinding? = None
    for binding in bindings {
      if binding.shot_id == shot.shot_id {
        if found is Some(_) {
          raise LongformRequestInvalid("duplicate shot media binding")
        }
        found = Some(binding)
      }
    }
    let binding = match found {
      None => raise LongformShotMissing(shot.shot_id)
      Some(value) => value
    }
    if binding.source_key == "" ||
      binding.source_sha256 == "" ||
      binding.duration_ms != shot.duration_ms ||
      binding.subtitle.length() > 2000 {
      raise LongformRequestInvalid(
        "shot binding differs from the approved graph",
      )
    }
    timeline.push({
      order: shot.order,
      shot_id: shot.shot_id,
      source_key: binding.source_key,
      source_sha256: binding.source_sha256,
      duration_ms: binding.duration_ms,
      subtitle: binding.subtitle,
    })
  }
  timeline
}

///|
fn subtitle_document(timeline : Array[MasterTimelineEntry]) -> String {
  let blocks : Array[String] = []
  let mut cursor = 0
  for index, entry in timeline {
    let end = cursor + entry.duration_ms
    blocks.push(
      (index + 1).to_string() +
      "\n" +
      srt_time(cursor) +
      " --> " +
      srt_time(end) +
      "\n" +
      entry.subtitle +
      "\n",
    )
    cursor = end
  }
  blocks.join("\n")
}

///|
async fn LongformProductionService::probe_master(
  self : LongformProductionService,
  path : String,
) -> MasterMedia {
  let result = @host_process.run_capture({
    executable: self.ffprobe_executable,
    arguments: [
      "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 2097152,
  })
  if result.exit_code != Some(0) || result.timed_out || result.output_truncated {
    raise LongformProbeFailed("ffprobe_failed")
  }
  let document : ProbeDocument = @json.from_json(
    @json.parse(@utf8.decode(result.stdout)),
  ) catch {
    _ => raise LongformProbeFailed("ffprobe_json_invalid")
  }
  let mut video : ProbeStream? = None
  let mut has_audio = false
  let mut has_subtitles = false
  for stream in document.streams {
    if stream.codec_type == "video" && video is None {
      video = Some(stream)
    }
    if stream.codec_type == "audio" {
      has_audio = true
    }
    if stream.codec_type == "subtitle" {
      has_subtitles = true
    }
  }
  let video_stream = match video {
    None => raise LongformProbeFailed("master_video_missing")
    Some(value) => value
  }
  let duration = match document.format.duration {
    Some(value) => @string.parse_double(value) catch { _ => 0.0 }
    None => 0.0
  }
  {
    duration_seconds: duration,
    format_name: document.format.format_name.unwrap_or(""),
    video_codec: video_stream.codec_name.unwrap_or(""),
    width: video_stream.width,
    height: video_stream.height,
    has_audio,
    has_subtitles,
  }
}

///|
pub async fn LongformProductionService::assemble_master(
  self : LongformProductionService,
  snapshot : @kernel.ProjectSnapshot,
  request : MasterAssemblyRequest,
) -> MasterProvenance {
  if request.contract != "mooncast.master-assembly-request.v1" ||
    request.expected_project_revision != snapshot.revision ||
    request.evidence_digest == "" {
    raise LongformRequestInvalid(
      "exact project revision and evidence are required",
    )
  }
  if !has_gate(snapshot, G4) {
    raise LongformGateRequired("G4")
  }
  if self.ffmpeg_executable == "" || self.ffprobe_executable == "" {
    raise LongformCompositionFailed(
      "configured ffmpeg and ffprobe are required",
    )
  }
  let timeline = build_timeline(snapshot, request.shot_media)
  let timeline_digest = longform_digest(timeline.to_json().stringify())
  let master_id = longform_digest(
    snapshot.graph.project_id + ":" + timeline_digest + ":AI GENERATED",
  )[7:27].to_owned()
  let master_key = "master-" + master_id + ".mp4"
  let subtitle_key = "master-" + master_id + ".srt"
  let concat_key = "master-" + master_id + ".concat"
  let provenance_key = "master-" + master_id + ".json"
  match
    (self.masters.get_blob(master_key), self.masters.get_json(provenance_key)) {
    (Some(_), Some(value)) => {
      let cached : MasterProvenance = @json.from_json(value) catch {
        _ => raise LongformCompositionFailed("cached provenance is invalid")
      }
      return cached
    }
    _ => ()
  }
  let concat_lines : Array[String] = []
  for entry in timeline {
    let blob = match self.source.get_blob(entry.source_key) {
      None => raise LongformSourceMissing(entry.source_key)
      Some(value) => value
    }
    if blob.sha256 != entry.source_sha256 &&
      "sha256:" + blob.sha256 != entry.source_sha256 {
      raise LongformSourceMissing(entry.source_key)
    }
    concat_lines.push(
      "file '" + concat_escape(self.source.owned_path(entry.source_key)) + "'",
    )
  }
  ignore(
    self.masters.put_blob(
      concat_key,
      @utf8.encode(concat_lines.join("\n") + "\n"),
    ),
  )
  let subtitle_blob = self.masters.put_blob(
    subtitle_key,
    @utf8.encode(subtitle_document(timeline)),
  )
  let output_path = self.masters.owned_path(master_key)
  let result = @host_process.run_capture({
    executable: self.ffmpeg_executable,
    arguments: [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "concat",
      "-safe",
      "0",
      "-i",
      self.masters.owned_path(concat_key),
      "-i",
      self.masters.owned_path(subtitle_key),
      "-map",
      "0:v:0",
      "-map",
      "0:a:0",
      "-map",
      "1:0",
      "-c:v",
      "copy",
      "-c:a",
      "copy",
      "-c:s",
      "mov_text",
      "-metadata",
      "title=Mooncast systematic long-form master",
      "-metadata",
      "comment=AI GENERATED; project=" +
      snapshot.graph.project_id +
      "; timeline=" +
      timeline_digest,
      "-metadata:s:s:0",
      "language=eng",
      "-movflags",
      "+faststart",
      output_path,
    ],
    working_directory: None,
    timeout_ms: 90000,
    max_output_bytes: 2097152,
  })
  if result.exit_code != Some(0) || result.timed_out || result.output_truncated {
    raise LongformCompositionFailed("master_assembly_failed")
  }
  let media = self.probe_master(output_path)
  let target = snapshot.graph.target_duration_seconds.to_double()
  if media.duration_seconds < target - 1.0 ||
    media.duration_seconds > target + 2.0 ||
    !media.has_audio ||
    !media.has_subtitles {
    raise LongformProbeFailed("master_duration_or_streams_invalid")
  }
  let master_blob = match self.masters.get_blob(master_key) {
    None => raise LongformCompositionFailed("master_output_missing")
    Some(value) => value
  }
  let provenance : MasterProvenance = {
    contract: "mooncast.master-provenance.v2",
    master_id,
    project_id: snapshot.graph.project_id,
    project_revision: snapshot.revision,
    master_key,
    subtitle_key,
    provenance_key,
    sha256: master_blob.sha256,
    timeline_digest,
    timeline,
    media,
    explicit_ai_label: "AI GENERATED burned into every shot",
    qc_checks: [
      "target-duration", "video-present", "audio-present", "subtitle-stream-present",
      "ai-label-present", "shot-lineage-complete",
    ],
    created_at: @runtime.wall_clock_ms().to_string(),
    process_effect_performed: true,
    publication_effect_performed: false,
  }
  ignore(self.masters.put_json(provenance_key, provenance.to_json()))
  ignore(subtitle_blob)
  provenance
}

///|
pub fn master_domain_record(
  snapshot : @kernel.ProjectSnapshot,
  provenance : MasterProvenance,
) -> @governance.Master {
  let version = match snapshot.master {
    None => 1
    Some(value) => value.reference.version + 1
  }
  {
    reference: {
      id: snapshot.graph.project_id + "-master",
      version,
      digest: longform_digest(provenance.to_json().stringify()),
    },
    duration_seconds: provenance.media.duration_seconds.to_int(),
    video_digest: "sha256:" + provenance.sha256,
    audio_digest: "sha256:" + provenance.sha256,
    subtitle_digest: longform_digest(provenance.subtitle_key),
    provenance_digest: longform_digest(provenance.to_json().stringify()),
    ai_label: provenance.explicit_ai_label,
  }
}

///|
pub async fn LongformProductionService::provenance(
  self : LongformProductionService,
  master_id : String,
) -> MasterProvenance? {
  match self.masters.get_json("master-" + master_id + ".json") {
    None => None
    Some(value) => {
      let record : MasterProvenance = @json.from_json(value) catch {
        _ => raise LongformCompositionFailed("master provenance is invalid")
      }
      Some(record)
    }
  }
}

///|
pub async fn LongformProductionService::provenance_for_project(
  self : LongformProductionService,
  project_id : String,
) -> MasterProvenance? {
  let mut current : MasterProvenance? = None
  for key in self.masters.list_keys(prefix="master-", suffix=".json") {
    match self.masters.get_json(key) {
      None => ()
      Some(value) => {
        let record : MasterProvenance = @json.from_json(value) catch {
          _ => continue
        }
        if record.project_id == project_id {
          match current {
            None => current = Some(record)
            Some(previous) =>
              if record.project_revision > previous.project_revision {
                current = Some(record)
              }
          }
        }
      }
    }
  }
  current
}

///|
pub async fn LongformProductionService::master_blob(
  self : LongformProductionService,
  master_id : String,
) -> @store.StoredBlob? {
  self.masters.get_blob("master-" + master_id + ".mp4")
}

///|
pub async fn LongformProductionService::prepare_delivery(
  self : LongformProductionService,
  snapshot : @kernel.ProjectSnapshot,
) -> PreparedDeliveryRecord {
  if !has_gate(snapshot, G5) {
    raise LongformGateRequired("G5")
  }
  let delivery = match snapshot.delivery_package {
    None =>
      raise LongformDeliveryNotReady("approved delivery package is required")
    Some(value) => value
  }
  if !@governance.delivery_exact_accepted(
      Some(delivery),
      snapshot.master,
      snapshot.delivery_acceptances,
    ) {
    raise LongformDeliveryNotReady("exact delivery acceptance is required")
  }
  let package_digest = longform_digest(delivery.to_json().stringify())
  let delivery_key = "delivery-" +
    snapshot.graph.project_id +
    "-" +
    package_digest[7:27].to_owned() +
    ".json"
  let record : PreparedDeliveryRecord = {
    contract: "mooncast.prepared-delivery.v1",
    project_id: snapshot.graph.project_id,
    project_revision: snapshot.revision,
    delivery_package: delivery,
    delivery_key,
    package_digest,
    prepared_at: @runtime.wall_clock_ms().to_string(),
    external_effect_performed: false,
    publication_effect_performed: false,
  }
  match self.deliveries.get_json(delivery_key) {
    Some(value) if value.stringify() != record.to_json().stringify() =>
      raise LongformDeliveryNotReady("immutable delivery key conflict")
    Some(_) => ()
    None => ignore(self.deliveries.put_json(delivery_key, record.to_json()))
  }
  record
}
