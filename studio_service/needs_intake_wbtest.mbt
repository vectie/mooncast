///|
fn needs_packet_fixture() -> @intake.MoonWikiNeedsPacket {
  let brief : @intake.MoonWikiEvidenceRef = {
    source_id: "wiki-brief-1",
    source_version: "7",
    source_digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    provenance_ref: "moonwiki://project/brief",
  }
  let bible : @intake.MoonWikiEvidenceRef = {
    source_id: "wiki-bible-1",
    source_version: "3",
    source_digest: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    provenance_ref: "moonwiki://project/bible",
  }
  let script : @intake.MoonWikiEvidenceRef = {
    source_id: "wiki-script-1",
    source_version: "11",
    source_digest: "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    provenance_ref: "moonwiki://project/script",
  }
  {
    contract: "moonwiki.mooncast-needs-export.v1",
    packet_id: "needs-fixture-1",
    packet_version: 1,
    exported_at: "2026-07-19T12:00:00+08:00",
    evidence_refs: [brief, bible, script],
    intent_refs: { brief, bible, script },
    client_need: {
      customer: "Design partner",
      payable_problem: "Replace a slow agency production loop",
      audience: "brand audience",
      channels: ["review-only"],
      acceptance_method: "Accept exact master and provenance package",
      repeat_purchase_hypothesis: "Quarterly episode retainer",
    },
    contract_boundary: {
      contract_ref: "contract-1",
      budget_ceiling_cny: 20000.0,
      revision_limit: 2,
      target_duration_seconds: 180,
      deliverables: ["master", "subtitles", "provenance"],
      payment_milestones: ["deposit", "animatic", "master"],
    },
    constraints: {
      rights_owner: "Design partner",
      rights_confirmed: true,
      rights_constraints: ["licensed source only"],
      confidentiality_class: "contract-confidential",
      permitted_provider_ids: ["approved-provider"],
      prohibited_provider_ids: [],
      permitted_data_class: "rights-cleared-confidential",
    },
    creative_strategy: {
      project_title: "Evidence-bound episode",
      objective: "Create a complete accepted brand story",
      narrative_proposition: "Character demonstrates the product promise",
      tone: "human and cinematic",
      claims: [],
      success_metrics: ["acceptance", "completion", "repeat order"],
      negative_constraints: ["no invented claims"],
    },
    unresolved_questions: [],
    publication_authority: false,
    provider_execution_authority: false,
  }
}

///|
async test "MoonWiki intake requires exact approval and seeds real intent bindings" {
  let root = "/tmp/mooncast-needs-intake-" + @async.now().to_string()
  let service = StudioService::new(root)
  let packet = needs_packet_fixture()
  let validation = @intake.validate_intake(packet)
  assert_true(validation.complete)
  let imported = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/v2/needs-intakes",
    query: None,
    headers: { "content-type": "application/json" },
    body: @utf8.encode(
      Json::object({
        "packet": packet.to_json(),
        "imported_at": "2026-07-19T12:01:00+08:00".to_json(),
      }).stringify(),
    ),
  })
  assert_eq(imported.status, 201)
  assert_true(
    @utf8.decode(imported.body).contains(validation.provenance_digest),
  )

  let denied = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/v2/needs-intakes/needs-fixture-1/seed-project",
    query: None,
    headers: { "content-type": "application/json" },
    body: @utf8.encode(
      Json::object({
        "packet_version": (1).to_json(),
        "expected_provenance_digest": validation.provenance_digest.to_json(),
        "project_id": "needs-project-1".to_json(),
        "recorded_at": "2026-07-19T12:02:00+08:00".to_json(),
      }).stringify(),
    ),
  })
  assert_eq(denied.status, 409)

  let approved = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/v2/needs-intakes/needs-fixture-1/decisions",
    query: None,
    headers: { "content-type": "application/json" },
    body: @utf8.encode(
      Json::object({
        "packet_version": (1).to_json(),
        "expected_provenance_digest": validation.provenance_digest.to_json(),
        "decision": "approve".to_json(),
        "actor": "named-producer".to_json(),
        "actor_role": "creative-director".to_json(),
        "note": "Reviewed exact exported evidence".to_json(),
        "decided_at": "2026-07-19T12:03:00+08:00".to_json(),
        "human_confirmed": true.to_json(),
      }).stringify(),
    ),
  })
  assert_eq(approved.status, 201)

  let seeded = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/v2/needs-intakes/needs-fixture-1/seed-project",
    query: None,
    headers: { "content-type": "application/json" },
    body: @utf8.encode(
      Json::object({
        "packet_version": (1).to_json(),
        "expected_provenance_digest": validation.provenance_digest.to_json(),
        "project_id": "needs-project-1".to_json(),
        "recorded_at": "2026-07-19T12:04:00+08:00".to_json(),
      }).stringify(),
    ),
  })
  assert_eq(seeded.status, 201)
  let project = service.get_project("needs-project-1")
  assert_eq(
    project.snapshot.qualification.unwrap().payable_problem,
    packet.client_need.payable_problem,
  )
  let creative = project.snapshot.creative_artifacts
  assert_true(
    creative.any(value => {
      value.kind == @creative.Brief &&
      value.content.contains("wiki-brief-1") &&
      value.content.contains(validation.provenance_digest)
    }),
  )
  assert_true(
    creative.any(value => {
      value.kind == @creative.IpBible && value.content.contains("wiki-bible-1")
    }),
  )
  assert_true(
    creative.any(value => {
      value.kind == @creative.Script && value.content.contains("wiki-script-1")
    }),
  )
  assert_false(
    creative.any(value => value.content.contains("moonwiki:intent:")),
  )
  let bindings = service.needs_intake.list_bindings()
  assert_eq(bindings.length(), 1)
  assert_false(bindings[0].publication_authority)
  assert_false(bindings[0].provider_execution_authority)
  let editor = service.bind_editor_moonwiki_intents(
    editor_from_production_graph(project.snapshot.graph),
  )
  assert_eq(editor.intent_refs.length(), 3)
  assert_eq(
    editor.intent_refs[0].intent_ref,
    packet.intent_refs.brief.provenance_ref,
  )
  assert_eq(
    editor.intent_refs[1].intent_ref,
    packet.intent_refs.bible.provenance_ref,
  )
  assert_eq(
    editor.intent_refs[2].intent_ref,
    packet.intent_refs.script.provenance_ref,
  )
}
