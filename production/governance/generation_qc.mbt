///|
pub(all) struct GenerationAttempt {
  attempt : @project.VersionRef
  shot_id : String
  route_id : String
  route_plan : @project.VersionRef
  prompt_digest : String
  source_asset_digests : Array[String]
  seed : Int?
  duration_ms : Int
  cost_cny : Double
  output_digest : String
  status : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum QcDimension {
  Technical
  Continuity
  Safety
  Claims
  Rights
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn qc_dimensions() -> Array[QcDimension] {
  [Technical, Continuity, Safety, Claims, Rights]
}

///|
pub(all) struct QcFinding {
  finding : @project.VersionRef
  shot_id : String
  attempt_digest : String
  dimension : QcDimension
  status : String
  evidence_digest : String
  note : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct QcDecision {
  finding : @project.VersionRef
  decision : String
  actor : String
  role : String
  decided_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn shot_passes_qc(
  shot_id : String,
  attempts : Array[GenerationAttempt],
  findings : Array[QcFinding],
  decisions : Array[QcDecision],
) -> Bool {
  for dimension in qc_dimensions() {
    let mut passed = false
    for finding in findings {
      if finding.shot_id == shot_id &&
        finding.dimension == dimension &&
        finding.status == "pass" &&
        attempts.any(attempt => {
          attempt.shot_id == shot_id &&
          attempt.status == "succeeded" &&
          attempt.output_digest == finding.attempt_digest
        }) &&
        decisions.any(decision => {
          decision.finding == finding.finding &&
          decision.decision == "approved" &&
          decision.actor != ""
        }) {
        passed = true
      }
    }
    if !passed {
      return false
    }
  }
  true
}

///|
pub fn generation_attempt_valid(
  attempt : GenerationAttempt,
  graph : @project.ProjectGraph,
  plan : ModelRoutingPlan?,
) -> Bool {
  let shot_exists = @project.flattened_shots(graph).any(shot => {
    shot.shot_id == attempt.shot_id && shot.duration_ms == attempt.duration_ms
  })
  let route_exists = match plan {
    None => false
    Some(value) =>
      value.reference == attempt.route_plan &&
      value.routes.any(route => {
        route.route_id == attempt.route_id &&
        route.shot_ids.any(id => id == attempt.shot_id) &&
        attempt.cost_cny >= 0.0 &&
        attempt.cost_cny <= route.cost_ceiling_cny
      })
  }
  shot_exists &&
  route_exists &&
  attempt.attempt.id != "" &&
  attempt.attempt.version >= 1 &&
  attempt.prompt_digest != "" &&
  (
    attempt.status == "authorized" ||
    attempt.status == "running" ||
    attempt.status == "succeeded" ||
    attempt.status == "failed" ||
    attempt.status == "cancelled"
  ) &&
  (attempt.status != "succeeded" || attempt.output_digest != "")
}

///|
pub fn qc_finding_valid(
  finding : QcFinding,
  attempts : Array[GenerationAttempt],
) -> Bool {
  finding.finding.id != "" &&
  finding.finding.version >= 1 &&
  (finding.status == "pass" || finding.status == "fail") &&
  finding.evidence_digest != "" &&
  attempts.any(attempt => {
    attempt.shot_id == finding.shot_id &&
    attempt.status == "succeeded" &&
    attempt.output_digest == finding.attempt_digest
  })
}

///|
pub fn qc_decision_valid(
  decision : QcDecision,
  findings : Array[QcFinding],
) -> Bool {
  decision.actor != "" &&
  decision.role != "" &&
  decision.decided_at != "" &&
  (
    decision.decision == "approved" ||
    decision.decision == "rejected" ||
    decision.decision == "revision-requested"
  ) &&
  findings.any(finding => finding.finding == decision.finding)
}
