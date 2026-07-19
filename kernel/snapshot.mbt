///|
pub let production_kernel_version : String = "2.0.0"

///|
/// Complete replayable production state. Host services may persist it but do not
/// reinterpret the domain decisions it contains.
pub(all) struct ProjectSnapshot {
  schema_version : String
  revision : Int
  graph : @project.ProjectGraph
  qualification : @governance.ClientQualification?
  creative_artifacts : Array[@creative.CreativeArtifact]
  creative_decisions : Array[@creative.CreativeDecision]
  routing_plan : @governance.ModelRoutingPlan?
  routing_decisions : Array[@governance.RoutingDecision]
  generation_attempts : Array[@governance.GenerationAttempt]
  qc_findings : Array[@governance.QcFinding]
  qc_decisions : Array[@governance.QcDecision]
  master : @governance.Master?
  master_decisions : Array[@governance.MasterDecision]
  delivery_package : @governance.DeliveryPackage?
  delivery_acceptances : Array[@governance.DeliveryAcceptance]
  publication_authorizations : Array[@governance.PublicationAuthorization]
  publication_observations : Array[@governance.PublicationObservation]
  performance_reviews : Array[@governance.PerformanceReview]
  gate_receipts : Array[@governance.GateReceipt]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn empty_snapshot(graph : @project.ProjectGraph) -> ProjectSnapshot {
  {
    schema_version: "mooncast.project-snapshot.v2",
    revision: 0,
    graph,
    qualification: None,
    creative_artifacts: [],
    creative_decisions: [],
    routing_plan: None,
    routing_decisions: [],
    generation_attempts: [],
    qc_findings: [],
    qc_decisions: [],
    master: None,
    master_decisions: [],
    delivery_package: None,
    delivery_acceptances: [],
    publication_authorizations: [],
    publication_observations: [],
    performance_reviews: [],
    gate_receipts: [],
  }
}
