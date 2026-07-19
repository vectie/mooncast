///|
/// Versioned, append-only facts accepted by the deterministic reducer.
pub(all) struct ProjectEvent {
  schema_version : String
  event_id : String
  event_kind : String
  recorded_at : String
  source_digest : String
  invalidates_from_gate : String?
  qualification : @governance.ClientQualification?
  creative_artifact : @creative.CreativeArtifact?
  creative_decision : @creative.CreativeDecision?
  routing_plan : @governance.ModelRoutingPlan?
  routing_decision : @governance.RoutingDecision?
  generation_attempt : @governance.GenerationAttempt?
  qc_finding : @governance.QcFinding?
  qc_decision : @governance.QcDecision?
  master : @governance.Master?
  master_decision : @governance.MasterDecision?
  delivery_package : @governance.DeliveryPackage?
  delivery_acceptance : @governance.DeliveryAcceptance?
  publication_authorization : @governance.PublicationAuthorization?
  publication_observation : @governance.PublicationObservation?
  performance_review : @governance.PerformanceReview?
  gate_receipt : @governance.GateReceipt?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Typed host command. Exactly one payload matching `command` is accepted.
pub(all) struct ProjectCommand {
  schema_version : String
  kernel_version : String
  command_id : String
  command : String
  recorded_at : String
  evidence_digest : String
  snapshot : ProjectSnapshot
  gate : String?
  actor : String?
  role : String?
  qualification : @governance.ClientQualification?
  creative_artifact : @creative.CreativeArtifact?
  creative_decision : @creative.CreativeDecision?
  routing_plan : @governance.ModelRoutingPlan?
  routing_decision : @governance.RoutingDecision?
  generation_attempt : @governance.GenerationAttempt?
  qc_finding : @governance.QcFinding?
  qc_decision : @governance.QcDecision?
  master : @governance.Master?
  master_decision : @governance.MasterDecision?
  delivery_package : @governance.DeliveryPackage?
  delivery_acceptance : @governance.DeliveryAcceptance?
  publication_authorization : @governance.PublicationAuthorization?
  publication_observation : @governance.PublicationObservation?
  performance_review : @governance.PerformanceReview?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct KernelError {
  code : String
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GateReadiness {
  gate : String
  ready : Bool
  reasons : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionProjection {
  current_gate : String?
  next_gate : String?
  stage : String
  complete : Bool
  graph_validation : @project.GraphValidation
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommandResult {
  schema_version : String
  kernel_version : String
  command_id : String
  ok : Bool
  error : KernelError?
  snapshot : ProjectSnapshot
  emitted_events : Array[ProjectEvent]
  readiness : GateReadiness?
  projection : ProductionProjection
  authority : @governance.AuthorityBoundary
} derive(Debug, Eq, ToJson, FromJson)
