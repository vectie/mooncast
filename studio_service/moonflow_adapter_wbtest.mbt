///|
fn moonflow_test_request(
  spec : MoonflowOperationSpec,
  artifact_ref : String,
  input_digest : String,
  attempt : String,
) -> MoonflowAdapterRequest {
  {
    request_id: "request-run-review-" + attempt,
    run_id: "run-review",
    book_id: "book-review",
    work_item_id: "work-review",
    declaration_id: "mooncast-pack-local-v2",
    attempt_id: attempt,
    idempotency_key: "run-review/work-review/1/" + input_digest,
    product_id: "mooncast",
    operation: moonflow_operation_ref(spec),
    requested_authority: spec.authority,
    acceptance_criteria: ["exact durable output"],
    input_contracts: [moonflow_schema_ref(spec.input_schema)],
    output_contracts: [moonflow_schema_ref(spec.output_schema)],
    required_claim: spec.claim_ceiling,
    input_digest,
    input_artifacts: [artifact_ref],
    timeout_ms: 30000,
    created_at: "2026-07-31T08:00:00Z",
  }
}

///|
async fn moonflow_test_artifact(
  root : String,
  name : String,
  value : Json,
) -> (String, String) {
  let reference = "moonflow-inputs/" + name + ".json"
  let store = @host_store.AtomicStore::new(root + "/moonflow-inputs")
  ignore(store.put_json(name + ".json", value))
  (reference, moonflow_declared_input_digest(root, [reference]))
}

///|
test "selected MoonFlow declaration derives every contract from the manifest" {
  let specs = moonflow_operation_specs()
  let ids : Array[String] = []
  let manifest = @mooncast_pack.manifest()
  for spec in specs {
    assert_false(ids.contains(spec.operation_id))
    ids.push(spec.operation_id)
    guard manifest.tools.iter().find_first(tool => tool.id == spec.operation_id)
      is Some(tool) else {
      fail("selected adapter operation is missing from manifest")
    }
    assert_eq(spec.input_schema, tool.input_schema_id)
    assert_eq(spec.output_schema, tool.output_schema_id)
    assert_eq(spec.authority, moonflow_authority_id(tool.authority))
    assert_eq(spec.idempotent, tool.idempotent)
  }
  assert_eq(specs.length(), 34)
  let declaration = moonflow_adapter_declaration()
  guard moonflow_json_member(declaration, "operations") is Some(Array(ops)) else {
    fail("adapter declaration operations are missing")
  }
  assert_eq(ops.length(), specs.length())
  let projection = moonflow_adapter_pack_projection()
  guard moonflow_json_member(projection, "tools") is Some(Array(tools)) &&
    moonflow_json_member(projection, "schemas") is Some(Array(schemas)) else {
    fail("adapter pack projection is incomplete")
  }
  assert_eq(tools.length(), specs.length())
  assert_true(schemas.length() > 0)
  for
    required in [
      "editor.production.import", "editor.command.apply", "editor.preview.plan",
      "editor.preview.start", "editor.export.create", "editor.production.export",
      "editor.master.promote", "delivery-build.plan", "delivery-build.execute", "delivery-build.accept",
      "client-portal.decide", "handoff.final-deliverable.evidence",
    ] {
    assert_true(ids.contains(required))
  }
}

///|
async test "real MoonFlow key replays exactly and health exposes only exercised operations" {
  let root = "/tmp/mooncast-moonflow-replay-" + @async.now().to_string()
  let service = StudioService::new(root)
  let spec = moonflow_find_operation("mooncast/control-tower.observe@0.2.0").unwrap()
  let (artifact, digest) = moonflow_test_artifact(root, "control-query", {
    "as_of_date": "2026-07-31",
  })
  let request = moonflow_test_request(
    spec, artifact, digest, "attempt-control-1",
  )
  assert_true(request.idempotency_key.contains("/"))
  assert_true(request.idempotency_key.contains(":"))
  moonflow_validate_request(request, spec)
  let envelope : MoonflowInvokeEnvelope = {
    request,
    binding: Json::empty_object(),
  }
  let first = service.moonflow_invoke(envelope)
  let replay = service.moonflow_invoke(envelope)
  assert_eq(first, replay)
  assert_eq(moonflow_json_member(first, "status"), Some("succeeded".to_json()))
  let health = service.moonflow_adapter_health()
  assert_eq(
    moonflow_json_member(health, "operation_refs"),
    Some(["mooncast/control-tower.observe@0.2.0"].to_json()),
  )
}

///|
async test "provider, QC and non-idempotent reconcile fail closed" {
  let root = "/tmp/mooncast-moonflow-negative-" + @async.now().to_string()
  let service = StudioService::new(root)
  let generate = moonflow_find_operation(
    "mooncast/asset-factory.generate@0.2.0",
  ).unwrap()
  let plan : Json = {
    "contract": "mooncast.asset-factory-plan.v1",
    "plan": {
      "id": "plan-negative",
      "version": 1,
      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    },
    "project_id": "negative-project",
    "project_revision": 1,
    "specs": [],
    "total_cost_ceiling_cny": 0,
    "created_at": "2026-07-31T08:00:00Z",
    "publication_authority": false,
    "provider_execution_authority": false,
  }
  let (plan_ref, plan_digest) = moonflow_test_artifact(root, "asset-plan", plan)
  let denied_request = moonflow_test_request(
    generate, plan_ref, plan_digest, "attempt-provider-denied",
  )
  let denied_envelope : MoonflowInvokeEnvelope = {
    request: denied_request,
    binding: {
      "project_id": "negative-project",
      "resource_id": "variant-1",
      "operator_id": "named-producer",
      "operator_role": "producer",
      "human_confirmed": true,
    },
  }
  let denied = service.moonflow_invoke(denied_envelope)
  assert_eq(moonflow_json_member(denied, "status"), Some("failed".to_json()))
  assert_eq(service.moonflow_adapter_exercises().length(), 0)

  let unknown_request = {
    ..denied_request,
    request_id: "request-run-review-attempt-provider-unknown",
    attempt_id: "attempt-provider-unknown",
    idempotency_key: "run-review/work-review/2/" + plan_digest,
  }
  let unknown_envelope : MoonflowInvokeEnvelope = {
    request: unknown_request,
    binding: denied_envelope.binding,
  }
  let prepared : MoonflowAttemptRecord = {
    contract_id: "mooncast.moonflow-adapter-attempt.v1",
    adapter_id: "mooncast-pack-local-v2",
    request_id: unknown_request.request_id,
    attempt_id: unknown_request.attempt_id,
    idempotency_key: unknown_request.idempotency_key,
    operation_ref: unknown_request.operation,
    request_fingerprint: moonflow_request_fingerprint(unknown_envelope),
    input_digest: unknown_request.input_digest,
    status: "prepared",
    output_ref: "",
    output_digest: "",
    result: None,
    started_at: unknown_request.created_at,
    updated_at: unknown_request.created_at,
  }
  let state = @host_store.AtomicStore::new(root + "/moonflow-adapter/state")
  ignore(
    state.put_json(
      moonflow_attempt_key(unknown_request.idempotency_key),
      prepared.to_json(),
    ),
  )
  let reconcile = service.moonflow_reconcile(unknown_envelope)
  assert_eq(
    moonflow_json_member(reconcile, "decision"),
    Some("investigate-unknown".to_json()),
  )
  assert_eq(
    moonflow_json_member(reconcile, "retry_allowed"),
    Some(false.to_json()),
  )

  let review = moonflow_find_operation("mooncast/asset-factory.review@0.2.0").unwrap()
  let finding : Json = {
    "contract": "mooncast.asset-qc-finding.v1",
    "finding_id": "finding-only-one",
    "variant_id": "variant-1",
    "dimension": "technical",
    "status": "pass",
    "evidence_digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "reviewer": "named-qc",
    "reviewer_role": "human-reviewer",
    "reviewed_at": "2026-07-31T08:00:00Z",
    "human_confirmed": true,
    "immutable": true,
  }
  let (finding_ref, finding_digest) = moonflow_test_artifact(
    root, "one-finding", finding,
  )
  let review_request = moonflow_test_request(
    review, finding_ref, finding_digest, "attempt-qc-incomplete",
  )
  let incomplete = service.moonflow_invoke({
    request: review_request,
    binding: {
      "project_id": "negative-project",
      "resource_id": "asset-1",
      "resource_version": 1,
      "variant_id": "variant-1",
      "operator_id": "named-qc",
      "operator_role": "human-reviewer",
      "human_confirmed": true,
    },
  })
  assert_eq(
    moonflow_json_member(incomplete, "status"),
    Some("failed".to_json()),
  )
  assert_eq(service.moonflow_adapter_exercises().length(), 0)
}
