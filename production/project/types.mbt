///|
/// Immutable content identity used across the production graph.
pub(all) struct VersionRef {
  id : String
  version : Int
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Asset {
  asset_id : String
  kind : String
  version : Int
  digest : String
  uri : String
  rights_record_id : String
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Shot {
  shot_id : String
  order : Int
  duration_ms : Int
  character_ids : Array[String]
  location_id : String
  source_asset_ids : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Scene {
  scene_id : String
  order : Int
  title : String
  shots : Array[Shot]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Episode {
  episode_id : String
  order : Int
  title : String
  scenes : Array[Scene]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Canonical project -> episode -> scene -> shot -> asset graph.
pub(all) struct ProjectGraph {
  project_id : String
  revision : Int
  title : String
  target_duration_seconds : Int
  maximum_budget_cny : Double
  episodes : Array[Episode]
  assets : Array[Asset]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GraphValidation {
  valid : Bool
  errors : Array[String]
  episode_count : Int
  scene_count : Int
  shot_count : Int
  planned_duration_ms : Int
} derive(Debug, Eq, ToJson, FromJson)
