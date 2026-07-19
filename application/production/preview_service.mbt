///|
pub(all) struct PreviewBrief {
  prompt : String
  duration_seconds : Double
  rights_owner : String
  rights_confirmed : Bool
  brand_name : String
  audience : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewMedia {
  format_name : String
  duration_seconds : Double
  video_codec : String
  width : Int?
  height : Int?
  has_audio : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewCost {
  currency : String
  amount : Double
  maximum : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewAsset {
  contract : String
  asset_id : String
  created_at : String
  video_key : String
  metadata_key : String
  sha256 : String
  request_sha256 : String
  provider : String
  model : String
  creative_brief : PreviewBrief
  cost : PreviewCost
  media : PreviewMedia
  rights_scope : String
  safety_status : String
  explicit_ai_label : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewReview {
  contract : String
  review_id : String
  asset_id : String
  decision : String
  actor : String
  note : String
  target_sha256 : String
  reviewed_at : String
  external_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewRenderResult {
  asset : PreviewAsset
  created : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewAssetProjection {
  asset : PreviewAsset
  human_review : PreviewReview?
  review_required : Bool
  publication_status : String
  publication_eligible : Bool
  publication_adapter_invoked : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub suberror PreviewApplicationError {
  PreviewBriefInvalid(String)
  PreviewSafetyRejected
  PreviewRuntimeUnavailable(String)
  PreviewRenderFailed(String)
  PreviewProbeFailed(String)
  PreviewAssetNotFound(String)
  PreviewReviewInvalid(String)
} derive(Debug)

///|
pub struct LegacyPreviewService {
  state : @store.AtomicStore
  media : @store.AtomicStore
  media_root : String
  ffmpeg_executable : String
  ffprobe_executable : String
  font_path : String
}

///|
pub fn LegacyPreviewService::new(
  state_root : String,
  media_root : String,
  ffmpeg_executable : String,
  ffprobe_executable : String,
  font_path : String,
) -> LegacyPreviewService {
  {
    state: @store.AtomicStore::new(state_root, max_read_bytes=16777216),
    media: @store.AtomicStore::new(media_root),
    media_root,
    ffmpeg_executable,
    ffprobe_executable,
    font_path,
  }
}

///|
fn preview_digest(value : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn preview_now() -> String {
  @runtime.wall_clock_ms().to_string()
}

///|
fn bounded_text(
  value : String,
  field : String,
  maximum : Int,
) -> String raise PreviewApplicationError {
  let normalized = value.trim().to_owned()
  if normalized == "" ||
    normalized.length() > maximum ||
    normalized.contains("\u0000") {
    raise PreviewBriefInvalid(field)
  }
  normalized
}

///|
pub fn normalize_preview_brief(
  brief : PreviewBrief,
) -> PreviewBrief raise PreviewApplicationError {
  let prompt = bounded_text(brief.prompt, "prompt", 1000)
  let lowered = prompt.to_lower()
  if lowered.contains("child sexual") ||
    lowered.contains("credit card dump") ||
    lowered.contains("terrorist recruitment") {
    raise PreviewSafetyRejected
  }
  if brief.duration_seconds < 1.0 || brief.duration_seconds > 12.0 {
    raise PreviewBriefInvalid("duration_seconds")
  }
  if !brief.rights_confirmed {
    raise PreviewBriefInvalid("rights_confirmed")
  }
  {
    prompt,
    duration_seconds: brief.duration_seconds,
    rights_owner: bounded_text(brief.rights_owner, "rights_owner", 200),
    rights_confirmed: true,
    brand_name: if brief.brand_name.trim() == "" {
      "Mooncast"
    } else {
      brief.brand_name.trim().to_owned()
    },
    audience: if brief.audience.trim() == "" {
      "general"
    } else {
      brief.audience.trim().to_owned()
    },
  }
}

///|
pub fn deterministic_preview_cost(duration_seconds : Double) -> Double? {
  if duration_seconds < 1.0 || duration_seconds > 12.0 {
    None
  } else {
    Some(duration_seconds * 0.08)
  }
}

///|
fn preview_request_digest(brief : PreviewBrief) -> String {
  preview_digest(brief.to_json().stringify())
}

///|
fn preview_record_key(asset_id : String) -> String {
  "preview-asset-" + asset_id + ".json"
}

///|
fn preview_video_key(asset_id : String) -> String {
  "preview-asset-" + asset_id + ".mp4"
}

///|
pub async fn LegacyPreviewService::get_asset(
  self : LegacyPreviewService,
  asset_id : String,
) -> PreviewAsset? {
  match self.state.get_json(preview_record_key(asset_id)) {
    None => None
    Some(value) => {
      let asset : PreviewAsset = @json.from_json(value) catch {
        _ => raise PreviewAssetNotFound(asset_id)
      }
      Some(asset)
    }
  }
}

///|
pub async fn LegacyPreviewService::list_assets(
  self : LegacyPreviewService,
) -> Array[PreviewAsset] {
  let assets : Array[PreviewAsset] = []
  for key in self.state.list_keys(prefix="preview-asset-", suffix=".json") {
    match self.state.get_json(key) {
      None => ()
      Some(value) => {
        let asset : PreviewAsset = @json.from_json(value) catch {
          _ => continue
        }
        assets.push(asset)
      }
    }
  }
  assets
}

///|
pub async fn LegacyPreviewService::get_projection(
  self : LegacyPreviewService,
  asset_id : String,
) -> PreviewAssetProjection? {
  let asset = match self.get_asset(asset_id) {
    None => return None
    Some(value) => value
  }
  let reviews = self.reviews(asset_id)
  let latest = if reviews.length() == 0 {
    None
  } else {
    Some(reviews[reviews.length() - 1])
  }
  Some({
    asset,
    human_review: latest,
    review_required: true,
    publication_status: "not_published",
    publication_eligible: match latest {
      Some(review) => review.decision == "approved"
      None => false
    },
    publication_adapter_invoked: false,
  })
}

///|
pub async fn LegacyPreviewService::list_projections(
  self : LegacyPreviewService,
) -> Array[PreviewAssetProjection] {
  let projections : Array[PreviewAssetProjection] = []
  for asset in self.list_assets() {
    match self.get_projection(asset.asset_id) {
      Some(value) => projections.push(value)
      None => ()
    }
  }
  projections
}

///|
pub async fn LegacyPreviewService::media_blob(
  self : LegacyPreviewService,
  asset_id : String,
) -> @store.StoredBlob? {
  match self.get_asset(asset_id) {
    None => None
    Some(asset) => self.media.get_blob(asset.video_key)
  }
}

///|
pub async fn LegacyPreviewService::review(
  self : LegacyPreviewService,
  asset_id : String,
  decision : String,
  actor : String,
  note : String,
) -> PreviewReview {
  let asset = match self.get_asset(asset_id) {
    None => raise PreviewAssetNotFound(asset_id)
    Some(value) => value
  }
  let normalized_decision = match decision {
    "approve" | "approved" => "approved"
    "reject" | "rejected" => "rejected"
    _ => raise PreviewReviewInvalid("decision")
  }
  let reviewer = bounded_text(actor, "actor", 100)
  let review : PreviewReview = {
    contract: "mooncast.preview-review.v1",
    review_id: @runtime.new_id(prefix="preview-review"),
    asset_id,
    decision: normalized_decision,
    actor: reviewer,
    note: note.trim().to_owned(),
    target_sha256: asset.sha256,
    reviewed_at: preview_now(),
    external_effect_performed: false,
  }
  ignore(
    self.state.put_json(
      "preview-review-" + asset_id + "-" + review.review_id + ".json",
      review.to_json(),
    ),
  )
  review
}

///|
pub async fn LegacyPreviewService::reviews(
  self : LegacyPreviewService,
  asset_id : String,
) -> Array[PreviewReview] {
  let reviews : Array[PreviewReview] = []
  for
    key in self.state.list_keys(
      prefix="preview-review-" + asset_id + "-",
      suffix=".json",
    ) {
    match self.state.get_json(key) {
      None => ()
      Some(value) => {
        let review : PreviewReview = @json.from_json(value) catch {
          _ => continue
        }
        reviews.push(review)
      }
    }
  }
  reviews
}

///|
pub(all) struct ProbeStream {
  codec_type : String
  codec_name : String?
  width : Int?
  height : Int?
} derive(Debug, FromJson)

///|
pub(all) struct ProbeFormat {
  format_name : String?
  duration : String?
} derive(Debug, FromJson)

///|
pub(all) struct ProbeDocument {
  streams : Array[ProbeStream]
  format : ProbeFormat
} derive(Debug, FromJson)

///|
async fn LegacyPreviewService::probe(
  self : LegacyPreviewService,
  path : String,
) -> PreviewMedia {
  let result = @host_process.run_capture({
    executable: self.ffprobe_executable,
    arguments: [
      "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path,
    ],
    working_directory: None,
    timeout_ms: 15000,
    max_output_bytes: 1048576,
  })
  if result.exit_code != Some(0) || result.timed_out || result.output_truncated {
    raise PreviewProbeFailed("ffprobe_failed")
  }
  let document : ProbeDocument = @json.from_json(
    @json.parse(@utf8.decode(result.stdout)),
  ) catch {
    _ => raise PreviewProbeFailed("ffprobe_json_invalid")
  }
  let mut video : ProbeStream? = None
  let mut has_audio = false
  for stream in document.streams {
    if stream.codec_type == "video" && video is None {
      video = Some(stream)
    }
    if stream.codec_type == "audio" {
      has_audio = true
    }
  }
  let stream = match video {
    None => raise PreviewProbeFailed("video_stream_missing")
    Some(value) => value
  }
  let duration = match document.format.duration {
    Some(value) => @string.parse_double(value) catch { _ => 0.0 }
    None => 0.0
  }
  if duration <= 0.0 || duration > 12.25 {
    raise PreviewProbeFailed("video_duration_invalid")
  }
  {
    format_name: document.format.format_name.unwrap_or(""),
    duration_seconds: duration,
    video_codec: stream.codec_name.unwrap_or(""),
    width: stream.width,
    height: stream.height,
    has_audio,
  }
}

///|
pub async fn LegacyPreviewService::render(
  self : LegacyPreviewService,
  raw : PreviewBrief,
) -> PreviewRenderResult {
  let brief = normalize_preview_brief(raw)
  if self.ffmpeg_executable == "" ||
    self.ffprobe_executable == "" ||
    self.font_path == "" {
    raise PreviewRuntimeUnavailable(
      "configured ffmpeg, ffprobe, and TrueType font are required",
    )
  }
  let request_sha256 = preview_request_digest(brief)
  let asset_id = request_sha256[:20].to_owned()
  match
    (self.get_asset(asset_id), self.media.get_blob(preview_video_key(asset_id))) {
    (Some(asset), Some(_)) => return { asset, created: false }
    _ => ()
  }
  let video_key = preview_video_key(asset_id)
  let output_path = self.media.owned_path(video_key)
  let primary = request_sha256[:6].to_owned()
  let filter = "drawtext=fontfile='" +
    self.font_path.replace_all(old="'", new="\\'") +
    "':text='MOONCAST / LOCAL PREVIEW':x=48:y=48:fontsize=28:fontcolor=white," +
    "drawtext=fontfile='" +
    self.font_path.replace_all(old="'", new="\\'") +
    "':text='AI GENERATED':x=w-tw-40:y=h-th-32:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.62:boxborderw=10,format=yuv420p"
  let duration = brief.duration_seconds.to_string()
  let result = @host_process.run_capture({
    executable: self.ffmpeg_executable,
    arguments: [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "lavfi",
      "-i",
      "color=c=0x" + primary + ":s=960x540:r=24:d=" + duration,
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=330:sample_rate=44100:duration=" + duration,
      "-vf",
      filter,
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-crf",
      "24",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "aac",
      "-b:a",
      "96k",
      "-shortest",
      "-movflags",
      "+faststart",
      "-metadata",
      "title=Mooncast AI-generated local preview",
      "-metadata",
      "comment=prompt_sha256:" + request_sha256,
      output_path,
    ],
    working_directory: None,
    timeout_ms: 45000,
    max_output_bytes: 1048576,
  })
  if result.exit_code != Some(0) || result.timed_out || result.output_truncated {
    raise PreviewRenderFailed("ffmpeg_failed")
  }
  let media = self.probe(output_path)
  let blob = match self.media.get_blob(video_key) {
    None => raise PreviewRenderFailed("render_output_missing")
    Some(value) => value
  }
  let asset : PreviewAsset = {
    contract: "mooncast.preview-asset.v1",
    asset_id,
    created_at: preview_now(),
    video_key,
    metadata_key: preview_record_key(asset_id),
    sha256: blob.sha256,
    request_sha256,
    provider: "mooncast-local",
    model: "ffmpeg-lavfi-motion-v1",
    creative_brief: brief,
    cost: {
      currency: "CNY",
      amount: brief.duration_seconds * 0.08,
      maximum: 0.96,
    },
    media,
    rights_scope: "local generation and reviewed campaign delivery",
    safety_status: "passed",
    explicit_ai_label: "AI GENERATED visible in every frame",
    publication_authority: false,
  }
  ignore(self.state.put_json(preview_record_key(asset_id), asset.to_json()))
  { asset, created: true }
}

///|
pub(all) struct ProductionRuntimeReadiness {
  contract : String
  moonbit_native : Bool
  ffmpeg_configured : Bool
  ffprobe_configured : Bool
  font_configured : Bool
  automatic_download_performed : Bool
  ready : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn LegacyPreviewService::runtime_readiness(
  self : LegacyPreviewService,
) -> ProductionRuntimeReadiness {
  let ffmpeg = self.ffmpeg_executable != ""
  let ffprobe = self.ffprobe_executable != ""
  let font = self.font_path != ""
  {
    contract: "mooncast.production-runtime-readiness.v1",
    moonbit_native: true,
    ffmpeg_configured: ffmpeg,
    ffprobe_configured: ffprobe,
    font_configured: font,
    automatic_download_performed: false,
    ready: @runtime.is_supported_platform() && ffmpeg && ffprobe && font,
  }
}
