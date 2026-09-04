///|
/// Ephemeral editor state. Durable editorial truth is never synthesized here;
/// it is replaced by project-scoped server snapshots after every mutation.
enum MonitorMode {
  SourceMonitor
  ProgramMonitor
} derive(Eq)

///|
enum ProgramSurface {
  InteractiveProxy
  AuthoritativePreview
} derive(Eq)

///|
enum TimelineDragMode {
  DragMove
  DragTrimStart
  DragTrimEnd
} derive(Eq)

///|
enum WorkspaceLens {
  GraphLens
  EditorLens
  ReviewLens
} derive(Debug, Eq)

///|
enum WorkspaceRecipe {
  CombineVideosRecipe
  BriefToDeliveryRecipe
} derive(Debug, Eq)

///|
enum WorkspaceArtifactKind {
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
enum WorkspacePortCardinality {
  One
  Many
} derive(Debug, Eq, ToJson, FromJson)

///|
enum WorkspaceNodeKindSummary {
  InputNode
  OperationNode
  ControlNode
  HumanGateNode
  OutputNode
  CapsuleNode
} derive(Debug, Eq, ToJson, FromJson)

///|
enum WorkspaceAuthoritySummary {
  CognitiveMaintenance
  ExternalEffect
  Observe
  PhysicalEffect
  SandboxExecution
  WorkspaceMutation
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkspacePortSummary {
  port_id : String
  label : String
  schema_id : String
  artifact_kind : WorkspaceArtifactKind
  cardinality : WorkspacePortCardinality
  required : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkspaceDefinitionSummary {
  definition_id : String
  display_name : String
  category : String
  node_kind : WorkspaceNodeKindSummary
  tool_id : String
  inputs : Array[WorkspacePortSummary]
  outputs : Array[WorkspacePortSummary]
  authority : WorkspaceAuthoritySummary
  execution_owner : String
  idempotent : Bool
  review_required : Bool
  evidence_outputs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkspaceNodeParameterSummary {
  key : String
  value : Json
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkspaceGraphNodeSummary {
  node_id : String
  definition_id : String
  title : String
  x : Int
  y : Int
  parameters : Array[WorkspaceNodeParameterSummary]
  collapsed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkspaceGraphEdgeSummary {
  edge_id : String
  source_node_id : String
  source_port_id : String
  target_node_id : String
  target_port_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkspaceGraphSummary {
  contract : String
  graph_id : String
  project_id : String
  revision : Int
  title : String
  nodes : Array[WorkspaceGraphNodeSummary]
  edges : Array[WorkspaceGraphEdgeSummary]
  output_node_ids : Array[String]
  created_by : String
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkspaceCatalogPayload {
  definitions : Array[WorkspaceDefinitionSummary]
} derive(FromJson)

///|
struct WorkspaceNodePosition {
  recipe : WorkspaceRecipe
  node_id : String
  x : Int
  y : Int
}

///|
struct WorkspaceCanvasDrag {
  node_id : String
  origin_client_x : Int
  origin_client_y : Int
  origin_x : Int
  origin_y : Int
}

///|
struct WorkspaceConnection {
  recipe : WorkspaceRecipe
  source_node_id : String
  target_node_id : String
}

///|
struct WorkspaceAssetNode {
  recipe : WorkspaceRecipe
  node_id : String
  title : String
  artifact_kind : String
  x : Int
  y : Int
}

///|
#warnings("-unused_field")
struct WorkspaceRunPayload {
  run_id : String
  state : Json
  updated_at : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct WorkspaceProposalSummary {
  proposal_id : String
  base_graph_revision : Int
  explanation : String
  affected_node_ids : Array[String]
  provider_ids : Array[String]
  expected_cost_cny : Double
  required_approvals : Array[String]
  applied : Bool
  created_by : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct WorkspaceShareSummary {
  share_id : String
  expires_at : String
  revoked : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct WorkspaceShareCreatedPayload {
  share : WorkspaceShareSummary
  access_path : String
  token : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct WorkspaceProposalPayload {
  proposals : Array[WorkspaceProposalSummary]
} derive(FromJson)

///|
#warnings("-unused_field")
struct WorkspaceSearchSummary {
  project_id : String
  target_id : String
  title : String
  detail : String
  score : Int
} derive(FromJson)

///|
#warnings("-unused_field")
struct WorkspaceSearchPayload {
  matches : Array[WorkspaceSearchSummary]
} derive(FromJson)

///|
struct TimelineDrag {
  clip_id : String
  mode : TimelineDragMode
  origin_client_x : Int
  preview_delta_ticks : Int
}

///|
struct AssetFilters {
  search : String
  kind : String
  qc : String
  rights : String
  placement : String
}

///|
struct InspectorDraft {
  transition : String
  transition_seconds : String
  brightness : String
  contrast : String
  saturation : String
  gamma : String
  opacity : String
  scale : String
  position_x : String
  position_y : String
  rotation : String
  mask_shape : String
  mask_x : String
  mask_y : String
  mask_width : String
  mask_height : String
  mask_feather : String
  mask_invert : Bool
  speed_midpoint : String
  overlay_text : String
  overlay_position : String
  overlay_size : String
  overlay_color : String
  overlay_background : String
  track_volume_db : String
  track_pan : String
  track_muted : Bool
  keyframe_channel : String
  keyframe_value : String
  keyframe_interpolation : String
}

///|
struct IntakeDraft {
  selected_blob : @dom.Blob?
  role : String
  file_name : String
  mime_type : String
  size_bytes : String
  sha256 : String
  duration_seconds : String
  owner : String
  basis : String
  territory : String
  channels : String
  rights_ref : String
  source_kind : String
  source_ref : String
  pasted_content : String
}

///|
struct LocalMediaSelection {
  blob : @dom.Blob
  file_name : String
  mime_type : String
  size_bytes : Int
  sha256 : String
}

///|
struct UtilityConcatInput {
  blob : @dom.Blob
  file_name : String
  mime_type : String
  size_bytes : Int
  sha256 : String
}

///|
#warnings("-unused_field")
struct UtilityConcatJobInput {
  index : Int
  file_name : String
  mime_type : String
  size_bytes : Int
  sha256 : String
  uploaded : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct UtilityConcatJob {
  contract : String
  job_id : String
  idempotency_key : String
  state : String
  inputs : Array[UtilityConcatJobInput]
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
} derive(FromJson)

///|
struct UtilityConcatState {
  files : Array[UtilityConcatInput]
  job_id : String
  phase : String
  completed : Int
  output_digest : String
  output_size : Int
  media_url : String
  error : String
}

///|
struct ExportState {
  output_preset : String
  actor : String
  authority_ref : String
  job_id : String
  download_url : String
  promoted : Bool
  handed_off : Bool
  receipt_state : String
  canonical_revision : Int
  timeline_revision : Int
  output_digest : String
  render_plan_digest : String
  handoff_record_id : String
  handoff_record_digest : String
  handoff_request_id : String
  handoff_status : String
}

///|
struct ExportReceiptView {
  digest : String
  plan_digest : String
  output_ref : String?
} derive(FromJson)

///|
struct EditorJobResultView {
  export_receipt : ExportReceiptView?
} derive(FromJson)

///|
/// Accepts both the native direct job response and the legacy data-wrapped
/// transport while keeping the editor state typed.
struct EditorJobPayload {
  session_id : String?
  job_id : String?
  state : String?
  status : String?
  attempts : Int?
  max_attempts : Int?
  output_digest : String?
  media_url : String?
  result : EditorJobResultView?
} derive(FromJson)

///|
struct EditorJobResponse {
  data : EditorJobPayload?
  session_id : String?
  job_id : String?
  state : String?
  status : String?
  attempts : Int?
  max_attempts : Int?
  output_digest : String?
  media_url : String?
  result : EditorJobResultView?
  error : @api.ApiErrorBody?
} derive(FromJson)

///|
#warnings("-unused_field")
struct ImmutableRecordView {
  contract : String
  record_type : String
  record_id : String
  payload_digest : String
  envelope_digest : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct ImmutablePutView {
  envelope : ImmutableRecordView?
  created : Bool?
  error : @api.ApiErrorBody?
} derive(FromJson)

///|
#warnings("-unused_field")
struct MasterPromotionResponse {
  contract : String?
  master_id : String?
  project_id : String?
  job_id : String?
  digest : String?
  size : Int?
  video_ref : String?
  subtitle_ref : String?
  plan_digest : String?
  actor : String?
  authority_ref : String?
  publication_authority : Bool?
  error : @api.ApiErrorBody?
} derive(FromJson)

///|
#warnings("-unused_field")
struct NativeProjectSummary {
  project_id : String
  revision : Int
  timeline_id : String
  duration_ticks : Int
  updated_at : String
} derive(FromJson)

///|
#warnings("-unused_field")
struct NativeTakeRecord {
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
  identity : @api.Identity
  approved : Bool
  already_placed : Bool
  track_id : String
  track_kind : String
  add_clip_template : @api.AddClipTemplate?
} derive(FromJson)

///|
struct NativeTickRange {
  start_tick : Int
  duration_ticks : Int
} derive(FromJson)

///|
#warnings("-unused_field")
struct NativeReviewComment {
  comment_id : String
  range : NativeTickRange
  text : String
  revision_round : Int
} derive(FromJson)

///|
#warnings("-unused_field")
struct NativeEditorOpen {
  project_id : String
  revision : Int
  snapshot : @api.CanonicalSnapshot
  command_log : Array[@api.CommandRecord]
  media_bindings : Array[Json]
  takes : Array[NativeTakeRecord]
  review_comments : Array[NativeReviewComment]
  production_source : @api.ProductionSource?
  master_promotion : @api.MasterPromotion?
  publication_authority : Bool
  provider_authority : Bool
} derive(FromJson)

///|
#warnings("-unused_field")
struct NativeWaveform {
  state : String
  peaks : Array[Int]
  digest : String?
} derive(FromJson)

///|
struct NativeMediaAnalysis {
  contract : String
  state : String
  source_digest : String
  analysis_digest : String?
  thumbnail_url : String?
  duration_seconds : Double?
  thumbnail : Json
  waveform : NativeWaveform
  video : Json
  audio : Json
} derive(FromJson)

///|
#warnings("-unused_field")
struct NativePreparedIntake {
  intake_id : String
  upload_url : String
  status : String
} derive(FromJson)

///|
struct Model {
  bootstrapped : Bool
  loading : Bool
  busy : Bool
  projects : Array[@api.ProjectSummary]
  project_id : String
  workspace_lens : WorkspaceLens
  selected_workspace_recipe : WorkspaceRecipe
  selected_workspace_node : String
  workspace_catalog : Array[WorkspaceDefinitionSummary]
  workspace_graph : WorkspaceGraphSummary?
  workspace_graph_undo : Array[WorkspaceGraphSummary]
  workspace_graph_redo : Array[WorkspaceGraphSummary]
  workspace_graph_dirty : Bool
  workspace_graph_saving : Bool
  workspace_pending_run : String
  workspace_node_palette_search : String
  workspace_connect_port : String
  workspace_node_positions : Array[WorkspaceNodePosition]
  workspace_canvas_drag : WorkspaceCanvasDrag?
  workspace_canvas_zoom : Double
  workspace_connections : Array[WorkspaceConnection]
  workspace_asset_nodes : Array[WorkspaceAssetNode]
  workspace_dragged_asset : String
  workspace_connect_from : String
  workspace_app_view : Bool
  workspace_search : String
  workspace_search_results : Array[WorkspaceSearchSummary]
  workspace_comment : String
  workspace_public_input : String
  workspace_activity : Array[String]
  workspace_run_id : String
  workspace_run_state : String
  workspace_proposals : Array[WorkspaceProposalSummary]
  workspace_share_url : String
  production_project_id : String
  workspace : @api.WorkspaceSnapshot?
  selected_take_id : String
  selected_clip_ids : Array[String]
  selected_transition_id : String
  playhead_ticks : Int
  last_animation_ms : Double?
  monitor_mode : MonitorMode
  program_surface : ProgramSurface
  playing : Bool
  muted : Bool
  volume : String
  loop_enabled : Bool
  loop_in : Int
  loop_out : Int?
  zoom : Double
  ripple : Bool
  snap : Bool
  blade : Bool
  multi_select : Bool
  timeline_drag : TimelineDrag?
  timeline_scroll_x : Int
  viewport_width : Int
  filters : AssetFilters
  inspector : InspectorDraft
  intake : IntakeDraft
  utility_concat : UtilityConcatState
  pending_intake_id : String
  review_comment : String
  analysis : @api.MediaAnalysis?
  preview_job : EditorJobPayload?
  preview_job_id : String
  preview_generation : Int
  open_generation : Int
  export_state : ExportState
  request_sequence : Int
  undo_stack : Array[String]
  redo_stack : Array[String]
  status : String
  error : String
  conflict : String
  retry : PendingAction?
}

///|
enum PendingAction {
  RetryOpen(String)
  RetryCommand(String, Json)
  RetryComment(String)
  RetryPreview
}

///|
fn initial_inspector() -> InspectorDraft {
  {
    transition: "cross-dissolve",
    transition_seconds: "0.5",
    brightness: "0",
    contrast: "1",
    saturation: "1",
    gamma: "1",
    opacity: "1",
    scale: "1",
    position_x: "0",
    position_y: "0",
    rotation: "0",
    mask_shape: "rectangle",
    mask_x: "0.1",
    mask_y: "0.1",
    mask_width: "0.8",
    mask_height: "0.8",
    mask_feather: "0.05",
    mask_invert: false,
    speed_midpoint: "50",
    overlay_text: "",
    overlay_position: "bottom",
    overlay_size: "48",
    overlay_color: "#ffffff",
    overlay_background: "#000000",
    track_volume_db: "0",
    track_pan: "0",
    track_muted: false,
    keyframe_channel: "opacity",
    keyframe_value: "1",
    keyframe_interpolation: "linear",
  }
}

///|
fn initial_model() -> Model {
  {
    bootstrapped: false,
    loading: false,
    busy: false,
    projects: [],
    project_id: "project-mc3a",
    workspace_lens: GraphLens,
    selected_workspace_recipe: CombineVideosRecipe,
    selected_workspace_node: "concat",
    workspace_catalog: [],
    workspace_graph: None,
    workspace_graph_undo: [],
    workspace_graph_redo: [],
    workspace_graph_dirty: false,
    workspace_graph_saving: false,
    workspace_pending_run: "",
    workspace_node_palette_search: "",
    workspace_connect_port: "",
    workspace_node_positions: [
      { recipe: CombineVideosRecipe, node_id: "intake", x: 40, y: 80 },
      { recipe: CombineVideosRecipe, node_id: "probe", x: 300, y: 80 },
      { recipe: CombineVideosRecipe, node_id: "normalize", x: 560, y: 80 },
      { recipe: CombineVideosRecipe, node_id: "concat", x: 820, y: 80 },
      { recipe: CombineVideosRecipe, node_id: "verify", x: 1080, y: 80 },
      { recipe: CombineVideosRecipe, node_id: "register", x: 1340, y: 80 },
      { recipe: BriefToDeliveryRecipe, node_id: "brief", x: 40, y: 80 },
      { recipe: BriefToDeliveryRecipe, node_id: "validate", x: 300, y: 80 },
      { recipe: BriefToDeliveryRecipe, node_id: "project", x: 560, y: 80 },
      { recipe: BriefToDeliveryRecipe, node_id: "generate", x: 820, y: 80 },
      { recipe: BriefToDeliveryRecipe, node_id: "review", x: 1080, y: 80 },
      { recipe: BriefToDeliveryRecipe, node_id: "delivery", x: 1340, y: 80 },
    ],
    workspace_canvas_drag: None,
    workspace_canvas_zoom: 1.0,
    workspace_connections: [],
    workspace_asset_nodes: [],
    workspace_dragged_asset: "",
    workspace_connect_from: "",
    workspace_app_view: false,
    workspace_search: "",
    workspace_search_results: [],
    workspace_comment: "",
    workspace_public_input: "",
    workspace_activity: ["Workspace opened · graph revision 1"],
    workspace_run_id: "",
    workspace_run_state: "idle",
    workspace_proposals: [],
    workspace_share_url: "",
    production_project_id: "",
    workspace: None,
    selected_take_id: "",
    selected_clip_ids: [],
    selected_transition_id: "",
    playhead_ticks: 0,
    last_animation_ms: None,
    monitor_mode: ProgramMonitor,
    program_surface: InteractiveProxy,
    playing: false,
    muted: false,
    volume: "1",
    loop_enabled: false,
    loop_in: 0,
    loop_out: None,
    zoom: 1.0,
    ripple: true,
    snap: true,
    blade: false,
    multi_select: false,
    timeline_drag: None,
    timeline_scroll_x: 0,
    viewport_width: 1280,
    filters: {
      search: "",
      kind: "all",
      qc: "all",
      rights: "all",
      placement: "all",
    },
    inspector: initial_inspector(),
    intake: {
      selected_blob: None,
      role: "voice",
      file_name: "",
      mime_type: "audio/wav",
      size_bytes: "0",
      sha256: "",
      duration_seconds: "5",
      owner: "Mooncast operator",
      basis: "commissioned and cleared",
      territory: "worldwide",
      channels: "master, social cuts",
      rights_ref: "",
      source_kind: "local_upload",
      source_ref: "",
      pasted_content: "",
    },
    utility_concat: {
      files: [],
      job_id: "",
      phase: "idle",
      completed: 0,
      output_digest: "",
      output_size: 0,
      media_url: "",
      error: "",
    },
    pending_intake_id: "",
    review_comment: "",
    analysis: None,
    preview_job: None,
    preview_job_id: "",
    preview_generation: 0,
    open_generation: 0,
    export_state: {
      output_preset: "horizontal-1080p",
      actor: "creative-director",
      authority_ref: "",
      job_id: "",
      download_url: "",
      promoted: false,
      handed_off: false,
      receipt_state: "idle",
      canonical_revision: 0,
      timeline_revision: 0,
      output_digest: "",
      render_plan_digest: "",
      handoff_record_id: "",
      handoff_record_digest: "",
      handoff_request_id: "",
      handoff_status: "not-prepared",
    },
    request_sequence: 0,
    undo_stack: [],
    redo_stack: [],
    status: "Preparing editor authority…",
    error: "",
    conflict: "",
    retry: None,
  }
}

///|
fn timeline(model : Model) -> @api.Timeline? {
  match model.workspace {
    None => None
    Some(workspace) =>
      match workspace.snapshot {
        Some(snapshot) => Some(snapshot.timeline)
        None => workspace.timeline
      }
  }
}

///|
fn takes(model : Model) -> Array[@api.TakeVariant] {
  model.workspace.bind(workspace => workspace.take_variants).unwrap_or([])
}

///|
fn tracks(model : Model) -> Array[@api.Track] {
  timeline(model).map(value => value.tracks).unwrap_or([])
}

///|
fn clips(model : Model) -> Array[@api.Clip] {
  flatten_tracks(tracks(model))
}

///|
fn selected_take(model : Model) -> @api.TakeVariant? {
  takes(model).iter().find_first(take => take.take_id == model.selected_take_id)
}

///|
fn selected_clip(model : Model) -> @api.Clip? {
  guard model.selected_clip_ids.length() > 0 else { None }
  let selected = model.selected_clip_ids[0]
  clips(model).iter().find_first(clip => clip.clip_id == selected)
}

///|
fn track_for_clip(model : Model, clip_id : String) -> @api.Track? {
  tracks(model)
  .iter()
  .find_first(track => track.clips.any(clip => clip.clip_id == clip_id))
}

///|
fn duration_ticks(model : Model) -> Int {
  clips(model).fold(init=0, (maximum, clip) => {
    Int::max(maximum, clip.start_tick + clip.duration_ticks)
  })
}

///|
fn ticks_per_second(model : Model) -> Int {
  timeline(model).map(value => value.timebase.ticks_per_second).unwrap_or(1000)
}

///|
fn frame_ticks(model : Model) -> Int {
  Int::max(1, ticks_per_second(model) / 24)
}

///|
fn selected_revision(model : Model) -> Int {
  model.workspace.map(value => value.revision).unwrap_or(0)
}

///|
fn fresh_key(model : Model, prefix : String) -> String {
  "rabbita-\{prefix}-\{model.request_sequence + 1}"
}
