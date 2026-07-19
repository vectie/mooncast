///|
/// The Studio UI is a projection and command surface. Canonical project state
/// remains in the native Mooncast service and is replaced after every command.
enum StudioTab {
  Overview
  NeedsStrategy
  Creative
  AssetFactory
  StoryboardAnimatic
  Routing
  ShotBoard
  Delivery
  Commercial
} derive(Eq)

///|
struct MoonWikiEvidenceProjection {
  source_id : String
  source_version : String
  source_digest : String
  provenance_ref : String
} derive(FromJson)

///|
struct IntakeIntentProjection {
  brief : MoonWikiEvidenceProjection
  bible : MoonWikiEvidenceProjection
  script : MoonWikiEvidenceProjection
} derive(FromJson)

///|
struct IntakeClientNeedProjection {
  customer : String
  payable_problem : String
  audience : String
  channels : Array[String]
  acceptance_method : String
  repeat_purchase_hypothesis : String
} derive(FromJson)

///|
struct IntakeContractProjection {
  contract_ref : String
  budget_ceiling_cny : Double
  revision_limit : Int
  target_duration_seconds : Int
  deliverables : Array[String]
  payment_milestones : Array[String]
} derive(FromJson)

///|
struct IntakeConstraintsProjection {
  rights_owner : String
  rights_confirmed : Bool
  rights_constraints : Array[String]
  confidentiality_class : String
  permitted_provider_ids : Array[String]
  prohibited_provider_ids : Array[String]
  permitted_data_class : String
} derive(FromJson)

///|
struct IntakeStrategyProjection {
  project_title : String
  objective : String
  narrative_proposition : String
  tone : String
  claims : Array[String]
  success_metrics : Array[String]
  negative_constraints : Array[String]
} derive(FromJson)

///|
struct NeedsPacketProjection {
  contract : String
  packet_id : String
  packet_version : Int
  exported_at : String
  evidence_refs : Array[MoonWikiEvidenceProjection]
  intent_refs : IntakeIntentProjection
  client_need : IntakeClientNeedProjection
  contract_boundary : IntakeContractProjection
  constraints : IntakeConstraintsProjection
  creative_strategy : IntakeStrategyProjection
  unresolved_questions : Array[String]
  publication_authority : Bool
  provider_execution_authority : Bool
} derive(FromJson)

///|
struct IntakeValidationProjection {
  complete : Bool
  errors : Array[String]
  unresolved_questions : Array[String]
  provenance_digest : String
} derive(FromJson)

///|
struct ImportedIntakeProjection {
  packet : NeedsPacketProjection
  validation : IntakeValidationProjection
  imported_at : String
  immutable : Bool
} derive(FromJson)

///|
struct IntakeDecisionProjection {
  packet_id : String
  packet_version : Int
  provenance_digest : String
  decision : String
  actor : String
  actor_role : String
  note : String
  decided_at : String
  human_confirmed : Bool
  decision_digest : String
} derive(FromJson)

///|
struct IntakeBindingProjection {
  binding_id : String
  project_id : String
  project_revision : Int
  intake_id : String
  intake_version : Int
  intake_provenance_digest : String
  approval_digest : String
} derive(FromJson)

///|
struct NeedsIntakeWorkspaceProjection {
  intakes : Array[ImportedIntakeProjection]
  decisions : Array[IntakeDecisionProjection]
  bindings : Array[IntakeBindingProjection]
  publication_authority : Bool
  provider_execution_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct AssetVersionRefProjection {
  id : String
  version : Int
  digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct AssetFactorySpecProjection {
  asset_id : String
  asset_version : Int
  kind : String
  capability : String
  title : String
  variant_limit : Int
  retry_limit : Int
  cost_ceiling_cny : Double
  dependent_shot_ids : Array[String]
} derive(FromJson)

///|
#warnings("-unused_field")
struct AssetFactoryPlanProjection {
  plan : AssetVersionRefProjection
  project_id : String
  project_revision : Int
  specs : Array[AssetFactorySpecProjection]
  total_cost_ceiling_cny : Double
} derive(FromJson)

///|
#warnings("-unused_field")
struct AssetFactoryDecisionProjection {
  plan : AssetVersionRefProjection
  decision : String
  actor : String
  actor_role : String
  decided_at : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct AssetFactoryVariantProjection {
  variant_id : String
  asset_id : String
  asset_version : Int
  variant : Int
  modality : String
  state : String
  output_digest : String?
  cost_cny : Double
} derive(FromJson)

///|
#warnings("-unused_field")
struct AssetFactoryApprovedProjection {
  reference : Json
  variant_id : String
  modality : String
  approval_actor : String
  approval_digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct AnimaticRenderRefProjection {
  id : String
  version : Int
  digest : String
} derive(FromJson)

///|
struct AnimaticBudgetProjection {
  planned_cny : Double
  actual_cny : Double
  within_ceiling : Bool
  evidence_digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct AnimaticRenderProjection {
  reference : AnimaticRenderRefProjection
  panel_count : Int
  duration_seconds : Int
  storyboard_sheet_digest : String
  video_digest : String
  budget : AnimaticBudgetProjection
  provider : String
  model : String
  immutable : Bool
} derive(FromJson)

///|
struct AnimaticAttemptProjection {
  attempt_id : String
  attempt : Int
  state : String
  failure : String?
} derive(FromJson)

///|
#warnings("-unused_field")
struct AnimaticApprovalProjection {
  rendered : AnimaticRenderProjection
  actor : String
  actor_role : String
  approval_digest : String
} derive(FromJson)

///|
struct AnimaticWorkspaceProjection {
  plans : Array[Json]
  attempts : Array[AnimaticAttemptProjection]
  renders : Array[AnimaticRenderProjection]
  approvals : Array[AnimaticApprovalProjection]
  publication_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct AssetFactoryBindingProjection {
  binding_id : String
  shot_id : String
  assets : Array[Json]
} derive(FromJson)

///|
#warnings("-unused_field")
struct AssetFactoryWorkspaceProjection {
  plans : Array[AssetFactoryPlanProjection]
  plan_decisions : Array[AssetFactoryDecisionProjection]
  variants : Array[AssetFactoryVariantProjection]
  findings : Array[Json]
  approved_assets : Array[AssetFactoryApprovedProjection]
  shot_bindings : Array[AssetFactoryBindingProjection]
  total_spent_cny : Double
  publication_authority : Bool
  provider_execution_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct GateProjection {
  name : String
  status : String
  receipt : Json?
} derive(FromJson)

///|
#warnings("-unused_field")
struct ArtifactDecisionProjection {
  decision : String
  actor : String
  actor_role : String
  note : String
  digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ArtifactProjection {
  artifact_id : String
  artifact_type : String
  version : Int
  digest : String
  status : String
  content : Json
  latest_decision : ArtifactDecisionProjection?
} derive(FromJson)

///|
#warnings("-unused_field")
struct SceneProjection {
  id : String
  title : String
  summary : String
  shot_ids : Array[String]
} derive(FromJson)

///|
#warnings("-unused_field")
struct EpisodeProjection {
  id : String
  title : String
  scenes : Array[SceneProjection]
} derive(FromJson)

///|
#warnings("-unused_field")
struct ShotQcProjection {
  status : String
  findings : Array[Json]
} derive(FromJson)

///|
#warnings("-unused_field")
struct ShotProjection {
  id : String
  episode_id : String
  scene_id : String
  order : Int
  duration_seconds : Double
  prompt : String
  subtitle : String
  framing : String
  location : String
  status : String
  asset_id : String?
  provider_attempt_id : String?
  qc : ShotQcProjection
} derive(FromJson)

///|
#warnings("-unused_field")
struct BudgetProjection {
  currency : String
  maximum : Double
  reserved : Double
  spent : Double
} derive(FromJson)

///|
#warnings("-unused_field")
struct RoutingRetryProjection {
  maximum_attempts : Int
  backoff_seconds : Int
  retryable_failures : Array[String]
} derive(FromJson)

///|
#warnings("-unused_field")
struct RouteProjection {
  route_id : String
  capability : String
  asset_class : String
  asset_ids : Array[String]
  provider : String
  model : String
  model_version : String
  permitted_data_class : String
  fallback : Array[String]
  retry_policy : RoutingRetryProjection
  unit_estimate_cny : Double
  cost_ceiling_cny : Double
} derive(FromJson)

///|
#warnings("-unused_field")
struct RoutingContentProjection {
  routes : Array[RouteProjection]
  estimated_total_cny : Double
  total_ceiling_cny : Double
} derive(FromJson)

///|
#warnings("-unused_field")
struct RoutingPlanProjection {
  version : Int
  digest : String
  content : RoutingContentProjection
} derive(FromJson)

///|
#warnings("-unused_field")
struct EconomicsProjection {
  provider_cost_cny : Double
  recognized_revenue_cny : Double
  gross_margin_cny : Double
} derive(FromJson)

///|
#warnings("-unused_field")
struct MasterMediaProjection {
  duration_seconds : Int
} derive(FromJson)

///|
#warnings("-unused_field")
struct MasterProjection {
  master_id : String
  version : Int
  digest : String
  sha256 : String
  media : MasterMediaProjection
} derive(FromJson)

///|
#warnings("-unused_field")
struct DeliveryPackageContentProjection {
  master_digest : String
  formats : Array[String]
  destinations : Array[String]
  provenance_included : Bool
  manifest_digest : String
  rights_ledger_digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct DeliveryPackageProjection {
  version : Int
  digest : String
  content : DeliveryPackageContentProjection
} derive(FromJson)

///|
#warnings("-unused_field")
struct HandoffRecordRefProjection {
  record_id : String
  record_version : String
  record_digest : String
  provenance_ref : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct FinalDeliverableHandoffProjection {
  record : HandoffRecordRefProjection
  episode_id : String
  export_job_id : String
  editor_output_digest : String
  prepared_at : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct OutcomeHandoffProjection {
  contract : String
  eligible_final_deliverables : Array[FinalDeliverableHandoffProjection]
  production_outcomes : Array[Json]
  external_handoff_requests : Array[Json]
  publication_authority : Bool
  payment_authority : Bool
  external_effect_authorized : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct ProjectProjection {
  contract : String
  id : String
  title : String
  objective : String
  audience : String
  channels : Array[String]
  target_duration_seconds : Int
  revision : Int
  stage : String
  current_gate : String?
  gates : Map[String, GateProjection]
  brief : ArtifactProjection?
  rights : ArtifactProjection?
  bible : ArtifactProjection?
  script : ArtifactProjection?
  claims_ledger : ArtifactProjection?
  storyboard : ArtifactProjection?
  animatic : ArtifactProjection?
  episodes : Array[EpisodeProjection]
  shots : Array[ShotProjection]
  budget : BudgetProjection
  model_routing_plan : RoutingPlanProjection?
  generation_attempts : Json
  master : MasterProjection?
  delivery_package : DeliveryPackageProjection?
  delivery_milestone_acceptances : Array[Json]
  publication_authorizations : Array[Json]
  publication_receipts : Array[Json]
  performance_reviews : Array[Json]
  outcome_handoff : OutcomeHandoffProjection
  governance_invalidations : Array[String]
  economics : EconomicsProjection
} derive(FromJson)

///|
#warnings("-unused_field")
struct ProjectSummaryProjection {
  project_id : String
  title : String
  revision : Int
  stage : String
  current_gate : String?
  next_gate : String?
  updated_at : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ProjectListProjection {
  projects : Array[ProjectSummaryProjection]
} derive(FromJson)

///|
#warnings("-unused_field")
struct RoutedShotBinding {
  shot_id : String
  route_id : String
  job_id : String
  cost_ceiling_cny : Double
} derive(FromJson)

///|
#warnings("-unused_field")
struct RoutedExecutionSummary {
  execution_id : String
  revision : Int
  state : String
  record_digest : String
  shots : Array[RoutedShotBinding]
} derive(FromJson)

///|
#warnings("-unused_field")
struct RoutedListProjection {
  executions : Array[RoutedExecutionSummary]
  publication_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct DeliveryBuildProjection {
  build_id : String
  build_digest : String
  state : String
  revision : Int
  attempt_count : Int
  recovery_count : Int
  master_sha256 : String
  delivery_digest : String
  download_url : String?
  last_error : String?
  record_digest : String
  publication_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct DeliveryListProjection {
  builds : Array[DeliveryBuildProjection]
  publication_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientBrandProjection {
  name : String
  accent : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientPortalProjection {
  contract : String
  portal_id : String
  project_id : String
  master_sha256 : String
  delivery_digest : String
  build_id : String
  build_digest : String
  client_name : String
  brand : ClientBrandProjection
  scopes : Array[String]
  expires_at : String
  status : String
  revision : Int
  created_by : String
  created_by_role : String
  created_at : String
  updated_at : String
  record_digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct PortalListProjection {
  portals : Array[ClientPortalProjection]
  publication_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct ClientPortalCreatedProjection {
  portal : ClientPortalProjection
  client_url : String
  raw_token_returned_once : Bool
  external_effect_performed : Bool
  publication_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct BillingProjection {
  contract : String
  billing_id : String
  project_id : String
  kind : String
  currency : String
  amount : Double
  reference : String
  state : String
  quoted_at : String
  due_at : String?
  paid_at : String?
  waived_at : String?
  revision : Int
  record_digest : String
  payment_effect_performed : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct BillingListProjection {
  entries : Array[BillingProjection]
  payment_effect_performed : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct LeadProjection {
  contract : String
  lead_id : String
  version : Int
  digest : String
  customer : String
  customer_contact_ref : String
  payable_problem : String
  baseline_cost_cny : Double
  baseline_time_hours : Double
  channels : Array[String]
  measurable_acceptance : Array[String]
  repeat_hypothesis : String
  status : String
  qualification : Json?
} derive(FromJson)

///|
#warnings("-unused_field")
struct QuotedProjectProjection {
  project_id : String
  title : String
  objective : String
  audience : String
  rights_owner : String
  target_duration_seconds : Int
  production_budget_cny : Double
} derive(FromJson)

///|
#warnings("-unused_field")
struct MarginProjection {
  quoted_revenue_cny : Double
  provider_cost_cny : Double
  labor_cost_cny : Double
  other_cost_cny : Double
  direct_cost_cny : Double
  gross_margin_cny : Double
  gross_margin_rate : Double
  contingency_cny : Double
  contribution_margin_cny : Double
  contribution_margin_rate : Double
  founder_hours : Double
  digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct QuoteProjection {
  contract : String
  quote_id : String
  version : Int
  digest : String
  source_lead_id : String
  source_lead_version : Int
  source_lead_digest : String
  project : QuotedProjectProjection
  deliverables : Array[String]
  revision_rounds : Int
  provider_overage_policy : String
  milestones : Array[Json]
  restrictions : Json
  schedule : Json
  forecast : MarginProjection
  status : String
  internal_approvals : Json
  client_acceptance : Json?
} derive(FromJson)

///|
#warnings("-unused_field")
struct ResourceProjection {
  contract : String
  resource_id : String
  version : Int
  digest : String
  name : String
  role : String
  skills : Array[String]
  weekly_hours : Double
  available_from : String
  available_to : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ReservationProjection {
  contract : String
  reservation_id : String
  revision : Int
  digest : String
  quote_id : String
  quote_version : Int
  quote_digest : String
  resource_id : String
  role : String
  skills : Array[String]
  start_date : String
  end_date : String
  hours : Double
  depends_on : Array[String]
  status : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ConversionProjection {
  contract : String
  quote_id : String
  quote_version : Int
  quote_digest : String
  capacity_digest : String
  project_id : String
  actor : String
  actor_role : String
  converted_at : String
  digest : String
  payment_effect_performed : Bool
  publication_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct CommercialDashboardProjection {
  contract : String
  revision : Int
  record_digest : String
  leads : Array[LeadProjection]
  quotes : Array[QuoteProjection]
  resources : Array[ResourceProjection]
  reservations : Array[ReservationProjection]
  conversions : Array[ConversionProjection]
  external_effects : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct CapacityBoardProjection {
  contract : String
  quote_id : String
  quote_version : Int
  quote_digest : String
  reservations : Array[ReservationProjection]
  utilization : Array[Json]
  conflicts : Array[Json]
  ready : Bool
  calculated_at : String
  digest : String
} derive(FromJson)

///|
struct CreateForm {
  project_id : String
  title : String
  objective : String
  audience : String
  channels : String
  rights_owner : String
  rights_confirmed : Bool
  duration_seconds : String
  maximum_budget_cny : String
}

///|
struct OperatorForm {
  actor : String
  role : String
  recorded_at : String
  note : String
  human_confirmed : Bool
}

///|
struct CommercialForm {
  customer : String
  contact_ref : String
  payable_problem : String
  baseline_cost_cny : String
  baseline_hours : String
  measurable_acceptance : String
  repeat_hypothesis : String
}

///|
struct QuoteForm {
  project_id : String
  title : String
  objective : String
  audience : String
  rights_owner : String
  duration_seconds : String
  production_budget_cny : String
  start_date : String
  delivery_date : String
  deliverables : String
  quoted_revenue_cny : String
  provider_cost_cny : String
  labor_cost_cny : String
  other_cost_cny : String
  founder_hours : String
  contingency_percent : String
  deposit_cny : String
  animatic_cny : String
  master_cny : String
}

///|
struct CapacityForm {
  resource_name : String
  resource_role : String
  resource_skills : String
  weekly_hours : String
  available_from : String
  available_to : String
  resource_id : String
  reservation_skills : String
  depends_on : String
  reservation_start : String
  reservation_end : String
  reservation_hours : String
}

///|
struct RoutingForm {
  route_id : String
  provider : String
  model : String
  model_version : String
  permitted_data_class : String
  cost_ceiling_cny : String
  total_cost_ceiling_cny : String
  retry_limit : String
  fallback_route_ids : String
}

///|
struct QcForm {
  shot_id : String
  attempt_id : String
  route_id : String
  prompt_digest : String
  source_asset_digests : String
  cost_cny : String
  output_digest : String
  attempt_status : String
  dimension : String
  finding_status : String
  evidence_digest : String
  finding_version : String
  finding_digest : String
  note : String
}

///|
struct DeliveryGovernanceForm {
  video_digest : String
  audio_digest : String
  subtitle_digest : String
  provenance_digest : String
  ai_label : String
  destination_ids : String
  manifest_digest : String
  rights_ledger_digest : String
  destination_id : String
  publication_scope : String
  publication_expires_at : String
  publication_receipt_digest : String
  publication_authority_ref : String
  performance_status : String
  performance_evidence_digest : String
  reach : String
  completion_rate : String
  conversion_rate : String
  revenue_cny : String
  provider_cost_cny : String
  founder_hours : String
  repeat_purchase_status : String
}

///|
struct ClientOpsForm {
  client_name : String
  brand_name : String
  brand_accent : String
  expires_at : String
  billing_kind : String
  billing_state : String
  billing_currency : String
  billing_amount : String
  billing_due_at : String
  billing_reference : String
  repeat_project_id : String
  repeat_title : String
  repeat_objective : String
  repeat_audience : String
  repeat_rights_owner : String
  repeat_duration_seconds : String
  repeat_budget_cny : String
}

///|
struct Model {
  tab : StudioTab
  loading : Bool
  busy : Bool
  projects : Array[ProjectSummaryProjection]
  selected_project_id : String
  project : ProjectProjection?
  routed : Array[RoutedExecutionSummary]
  delivery_builds : Array[DeliveryBuildProjection]
  client_portals : Array[ClientPortalProjection]
  billing_entries : Array[BillingProjection]
  latest_client_url : String?
  commercial : CommercialDashboardProjection?
  capacity_board : CapacityBoardProjection?
  needs_intake : NeedsIntakeWorkspaceProjection?
  asset_factory : AssetFactoryWorkspaceProjection?
  asset_plan_draft : String
  animatic_workspace : AnimaticWorkspaceProjection?
  animatic_plan_draft : String
  selected_intake_id : String
  intake_packet_draft : String
  intake_seed_project_id : String
  selected_lead_id : String
  selected_quote_id : String
  selected_artifact_kind : String
  artifact_draft : String
  create : CreateForm
  operator : OperatorForm
  commercial_form : CommercialForm
  quote_form : QuoteForm
  capacity_form : CapacityForm
  routing_form : RoutingForm
  qc_form : QcForm
  delivery_governance_form : DeliveryGovernanceForm
  client_ops_form : ClientOpsForm
  status : String
  error : String?
  command_sequence : Int
}

///|
enum Msg {
  Bootstrap
  SelectTab(StudioTab)
  SelectProject(String)
  RefreshProject
  LoadedProjects(Result[ProjectListProjection, Error])
  LoadedProject(Result[ProjectProjection, Error])
  LoadedRouted(Result[RoutedListProjection, Error])
  LoadedDeliveries(Result[DeliveryListProjection, Error])
  LoadedPortals(Result[PortalListProjection, Error])
  LoadedBilling(Result[BillingListProjection, Error])
  CreatedClientPortal(Result[ClientPortalCreatedProjection, Error])
  LoadedCommercial(Result[CommercialDashboardProjection, Error])
  LoadedCapacity(Result[CapacityBoardProjection, Error])
  LoadedNeedsIntake(Result[NeedsIntakeWorkspaceProjection, Error])
  LoadedAssetFactory(Result[AssetFactoryWorkspaceProjection, Error])
  SetAssetPlanDraft(String)
  RecordAssetPlan
  DecideAssetPlan(String)
  RunAssetFactory
  RecordAssetVariantQc(String)
  ApproveAssetVariant(String)
  BindAssetFactoryShots
  LoadedAnimaticWorkspace(Result[AnimaticWorkspaceProjection, Error])
  SetAnimaticPlanDraft(String)
  RecordAnimaticPlan
  RenderAnimatic
  ApproveRenderedAnimatic
  SelectIntake(String)
  SetIntakePacketDraft(String)
  SetIntakeSeedProjectId(String)
  ImportNeedsPacket
  DecideNeedsIntake(String)
  SeedProjectFromIntake
  ActionCompleted(String, Result[Json, Error])
  CreatedProject(Result[ProjectProjection, Error])
  SetCreateField(String, String)
  SetRightsConfirmed(Bool)
  CreateProject
  SelectArtifact(String)
  SetArtifactDraft(String)
  ReviseArtifact
  DecideArtifact(String)
  AdvanceGate(String)
  CreateRoutedExecution
  SetRoutingField(String, String)
  RecordRoutingPlan
  DecideRouting(String, String)
  SetQcField(String, String)
  SelectQcShot(String)
  RecordGenerationAttempt
  RecordQcFinding
  DecideQc(String)
  SetDeliveryGovernanceField(String, String)
  RecordMaster
  DecideMaster(String, String)
  RecordDeliveryPackage
  RecordDeliveryMilestone(String)
  AuthorizePublication(String)
  RecordPublicationObservation
  RecordPerformanceReview
  PrepareOutcomeHandoff(String)
  SetClientOpsField(String, String)
  CreateClientPortal
  ControlClientPortal(String, String)
  CreateBillingEntry
  TransitionBilling(String, String)
  CreateRepeatOrder
  RunRoutedShot(String, String, String)
  RunAllPendingShots(String)
  ConfirmBatchQc
  CreateDeliveryBuild
  RunDeliveryAction(String, String)
  AcceptDelivery(String)
  SetOperatorField(String, String)
  SetHumanConfirmed(Bool)
  SetCommercialField(String, String)
  CreateLead
  SelectLead(String)
  QualifyLead(String)
  SetQuoteField(String, String)
  CreateOrReviseQuote
  SelectQuote(String)
  DecideQuote(String)
  SetCapacityField(String, String)
  CreateResource
  CreateReservation
  LoadCapacity
  ConvertQuote
}

///|
fn starter_moonwiki_packet() -> String {
  let value =
    #|{
  #|  "contract": "moonwiki.mooncast-needs-export.v1",
  #|  "packet_id": "brand-episode-needs-001",
  #|  "packet_version": 1,
  #|  "exported_at": "2026-07-19T00:00:00+08:00",
  #|  "evidence_refs": [
  #|    {"source_id":"wiki-brief-001","source_version":"1","source_digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111","provenance_ref":"moonwiki://projects/brand/brief"},
  #|    {"source_id":"wiki-bible-001","source_version":"1","source_digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222","provenance_ref":"moonwiki://projects/brand/bible"},
  #|    {"source_id":"wiki-script-001","source_version":"1","source_digest":"sha256:3333333333333333333333333333333333333333333333333333333333333333","provenance_ref":"moonwiki://projects/brand/script"}
  #|  ],
  #|  "intent_refs": {
  #|    "brief":{"source_id":"wiki-brief-001","source_version":"1","source_digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111","provenance_ref":"moonwiki://projects/brand/brief"},
  #|    "bible":{"source_id":"wiki-bible-001","source_version":"1","source_digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222","provenance_ref":"moonwiki://projects/brand/bible"},
  #|    "script":{"source_id":"wiki-script-001","source_version":"1","source_digest":"sha256:3333333333333333333333333333333333333333333333333333333333333333","provenance_ref":"moonwiki://projects/brand/script"}
  #|  },
  #|  "client_need":{"customer":"Named design partner","payable_problem":"Produce a repeatable branded narrative episode faster than the current agency workflow","audience":"Customer-defined audience","channels":["review-only"],"acceptance_method":"Named client accepts the exact 3–8 minute master and provenance package","repeat_purchase_hypothesis":"Quarterly episode retainer"},
  #|  "contract_boundary":{"contract_ref":"contract:pending-signature","budget_ceiling_cny":20000,"revision_limit":2,"target_duration_seconds":240,"deliverables":["horizontal master","vertical master","subtitles","cover","provenance manifest"],"payment_milestones":["deposit","approved animatic","accepted master"]},
  #|  "constraints":{"rights_owner":"Named contract party","rights_confirmed":true,"rights_constraints":["licensed source assets only","named-human final review"],"confidentiality_class":"contract-confidential","permitted_provider_ids":["approved-provider"],"prohibited_provider_ids":[],"permitted_data_class":"rights-cleared-confidential"},
  #|  "creative_strategy":{"project_title":"Governed brand episode","objective":"Tell one complete branded story with measurable audience retention","narrative_proposition":"A character-led story demonstrates the product promise","tone":"confident, human, cinematic","claims":[],"success_metrics":["client acceptance","completion rate","repeat order"],"negative_constraints":["no invented product claims","no unlicensed identity"]},
  #|  "unresolved_questions":[],
  #|  "publication_authority":false,
  #|  "provider_execution_authority":false
    #|}
  value
}

///|
fn starter_asset_factory_plan(project : ProjectProjection) -> String {
  let shot_id = project.shots.get(0).map(shot => shot.id).unwrap_or("shot-001")
  let source_digest = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
  let prompt_digest = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
  let specs : Array[Json] = []
  for item in [
    ("hero", "character", "image"),
    ("main-location", "location", "image"),
    ("narrator", "voice", "voice"),
    ("episode-score", "music", "music"),
    ("hero-motion", "motion", "video"),
    ("style-copy", "text", "text"),
  ] {
    let (asset_id, kind, capability) = item
    specs.push({
      "asset_id": asset_id,
      "asset_version": 1,
      "kind": kind,
      "capability": capability,
      "title": asset_id,
      "intent": {
        "source_id": "moonwiki-" + asset_id,
        "source_version": "1",
        "source_digest": source_digest,
        "provenance_ref": "moonwiki://asset-intent/" + asset_id,
      },
      "prompt_digest": prompt_digest,
      "source_asset_refs": [],
      "rights_refs": ["rights://contract-cleared/" + asset_id],
      "continuity_key": "continuity:" + asset_id,
      "provider_adapter_id": "approved-" + capability,
      "provider": "approved-provider",
      "model": "approved-" + capability + "-model",
      "permitted_data_class": "rights-cleared-confidential",
      "variant_limit": 2,
      "retry_limit": 2,
      "cost_ceiling_cny": 0,
      "dependent_shot_ids": [shot_id],
    })
  }
  let value : Json = {
    "contract": "mooncast.asset-factory-plan.v1",
    "plan": { "id": "asset-factory:" + project.id, "version": 1, "digest": "" },
    "project_id": project.id,
    "project_revision": project.revision,
    "specs": specs,
    "total_cost_ceiling_cny": 0,
    "created_at": "2026-07-19T00:00:00+08:00",
    "publication_authority": false,
    "provider_execution_authority": false,
  }
  value.stringify(indent=2)
}

///|
fn starter_animatic_plan(
  project : ProjectProjection,
  factory : AssetFactoryWorkspaceProjection,
  current_version : Int,
) -> String {
  guard project.bible is Some(bible) && project.script is Some(script) &&
    project.storyboard is Some(storyboard) && !factory.approved_assets.is_empty() else {
    return "{}"
  }
  let assets = factory.approved_assets.map(value => value.reference)
  let visual_ids : Array[String] = []
  let voice_ids : Array[String] = []
  let music_ids : Array[String] = []
  for approved in factory.approved_assets {
    match approved.reference {
      Object(fields) => {
        let id = match fields.get("asset_id") { Some(String(value)) => value; _ => "" }
        let kind = match fields.get("kind") { Some(String(value)) => value; _ => "" }
        if ["character", "location", "prop", "image", "motion"].contains(kind) {
          visual_ids.push(id)
        }
        if kind == "voice" { voice_ids.push(id) }
        if kind == "music" { music_ids.push(id) }
      }
      _ => ()
    }
  }
  let panels : Array[Json] = []
  for shot in project.shots {
    panels.push({
      "panel_id": "panel-" + shot.id,
      "scene_id": shot.scene_id,
      "shot_id": shot.id,
      "order": shot.order,
      "duration_ms": (shot.duration_seconds * 1000.0).to_int(),
      "caption": if shot.subtitle.trim() == "" { shot.prompt } else { shot.subtitle },
      "visual_asset_ids": visual_ids,
      "transition": "cut",
    })
  }
  let value : Json = {
    "contract": "mooncast.animatic-plan.v1",
    "reference": { "id": project.id + "-animatic-render-plan", "version": current_version, "digest": "" },
    "project_id": project.id,
    "project_revision": project.revision,
    "bible": { "id": bible.artifact_id, "version": bible.version, "digest": bible.digest },
    "script": { "id": script.artifact_id, "version": script.version, "digest": script.digest },
    "storyboard": { "id": storyboard.artifact_id, "version": storyboard.version, "digest": storyboard.digest },
    "panels": panels,
    "approved_assets": assets,
    "temporary_voice_asset_ids": voice_ids,
    "temporary_music_asset_ids": music_ids,
    "caption_language": "zh-CN",
    "provider": "mooncast-native-storyboard",
    "model": "deterministic-animatic-v1",
    "cost_ceiling_cny": 1000,
    "retry_limit": 3,
    "created_at": "2026-07-19T00:00:00+08:00",
    "process_authority": false,
    "publication_authority": false,
  }
  value.stringify(indent=2)
}

///|
fn initial_model() -> Model {
  {
    tab: Overview,
    loading: true,
    busy: false,
    projects: [],
    selected_project_id: "",
    project: None,
    routed: [],
    delivery_builds: [],
    client_portals: [],
    billing_entries: [],
    latest_client_url: None,
    commercial: None,
    capacity_board: None,
    needs_intake: None,
    asset_factory: None,
    asset_plan_draft: "",
    animatic_workspace: None,
    animatic_plan_draft: "",
    selected_intake_id: "",
    intake_packet_draft: starter_moonwiki_packet(),
    intake_seed_project_id: "brand-episode-001",
    selected_lead_id: "",
    selected_quote_id: "",
    selected_artifact_kind: "brief",
    artifact_draft: "{}",
    create: {
      project_id: "mooncast-episode-001",
      title: "Mooncast governed episode",
      objective: "Produce a complete 3–8 minute branded narrative episode",
      audience: "brand and IP content teams",
      channels: "review-only",
      rights_owner: "",
      rights_confirmed: false,
      duration_seconds: "240",
      maximum_budget_cny: "20000",
    },
    operator: {
      actor: "creative-director",
      role: "creative-director",
      recorded_at: "2026-07-19T00:00:00+08:00",
      note: "Reviewed in Mooncast Studio against the exact displayed revision.",
      human_confirmed: false,
    },
    commercial_form: {
      customer: "",
      contact_ref: "",
      payable_problem: "",
      baseline_cost_cny: "0",
      baseline_hours: "0",
      measurable_acceptance: "Accepted 3–8 minute master\nRights and provenance package",
      repeat_hypothesis: "Quarterly content-operation retainer",
    },
    quote_form: {
      project_id: "design-partner-episode-001",
      title: "Design partner episode",
      objective: "Deliver an accepted 3–8 minute branded narrative master",
      audience: "customer-defined audience",
      rights_owner: "",
      duration_seconds: "240",
      production_budget_cny: "20000",
      start_date: "2026-07-26",
      delivery_date: "2026-08-26",
      deliverables: "Horizontal master\nVertical master\nSubtitles\nCover images\nRights and provenance manifest",
      quoted_revenue_cny: "40000",
      provider_cost_cny: "6000",
      labor_cost_cny: "10000",
      other_cost_cny: "2000",
      founder_hours: "30",
      contingency_percent: "15",
      deposit_cny: "16000",
      animatic_cny: "12000",
      master_cny: "12000",
    },
    capacity_form: {
      resource_name: "",
      resource_role: "creative-director",
      resource_skills: "creative-direction, editorial-review",
      weekly_hours: "20",
      available_from: "2026-07-26",
      available_to: "2026-08-26",
      resource_id: "",
      reservation_skills: "creative-direction",
      depends_on: "",
      reservation_start: "2026-07-26",
      reservation_end: "2026-08-26",
      reservation_hours: "20",
    },
    routing_form: {
      route_id: "primary-video-route",
      provider: "configured-video-provider",
      model: "configured-video-model",
      model_version: "pinned-version",
      permitted_data_class: "contract-cleared-production-assets",
      cost_ceiling_cny: "6000",
      total_cost_ceiling_cny: "6000",
      retry_limit: "2",
      fallback_route_ids: "",
    },
    qc_form: {
      shot_id: "",
      attempt_id: "attempt-001",
      route_id: "primary-video-route",
      prompt_digest: "sha256:prompt-evidence-required",
      source_asset_digests: "",
      cost_cny: "0",
      output_digest: "sha256:provider-output-required",
      attempt_status: "succeeded",
      dimension: "technical",
      finding_status: "pass",
      evidence_digest: "sha256:qc-evidence-required",
      finding_version: "1",
      finding_digest: "",
      note: "Independent QC evidence reviewed against the exact shot output.",
    },
    delivery_governance_form: {
      video_digest: "sha256:editor-video-master-required",
      audio_digest: "sha256:editor-audio-master-required",
      subtitle_digest: "sha256:subtitle-master-required",
      provenance_digest: "sha256:provenance-manifest-required",
      ai_label: "ai-assisted-production",
      destination_ids: "client-delivery",
      manifest_digest: "sha256:delivery-manifest-required",
      rights_ledger_digest: "sha256:rights-ledger-required",
      destination_id: "client-delivery",
      publication_scope: "exact accepted delivery package only",
      publication_expires_at: "",
      publication_receipt_digest: "",
      publication_authority_ref: "authority:",
      performance_status: "observed",
      performance_evidence_digest: "",
      reach: "0",
      completion_rate: "0",
      conversion_rate: "0",
      revenue_cny: "0",
      provider_cost_cny: "0",
      founder_hours: "0",
      repeat_purchase_status: "not-yet-observed",
    },
    client_ops_form: {
      client_name: "",
      brand_name: "Mooncast client",
      brand_accent: "#b8ff61",
      expires_at: "2026-08-26T23:59:59+08:00",
      billing_kind: "deposit",
      billing_state: "quoted",
      billing_currency: "CNY",
      billing_amount: "0",
      billing_due_at: "2026-07-26T23:59:59+08:00",
      billing_reference: "contract:milestone:",
      repeat_project_id: "repeat-episode-002",
      repeat_title: "Repeat episode",
      repeat_objective: "Produce the next episode using only explicitly selected reusable assets",
      repeat_audience: "customer-defined audience",
      repeat_rights_owner: "",
      repeat_duration_seconds: "240",
      repeat_budget_cny: "20000",
    },
    status: "Loading canonical Mooncast state…",
    error: None,
    command_sequence: 0,
  }
}

///|
fn artifact_for(
  project : ProjectProjection,
  kind : String,
) -> ArtifactProjection? {
  match kind {
    "brief" => project.brief
    "rights-ledger" => project.rights
    "ip-bible" => project.bible
    "script" => project.script
    "claims-ledger" => project.claims_ledger
    "storyboard" => project.storyboard
    "animatic" => project.animatic
    _ => None
  }
}

///|
fn next_gate(project : ProjectProjection) -> String? {
  for gate in ["G0", "G1", "G2", "G3", "G4", "G5", "G6", "G7"] {
    match project.gates.get(gate) {
      Some(value) if value.status != "passed" => return Some(gate)
      _ => ()
    }
  }
  None
}

///|
fn split_lines(value : String) -> Array[String] {
  value
  .split("\n")
  .filter_map(fn(line) {
    let trimmed = line.trim().to_owned()
    if trimmed == "" {
      None
    } else {
      Some(trimmed)
    }
  })
  .collect()
}

///|
fn split_csv(value : String) -> Array[String] {
  value
  .split(",")
  .filter_map(fn(item) {
    let trimmed = item.trim().to_owned()
    if trimmed == "" {
      None
    } else {
      Some(trimmed)
    }
  })
  .collect()
}
