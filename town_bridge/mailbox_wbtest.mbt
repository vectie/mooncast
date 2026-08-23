///|
async test "delivered creative candidate stays in brief review" {
  let workspace = @fs.tmpdir(prefix="mooncast-town-bridge")
  let candidate : TownPackCandidate = {
    contract_id: "moontown.pack-candidate-intake.v1",
    candidate_ref: "town/candidates/night-bus-campaign",
    origin_ref: "town/ideas/night-bus-campaign",
    target_pack_id: "mooncast",
    intake_operation_id: "creative.candidate.intake",
    submitted_by: "transit-salon",
    submitted_at: "2026-08-23T10:00:00Z",
    title: "Night bus awareness",
    rationale: "Explain the proposed service and invite public review.",
    claim_ceiling: "observation",
    evidence_refs: ["evidence/night-bus.json"],
    domain_payload: {},
  }
  let key = bridge_mailbox_key(candidate.candidate_ref)
  bridge_write_json(
    bridge_root(workspace) + "/inbox/candidates/\{key}.json",
    candidate.to_json(),
  )
  let projection = prepare_creative_candidate(
    workspace,
    candidate,
    "night-shift workers",
    ["web"],
    ["review draft"],
    ["no publication before approval"],
    "2026-08-24T10:00:00Z",
  )
  assert_eq(projection.subjects.length(), 1)
  assert_eq(projection.subjects[0].lifecycle_state, "brief-review")
  let replayed = prepare_creative_candidate(
    workspace,
    candidate,
    "night-shift workers",
    ["web"],
    ["review draft"],
    ["no publication before approval"],
    "2026-08-24T10:00:00Z",
  )
  assert_eq(replayed.subjects.length(), 1)
  let acknowledgement = @fs.read_file(
    bridge_root(workspace) + "/outbox/candidate-receipts/\{key}.json",
  ).text()
  assert_true(acknowledgement.contains("received"))
  @fs.rmdir(workspace, recursive=true)
}
