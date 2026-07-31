///|
pub(all) struct ProjectCommandReceipt {
  command_id : String
  input_digest : String
  result_key : String
  result_digest : String
  result_revision : Int
  ok : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectRecord {
  contract : String
  project_id : String
  created_at : String
  updated_at : String
  deleted : Bool
  deleted_at : String?
  snapshot : @kernel.ProjectSnapshot
  events : Array[@kernel.ProjectEvent]
  command_receipts : Array[ProjectCommandReceipt]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectSummary {
  project_id : String
  title : String
  revision : Int
  stage : String
  current_gate : String?
  next_gate : String?
  updated_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectCommandRequest {
  expected_revision : Int
  command : @kernel.ProjectCommand
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectCommandResponse {
  project : ProjectRecord
  result : @kernel.CommandResult
  idempotent_replay : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeArtifactRequest {
  expected_revision : Int
  command_id : String
  recorded_at : String
  evidence_digest : String
  artifact : @creative.CreativeArtifact
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeDecisionRequest {
  expected_revision : Int
  command_id : String
  recorded_at : String
  evidence_digest : String
  decision : @creative.CreativeDecision
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GateCommandRequest {
  expected_revision : Int
  command_id : String
  recorded_at : String
  evidence_digest : String
  gate : String
  actor : String
  role : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeView {
  artifact : @creative.CreativeArtifact?
  history : Array[@creative.CreativeArtifact]
  decisions : Array[@creative.CreativeDecision]
  project_revision : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GovernanceView {
  project_revision : Int
  model_routing_plan : @governance.ModelRoutingPlan?
  model_routing_history : Array[@governance.ModelRoutingPlan]
  model_routing_decisions : Array[@governance.RoutingDecision]
  generation_attempts : Array[@governance.GenerationAttempt]
  shot_qc_findings : Array[@governance.QcFinding]
  shot_qc_decisions : Array[@governance.QcDecision]
  master_lineage : @governance.Master?
  master_decisions : Array[@governance.MasterDecision]
  delivery_package : @governance.DeliveryPackage?
  delivery_package_history : Array[@governance.DeliveryPackage]
  delivery_milestone_acceptances : Array[@governance.DeliveryAcceptance]
  publication_authorizations : Array[@governance.PublicationAuthorization]
  publication_receipts : Array[@governance.PublicationObservation]
  performance_reviews : Array[@governance.PerformanceReview]
  governance_invalidations : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderCommandReceipt {
  command_id : String
  input_digest : String
  result_key : String
  result_digest : String
  result_revision : Int
  ok : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderJobRecord {
  contract : String
  job : @execution.ProviderExecutionJob
  events : Array[@execution.ProviderExecutionEvent]
  command_receipts : Array[ProviderCommandReceipt]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderAuthorizationRequest {
  job : @execution.ProviderExecutionJob
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderCommandResponse {
  record : ProviderJobRecord
  result : @execution.ProviderExecutionResult
  idempotent_replay : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RoutedPlanRequest {
  expected_project_revision : Int
  execution_id : String
  actor_id : String
  binding_digest : String
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RoutedExecutionRecord {
  contract : String
  project_id : String
  execution : @execution.RoutedExecution
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MediaRecord {
  contract : String
  media_id : String
  content_type : String
  bytes : Int
  sha256 : String
  created_at : String
  source_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ResolvedMedia {
  record : MediaRecord
  content : Bytes
} derive(Debug, Eq)

///|
/// Application packages register only a bounded prefix and an async HTTP
/// adapter. The studio owns transport dispatch; execution, commerce and
/// handoff packages retain their own state machines and authority rules.
pub struct RouteExtension {
  prefix : String
  handler : async (@host_http.Request) -> @host_http.Response?
}

///|
pub fn RouteExtension::new(
  prefix : String,
  handler : async (@host_http.Request) -> @host_http.Response?,
) -> RouteExtension {
  { prefix, handler }
}

///|
pub(all) struct EditorProjectSummary {
  project_id : String
  revision : Int
  timeline_id : String
  duration_ticks : Int
  updated_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorOpenView {
  project_id : String
  revision : Int
  snapshot : @editor_domain.EditorProject
  command_log : Array[@editor_domain.CommandLogRecord]
  media_bindings : Array[@editor_domain.LocalMediaBinding]
  takes : Array[EditorTakeRecord]
  review_comments : Array[@editor_integration.ReviewComment]
  production_source : @editor_integration.ProductionSourceBinding?
  master_promotion : @editor_integration.MasterPromotionReceipt?
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorReviewCommentInput {
  comment_id : String
  kind : String
  start_tick : Int
  end_tick : Int
  text : String
  revision_round : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorReviewCommentRequest {
  expected_revision : Int
  idempotency_key : String
  comment : EditorReviewCommentInput
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorTakeRecord {
  take_id : String
  project_id : String
  media_ref_id : String
  media_digest : String
  mime_type : String
  role : String
  source_url : String
  thumbnail_url : String
  analysis_url : String
  proxy_state : String
  identity : @editor_domain.ProductionIdentity
  approved : Bool
  already_placed : Bool
  track_id : String
  track_kind : String
  add_clip_template : EditorAddClipTemplate?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorAddClipTemplate {
  track_id : String
  clip : @editor_domain.Clip
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorCreateRequest {
  project : @editor_domain.EditorProject
  content_digest : String
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorProductionImportRequest {
  production : @editor_integration.ProductionImport
  content_digest : String
  recorded_at : String
  expected_editor_revision : Int?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorPrepareIntakeRequest {
  expected_editor_revision : Int
  idempotency_key : String
  role : String
  file_name : String
  mime_type : String
  size_bytes : Int
  sha256 : String
  duration_ticks : Int
  identity : @editor_domain.ProductionIdentity
  rights : @editor_domain.RightsAttestation
  source : @editor_domain.MediaSourceAttestation
  created_by : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorPreparedIntake {
  intake : @editor_media.IntakeRequest
  intake_id : String
  upload_url : String
  status : String
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorMediaAnalysisView {
  analysis : @editor_media.MediaAnalysis
  proxy : @editor_plan.ProxyReadiness
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorPreviewCreateRequest {
  expected_editor_revision : Int
  idempotency_key : String
  quality : String
  job_id : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorExportCreateRequest {
  export_request : @editor_integration.ProductionExportRequest
  idempotency_key : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct UtilityConcatInputRequest {
  file_name : String
  mime_type : String
  size_bytes : Int
  sha256 : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct UtilityConcatCreateRequest {
  contract : String
  job_id : String
  idempotency_key : String
  inputs : Array[UtilityConcatInputRequest]
  created_by : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct UtilityConcatInput {
  index : Int
  file_name : String
  mime_type : String
  size_bytes : Int
  sha256 : String
  uploaded : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct UtilityConcatJob {
  contract : String
  job_id : String
  idempotency_key : String
  request_digest : String
  state : String
  inputs : Array[UtilityConcatInput]
  uploaded_count : Int
  expected_count : Int
  output_digest : String
  output_size : Int
  media_url : String
  error : String
  created_by : String
  created_at : String
  updated_at : String
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorJobView {
  job : @editor_jobs.EditorJob
  render_plan : @editor_plan.RenderPlan
  render_receipt : @editor_render.RenderReceipt?
  export_receipt : @editor_integration.ExportReceipt?
  export_spec : @editor_integration.ExportSpec?
  export_request : @editor_integration.ProductionExportRequest?
  media_url : String?
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EditorMasterPromotionEnvelope {
  request : @editor_integration.MasterPromotionRequest
  production_source : @editor_integration.ProductionSourceBinding
  master_id : String
  subtitle_ref : String
  promoted_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror StudioError {
  NotFound(entity~ : String, id~ : String)
  Conflict(code~ : String, message~ : String)
  Invalid(code~ : String, message~ : String)
} derive(Debug)

///|
pub fn StudioError::status(self : StudioError) -> Int {
  match self {
    NotFound(entity=_, id=_) => 404
    Conflict(code=_, message=_) => 409
    Invalid(code=_, message=_) => 422
  }
}

///|
pub fn StudioError::code(self : StudioError) -> String {
  match self {
    NotFound(entity~, id=_) => entity + "_not_found"
    Conflict(code~, message=_) => code
    Invalid(code~, message=_) => code
  }
}

///|
pub fn StudioError::message(self : StudioError) -> String {
  match self {
    NotFound(entity~, id~) => entity + " " + id + " was not found"
    Conflict(code=_, message~) => message
    Invalid(code=_, message~) => message
  }
}
