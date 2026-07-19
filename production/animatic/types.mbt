///|
pub(all) struct StoryboardPanel {
  panel_id : String
  scene_id : String
  shot_id : String
  order : Int
  duration_ms : Int
  caption : String
  visual_asset_ids : Array[String]
  transition : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnimaticPlan {
  contract : String
  reference : @project.VersionRef
  project_id : String
  project_revision : Int
  bible : @project.VersionRef
  script : @project.VersionRef
  storyboard : @project.VersionRef
  panels : Array[StoryboardPanel]
  approved_assets : Array[@project.Asset]
  temporary_voice_asset_ids : Array[String]
  temporary_music_asset_ids : Array[String]
  caption_language : String
  provider : String
  model : String
  cost_ceiling_cny : Double
  retry_limit : Int
  created_at : String
  process_authority : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnimaticRenderAttempt {
  contract : String
  attempt_id : String
  plan : @project.VersionRef
  attempt : Int
  state : String
  started_at : String
  completed_at : String?
  failure : String?
  process_effect_performed : Bool
  network_effect_performed : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnimaticBudgetReceipt {
  currency : String
  planned_cny : Double
  actual_cny : Double
  within_ceiling : Bool
  evidence_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RenderedAnimatic {
  contract : String
  reference : @project.VersionRef
  plan : @project.VersionRef
  project_id : String
  project_revision_anchor : Int
  bible : @project.VersionRef
  script : @project.VersionRef
  storyboard : @project.VersionRef
  approved_assets : Array[@project.Asset]
  temporary_voice_asset_ids : Array[String]
  temporary_music_asset_ids : Array[String]
  panel_count : Int
  duration_seconds : Int
  storyboard_sheet_key : String
  storyboard_sheet_digest : String
  video_key : String
  video_digest : String
  caption_language : String
  transitions : Array[String]
  provider : String
  model : String
  budget : AnimaticBudgetReceipt
  provenance_digest : String
  created_at : String
  process_effect_performed : Bool
  network_effect_performed : Bool
  publication_authority : Bool
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RenderedAnimaticApproval {
  contract : String
  rendered : RenderedAnimatic
  decision : String
  actor : String
  actor_role : String
  note : String
  approved_at : String
  human_confirmed : Bool
  approval_digest : String
  publication_authority : Bool
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnimaticWorkspace {
  plans : Array[AnimaticPlan]
  attempts : Array[AnimaticRenderAttempt]
  renders : Array[RenderedAnimatic]
  approvals : Array[RenderedAnimaticApproval]
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)
