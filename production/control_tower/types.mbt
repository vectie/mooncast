///|
/// A named, evidence-bound operating update. Provider spend is kept separate
/// from the canonical provider-operation total so the projection can expose a
/// discrepancy instead of silently choosing one source.
pub(all) struct OperatingActuals {
  contract : String
  command_id : String
  project_id : String
  version : Int
  project_revision : Int
  provider_cost_confirmed_cny : Double?
  labor_cost_cny : Double?
  other_cost_cny : Double?
  recognized_revenue_cny : Double?
  founder_hours : Double?
  completed_labor_hours : Double?
  forecast_completion_date : String?
  provider_cost_reconciled : Bool
  evidence_refs : Array[String]
  actor : String
  actor_role : String
  observed_at : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Ownership is an operating acknowledgement, not authority to perform an
/// external effect. It binds the immutable exception evidence that was
/// displayed when the assignment was made.
pub(all) struct ExceptionAssignment {
  contract : String
  command_id : String
  exception_id : String
  exception_digest : String
  version : Int
  owner : String
  owner_role : String
  action_due_date : String
  note : String
  assigned_by : String
  assigned_by_role : String
  assigned_at : String
  human_confirmed : Bool
  external_effect_authorized : Bool
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SpendPlan {
  provider_cny : Double
  labor_cny : Double
  other_cny : Double
  direct_cny : Double
  contingency_cny : Double
  revenue_cny : Double
  gross_margin_cny : Double
  contribution_margin_cny : Double
  founder_hours : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderCostBreakdown {
  generation_attempts_cny : Double
  asset_factory_cny : Double
  animatic_cny : Double
  postprocess_cny : Double
  automated_qc_cny : Double
  operational_total_cny : Double
  confirmed_total_cny : Double?
  discrepancy_cny : Double?
  evidence_state : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SpendActual {
  provider : ProviderCostBreakdown
  labor_cny : Double?
  other_cny : Double?
  direct_cny : Double?
  revenue_cny : Double?
  gross_margin_cny : Double?
  contribution_margin_cny : Double?
  founder_hours : Double?
  completed_labor_hours : Double?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SpendVariance {
  provider_cny : Double?
  labor_cny : Double?
  other_cny : Double?
  direct_cny : Double?
  revenue_cny : Double?
  gross_margin_cny : Double?
  contribution_margin_cny : Double?
  founder_hours : Double?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RemainingWork {
  total_shots : Int
  shots_without_output : Int
  shots_awaiting_qc : Int
  creative_approvals_remaining : Int
  routing_approval_remaining : Bool
  master_work_remaining : Bool
  client_acceptance_remaining : Bool
  delivery_work_remaining : Bool
  performance_review_remaining : Bool
  work_units_total : Int
  work_units_complete : Int
  completion_rate : Double
  next_actions : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ScheduleHealth {
  as_of_date : String
  start_date : String?
  promised_delivery_date : String?
  forecast_completion_date : String?
  drift_days : Int?
  days_to_delivery : Int?
  risk : String
  basis : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RevisionBurden {
  included_rounds : Int?
  used_rounds : Int
  remaining_rounds : Int?
  overage_rounds : Int?
  state : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReallocationCandidate {
  resource_id : String
  resource_name : String
  role : String
  available_hours : Double
  matched_skills : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapacityConflict {
  conflict_id : String
  exception_id : String
  resource_id : String
  resource_name : String
  role : String
  reservation_ids : Array[String]
  project_ids : Array[String]
  overlap_start : String
  overlap_end : String
  reserved_hours : Double
  weekly_hours : Double
  overbooked_hours : Double
  reallocation_candidates : Array[ReallocationCandidate]
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ControlTowerException {
  exception_id : String
  project_id : String?
  kind : String
  severity : String
  summary : String
  evidence_refs : Array[String]
  digest : String
  assignment : ExceptionAssignment?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProjectControl {
  contract : String
  project_id : String
  project_revision : Int
  title : String
  stage : String
  current_gate : String?
  quote_id : String?
  quote_version : Int?
  quote_digest : String?
  actuals_version : Int?
  actuals_digest : String?
  actuals_observed_at : String?
  actuals_evidence_refs : Array[String]
  planned : SpendPlan?
  actual : SpendActual
  variance : SpendVariance?
  schedule : ScheduleHealth
  remaining : RemainingWork
  revisions : RevisionBurden
  accepted_minutes : Double?
  cost_per_accepted_minute_cny : Double?
  capacity_conflict_ids : Array[String]
  exception_ids : Array[String]
  missing_evidence : Array[String]
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PortfolioTotals {
  project_count : Int
  projects_with_accepted_quotes : Int
  planned_revenue_cny : Double
  planned_direct_cost_cny : Double
  planned_contribution_margin_cny : Double
  actual_provider_cost_cny : Double
  actual_labor_cost_cny : Double?
  actual_other_cost_cny : Double?
  actual_revenue_cny : Double?
  actual_gross_margin_cny : Double?
  actual_contribution_margin_cny : Double?
  planned_founder_hours : Double
  actual_founder_hours : Double?
  projects_at_sla_risk : Int
  open_exception_count : Int
  unowned_exception_count : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ControlTower {
  contract : String
  pack_id : String
  pack_version : String
  as_of_date : String
  projects : Array[ProjectControl]
  capacity_conflicts : Array[CapacityConflict]
  exceptions : Array[ControlTowerException]
  totals : PortfolioTotals
  missing_evidence : Array[String]
  publication_authority : Bool
  payment_effect_performed : Bool
  external_effect_authorized : Bool
  digest : String
} derive(Debug, Eq, ToJson, FromJson)
