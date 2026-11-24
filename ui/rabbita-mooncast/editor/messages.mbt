///|
enum Msg {
  ProjectReply(String, Int32, Msg)
  ExportReply(String, Int32, Msg)
  Bootstrap
  ReloadProjects
  ProjectsLoaded(Int32, Result[Json, Error])
  WorkspaceProposalsLoaded(Result[Json, Error])
  WorkspaceCatalogLoaded(Result[Json, Error])
  WorkspaceCapsulesLoaded(Result[Json, Error])
  WorkspaceGraphLoaded(Result[Json, Error])
  WorkspaceAssetsLoaded(Result[Json, Error])
  WorkspaceAssetQueryChanged(String)
  WorkspaceAssetKindChanged(String)
  WorkspaceAssetTagChanged(String)
  WorkspaceAssetPageChanged(Int32)
  WorkspaceFeaturesLoaded(Result[Json, Error])
  SaveWorkspaceGraph(String)
  WorkspaceGraphSaved(String, Result[Json, Error])
  WorkspaceNodePaletteChanged(String)
  AddWorkspaceNode(String)
  ExpandWorkspaceCapsule(String, Int32)
  DeleteSelectedWorkspaceNode
  DuplicateSelectedWorkspaceNode
  ToggleSelectedWorkspaceNodeCollapsed
  WorkspaceParameterKeyChanged(String)
  WorkspaceParameterValueChanged(String)
  WorkspaceParameterTypeChanged(String)
  SetWorkspaceNodeParameter
  SetWorkspaceDeclaredParameter(String, String, String)
  ToggleWorkspaceDeclaredBoolean(String, String)
  DeleteWorkspaceNodeParameter(String)
  WorkspaceGraphUndo
  WorkspaceGraphRedo
  SelectProject(String)
  SwitchWorkspaceLens(WorkspaceLens)
  SelectWorkspaceRecipe(WorkspaceRecipe)
  SelectWorkspaceNode(String)
  ToggleWorkspaceNodeSelection
  SelectWorkspaceEdge(String)
  DeleteSelectedWorkspaceEdge
  CopyWorkspaceNodes
  PasteWorkspaceNodes
  GroupWorkspaceNodes
  ToggleWorkspaceNodeMode(String)
  AutoLayoutWorkspaceGraph
  WorkspacePresenceRenewed(Result[Json, Error])
  RenewWorkspacePresence
  WorkspaceActorChanged(String)
  WorkspaceCanvasPointerDown(String, @common.Mouse)
  WorkspaceCanvasPointerMoved(@common.Mouse)
  WorkspaceCanvasPointerReleased
  WorkspaceNodeNudged(String, Int32, Int32)
  WorkspaceZoomChanged(Double)
  WorkspacePortActivated(String, String, Bool)
  WorkspaceAssetDragStarted(String)
  WorkspaceAssetAddRequested(String)
  WorkspaceAssetDropped
  ToggleWorkspaceAssetSelection(String)
  TagSelectedWorkspaceAsset
  DeleteSelectedWorkspaceAsset
  WorkspaceAssetMutationFinished(String, Result[Json, Error])
  ToggleWorkspaceAppView
  WorkspaceSearchChanged(String)
  WorkspaceSearchLoaded(Result[Json, Error])
  WorkspaceCommentChanged(String)
  WorkspacePublicInputChanged(String)
  PostWorkspaceNodeComment
  CompareWorkspaceAssets
  WorkspaceAssetComparisonLoaded(Result[Json, Error])
  PromoteWorkspaceAsset
  BranchWorkspaceAsset
  PublishWorkspaceCapsule
  ShareWorkspaceRun
  WorkspaceSecureShareCreated(Result[Json, Error])
  RevokeWorkspaceShare
  WorkspaceShareRevoked(Result[Json, Error])
  ApplyWorkspaceProposal(String)
  ReviewWorkspaceProposal(String)
  WorkspaceProposalReviewLoaded(Result[Json, Error])
  WorkspaceProposalApplied(Result[Json, Error])
  WorkspaceAgentInstructionChanged(String)
  AskWorkspaceAgent
  WorkspaceAgentAssisted(Result[Json, Error])
  StartWorkspaceRecipe
  StartWorkspaceSelectedOutput
  WorkspaceRecipeStarted(Result[Json, Error])
  PollWorkspaceRun
  WorkspaceRunPolled(Result[Json, Error])
  WorkspaceRunEventsLoaded(Result[Json, Error])
  WorkspaceRunHistoryLoaded(Result[Json, Error])
  OpenWorkspaceRun(String)
  ClaimWorkspaceNode
  WorkspaceRunAdvanced(Result[Json, Error])
  DecideWorkspaceHumanGate(String)
  WorkspaceHumanDecisionFinished(Result[Json, Error])
  CancelWorkspaceRun
  RetryWorkspaceNode
  WorkspaceActionFinished(String, Result[Json, Error])
  OpenProject
  ProductionProjectChanged(String)
  ImportProduction
  ProductionImported(Result[Json, Error])
  WorkspaceOpened(Int32, Result[Json, Error])
  SnapshotLoaded(Int32, Result[Json, Error])
  SelectTake(String)
  SelectAdjacentTake(Int32)
  AnalysisLoaded(String, Result[Json, Error])
  FilterSearchChanged(String)
  FilterKindChanged(String)
  FilterQcChanged(String)
  FilterRightsChanged(String)
  FilterPlacementChanged(String)
  SelectClip(String, Bool)
  SelectAdjacentClip(Int32, Bool)
  SelectTransition(String)
  SeekTicks(Int32)
  ScrubChanged(String)
  StepFrame(Int32)
  TogglePlay
  SetPlaybackSpeed(String)
  SetPreviewHeight(String)
  SetOutputHeight(String)
  PlayerFullscreen
  OpenPlayerFile
  ClosePlayerFile
  TogglePlayerCaptions
  SetPlayerTranslation(String)
  PollPlayerCaptions
  PlayerCaptionsLoaded(Int, String, Result[Json, Error])
  ToggleLocalCaptions
  ToggleCaptionTranslation
  GenerateLocalCaptions
  LocalCaptionsLoaded(String, Result[Json, Error])
  AnimationFrame(Double)
  SwitchMonitor(MonitorMode)
  SwitchProgramSurface(ProgramSurface)
  VolumeChanged(String)
  ToggleMute
  ToggleTrackSolo(String)
  ClearTrackSolo
  SetLoopIn
  SetLoopOut
  ToggleLoop
  ResyncProxy
  RefreshProgramMedia
  ToggleRipple
  ToggleSnap
  ToggleBlade
  ToggleMultiSelect
  TimelinePointerDown(String, Int32, @common.Mouse)
  TimelinePointerMoved(@common.Mouse)
  TimelinePointerReleased
  TimelineScrolled(@common.Scroll)
  ZoomIn
  ZoomOut
  FitTimeline
  AddSelectedTake
  MoveSelection(Int32)
  TrimSelection(String, Int32)
  RollSelection(Int32)
  SlipSelection(Int32)
  SetSlideOffset(String)
  SlideSelection
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
  ResizeTransition(Int32)
  RemoveTransition
  SetKeyframe
  RemoveKeyframe
  UtilityConcatFilesSelected(Array[UtilityConcatInput])
  StartUtilityConcat
  UtilityConcatFileHashed(Int32, Result[String, Error])
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
  PreviewStarted(Int32, Result[EditorJobResponse, Error])
  PollPreview(Int32)
  PreviewPolled(Int32, Result[EditorJobResponse, Error])
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
