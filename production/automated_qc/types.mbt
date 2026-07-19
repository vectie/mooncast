///|
pub(all) struct AnalyzerTask {
  contract : String
  reference : @project.VersionRef
  project_id : String
  project_revision : Int
  shot_id : String
  attempt_digest : String
  source_artifact_digest : String
  analyzer : String
  execution_mode : String
  expected_duration_ms : Int
  duration_tolerance_ms : Int
  subtitle_track_digest : String?
  subtitle_cue_count : Int
  subtitle_last_end_ms : Int
  subtitle_safe_area_ratio : Double
  identity_refs : Array[String]
  continuity_refs : Array[String]
  rights_refs : Array[String]
  provider_adapter_id : String?
  provider : String?
  model : String?
  permitted_data_class : String
  cost_ceiling_cny : Double
  retry_limit : Int
  created_at : String
  provider_execution_authority : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnalyzerMeasurement {
  metric : String
  value : Double
  unit : String
  comparator : String
  threshold : Double
  status : String
  evidence_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnalyzerFinding {
  contract : String
  finding : @project.VersionRef
  task : @project.VersionRef
  shot_id : String
  attempt_digest : String
  analyzer : String
  governance_dimension : String
  status : String
  measurements : Array[AnalyzerMeasurement]
  evidence_digest : String
  note : String
  human_decision_required : Bool
  publication_authority : Bool
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnalyzerReceipt {
  contract : String
  receipt : @project.VersionRef
  task : @project.VersionRef
  provider_job_id : String?
  source_artifact_digest : String
  analyzer : String
  execution_mode : String
  finding : AnalyzerFinding
  cost_cny : Double
  completed_at : String
  network_effect_performed : Bool
  human_decision_performed : Bool
  publication_authority : Bool
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnalyzerWorkspace {
  tasks : Array[AnalyzerTask]
  receipts : Array[AnalyzerReceipt]
  findings : Array[AnalyzerFinding]
  total_cost_cny : Double
  human_decisions : Int
  provider_execution_authority : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)
