///|
pub(all) struct AssetIntentEvidence {
  source_id : String
  source_version : String
  source_digest : String
  provenance_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReusableAssetSpec {
  asset_id : String
  asset_version : Int
  kind : String
  capability : String
  title : String
  intent : AssetIntentEvidence
  prompt_digest : String
  source_asset_refs : Array[String]
  rights_refs : Array[String]
  continuity_key : String
  provider_adapter_id : String
  provider : String
  model : String
  permitted_data_class : String
  variant_limit : Int
  retry_limit : Int
  cost_ceiling_cny : Double
  dependent_shot_ids : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AssetFactoryPlan {
  contract : String
  plan : @project.VersionRef
  project_id : String
  project_revision : Int
  specs : Array[ReusableAssetSpec]
  total_cost_ceiling_cny : Double
  created_at : String
  publication_authority : Bool
  provider_execution_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AssetFactoryPlanDecision {
  contract : String
  plan : @project.VersionRef
  decision : String
  actor : String
  actor_role : String
  note : String
  decided_at : String
  human_confirmed : Bool
  decision_digest : String
  provider_execution_authority : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AssetGenerationVariant {
  contract : String
  variant_id : String
  plan : @project.VersionRef
  asset_id : String
  asset_version : Int
  variant : Int
  provider_job_id : String
  provider_artifact_id : String?
  output_digest : String?
  modality : String
  cost_cny : Double
  state : String
  evidence_refs : Array[String]
  updated_at : String
  network_effect_performed : Bool
  publication_authority : Bool
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AssetQcFinding {
  contract : String
  finding_id : String
  variant_id : String
  dimension : String
  status : String
  evidence_digest : String
  reviewer : String
  reviewer_role : String
  reviewed_at : String
  human_confirmed : Bool
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ApprovedReusableAsset {
  contract : String
  reference : @project.Asset
  plan : @project.VersionRef
  spec_version : Int
  variant_id : String
  provider_job_id : String
  provider_artifact_id : String
  output_digest : String
  modality : String
  continuity_key : String
  intent : AssetIntentEvidence
  rights_refs : Array[String]
  qc_finding_ids : Array[String]
  approval_actor : String
  approval_role : String
  approved_at : String
  approval_digest : String
  publication_authority : Bool
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ShotAssetBinding {
  contract : String
  binding_id : String
  project_id : String
  project_revision : Int
  shot_id : String
  assets : Array[@project.Asset]
  approval_digests : Array[String]
  bound_at : String
  immutable : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AssetFactoryWorkspace {
  contract : String
  plans : Array[AssetFactoryPlan]
  plan_decisions : Array[AssetFactoryPlanDecision]
  variants : Array[AssetGenerationVariant]
  findings : Array[AssetQcFinding]
  approved_assets : Array[ApprovedReusableAsset]
  shot_bindings : Array[ShotAssetBinding]
  total_spent_cny : Double
  publication_authority : Bool
  provider_execution_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)
