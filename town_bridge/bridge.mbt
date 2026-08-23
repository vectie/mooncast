///|
pub(all) struct TownPackCandidate {
  contract_id : String
  candidate_ref : String
  origin_ref : String
  target_pack_id : String
  intake_operation_id : String
  submitted_by : String
  submitted_at : String
  title : String
  rationale : String
  claim_ceiling : String
  evidence_refs : Array[String]
  domain_payload : Json
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CreativeBrief {
  campaign_id : String
  objective : String
  audience : String
  channels : Array[String]
  deliverables : Array[String]
  rights_constraints : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PackTownSubject {
  subject_ref : String
  schema_id : String
  title : String
  summary : String
  lifecycle_state : String
  attention : String
  place_refs : Array[String]
  related_refs : Array[String]
  workflow_refs : Array[String]
  run_refs : Array[String]
  evidence_refs : Array[String]
  operation_ids : Array[String]
  domain_payload : Json
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PackTownProjection {
  contract_id : String
  pack_id : String
  product_id : String
  version : String
  generated_at : String
  subjects : Array[PackTownSubject]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn intake_creative_candidate(
  candidate : TownPackCandidate,
  audience : String,
  channels : Array[String],
  deliverables : Array[String],
  rights_constraints : Array[String],
) -> CreativeBrief raise {
  if candidate.contract_id != "moontown.pack-candidate-intake.v1" ||
    candidate.target_pack_id != "mooncast" ||
    candidate.intake_operation_id != "creative.candidate.intake" {
    fail("candidate is not addressed to MoonCast creative intake")
  }
  if candidate.candidate_ref.trim().is_empty() ||
    candidate.title.trim().is_empty() ||
    candidate.rationale.trim().is_empty() ||
    audience.trim().is_empty() ||
    channels.is_empty() ||
    deliverables.is_empty() {
    fail(
      "creative candidate requires identity, objective, audience, channels, and deliverables",
    )
  }
  {
    campaign_id: candidate.candidate_ref,
    objective: candidate.rationale,
    audience,
    channels,
    deliverables,
    rights_constraints,
  }
}

///|
pub fn project_creative_brief(
  candidate : TownPackCandidate,
  brief : CreativeBrief,
  generated_at : String,
) -> PackTownProjection {
  {
    contract_id: "moontown.pack-projection.v1",
    pack_id: "mooncast",
    product_id: "mooncast",
    version: "0.2.3",
    generated_at,
    subjects: [
      {
        subject_ref: "creative/briefs/\{brief.campaign_id}",
        schema_id: "creative-brief",
        title: candidate.title,
        summary: brief.objective,
        lifecycle_state: "brief-review",
        attention: "review",
        place_refs: ["places/media-studio"],
        related_refs: [candidate.origin_ref],
        workflow_refs: ["workflows/brief-to-delivery"],
        run_refs: [],
        evidence_refs: candidate.evidence_refs,
        operation_ids: ["project.create"],
        domain_payload: brief.to_json(),
      },
    ],
  }
}
