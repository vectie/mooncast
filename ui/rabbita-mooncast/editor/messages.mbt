///|
enum Msg {
  Bootstrap
  ProjectsLoaded(Result[Json, Error])
  WorkspaceProposalsLoaded(Result[Json, Error])
  WorkspaceCatalogLoaded(Result[Json, Error])
  WorkspaceGraphLoaded(Result[Json, Error])
  SaveWorkspaceGraph(String)
  WorkspaceGraphSaved(String, Result[Json, Error])
  WorkspaceNodePaletteChanged(String)
  AddWorkspaceNode(String)
  DeleteSelectedWorkspaceNode
  DuplicateSelectedWorkspaceNode
  ToggleSelectedWorkspaceNodeCollapsed
  WorkspaceGraphUndo
  WorkspaceGraphRedo
  SelectProject(String)
  SwitchWorkspaceLens(WorkspaceLens)
  SelectWorkspaceRecipe(WorkspaceRecipe)
  SelectWorkspaceNode(String)
  WorkspacePresenceRenewed(Result[Json, Error])
  WorkspaceCanvasPointerDown(String, @common.Mouse)
  WorkspaceCanvasPointerMoved(@common.Mouse)
  WorkspaceCanvasPointerReleased
  WorkspaceNodeNudged(String, Int, Int)
  WorkspaceZoomChanged(Double)
  WorkspacePortActivated(String, String, Bool)
  WorkspaceAssetDragStarted(String)
  WorkspaceAssetAddRequested(String)
  WorkspaceAssetDropped
  ToggleWorkspaceAppView
  WorkspaceSearchChanged(String)
  WorkspaceSearchLoaded(Result[Json, Error])
  WorkspaceCommentChanged(String)
  WorkspacePublicInputChanged(String)
  PostWorkspaceNodeComment
  CompareWorkspaceAssets
  PromoteWorkspaceAsset
  BranchWorkspaceAsset
  PublishWorkspaceCapsule
  ShareWorkspaceRun
  WorkspaceSecureShareCreated(Result[Json, Error])
  ApplyWorkspaceProposal(String)
  WorkspaceProposalApplied(Result[Json, Error])
  StartWorkspaceRecipe
  StartWorkspaceSelectedOutput
  WorkspaceRecipeStarted(Result[Json, Error])
  PollWorkspaceRun
  WorkspaceRunPolled(Result[Json, Error])
  WorkspaceActionFinished(String, Result[Json, Error])
  OpenProject
  ProductionProjectChanged(String)
  ImportProduction
  ProductionImported(Result[Json, Error])
  WorkspaceOpened(Int, Result[Json, Error])
  SnapshotLoaded(Int, Result[Json, Error])
  SelectTake(String)
  SelectAdjacentTake(Int)
  AnalysisLoaded(String, Result[Json, Error])
  FilterSearchChanged(String)
  FilterKindChanged(String)
  FilterQcChanged(String)
  FilterRightsChanged(String)
  FilterPlacementChanged(String)
  SelectClip(String, Bool)
  SelectAdjacentClip(Int, Bool)
  SelectTransition(String)
  SeekTicks(Int)
  ScrubChanged(String)
  StepFrame(Int)
  TogglePlay
  AnimationFrame(Double)
  SwitchMonitor(MonitorMode)
  SwitchProgramSurface(ProgramSurface)
  VolumeChanged(String)
  ToggleMute
  SetLoopIn
  SetLoopOut
  ToggleLoop
  ResyncProxy
  RefreshProgramMedia
  ToggleRipple
  ToggleSnap
  ToggleBlade
  ToggleMultiSelect
  TimelinePointerDown(String, Int, @common.Mouse)
  TimelinePointerMoved(@common.Mouse)
  TimelinePointerReleased
  TimelineScrolled(@common.Scroll)
  ZoomIn
  ZoomOut
  FitTimeline
  AddSelectedTake
  MoveSelection(Int)
  TrimSelection(String, Int)
  SplitSelection
  DeleteSelection
  Undo
  Redo
  CommandFinished(String, Json, Result[Json, Error])
  InspectorChanged(String, String)
  ToggleTrackMute
  ApplyClipSettings
  ApplyEffectStack
  ToggleMaskInvert
  ApplyTrackMix
  AddTextLayer(String)
  AddAudioLayer(String)
  ApplyTransition
  ResizeTransition(Int)
  RemoveTransition
  SetKeyframe
  RemoveKeyframe
  UtilityConcatFilesSelected(Array[UtilityConcatInput])
  StartUtilityConcat
  UtilityConcatFileHashed(Int, Result[String, Error])
  UtilityConcatCreated(Result[UtilityConcatJob, Error])
  UtilityConcatInputUploaded(Result[UtilityConcatJob, Error])
  UtilityConcatFinished(Result[UtilityConcatJob, Error])
  IntakeFileSelected(@dom.Blob?)
  IntakeFilePrepared(Result[LocalMediaSelection, Error])
  IntakeChanged(String, String)
  CreateMediaIntake
  IntakeCreated(Result[Json, Error])
  IntakeContentUploaded(Result[Json, Error])
  ReviewCommentChanged(String)
  PostReviewComment
  CommentSaved(Result[Json, Error])
  ApplyOutputPreset
  ExportChanged(String, String)
  StartPreview
  PreviewStarted(Int, Result[EditorJobResponse, Error])
  PollPreview(Int)
  PreviewPolled(Int, Result[EditorJobResponse, Error])
  RetryPreview
  StartExport
  ExportStarted(Result[EditorJobResponse, Error])
  PollExport
  ExportPolled(Result[EditorJobResponse, Error])
  RetryExport
  PromoteMaster
  MasterPromoted(Result[MasterPromotionResponse, Error])
  PrepareDeliverableHandoff
  HandoffRequestRecorded(Result[ImmutablePutView, Error])
  RetryPending
  ClearError
  KeyPressed(@common.Keyboard)
  Resized(@common.Viewport)
  UrlRequested(@url.UrlRequest)
}
