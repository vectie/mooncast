///|
test "bottom-up creative candidate stays a brief until MoonCast accepts it" {
  let candidate : TownPackCandidate = {
    contract_id: "moontown.pack-candidate-intake.v1",
    candidate_ref: "river-memory",
    origin_ref: "town/ideas/river-memory",
    target_pack_id: "mooncast",
    intake_operation_id: "creative.candidate.intake",
    submitted_by: "river-neighborhood-book",
    submitted_at: "2026-08-23T10:00:00Z",
    title: "River-worker memories",
    rationale: "Preserve documented community stories in a short film.",
    claim_ceiling: "research-evidence",
    evidence_refs: ["evidence/river-interviews.json"],
    domain_payload: {},
  }
  let brief = intake_creative_candidate(
    candidate,
    "Moontown residents",
    ["town-screening"],
    ["short-documentary"],
    ["named interview consent required"],
  )
  let projection = project_creative_brief(
    candidate,
    brief,
    candidate.submitted_at,
  )
  assert_eq(projection.subjects[0].schema_id, "creative-brief")
  assert_eq(projection.subjects[0].operation_ids, ["project.create"])
  assert_false(projection.subjects[0].operation_ids.contains("shots.generate"))
}
