///|
/// Creative values passed between workspace nodes. `AnyArtifact` is reserved
/// for boundary adapters; built-in recipes use a concrete kind.
pub(all) enum ArtifactKind {
  TextArtifact
  ImageArtifact
  AudioArtifact
  VideoArtifact
  MediaCollection
  ShotCollection
  TimelineArtifact
  ReviewDecisionArtifact
  DeliveryPackageArtifact
  DataArtifact
  AnyArtifact
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum PortCardinality {
  One
  Many
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum WorkspaceNodeKind {
  InputNode
  OperationNode
  ControlNode
  HumanGateNode
  OutputNode
  CapsuleNode
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PortDefinition {
  port_id : String
  label : String
  schema_id : String
  artifact_kind : ArtifactKind
  cardinality : PortCardinality
  required : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The semantic value expected by a creative parameter. Keeping this separate
/// from its visual control lets every surface render the same graph contract
/// without putting UI details into execution logic.
pub(all) enum ParameterValueKind {
  TextValue
  IntegerValue
  NumberValue
  BooleanValue
  JsonValue
  AssetReferenceValue
  ProviderValue
  ModelValue
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A portable control hint. Clients may choose a native equivalent, but must
/// preserve the value semantics declared by `value_kind`.
pub(all) enum ParameterControl {
  TextFieldControl
  TextAreaControl
  NumberFieldControl
  SliderControl
  SelectControl
  CheckboxControl
  JsonEditorControl
  AssetPickerControl
  ProviderPickerControl
  ModelPickerControl
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ParameterOption {
  value : String
  label : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Declarative parameter metadata shared by the graph editor, App Mode, the
/// planner, and agents. Defaults are data, so they participate in frozen plans
/// and cache identity instead of being hidden in UI code.
pub(all) struct ParameterDefinition {
  parameter_id : String
  label : String
  description : String
  value_kind : ParameterValueKind
  control : ParameterControl
  default_value : Json?
  required : Bool
  advanced : Bool
  minimum : Double?
  maximum : Double?
  step : Double?
  options : Array[ParameterOption]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A graph node type. Manifest-backed definitions retain the manifest tool id
/// so the workspace never becomes a second capability registry.
pub(all) struct NodeDefinition {
  definition_id : String
  display_name : String
  category : String
  node_kind : WorkspaceNodeKind
  tool_id : String
  inputs : Array[PortDefinition]
  outputs : Array[PortDefinition]
  parameters : Array[ParameterDefinition]
  authority : @pack.AuthorityClass
  execution_owner : String
  idempotent : Bool
  review_required : Bool
  evidence_outputs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeParameter {
  key : String
  value : Json
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeParameterValidation {
  valid : Bool
  errors : Array[String]
  warnings : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkflowNode {
  node_id : String
  definition_id : String
  title : String
  x : Int
  y : Int
  parameters : Array[NodeParameter]
  collapsed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkflowEdge {
  edge_id : String
  source_node_id : String
  source_port_id : String
  target_node_id : String
  target_port_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceGraph {
  contract : String
  graph_id : String
  project_id : String
  revision : Int
  title : String
  nodes : Array[WorkflowNode]
  edges : Array[WorkflowEdge]
  output_node_ids : Array[String]
  created_by : String
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GraphValidation {
  contract : String
  valid : Bool
  errors : Array[String]
  warnings : Array[String]
  topological_node_ids : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CachedNodeOutput {
  node_id : String
  cache_key : String
  output_digest : String
  output_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExecutionContext {
  provider : String
  model : String
  policy_digest : String
  cached_outputs : Array[CachedNodeOutput]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlannedNode {
  node_id : String
  definition_id : String
  tool_digest : String
  input_node_ids : Array[String]
  cache_key : String
  cache_hit : Bool
  cached_output_digest : String
  cached_output_ref : String
  authority : @pack.AuthorityClass
  execution_owner : String
  review_required : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExecutionPlan {
  contract : String
  plan_id : String
  graph_id : String
  graph_revision : Int
  graph_digest : String
  frozen_graph : WorkspaceGraph
  selected_output_node_ids : Array[String]
  nodes : Array[PlannedNode]
  provider : String
  model : String
  policy_digest : String
  frozen_at : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum NodeRunState {
  Blocked
  Ready
  Running
  Cached
  Succeeded
  Failed
  Cancelled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum WorkspaceRunState {
  Queued
  RunningRun
  SucceededRun
  FailedRun
  CancelledRun
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeAttempt {
  attempt : Int
  state : NodeRunState
  started_at : String
  finished_at : String
  output_digest : String
  output_ref : String
  error_code : String
  error_message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeRun {
  node_id : String
  state : NodeRunState
  progress_numerator : Int
  progress_denominator : Int
  retry_count : Int
  maximum_retries : Int
  attempts : Array[NodeAttempt]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RunRecord {
  contract : String
  run_id : String
  plan : ExecutionPlan
  state : WorkspaceRunState
  nodes : Array[NodeRun]
  created_by : String
  created_at : String
  updated_at : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ArtifactAnnotation {
  annotation_id : String
  actor : String
  body : String
  start_tick : Int?
  end_tick : Int?
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Immutable, provenance-bearing output of a workspace node.
pub(all) struct WorkspaceArtifact {
  contract : String
  artifact_id : String
  version : Int
  project_id : String
  kind : ArtifactKind
  digest : String
  uri : String
  preview_uri : String
  parent_digests : Array[String]
  graph_id : String
  run_id : String
  node_id : String
  prompt_digest : String
  provider : String
  model : String
  provider_receipt : Json
  rights_state : String
  qc_state : String
  qc_results : Array[String]
  cost_cny : Double
  duration_seconds : Double
  annotations : Array[ArtifactAnnotation]
  created_at : String
  immutable : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Mutable library metadata wraps an immutable artifact version. Deleting an
/// asset hides the index entry without erasing its evidence or provenance.
pub(all) struct WorkspaceAssetEntry {
  contract : String
  artifact : WorkspaceArtifact
  tags : Array[String]
  deleted : Bool
  indexed_at : String
  updated_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapsulePort {
  port_id : String
  node_id : String
  node_port_id : String
  label : String
  artifact_kind : ArtifactKind
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapsuleParameter {
  parameter_id : String
  node_id : String
  node_parameter_key : String
  label : String
  default_value : Json
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeCapsule {
  contract : String
  capsule_id : String
  version : Int
  title : String
  summary : String
  graph : WorkspaceGraph
  public_inputs : Array[CapsulePort]
  public_outputs : Array[CapsulePort]
  exposed_parameters : Array[CapsuleParameter]
  policy_constraints : Array[String]
  provider_constraints : Array[String]
  example_asset_refs : Array[String]
  thumbnail_uri : String
  minimum_mooncast_version : String
  created_by : String
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GraphDiff {
  contract : String
  changed_graph_fields : Array[String]
  added_node_ids : Array[String]
  removed_node_ids : Array[String]
  modified_node_ids : Array[String]
  added_edge_ids : Array[String]
  removed_edge_ids : Array[String]
  modified_edge_ids : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AgentGraphProposal {
  contract : String
  proposal_id : String
  project_id : String
  base_graph_id : String
  base_graph_revision : Int
  proposed_graph : WorkspaceGraph
  explanation : String
  affected_node_ids : Array[String]
  provider_ids : Array[String]
  expected_cost_cny : Double
  required_approvals : Array[String]
  created_by : String
  created_at : String
  applied : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Addressable workspace objects. Comments, presence, shares, search results,
/// and activity all use this finite target vocabulary instead of loose URLs.
pub(all) enum WorkspaceTargetKind {
  GraphTarget
  NodeTarget
  RunTarget
  ArtifactTarget
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceComment {
  contract : String
  comment_id : String
  project_id : String
  target_kind : WorkspaceTargetKind
  target_id : String
  body : String
  actor : String
  start_tick : Int?
  end_tick : Int?
  created_at : String
  resolved : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A renewable edit lease. It is advisory presence, never publication or
/// provider authority.
pub(all) struct WorkspacePresence {
  contract : String
  project_id : String
  actor_id : String
  display_name : String
  target_kind : WorkspaceTargetKind
  target_id : String
  lease_expires_at : String
  updated_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ArtifactComparison {
  contract : String
  project_id : String
  artifact_ids : Array[String]
  baseline_artifact_id : String
  comparable : Bool
  differences : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ArtifactPromotion {
  contract : String
  promotion_id : String
  project_id : String
  artifact_id : String
  artifact_version : Int
  channel : String
  actor : String
  note : String
  promoted_at : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum SpecializedLens {
  ScriptLens
  StoryboardLens
  ImageCompareLens
  AudioTranscriptLens
  TimelineLens
  ReviewLens
  DeliveryLens
  DataLens
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapsulePublication {
  contract : String
  publication_id : String
  capsule : CreativeCapsule
  visibility : String
  actor : String
  published_at : String
  immutable_digest : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceTemplatePromotion {
  contract : String
  promotion_id : String
  project_id : String
  run_id : String
  capsule : CreativeCapsule
  actor : String
  promoted_at : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceShare {
  contract : String
  share_id : String
  project_id : String
  target_kind : WorkspaceTargetKind
  target_id : String
  mode : String
  token_digest : String
  expires_at : String
  created_by : String
  created_at : String
  revoked : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceActivity {
  contract : String
  activity_id : String
  project_id : String
  actor : String
  action : String
  target_kind : WorkspaceTargetKind
  target_id : String
  detail : String
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Mooncast prepares deterministic work for MoonFlow and imports a signed or
/// otherwise provider-verifiable receipt later. Prepared is not success.
pub(all) enum WorkspaceDispatchState {
  PreparedDispatch
  AcceptedDispatch
  SucceededDispatch
  FailedDispatch
  CancelledDispatch
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceDispatch {
  contract : String
  dispatch_id : String
  run_id : String
  node_id : String
  execution_owner : String
  operation : String
  input_digest : String
  input_refs : Array[String]
  idempotency_key : String
  state : WorkspaceDispatchState
  output_digest : String
  output_ref : String
  provider_receipt : Json
  error_code : String
  error_message : String
  created_at : String
  updated_at : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceDispatchReceipt {
  contract : String
  dispatch_id : String
  idempotency_key : String
  state : WorkspaceDispatchState
  output_digest : String
  output_ref : String
  provider_receipt : Json
  error_code : String
  error_message : String
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkspaceSearchMatch {
  contract : String
  project_id : String
  target_kind : WorkspaceTargetKind
  target_id : String
  title : String
  detail : String
  score : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A complete reconnect-safe snapshot encoded as an SSE event by the service.
pub(all) struct WorkspaceRunEvent {
  contract : String
  event_id : String
  event_name : String
  run_id : String
  run : RunRecord
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror WorkspaceError {
  InvalidGraph(Array[String])
  UnknownNode(String)
  InvalidTransition(String)
  RevisionConflict(expected~ : Int, actual~ : Int)
  ProposalAlreadyApplied(String)
} derive(Debug, Eq)
