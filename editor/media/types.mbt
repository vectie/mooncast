///|
pub(all) struct ByteRange {
  start : Int
  length : Int
  total : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaObjectRecord {
  contract : String
  digest : String
  size : Int
  mime : String
  duration : Double?
  role : String
  original_digest : String
  locator : String
  source_refs : Array[String]
  provenance_refs : Array[String]
  rights_refs : Array[String]
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct VideoAnalysis {
  state : String
  width : Int?
  height : Int?
  codec : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AudioAnalysis {
  state : String
  channels : Int?
  sample_rate : Int?
  codec : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ThumbnailAnalysis {
  state : String
  digest : String?
  mime : String?
  width : Int?
  height : Int?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WaveformAnalysis {
  state : String
  peak_count : Int
  peaks : Array[Int]
  digest : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaAnalysis {
  contract : String
  analysis_version : String
  analysis_id : String
  source_digest : String
  source_size : Int
  source_mime : String
  state : String
  duration_seconds : Double?
  video : VideoAnalysis
  audio : AudioAnalysis
  thumbnail : ThumbnailAnalysis
  waveform : WaveformAnalysis
  analysis_digest : String?
  source_url : String?
  thumbnail_url : String?
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IntakeRequest {
  contract : String
  project_id : String
  expected_editor_revision : Int
  idempotency_key : String
  role : String
  file_name : String
  mime_type : String
  size_bytes : Int
  sha256 : String
  duration_ticks : Int
  identity : @domain.ProductionIdentity
  rights : @domain.RightsAttestation
  source : @domain.MediaSourceAttestation
  created_by : String
  created_at : String
  request_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreparedIntake {
  contract : String
  intake_id : String
  request : IntakeRequest
  status : String
  upload_path : String
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CompletedIntake {
  receipt : @domain.LocalMediaReceipt
  binding : @domain.LocalMediaBinding
  media_ref : @domain.MediaRef
  media_record : MediaObjectRecord
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaByteDescriptor {
  digest : String
  object_key : String
  mime : String
  range : ByteRange
  etag : String
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaFinding {
  code : String
  digest : String
  locator : String
  detail : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaResolution {
  record : MediaObjectRecord?
  findings : Array[MediaFinding]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaAvailability {
  state : String
  digest : String
  mime : String?
  size : Int?
  source_descriptor : MediaByteDescriptor?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaRecoveryPlan {
  contract : String
  findings : Array[MediaFinding]
  regenerate_digests : Array[String]
  restore_original_digests : Array[String]
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)
