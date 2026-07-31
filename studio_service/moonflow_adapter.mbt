/// MoonFlow is the generic director. This file is only Mooncast's durable,
/// pack-local transport adapter over the existing StudioService capabilities;
/// it is deliberately not an agent runtime or a second workflow engine.

///|
struct MoonflowOperationSpec {
  operation_id : String
  authority : String
  input_schema : String
  output_schema : String
  claim_ceiling : String
  idempotent : Bool
} derive(Debug, Eq)

///|
struct MoonflowAdapterRequest {
  request_id : String
  run_id : String
  book_id : String
  work_item_id : String
  declaration_id : String
  attempt_id : String
  idempotency_key : String
  product_id : String
  operation : String
  requested_authority : String
  acceptance_criteria : Array[String]
  input_contracts : Array[String]
  output_contracts : Array[String]
  required_claim : String
  input_digest : String
  input_artifacts : Array[String]
  timeout_ms : Int
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct MoonflowInvokeEnvelope {
  request : MoonflowAdapterRequest
  binding : Json
} derive(Debug, ToJson, FromJson)

///|
struct MoonflowAttemptRecord {
  contract_id : String
  adapter_id : String
  request_id : String
  attempt_id : String
  idempotency_key : String
  operation_ref : String
  request_fingerprint : String
  input_digest : String
  status : String
  output_ref : String
  output_digest : String
  result : Json?
  started_at : String
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
struct MoonflowAdapterExercise {
  contract_id : String
  adapter_id : String
  operation_ref : String
  attempt_id : String
  output_ref : String
  output_digest : String
  result_ref : String
  exercised_at : String
} derive(Debug, ToJson, FromJson)

///|
fn moonflow_operation_claims() -> Array[MoonflowOperationSpec] {
  [
    {
      operation_id: "project.create",
      authority: "sandbox-execution",
      input_schema: "creative-brief",
      output_schema: "production-project",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
    {
      operation_id: "creative.artifact.revise",
      authority: "workspace-mutation",
      input_schema: "creative-revision-request",
      output_schema: "creative-artifact",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
    {
      operation_id: "creative.artifact.decide",
      authority: "workspace-mutation",
      input_schema: "creative-decision-request",
      output_schema: "creative-decision",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
    {
      operation_id: "project.advance",
      authority: "workspace-mutation",
      input_schema: "gate-decision",
      output_schema: "production-project",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
    {
      operation_id: "asset-factory.plan.record",
      authority: "workspace-mutation",
      input_schema: "asset-factory-plan",
      output_schema: "asset-factory-plan",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "asset-factory.generate",
      authority: "external-effect",
      input_schema: "asset-factory-plan",
      output_schema: "asset-generation-variant",
      claim_ceiling: "digital-artifact",
      idempotent: false,
    },
    {
      operation_id: "asset-factory.review",
      authority: "workspace-mutation",
      input_schema: "asset-qc-finding",
      output_schema: "approved-reusable-asset",
      claim_ceiling: "accepted-knowledge",
      idempotent: true,
    },
    {
      operation_id: "asset-factory.bind-shots",
      authority: "workspace-mutation",
      input_schema: "approved-reusable-asset",
      output_schema: "shot-asset-binding",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
    {
      operation_id: "animatic.plan.record",
      authority: "workspace-mutation",
      input_schema: "animatic-plan",
      output_schema: "animatic-plan",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "animatic.render",
      authority: "sandbox-execution",
      input_schema: "animatic-plan",
      output_schema: "rendered-animatic",
      claim_ceiling: "digital-artifact",
      idempotent: false,
    },
    {
      operation_id: "animatic.approve",
      authority: "workspace-mutation",
      input_schema: "rendered-animatic",
      output_schema: "rendered-animatic-approval",
      claim_ceiling: "accepted-knowledge",
      idempotent: true,
    },
    {
      operation_id: "model-routing.plan.revise",
      authority: "workspace-mutation",
      input_schema: "model-routing-plan",
      output_schema: "model-routing-plan",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
    {
      operation_id: "model-routing.plan.decide",
      authority: "workspace-mutation",
      input_schema: "model-routing-plan",
      output_schema: "model-routing-decision",
      claim_ceiling: "accepted-knowledge",
      idempotent: true,
    },
    {
      operation_id: "routed-execution.create",
      authority: "workspace-mutation",
      input_schema: "routed-execution-create",
      output_schema: "routed-execution",
      claim_ceiling: "execution-result",
      idempotent: false,
    },
    {
      operation_id: "production-coordinator.run-pending",
      authority: "external-effect",
      input_schema: "production-coordinator-run-request",
      output_schema: "production-coordinator-run-result",
      claim_ceiling: "digital-artifact",
      idempotent: false,
    },
    {
      operation_id: "production-coordinator.confirm-qc",
      authority: "workspace-mutation",
      input_schema: "production-coordinator-qc-request",
      output_schema: "production-coordinator-qc-result",
      claim_ceiling: "accepted-knowledge",
      idempotent: true,
    },
    {
      operation_id: "editor.production.import",
      authority: "workspace-mutation",
      input_schema: "editor-production-intent",
      output_schema: "editor-production-import",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "editor.command.apply",
      authority: "workspace-mutation",
      input_schema: "editor-edit-command",
      output_schema: "editor-project",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "editor.preview.plan",
      authority: "sandbox-execution",
      input_schema: "editor-project",
      output_schema: "editor-render-plan",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "editor.preview.start",
      authority: "sandbox-execution",
      input_schema: "editor-render-plan",
      output_schema: "editor-preview-session",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "editor.export.create",
      authority: "sandbox-execution",
      input_schema: "editor-render-plan",
      output_schema: "editor-export-job",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "editor.production.export",
      authority: "workspace-mutation",
      input_schema: "editor-production-export-request",
      output_schema: "editor-export",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "editor.master.promote",
      authority: "workspace-mutation",
      input_schema: "editor-master-promotion",
      output_schema: "master-provenance",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "production.review",
      authority: "workspace-mutation",
      input_schema: "master-provenance",
      output_schema: "review-decision",
      claim_ceiling: "accepted-knowledge",
      idempotent: true,
    },
    {
      operation_id: "delivery.prepare",
      authority: "sandbox-execution",
      input_schema: "production-project",
      output_schema: "delivery-package-v2",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "delivery-build.plan",
      authority: "workspace-mutation",
      input_schema: "delivery-build-request",
      output_schema: "delivery-build",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "delivery-build.execute",
      authority: "sandbox-execution",
      input_schema: "delivery-build-action",
      output_schema: "delivery-build",
      claim_ceiling: "digital-artifact",
      idempotent: true,
    },
    {
      operation_id: "delivery-build.accept",
      authority: "workspace-mutation",
      input_schema: "delivery-build-acceptance",
      output_schema: "delivery-milestone-acceptance",
      claim_ceiling: "accepted-knowledge",
      idempotent: true,
    },
    {
      operation_id: "client-portal.create",
      authority: "workspace-mutation",
      input_schema: "client-portal-create",
      output_schema: "client-portal",
      claim_ceiling: "execution-result",
      idempotent: false,
    },
    {
      operation_id: "client-portal.decide",
      authority: "workspace-mutation",
      input_schema: "client-decision-request",
      output_schema: "client-decision-receipt",
      claim_ceiling: "accepted-knowledge",
      idempotent: false,
    },
    {
      operation_id: "handoff.final-deliverable.evidence",
      authority: "workspace-mutation",
      input_schema: "final-deliverable-evidence",
      output_schema: "final-deliverable-evidence",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
    {
      operation_id: "control-tower.observe",
      authority: "observe",
      input_schema: "control-tower-query",
      output_schema: "production-control-tower",
      claim_ceiling: "observation",
      idempotent: true,
    },
    {
      operation_id: "control-tower.actuals.record",
      authority: "workspace-mutation",
      input_schema: "control-tower-actuals-input",
      output_schema: "control-tower-operating-actuals",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
    {
      operation_id: "control-tower.exception.assign",
      authority: "workspace-mutation",
      input_schema: "control-tower-exception-assignment-input",
      output_schema: "control-tower-exception-assignment",
      claim_ceiling: "execution-result",
      idempotent: true,
    },
  ]
}

///|
fn moonflow_authority_id(authority : @pack.AuthorityClass) -> String {
  match authority {
    Observe => "observe"
    CognitiveMaintenance => "cognitive-maintenance"
    SandboxExecution => "sandbox-execution"
    WorkspaceMutation => "workspace-mutation"
    ExternalEffect => "external-effect"
    PhysicalEffect => "physical-effect"
  }
}

///|
fn moonflow_operation_specs() -> Array[MoonflowOperationSpec] {
  let manifest = @mooncast_pack.manifest()
  let result : Array[MoonflowOperationSpec] = []
  for policy in moonflow_operation_claims() {
    let tool = manifest.tools
      .iter()
      .find_first(tool => tool.id == policy.operation_id)
      .unwrap()
    result.push({
      operation_id: tool.id,
      authority: moonflow_authority_id(tool.authority),
      input_schema: tool.input_schema_id,
      output_schema: tool.output_schema_id,
      claim_ceiling: policy.claim_ceiling,
      idempotent: tool.idempotent,
    })
  }
  result
}

///|
fn moonflow_operation_ref(spec : MoonflowOperationSpec) -> String {
  "mooncast/" + spec.operation_id + "@0.2.0"
}

///|
fn moonflow_schema_ref(schema_id : String) -> String {
  "mooncast/" + schema_id + "@1.0.0"
}

///|
fn moonflow_find_operation(reference : String) -> MoonflowOperationSpec? {
  moonflow_operation_specs()
  .iter()
  .find_first(spec => moonflow_operation_ref(spec) == reference)
}

///|
fn moonflow_safe_component(value : String) -> Bool {
  !value.trim().is_empty() &&
  value != "." &&
  value != ".." &&
  value.all(ch => {
    (ch >= 'a' && ch <= 'z') ||
    (ch >= 'A' && ch <= 'Z') ||
    (ch >= '0' && ch <= '9') ||
    ch == '-' ||
    ch == '_' ||
    ch == '.'
  })
}

///|
fn moonflow_safe_artifact_ref(reference : String) -> Bool {
  let normalized = reference.trim().replace(old="\\", new="/")
  !normalized.is_empty() &&
  !normalized.has_prefix("/") &&
  !normalized
  .split("/")
  .any(part => part.is_empty() || part == "." || part == "..")
}

///|
fn moonflow_scoped_path(root : String, reference : String) -> String raise {
  guard moonflow_safe_artifact_ref(reference) else {
    fail("Mooncast MoonFlow artifacts must be workspace-relative")
  }
  @pathx.join(root, reference)
}

///|
async fn moonflow_read_artifact(
  root : String,
  reference : String,
) -> (Bytes, Json) {
  let canonical_root = @fs.realpath(@pathx.normalize(root))
  let path = @fs.realpath(moonflow_scoped_path(canonical_root, reference))
  guard path.has_prefix(canonical_root + "/") else {
    fail("Mooncast MoonFlow artifact escaped the data root")
  }
  let file = @fs.read_file(path)
  let bytes = file.binary()
  guard bytes.length() <= 16777216 else {
    fail("Mooncast MoonFlow input artifact exceeds 16 MiB")
  }
  (bytes, @json.parse(file.text()))
}

///|
async fn moonflow_declared_input_digest(
  root : String,
  artifacts : Array[String],
) -> String {
  let identities : Array[String] = []
  for reference in artifacts {
    let (bytes, _) = moonflow_read_artifact(root, reference)
    identities.push(
      reference +
      "|sha256:" +
      @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    )
  }
  "sha256:" + sha256_text(identities.join("\n"))
}

///|
async fn moonflow_write_immutable_json(
  root : String,
  reference : String,
  value : Json,
) -> String {
  let path = moonflow_scoped_path(root, reference)
  let text = value.stringify(indent=2) + "\n"
  if @fs.exists(path) {
    guard @fs.read_file(path).text() == text else {
      fail("Mooncast MoonFlow immutable output conflicts")
    }
    return "sha256:" + sha256_text(text)
  }
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fs.write_file(path, text, create=0o600, sync=Full)
  "sha256:" + sha256_text(text)
}

///|
fn moonflow_binding_string(
  binding : Json,
  name : String,
  default? : String = "",
) -> String {
  match binding {
    Object(fields) =>
      match fields.get(name) {
        Some(String(value)) => value
        _ => default
      }
    _ => default
  }
}

///|
fn moonflow_binding_int(
  binding : Json,
  name : String,
  default? : Int = 0,
) -> Int {
  match binding {
    Object(fields) =>
      match fields.get(name) {
        Some(Number(value, ..)) => value.to_int()
        _ => default
      }
    _ => default
  }
}

///|
fn moonflow_binding_bool(
  binding : Json,
  name : String,
  default? : Bool = false,
) -> Bool {
  match binding {
    Object(fields) =>
      match fields.get(name) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///|
fn moonflow_json_string(value : Json, name : String) -> String raise {
  guard value is Object(fields) && fields.get(name) is Some(String(result)) else {
    fail("Mooncast MoonFlow input requires string field " + name)
  }
  result
}

///|
fn moonflow_validate_request(
  request : MoonflowAdapterRequest,
  spec : MoonflowOperationSpec,
) -> Unit raise {
  guard request.product_id == "mooncast" &&
    request.operation == moonflow_operation_ref(spec) else {
    fail("Mooncast adapter owns only exact versioned Mooncast operations")
  }
  guard request.requested_authority == spec.authority else {
    fail("Mooncast adapter authority does not match the manifest tool")
  }
  guard request.input_contracts == [moonflow_schema_ref(spec.input_schema)] &&
    request.output_contracts == [moonflow_schema_ref(spec.output_schema)] else {
    fail("Mooncast adapter schema identities do not match the manifest tool")
  }
  guard request.required_claim == spec.claim_ceiling else {
    fail("Mooncast adapter required claim must match the declared ceiling")
  }
  for
    identity in [
      request.request_id,
      request.run_id,
      request.book_id,
      request.work_item_id,
      request.declaration_id,
      request.attempt_id,
    ] {
    guard moonflow_safe_component(identity) else {
      fail("Mooncast adapter identities must be safe path components")
    }
  }
  guard !request.idempotency_key.trim().is_empty() &&
    request.idempotency_key.length() <= 4096 else {
    fail(
      "Mooncast adapter idempotency_key must be non-empty bounded opaque text",
    )
  }
  guard request.timeout_ms > 0 &&
    request.input_artifacts.length() > 0 &&
    request.input_digest.has_prefix("sha256:") &&
    request.input_digest.length() == 71 else {
    fail("Mooncast adapter requires bounded inputs and a sha256 digest")
  }
  for reference in request.input_artifacts {
    guard moonflow_safe_artifact_ref(reference) else {
      fail("Mooncast adapter input artifact reference is unsafe")
    }
  }
}

///|
fn moonflow_json_member(value : Json, name : String) -> Json? {
  match value {
    Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn moonflow_json_with(
  value : Json,
  name : String,
  field_value : Json,
) -> Json raise {
  guard value is Object(fields) else {
    fail("Mooncast MoonFlow expected an object output")
  }
  let copy = fields.copy()
  copy[name] = field_value
  Json::object(copy)
}

///|
async fn StudioService::moonflow_internal_post(
  self : StudioService,
  path : String,
  body : Json,
) -> Result[Json, String] {
  let response = self.dispatch_http({
    request_method: Post,
    path,
    query: None,
    headers: Map([]),
    body: @utf8.encode(body.stringify()),
  })
  if response.status >= 200 && response.status < 300 {
    Ok(@json.parse(@utf8.decode(response.body)))
  } else {
    Err(
      "Mooncast operation returned HTTP " +
      response.status.to_string() +
      ": " +
      @utf8.decode(response.body),
    )
  }
}

///|
async fn StudioService::moonflow_internal_get(
  self : StudioService,
  path : String,
) -> Result[Json, String] {
  let response = self.dispatch_http({
    request_method: Get,
    path,
    query: None,
    headers: Map([]),
    body: [],
  })
  if response.status >= 200 && response.status < 300 {
    Ok(@json.parse(@utf8.decode(response.body)))
  } else {
    Err(
      "Mooncast observation returned HTTP " +
      response.status.to_string() +
      ": " +
      @utf8.decode(response.body),
    )
  }
}

///|
fn moonflow_project_id(binding : Json, input : Json) -> String raise {
  let explicit = moonflow_binding_string(binding, "project_id")
  if !explicit.is_blank() {
    return explicit
  }
  match moonflow_json_member(input, "project_id") {
    Some(String(value)) => value
    _ =>
      match moonflow_json_member(input, "campaign_id") {
        Some(String(value)) => value
        _ =>
          match moonflow_json_member(input, "id") {
            Some(String(value)) => value
            _ => fail("Mooncast MoonFlow route requires project_id")
          }
      }
  }
}

///|
fn moonflow_external_authority_granted(
  artifacts : Array[Json],
  authority_kind : String,
) -> Bool {
  let now = utc_timestamp_from_seconds(@runtime.wall_clock_ms() / 1000L)
  artifacts.any(value => {
    moonflow_json_member(value, "contract") ==
    Some("mooncast.host-authority-grant.v1".to_json()) &&
    moonflow_json_member(value, "authority") == Some(authority_kind.to_json()) &&
    moonflow_json_member(value, "granted") == Some(true.to_json()) &&
    (match moonflow_json_member(value, "granted_by") {
      Some(String(actor)) => !actor.is_blank()
      _ => false
    }) &&
    (match moonflow_json_member(value, "authority_ref") {
      Some(String(reference)) => !reference.is_blank()
      _ => false
    }) &&
    (match moonflow_json_member(value, "valid_until") {
      Some(String(valid_until)) => valid_until > now
      _ => false
    }) &&
    moonflow_json_member(value, "publication_authority") != Some(true.to_json())
  })
}

///|
fn moonflow_extract_creative_output(
  workspace : Json,
  decision : Bool,
) -> Json raise {
  let output = if decision {
    guard moonflow_json_member(workspace, "decisions") is Some(Array(values)) &&
      !values.is_empty() else {
      fail("Mooncast creative decision was not materialized")
    }
    values[values.length() - 1]
  } else {
    guard moonflow_json_member(workspace, "artifact") is Some(value) else {
      fail("Mooncast creative artifact was not materialized")
    }
    value
  }
  let contract = if decision {
    "mooncast.creative-decision.v1"
  } else {
    "mooncast.creative-artifact.v1"
  }
  let with_contract = moonflow_json_with(output, "contract", contract.to_json())
  if decision &&
    moonflow_json_member(with_contract, "client_revision_round") is None {
    moonflow_json_with(with_contract, "client_revision_round", (0).to_json())
  } else {
    with_contract
  }
}

///|
async fn StudioService::moonflow_editor_plan(
  self : StudioService,
  project_id : String,
  input : Json,
) -> Json {
  let editor = self.get_editor_project(project_id)
  guard moonflow_json_member(input, "project_id") == Some(project_id.to_json()) &&
    moonflow_json_member(input, "revision") == Some(editor.revision.to_json()) else {
    fail("Mooncast render plan input is not the current editor project")
  }
  @editor_http.freeze_render_plan(
    self.editor_repository,
    project_id,
    editor.media_bindings,
    "original",
  ).to_json()
}

///|
fn moonflow_preview_session(view : EditorJobView) -> Json {
  let error : Json = if view.job.state == "failed" &&
    !view.job.attempts.is_empty() {
    let attempt = view.job.attempts[view.job.attempts.length() - 1]
    { "code": attempt.error_code, "message": attempt.error_message }
  } else {
    Json::null()
  }
  {
    "contract": "mooncast.editor-preview-session.v1",
    "session_id": view.job.job_id,
    "state": view.job.state,
    "plan_digest": view.render_plan.plan_digest,
    "created_at": view.job.created_at,
    "output_refs": match view.media_url {
      Some(value) => ["ephemeral:" + value]
      None => []
    },
    "error": error,
    "publication_authority": false,
  }
}

///|
async fn StudioService::moonflow_editor_preview(
  self : StudioService,
  project_id : String,
  input : Json,
  request : MoonflowAdapterRequest,
  binding : Json,
) -> Json {
  let plan : @editor_plan.RenderPlan = @json.from_json(input)
  let current = self.moonflow_editor_plan(
    project_id,
    self.get_editor_project(project_id).snapshot.to_json(),
  )
  guard moonflow_json_member(current, "plan_digest") ==
    Some(plan.plan_digest.to_json()) else {
    fail("Mooncast preview must bind the current frozen render plan")
  }
  let job_id = match moonflow_binding_string(binding, "resource_id") {
    "" => "preview-" + request.attempt_id
    value => value
  }
  moonflow_preview_session(
    self.create_editor_preview(project_id, {
      expected_editor_revision: plan.project_revision,
      idempotency_key: request.idempotency_key,
      quality: plan.quality,
      job_id: Some(job_id),
    }),
  )
}

///|
fn moonflow_export_job(
  view : EditorJobView,
  cost_ceiling : String,
) -> Json raise {
  guard view.export_request is Some(request) else {
    fail("Mooncast export job is missing its production request")
  }
  let duration_seconds = view.render_plan.range.duration_ticks.to_double() /
    view.render_plan.timebase.ticks_per_second.to_double()
  let estimated = duration_seconds *
    request.spec.fps.numerator.to_double() /
    request.spec.fps.denominator.to_double() *
    request.spec.width.to_double() *
    request.spec.height.to_double() /
    1000000000.0
  let spec_seed : Json = {
    "width": request.spec.width,
    "height": request.spec.height,
    "fps": request.spec.fps,
    "container": request.spec.container,
    "video_codec": request.spec.video_codec,
    "audio_codec": request.spec.audio_codec,
    "subtitle_mode": request.spec.subtitle_mode,
    "ai_label_mode": request.spec.ai_label_mode,
    "provenance": { "retain_sources": request.spec.retain_sources },
    "project_id": view.render_plan.project_id,
    "timeline_id": view.render_plan.timeline_id,
    "project_revision": view.render_plan.project_revision,
    "timeline_revision": view.render_plan.timeline_revision,
    "cost_ceiling": cost_ceiling,
    "estimated_cost": estimated.to_string(),
    "estimate_method": "decimal-mpix-frames-v1",
    "contract": "mooncast.editor-export.v1",
    "test_only": false,
    "publication_authority": false,
  }
  let spec = moonflow_json_with(
    spec_seed,
    "spec_digest",
    ("sha256:" + sha256_text(spec_seed.stringify())).to_json(),
  )
  let error : Json = if view.job.state == "failed" &&
    !view.job.attempts.is_empty() {
    let attempt = view.job.attempts[view.job.attempts.length() - 1]
    { "code": attempt.error_code, "message": attempt.error_message }
  } else {
    Json::null()
  }
  {
    "contract": "mooncast.editor-export-job.v1",
    "job_id": view.job.job_id,
    "state": view.job.state,
    "plan": view.render_plan,
    "plan_digest": view.render_plan.plan_digest,
    "spec": spec,
    "attempt_count": view.job.attempts.length(),
    "job_revision": view.job.attempts.length(),
    "max_attempts": view.job.maximum_retries + 1,
    "provider_ref": "mooncast-native-ffmpeg",
    "provider_version": "argv-port-v1-verified",
    "cancel_requested": view.job.state == "cancelled",
    "error": error,
    "receipts": match view.export_receipt {
      Some(value) => [value]
      None => []
    },
    "publication_authority": false,
  }
}

///|
async fn StudioService::moonflow_editor_export_create(
  self : StudioService,
  project_id : String,
  input : Json,
  request : MoonflowAdapterRequest,
  binding : Json,
) -> Json {
  let plan : @editor_plan.RenderPlan = @json.from_json(input)
  let current = self.get_editor_project(project_id)
  guard current.revision == plan.project_revision else {
    fail("Mooncast export plan is stale")
  }
  let frozen = @editor_http.freeze_render_plan(
    self.editor_repository,
    project_id,
    current.media_bindings,
    plan.quality,
  )
  guard frozen.plan_digest == plan.plan_digest && plan.ready else {
    fail("Mooncast export requires the current ready render plan")
  }
  let job_id = match moonflow_binding_string(binding, "resource_id") {
    "" => "export-" + request.attempt_id
    value => value
  }
  let ceiling = moonflow_binding_string(
    binding,
    "cost_ceiling",
    default="100.0",
  )
  let view = self.create_editor_export(project_id, {
    idempotency_key: job_id,
    export_request: {
      job_id,
      request_id: job_id,
      expected_editor_revision: plan.project_revision,
      quality: "original",
      range: plan.range,
      max_attempts: 2,
      spec: {
        width: plan.output.width,
        height: plan.output.height,
        fps: plan.output.fps,
        container: "mp4",
        video_codec: "h264",
        audio_codec: "aac",
        subtitle_mode: "embedded-and-sidecar",
        ai_label_mode: "retain-visible",
        retain_sources: true,
        cost_ceiling: ceiling,
      },
    },
  })
  guard view.job.state == "succeeded" && view.export_receipt is Some(_) else {
    fail("Mooncast production export did not pass render verification")
  }
  moonflow_export_job(view, ceiling)
}

///|
async fn StudioService::moonflow_editor_export_envelope(
  self : StudioService,
  project_id : String,
  input : Json,
) -> Json {
  let request : @editor_integration.ProductionExportRequest = @json.from_json(
    input,
  )
  let view = self.get_editor_job(project_id, request.job_id)
  guard view.job.state == "succeeded" &&
    view.export_request == Some(request) &&
    view.export_receipt is Some(receipt) else {
    fail("Mooncast production export request does not bind a verified export")
  }
  {
    "contract": "mooncast.editor-export.v1",
    "request": {
      "request_id": request.request_id,
      "project_id": project_id,
      "timeline_id": view.render_plan.timeline_id,
      "project_revision": view.render_plan.project_revision,
      "timeline_revision": view.render_plan.timeline_revision,
      "publication_authority": false,
    },
    "job": {
      "job_id": request.job_id,
      "request_id": request.request_id,
      "state": view.job.state,
      "project_id": project_id,
      "timeline_id": view.render_plan.timeline_id,
      "project_revision": view.render_plan.project_revision,
      "timeline_revision": view.render_plan.timeline_revision,
    },
    "result": {
      "job_id": request.job_id,
      "state": "succeeded",
      "output_refs": [
        receipt.output_ref,
        "/api/editor/projects/" +
        project_id +
        "/exports/" +
        request.job_id +
        "/subtitles",
        "/api/editor/projects/" +
        project_id +
        "/exports/" +
        request.job_id +
        "/provenance",
      ],
      "publication_authority": false,
      "project_id": project_id,
      "timeline_id": view.render_plan.timeline_id,
      "project_revision": view.render_plan.project_revision,
      "timeline_revision": view.render_plan.timeline_revision,
    },
  }
}

///|
async fn StudioService::moonflow_editor_import(
  self : StudioService,
  project_id : String,
  input : Json,
) -> Json {
  let intent : @editor_integration.ProductionIntent = @json.from_json(input)
  let canonical = self.get_project(project_id)
  let existing_revision = match
    self.editor_repository.load_snapshot(project_id) {
    Some(record) => record.current_snapshot.revision
    None => 0
  }
  guard intent.contract == "mooncast.editor-production-intent.v1" &&
    intent.project_id == project_id &&
    intent.expected_production_revision == canonical.snapshot.revision &&
    intent.expected_editor_revision == existing_revision else {
    fail("Mooncast editor import intent is stale or targets another project")
  }
  let opened = self.import_editor_from_canonical_project(project_id)
  let seed : Json = {
    "contract": "mooncast.editor-production-import.v1",
    "snapshot": opened.snapshot,
    "command_log": opened.command_log,
    "media_records": opened.snapshot.media_refs,
    "lineage": [],
    "annotations": intent.annotations,
    "review_comments": intent.review_comments,
    "delivery_intents": intent.delivery_intents,
    "track_roles": intent.track_role_map,
    "publication_authority": false,
    "provider_authority": false,
  }
  moonflow_json_with(
    seed,
    "import_digest",
    ("sha256:" + sha256_text(seed.stringify())).to_json(),
  )
}

///|
async fn StudioService::moonflow_promote_master(
  self : StudioService,
  project_id : String,
  input : Json,
  request : MoonflowAdapterRequest,
  binding : Json,
) -> Json {
  let promotion : @editor_integration.MasterPromotionRequest = @json.from_json(
    input,
  )
  guard promotion.actor == moonflow_binding_string(binding, "operator_id") &&
    !promotion.actor.is_blank() &&
    !promotion.authority_ref.is_blank() else {
    fail("Mooncast master promotion requires the named bound operator")
  }
  let view = self.get_editor_job(project_id, promotion.job_id)
  guard view.job.state == "succeeded" &&
    view.export_receipt is Some(_) &&
    self.editor_production_source(project_id) is Some(source) else {
    fail("Mooncast promotion requires verified export and production source")
  }
  let receipt = self.promote_editor_master(project_id, promotion.job_id, {
    request: promotion,
    production_source: source,
    master_id: match moonflow_binding_string(binding, "master_id") {
      "" => "master-" + promotion.job_id
      value => value
    },
    subtitle_ref: "/api/editor/projects/" +
    project_id +
    "/exports/" +
    promotion.job_id +
    "/subtitles",
    promoted_at: request.created_at,
  })
  let digest = if receipt.digest.has_prefix("sha256:") {
    receipt.digest[7:].to_owned()
  } else {
    receipt.digest
  }
  {
    "contract": "mooncast.master-provenance.v2",
    "master_id": receipt.master_id,
    "project_id": project_id,
    "sha256": digest,
    "video_url": receipt.video_ref,
    "subtitle_url": receipt.subtitle_ref,
    "timeline": view.render_plan.tracks,
    "media": {
      "output_digest": receipt.digest,
      "size_bytes": receipt.size,
      "render_plan_digest": receipt.plan_digest,
      "export_job_id": receipt.job_id,
    },
    "labels": {
      "ai_generated": true,
      "visible_label": "AI GENERATED",
      "publication_authority": false,
    },
    "qc": {
      "render_verified": true,
      "subtitle_verified": true,
      "audio_verified": true,
      "lineage_verified": true,
    },
    "created_at": receipt.promoted_at,
  }
}

///|
async fn StudioService::moonflow_review_master(
  self : StudioService,
  project_id : String,
  input : Json,
  request : MoonflowAdapterRequest,
  binding : Json,
) -> Json {
  let kind = moonflow_binding_string(binding, "resource_id")
  guard ["technical-qc", "creative-director", "rights-compliance"].contains(
    kind,
  ) else {
    fail("Mooncast production review kind is not a named required review")
  }
  let actor = moonflow_binding_string(binding, "operator_id")
  let role = moonflow_binding_string(binding, "operator_role")
  let decision = moonflow_binding_string(binding, "decision")
  guard !actor.is_blank() &&
    !role.is_blank() &&
    (decision == "approved" || decision == "rejected") &&
    moonflow_binding_bool(binding, "human_confirmed") else {
    fail("Mooncast production review requires a named human decision")
  }
  let canonical = self.get_project(project_id)
  guard canonical.snapshot.master is Some(master) else {
    fail("Mooncast production review requires the canonical master")
  }
  let input_digest = moonflow_json_string(input, "sha256")
  let expected = if master.video_digest.has_prefix("sha256:") {
    master.video_digest[7:].to_owned()
  } else {
    master.video_digest
  }
  guard input_digest == expected else {
    fail("Mooncast production review input is not the canonical master")
  }
  let result = self.moonflow_internal_post(
    "/api/v2/projects/" +
    project_id +
    "/governance/master/" +
    kind +
    "/decisions",
    {
      "expected_project_revision": canonical.snapshot.revision,
      "expected_master_version": master.reference.version,
      "expected_master_digest": master.reference.digest,
      "human_confirmed": true,
      "actor": actor,
      "actor_role": role,
      "decision": decision,
      "note": moonflow_binding_string(binding, "note"),
    },
  )
  match result {
    Err(message) => fail(message)
    Ok(_) => {
      let approved = decision == "approved"
      {
        "asset_id": moonflow_json_string(input, "master_id"),
        "rights_cleared": approved,
        "safety_passed": approved,
        "human_approved": approved,
        "reviewer": actor,
        "reviewed_at": request.created_at,
      }
    }
  }
}

///|
async fn StudioService::moonflow_prepare_delivery(
  self : StudioService,
  project_id : String,
  input : Json,
  request : MoonflowAdapterRequest,
  binding : Json,
) -> Json {
  guard moonflow_json_member(input, "id") == Some(project_id.to_json()) else {
    fail("Mooncast delivery input is not the current production project")
  }
  let canonical = self.get_project(project_id)
  guard canonical.snapshot.master is Some(master) else {
    fail("Mooncast delivery requires a promoted canonical master")
  }
  let actor = moonflow_binding_string(binding, "operator_id")
  guard !actor.is_blank() && moonflow_binding_bool(binding, "human_confirmed") else {
    fail("Mooncast delivery preparation requires a named human confirmation")
  }
  let destination = moonflow_binding_string(
    binding,
    "destination_id",
    default="client-review",
  )
  let manifest_digest = "sha256:" +
    sha256_text(input.stringify() + ":delivery-manifest")
  let rights_digest = "sha256:" +
    sha256_text(input.stringify() + ":rights-ledger")
  match
    self.moonflow_internal_post(
      "/api/v2/projects/" + project_id + "/governance/delivery-package",
      {
        "expected_project_revision": canonical.snapshot.revision,
        "expected_master_version": master.reference.version,
        "expected_master_digest": master.reference.digest,
        "expected_delivery_version": Json::null(),
        "expected_delivery_digest": Json::null(),
        "destination_ids": [destination],
        "manifest_digest": manifest_digest,
        "rights_ledger_digest": rights_digest,
        "human_confirmed": true,
        "actor": actor,
      },
    ) {
    Err(message) => fail(message)
    Ok(_) => ()
  }
  let after = self.get_project(project_id)
  guard after.snapshot.delivery_package is Some(delivery) else {
    fail("Mooncast delivery package was not materialized")
  }
  let promotion = self.latest_editor_promotion(project_id).unwrap()
  let editor_export = self.get_editor_job(project_id, promotion.job_id)
  {
    "contract": "mooncast.delivery-package.v2",
    "delivery_id": delivery.reference.id,
    "project_id": project_id,
    "master": {
      "contract": "mooncast.master-provenance.v2",
      "master_id": promotion.master_id,
      "project_id": project_id,
      "sha256": if promotion.digest.has_prefix("sha256:") {
        promotion.digest[7:].to_owned()
      } else {
        promotion.digest
      },
      "video_url": promotion.video_ref,
      "subtitle_url": promotion.subtitle_ref,
      "timeline": editor_export.render_plan.tracks,
      "media": {
        "output_digest": promotion.digest,
        "size_bytes": promotion.size,
        "render_plan_digest": promotion.plan_digest,
      },
      "labels": { "visible_label": "AI GENERATED" },
      "qc": { "render_verified": true },
      "created_at": promotion.promoted_at,
    },
    "plan": {
      "delivery_version": delivery.reference.version,
      "delivery_digest": delivery.reference.digest,
      "destinations": delivery.destination_ids,
      "manifest_digest": delivery.manifest_digest,
      "rights_ledger_digest": delivery.rights_ledger_digest,
    },
    "gate_receipts": { "receipts": after.snapshot.gate_receipts },
    "publication": {
      "status": "not-authorized",
      "external_effect_authorized": false,
    },
    "created_at": request.created_at,
  }
}

///|
fn moonflow_result_or_fail(value : Result[Json, String]) -> Json raise {
  match value {
    Ok(output) => output
    Err(message) => fail(message)
  }
}

///|
async fn StudioService::moonflow_asset_generate(
  self : StudioService,
  project_id : String,
  input : Json,
  artifacts : Array[Json],
  request : MoonflowAdapterRequest,
  binding : Json,
) -> Json {
  guard moonflow_external_authority_granted(artifacts, "provider-execution") else {
    fail("Mooncast asset generation requires an explicit host provider grant")
  }
  guard moonflow_json_member(input, "plan") is Some(plan) else {
    fail("Mooncast asset generation requires a versioned asset plan")
  }
  let version : Int = match moonflow_json_member(plan, "version") {
    Some(value) => @json.from_json(value)
    None => fail("Mooncast asset plan version is missing")
  }
  let digest = moonflow_json_string(plan, "digest")
  let actor = moonflow_binding_string(binding, "operator_id")
  let actor_role = moonflow_binding_string(binding, "operator_role")
  guard !actor.is_blank() &&
    !actor_role.is_blank() &&
    moonflow_binding_bool(binding, "human_confirmed") else {
    fail("Mooncast asset execution requires a named plan approver")
  }
  ignore(
    moonflow_result_or_fail(
      self.moonflow_internal_post(
        "/api/v2/projects/" + project_id + "/asset-factory/plan-decisions",
        {
          "expected_plan_version": version,
          "expected_plan_digest": digest,
          "decision": "approve",
          "actor": actor,
          "actor_role": actor_role,
          "note": moonflow_binding_string(binding, "note"),
          "decided_at": request.created_at,
          "human_confirmed": true,
        },
      ),
    ),
  )
  let generated = moonflow_result_or_fail(
    self.moonflow_internal_post(
      "/api/v2/projects/" + project_id + "/asset-factory/run-pending",
      {
        "expected_plan_version": version,
        "expected_plan_digest": digest,
        "actor": actor,
        "human_confirmed": true,
        "network_authority": true,
      },
    ),
  )
  guard generated is Array(variants) else {
    fail("Mooncast asset generator returned no variant collection")
  }
  let wanted = moonflow_binding_string(binding, "resource_id")
  guard !wanted.is_blank() &&
    variants
    .iter()
    .find_first(value => {
      moonflow_json_member(value, "variant_id") == Some(wanted.to_json())
    })
    is Some(variant) else {
    fail("Mooncast asset generation requires an exact output variant binding")
  }
  variant
}

///|
async fn StudioService::moonflow_asset_review(
  self : StudioService,
  artifacts : Array[Json],
  request : MoonflowAdapterRequest,
  binding : Json,
) -> Json {
  let variant_id = moonflow_binding_string(binding, "variant_id")
  let asset_id = moonflow_binding_string(binding, "resource_id")
  let asset_version = moonflow_binding_int(binding, "resource_version")
  guard !variant_id.is_blank() && !asset_id.is_blank() && asset_version > 0 else {
    fail("Mooncast asset review requires exact variant and asset bindings")
  }
  let dimensions : Array[String] = []
  for finding in artifacts {
    guard moonflow_json_member(finding, "contract") ==
      Some("mooncast.asset-qc-finding.v1".to_json()) &&
      moonflow_json_member(finding, "variant_id") == Some(variant_id.to_json()) else {
      fail("Mooncast asset QC finding targets another variant")
    }
    let dimension = moonflow_json_string(finding, "dimension")
    ignore(
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" +
          moonflow_binding_string(binding, "project_id") +
          "/asset-factory/findings",
          {
            "variant_id": variant_id,
            "dimension": dimension,
            "status": moonflow_json_string(finding, "status"),
            "evidence_digest": moonflow_json_string(finding, "evidence_digest"),
            "reviewer": moonflow_json_string(finding, "reviewer"),
            "reviewer_role": moonflow_json_string(finding, "reviewer_role"),
            "reviewed_at": moonflow_json_string(finding, "reviewed_at"),
            "human_confirmed": moonflow_json_member(finding, "human_confirmed") ==
            Some(true.to_json()),
          },
        ),
      ),
    )
    if !dimensions.contains(dimension) {
      dimensions.push(dimension)
    }
  }
  guard dimensions.length() >= 5 else {
    fail("Mooncast asset approval requires all five independent QC dimensions")
  }
  moonflow_result_or_fail(
    self.moonflow_internal_post(
      "/api/v2/projects/" +
      moonflow_binding_string(binding, "project_id") +
      "/asset-factory/approvals",
      {
        "asset_id": asset_id,
        "asset_version": asset_version,
        "variant_id": variant_id,
        "actor": moonflow_binding_string(binding, "operator_id"),
        "actor_role": moonflow_binding_string(binding, "operator_role"),
        "approved_at": request.created_at,
        "human_confirmed": moonflow_binding_bool(binding, "human_confirmed"),
      },
    ),
  )
}

///|
async fn StudioService::moonflow_delivery_acceptance(
  self : StudioService,
  project_id : String,
  build_id : String,
  input : Json,
  request : MoonflowAdapterRequest,
) -> Json {
  let response = moonflow_result_or_fail(
    self.moonflow_internal_post(
      "/api/v2/projects/" +
      project_id +
      "/delivery-builds/" +
      build_id +
      "/acceptance",
      input,
    ),
  )
  guard moonflow_json_member(response, "acceptance") is Some(acceptance) &&
    self.get_project(project_id).snapshot.master is Some(master) &&
    self.get_project(project_id).snapshot.delivery_package is Some(delivery) else {
    fail("Mooncast accepted build did not retain master and delivery lineage")
  }
  let digest = "sha256:" +
    sha256_text(
      acceptance.stringify() +
      ":" +
      delivery.reference.digest +
      ":" +
      master.reference.digest,
    )
  {
    "contract": "mooncast.delivery-milestone-acceptance.v1",
    "receipt_id": "delivery-build-" + build_id,
    "milestone": "immutable-build",
    "delivery_version": delivery.reference.version,
    "delivery_digest": delivery.reference.digest,
    "master_digest": master.reference.digest,
    "decision": moonflow_json_string(acceptance, "decision"),
    "actor": moonflow_json_string(acceptance, "actor"),
    "actor_role": moonflow_json_string(acceptance, "actor_role"),
    "decided_at": match moonflow_json_member(acceptance, "decided_at") {
      Some(String(value)) => value
      _ => request.created_at
    },
    "digest": digest,
    "delivery_build_id": build_id,
    "delivery_build_digest": moonflow_json_string(acceptance, "build_digest"),
    "delivery_build_record_digest": moonflow_json_string(
      acceptance, "build_record_digest",
    ),
    "note": match moonflow_json_member(acceptance, "note") {
      Some(String(value)) => value
      _ => ""
    },
  }
}

///|
async fn StudioService::moonflow_create_client_portal(
  self : StudioService,
  project_id : String,
  input : Json,
) -> Json {
  let projection = moonflow_result_or_fail(
    self.moonflow_internal_post(
      "/api/v2/projects/" + project_id + "/client-portals",
      input,
    ),
  )
  guard moonflow_json_member(projection, "portal") is Some(portal) &&
    moonflow_json_member(projection, "client_url") is Some(String(client_url)) else {
    fail("Mooncast client portal did not return its one-time client route")
  }
  let parts = client_url.split("/").to_array()
  guard !parts.is_empty() && !parts[parts.length() - 1].is_blank() else {
    fail("Mooncast client portal route has no token")
  }
  let portal_id = moonflow_json_string(portal, "portal_id")
  let secret_store = @host_store.AtomicStore::new(
    self.root + "/moonflow-adapter/secrets",
  )
  ignore(
    secret_store.put_json("client-token-" + sha256_text(portal_id) + ".json", {
      "portal_id": portal_id,
      "token": parts[parts.length() - 1].to_owned(),
    }),
  )
  portal
}

///|
async fn StudioService::moonflow_client_decide(
  self : StudioService,
  portal_id : String,
  input : Json,
) -> Json {
  let secret_store = @host_store.AtomicStore::new(
    self.root + "/moonflow-adapter/secrets",
  )
  guard secret_store.get_json(
      "client-token-" + sha256_text(portal_id) + ".json",
    )
    is Some(secret) &&
    moonflow_json_member(secret, "portal_id") == Some(portal_id.to_json()) &&
    moonflow_json_member(secret, "token") is Some(String(token)) else {
    fail(
      "Mooncast client decision requires the portal's retained one-time token",
    )
  }
  moonflow_result_or_fail(
    self.moonflow_internal_post("/api/client/" + token + "/decision", input),
  )
}

///|
async fn StudioService::moonflow_execute_operation(
  self : StudioService,
  spec : MoonflowOperationSpec,
  input : Json,
  artifacts : Array[Json],
  request : MoonflowAdapterRequest,
  binding : Json,
) -> Json {
  let project_id = if spec.operation_id == "control-tower.observe" {
    moonflow_binding_string(binding, "project_id")
  } else {
    moonflow_project_id(binding, input)
  }
  let resource_id = moonflow_binding_string(binding, "resource_id")
  match spec.operation_id {
    "project.create" => {
      let project = moonflow_json_string(input, "campaign_id")
      guard project_id == project else {
        fail("Mooncast project creation route conflicts with the brief")
      }
      moonflow_result_or_fail(
        self.moonflow_internal_post("/api/v2/projects", {
          "project_id": project,
          "title": project,
          "objective": moonflow_json_string(input, "objective"),
          "audience": moonflow_json_string(input, "audience"),
          "channels": moonflow_json_member(input, "channels").unwrap(),
          "target_duration_seconds": 180,
          "maximum_budget_cny": 10000.0,
          "rights_owner": "pending-contract-rights",
          "rights_confirmed": false,
        }),
      )
    }
    "creative.artifact.revise" | "creative.artifact.decide" => {
      guard !resource_id.is_blank() else {
        fail("Mooncast creative operation requires its artifact kind")
      }
      let suffix = if spec.operation_id == "creative.artifact.revise" {
        "revise"
      } else {
        "decision"
      }
      ignore(
        moonflow_result_or_fail(
          self.moonflow_internal_post(
            "/api/v2/projects/" +
            project_id +
            "/creative/" +
            resource_id +
            "/" +
            suffix,
            input,
          ),
        ),
      )
      let workspace = moonflow_result_or_fail(
        self.moonflow_internal_get(
          "/api/v2/projects/" + project_id + "/creative/" + resource_id,
        ),
      )
      moonflow_extract_creative_output(
        workspace,
        spec.operation_id == "creative.artifact.decide",
      )
    }
    "project.advance" => {
      let canonical = self.get_project(project_id)
      let gate = moonflow_json_string(input, "gate")
      let output = moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" + project_id + "/advance",
          {
            "expected_revision": canonical.snapshot.revision,
            "command_id": "gate-" + gate + "-" + request.attempt_id,
            "recorded_at": moonflow_json_string(input, "decided_at"),
            "evidence_digest": moonflow_json_string(input, "evidence_digest"),
            "gate": gate,
            "actor": moonflow_json_string(input, "actor"),
            "role": moonflow_binding_string(
              binding,
              "operator_role",
              default="creative-director",
            ),
          },
        ),
      )
      moonflow_json_member(output, "project").unwrap_or(output)
    }
    "asset-factory.plan.record" =>
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" + project_id + "/asset-factory/plans",
          { "plan": input },
        ),
      )
    "asset-factory.generate" =>
      self.moonflow_asset_generate(
        project_id, input, artifacts, request, binding,
      )
    "asset-factory.review" =>
      self.moonflow_asset_review(artifacts, request, binding)
    "asset-factory.bind-shots" => {
      let canonical = self.get_project(project_id)
      let output = moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" + project_id + "/asset-factory/bind-shots",
          {
            "project_revision": canonical.snapshot.revision,
            "human_confirmed": moonflow_binding_bool(binding, "human_confirmed"),
            "bound_at": request.created_at,
          },
        ),
      )
      guard output is Array(bindings) &&
        bindings
        .iter()
        .find_first(value => {
          moonflow_json_member(value, "shot_id") == Some(resource_id.to_json())
        })
        is Some(found) else {
        fail("Mooncast shot binding output is missing the requested shot")
      }
      found
    }
    "animatic.plan.record" =>
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" + project_id + "/animatic-workspace/plans",
          { "plan": input },
        ),
      )
    "animatic.render" => {
      guard moonflow_external_authority_granted(artifacts, "sandbox-process") &&
        moonflow_json_member(input, "reference") is Some(reference) else {
        fail("Mooncast animatic render requires an explicit process grant")
      }
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" + project_id + "/animatic-workspace/render",
          {
            "expected_plan_version": moonflow_json_member(reference, "version").unwrap(),
            "expected_plan_digest": moonflow_json_string(reference, "digest"),
            "actor": moonflow_binding_string(binding, "operator_id"),
            "rendered_at": request.created_at,
            "human_confirmed": moonflow_binding_bool(binding, "human_confirmed"),
            "process_authority": true,
          },
        ),
      )
    }
    "animatic.approve" => {
      guard moonflow_json_member(input, "reference") is Some(reference) else {
        fail("Mooncast rendered animatic has no immutable reference")
      }
      let output = moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" + project_id + "/animatic-workspace/approve",
          {
            "expected_render_version": moonflow_json_member(
              reference, "version",
            ).unwrap(),
            "expected_render_digest": moonflow_json_string(reference, "digest"),
            "actor": moonflow_binding_string(binding, "operator_id"),
            "actor_role": moonflow_binding_string(binding, "operator_role"),
            "note": moonflow_binding_string(binding, "note"),
            "approved_at": request.created_at,
            "human_confirmed": moonflow_binding_bool(binding, "human_confirmed"),
          },
        ),
      )
      moonflow_json_member(output, "approval").unwrap_or(output)
    }
    "model-routing.plan.revise" => {
      guard moonflow_json_member(input, "content") is Some(content) else {
        fail("Mooncast model routing plan has no executable content")
      }
      ignore(
        moonflow_result_or_fail(
          self.moonflow_internal_post(
            "/api/v2/projects/" + project_id + "/governance/model-routing",
            content,
          ),
        ),
      )
      self.get_project(project_id).snapshot.routing_plan.unwrap().to_json()
    }
    "model-routing.plan.decide" => {
      let canonical = self.get_project(project_id)
      guard canonical.snapshot.routing_plan is Some(plan) else {
        fail("Mooncast routing decision requires the current plan")
      }
      ignore(
        moonflow_result_or_fail(
          self.moonflow_internal_post(
            "/api/v2/projects/" +
            project_id +
            "/governance/model-routing/decisions",
            {
              "expected_project_revision": canonical.snapshot.revision,
              "expected_plan_version": plan.reference.version,
              "expected_plan_digest": plan.reference.digest,
              "human_confirmed": moonflow_binding_bool(
                binding, "human_confirmed",
              ),
              "actor": moonflow_binding_string(binding, "operator_id"),
              "actor_role": moonflow_binding_string(binding, "operator_role"),
              "decision": moonflow_binding_string(binding, "decision"),
              "note": moonflow_binding_string(binding, "note"),
            },
          ),
        ),
      )
      let decisions = self.get_project(project_id).snapshot.routing_decisions
      decisions[decisions.length() - 1].to_json()
    }
    "routed-execution.create" =>
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" + project_id + "/routed-executions",
          input,
        ),
      )
    "production-coordinator.run-pending" => {
      guard moonflow_external_authority_granted(artifacts, "provider-execution") &&
        !resource_id.is_blank() else {
        fail("Mooncast shot execution requires provider grant and execution id")
      }
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" +
          project_id +
          "/production-coordinator/routed-executions/" +
          resource_id +
          "/run-pending",
          input,
        ),
      )
    }
    "production-coordinator.confirm-qc" =>
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" +
          project_id +
          "/production-coordinator/qc-batches",
          input,
        ),
      )
    "editor.production.import" => self.moonflow_editor_import(project_id, input)
    "editor.command.apply" => {
      let command : @editor_domain.EditCommand = @json.from_json(input)
      self.dispatch_editor_command(
        project_id,
        command,
        "sha256:" + sha256_text(input.stringify()),
      ).snapshot.to_json()
    }
    "editor.preview.plan" => self.moonflow_editor_plan(project_id, input)
    "editor.preview.start" =>
      self.moonflow_editor_preview(project_id, input, request, binding)
    "editor.export.create" =>
      self.moonflow_editor_export_create(project_id, input, request, binding)
    "editor.production.export" =>
      self.moonflow_editor_export_envelope(project_id, input)
    "editor.master.promote" =>
      self.moonflow_promote_master(project_id, input, request, binding)
    "production.review" =>
      self.moonflow_review_master(project_id, input, request, binding)
    "delivery.prepare" =>
      self.moonflow_prepare_delivery(project_id, input, request, binding)
    "delivery-build.plan" =>
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" + project_id + "/delivery-builds",
          input,
        ),
      )
    "delivery-build.execute" => {
      guard !resource_id.is_blank() else {
        fail("Mooncast delivery build execution requires build id")
      }
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/v2/projects/" +
          project_id +
          "/delivery-builds/" +
          resource_id +
          "/build",
          input,
        ),
      )
    }
    "delivery-build.accept" => {
      guard !resource_id.is_blank() else {
        fail("Mooncast delivery build acceptance requires build id")
      }
      self.moonflow_delivery_acceptance(project_id, resource_id, input, request)
    }
    "client-portal.create" =>
      self.moonflow_create_client_portal(project_id, input)
    "client-portal.decide" => {
      guard !resource_id.is_blank() else {
        fail("Mooncast client decision requires portal id")
      }
      self.moonflow_client_decide(resource_id, input)
    }
    "handoff.final-deliverable.evidence" => {
      ignore(
        moonflow_result_or_fail(
          self.moonflow_internal_post("/api/handoffs/final-deliverables", input),
        ),
      )
      input
    }
    "control-tower.observe" => {
      let date = match moonflow_json_member(input, "as_of_date") {
        Some(String(value)) => value
        _ => ""
      }
      if date.is_blank() {
        self.production_control_tower().to_json()
      } else {
        self.production_control_tower(as_of_date=date).to_json()
      }
    }
    "control-tower.actuals.record" =>
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/control-tower/projects/" + project_id + "/actuals",
          input,
        ),
      )
    "control-tower.exception.assign" => {
      guard !resource_id.is_blank() else {
        fail("Mooncast control-tower assignment requires exception id")
      }
      moonflow_result_or_fail(
        self.moonflow_internal_post(
          "/api/control-tower/exceptions/" + resource_id + "/assignment",
          input,
        ),
      )
    }
    _ => fail("Mooncast MoonFlow operation has no pack-local handler")
  }
}

///|
fn moonflow_attempt_key(idempotency_key : String) -> String {
  "attempt-" + sha256_text(idempotency_key) + ".json"
}

///|
fn moonflow_attempt_ref(request : MoonflowAdapterRequest) -> String {
  "moonflow-adapter/state/" + moonflow_attempt_key(request.idempotency_key)
}

///|
fn moonflow_output_ref(request : MoonflowAdapterRequest) -> String {
  "moonflow-adapter/outputs/output-" +
  sha256_text(request.idempotency_key) +
  ".json"
}

///|
fn moonflow_result_ref(request : MoonflowAdapterRequest) -> String {
  "moonflow-adapter/results/result-" +
  sha256_text(request.idempotency_key) +
  ".json"
}

///|
fn moonflow_request_fingerprint(envelope : MoonflowInvokeEnvelope) -> String {
  "sha256:" + sha256_text(envelope.to_json().stringify())
}

///|
fn moonflow_adapter_result(
  request : MoonflowAdapterRequest,
  status : String,
  output_digest : String,
  output_artifacts : Array[String],
  error_kind : String,
  external_job_id? : String = "",
) -> Json {
  {
    "result_id": "mooncast-result-" + request.attempt_id,
    "request_id": request.request_id,
    "attempt_id": request.attempt_id,
    "idempotency_key": request.idempotency_key,
    "product_id": "mooncast",
    "external_job_id": external_job_id,
    "status": status,
    "output_digest": output_digest,
    "output_artifacts": output_artifacts,
    "error_kind": error_kind,
    "compensable": false,
    "recorded_at": request.created_at,
  }
}

///|
fn moonflow_validate_attempt_binding(
  attempt : MoonflowAttemptRecord,
  envelope : MoonflowInvokeEnvelope,
) -> Unit raise {
  let request = envelope.request
  guard attempt.request_id == request.request_id &&
    attempt.attempt_id == request.attempt_id &&
    attempt.idempotency_key == request.idempotency_key &&
    attempt.operation_ref == request.operation &&
    attempt.input_digest == request.input_digest &&
    attempt.request_fingerprint == moonflow_request_fingerprint(envelope) else {
    fail("Mooncast MoonFlow idempotency key is bound to another request")
  }
}

///|
async fn StudioService::moonflow_record_exercise(
  self : StudioService,
  request : MoonflowAdapterRequest,
  output_ref : String,
  output_digest : String,
) -> Unit {
  let store = @host_store.AtomicStore::new(
    self.root + "/moonflow-adapter/exercises",
  )
  let exercise : MoonflowAdapterExercise = {
    contract_id: "mooncast.moonflow-adapter-exercise.v1",
    adapter_id: "mooncast-pack-local-v2",
    operation_ref: request.operation,
    attempt_id: request.attempt_id,
    output_ref,
    output_digest,
    result_ref: moonflow_result_ref(request),
    exercised_at: request.created_at,
  }
  ignore(
    store.put_json(
      "exercise-" + sha256_text(request.operation) + ".json",
      exercise.to_json(),
    ),
  )
}

///|
async fn StudioService::moonflow_finish_attempt(
  self : StudioService,
  envelope : MoonflowInvokeEnvelope,
  spec : MoonflowOperationSpec,
  input : Json,
  artifacts : Array[Json],
  prepared : MoonflowAttemptRecord,
) -> Json {
  let request = envelope.request
  let executed : Result[Json, String] = try
    self.moonflow_execute_operation(
      spec,
      input,
      artifacts,
      request,
      envelope.binding,
    )
  catch {
    error => Err("\{to_repr(error)}")
  } noraise {
    value => Ok(value)
  }
  let state_store = @host_store.AtomicStore::new(
    self.root + "/moonflow-adapter/state",
  )
  match executed {
    Err(message) => {
      let result = moonflow_adapter_result(
        request,
        "failed",
        "",
        [],
        "mooncast-operation-rejected:" + sha256_text(message)[:16].to_owned(),
      )
      ignore(
        moonflow_write_immutable_json(
          self.root,
          moonflow_result_ref(request),
          result,
        ),
      )
      ignore(
        state_store.put_json(
          moonflow_attempt_key(request.idempotency_key),
          {
            ..prepared,
            status: "failed",
            result: Some(result),
            updated_at: request.created_at,
          }.to_json(),
        ),
      )
      result
    }
    Ok(output) => {
      let output_ref = moonflow_output_ref(request)
      let output_digest = moonflow_write_immutable_json(
        self.root,
        output_ref,
        output,
      )
      let result = moonflow_adapter_result(
        request,
        "succeeded",
        output_digest,
        [output_ref],
        "",
      )
      ignore(
        moonflow_write_immutable_json(
          self.root,
          moonflow_result_ref(request),
          result,
        ),
      )
      ignore(
        state_store.put_json(
          moonflow_attempt_key(request.idempotency_key),
          {
            ..prepared,
            status: "succeeded",
            output_ref,
            output_digest,
            result: Some(result),
            updated_at: request.created_at,
          }.to_json(),
        ),
      )
      self.moonflow_record_exercise(request, output_ref, output_digest)
      result
    }
  }
}

///|
async fn StudioService::moonflow_load_inputs(
  self : StudioService,
  request : MoonflowAdapterRequest,
) -> Array[Json] {
  let values : Array[Json] = []
  for reference in request.input_artifacts {
    let (_, value) = moonflow_read_artifact(self.root, reference)
    values.push(value)
  }
  values
}

///|
async fn StudioService::moonflow_invoke(
  self : StudioService,
  envelope : MoonflowInvokeEnvelope,
) -> Json {
  let request = envelope.request
  guard moonflow_find_operation(request.operation) is Some(spec) else {
    fail("Mooncast adapter operation is not in the selected systematic graph")
  }
  moonflow_validate_request(request, spec)
  guard moonflow_declared_input_digest(self.root, request.input_artifacts) ==
    request.input_digest else {
    fail("Mooncast adapter input digest does not match observed artifacts")
  }
  let inputs = self.moonflow_load_inputs(request)
  guard inputs.get(0) is Some(input) else {
    fail("Mooncast adapter operation input is missing")
  }
  let state_store = @host_store.AtomicStore::new(
    self.root + "/moonflow-adapter/state",
  )
  match state_store.get_json(moonflow_attempt_key(request.idempotency_key)) {
    Some(value) => {
      let attempt : MoonflowAttemptRecord = @json.from_json(value)
      moonflow_validate_attempt_binding(attempt, envelope)
      match attempt.result {
        Some(result) => result
        None if spec.idempotent =>
          self.moonflow_finish_attempt(envelope, spec, input, inputs, attempt)
        None =>
          moonflow_adapter_result(
            request,
            "running",
            "",
            [],
            "",
            external_job_id="mooncast-" + request.attempt_id,
          )
      }
    }
    None => {
      let prepared : MoonflowAttemptRecord = {
        contract_id: "mooncast.moonflow-adapter-attempt.v1",
        adapter_id: "mooncast-pack-local-v2",
        request_id: request.request_id,
        attempt_id: request.attempt_id,
        idempotency_key: request.idempotency_key,
        operation_ref: request.operation,
        request_fingerprint: moonflow_request_fingerprint(envelope),
        input_digest: request.input_digest,
        status: "prepared",
        output_ref: "",
        output_digest: "",
        result: None,
        started_at: request.created_at,
        updated_at: request.created_at,
      }
      ignore(
        state_store.put_json(
          moonflow_attempt_key(request.idempotency_key),
          prepared.to_json(),
        ),
      )
      self.moonflow_finish_attempt(envelope, spec, input, inputs, prepared)
    }
  }
}

///|
async fn StudioService::moonflow_reconcile(
  self : StudioService,
  envelope : MoonflowInvokeEnvelope,
) -> Json {
  let request = envelope.request
  guard moonflow_find_operation(request.operation) is Some(spec) else {
    fail("Mooncast reconcile operation is outside the selected graph")
  }
  moonflow_validate_request(request, spec)
  guard moonflow_declared_input_digest(self.root, request.input_artifacts) ==
    request.input_digest else {
    fail("Mooncast reconcile input digest changed")
  }
  let state_store = @host_store.AtomicStore::new(
    self.root + "/moonflow-adapter/state",
  )
  guard state_store.get_json(moonflow_attempt_key(request.idempotency_key))
    is Some(value) else {
    fail("Mooncast reconcile has no durable prepared attempt")
  }
  let attempt : MoonflowAttemptRecord = @json.from_json(value)
  moonflow_validate_attempt_binding(attempt, envelope)
  let result = match attempt.result {
    Some(result) => result
    None if spec.idempotent => {
      let inputs = self.moonflow_load_inputs(request)
      guard inputs.get(0) is Some(input) else {
        fail("Mooncast reconcile input is missing")
      }
      self.moonflow_finish_attempt(envelope, spec, input, inputs, attempt)
    }
    None =>
      moonflow_adapter_result(
        request,
        "running",
        "",
        [],
        "",
        external_job_id="mooncast-" + request.attempt_id,
      )
  }
  let status = match moonflow_json_member(result, "status") {
    Some(String(value)) => value
    _ => "running"
  }
  let decision = match status {
    "succeeded" => "import-success"
    "failed" => "import-failure"
    _ => "investigate-unknown"
  }
  let receipt : Json = {
    "contract_id": "mooncast.moonflow-adapter-reconcile.v1",
    "adapter_id": "mooncast-pack-local-v2",
    "request_id": request.request_id,
    "attempt_id": request.attempt_id,
    "decision": decision,
    "retry_allowed": status == "failed" && spec.idempotent,
    "evidence_refs": [
      moonflow_attempt_ref(request),
      moonflow_result_ref(request),
    ],
    "result": result,
    "message": if decision == "investigate-unknown" {
      "A non-idempotent effect may have started; Mooncast will not blindly retry it."
    } else {
      "Durable Mooncast adapter state reconciled the exact request."
    },
    "recorded_at": request.created_at,
  }
  let reconcile_ref = "moonflow-adapter/reconcile/reconcile-" +
    sha256_text(request.idempotency_key) +
    ".json"
  ignore(moonflow_write_immutable_json(self.root, reconcile_ref, receipt))
  receipt
}

///|
fn moonflow_adapter_declaration() -> Json {
  let operations : Array[Json] = []
  for spec in moonflow_operation_specs() {
    operations.push({
      "operation_id": spec.operation_id,
      "claim_ceiling": spec.claim_ceiling,
      "supports_cancel": false,
      "supports_reconcile": true,
    })
  }
  {
    "contract_id": "moonflow.adapter-declaration.v1",
    "adapter_id": "mooncast-pack-local-v2",
    "product_id": "mooncast",
    "pack_id": "mooncast",
    "pack_version": "0.2.0",
    "protocol": "moonflow.adapter.v2",
    "operations": operations,
  }
}

///|
fn moonflow_adapter_pack_projection() -> Json {
  let manifest = @mooncast_pack.manifest()
  let selected = moonflow_operation_specs().map(spec => spec.operation_id)
  let tools = manifest.tools.filter(tool => selected.contains(tool.id))
  let schema_ids : Array[String] = ["host-authority-grant"]
  for tool in tools {
    if !schema_ids.contains(tool.input_schema_id) {
      schema_ids.push(tool.input_schema_id)
    }
    if !schema_ids.contains(tool.output_schema_id) {
      schema_ids.push(tool.output_schema_id)
    }
  }
  {
    "id": manifest.id,
    "product_id": manifest.product_id,
    "version": manifest.version,
    "schemas": manifest.schemas.filter(schema => schema_ids.contains(schema.id)),
    "tools": tools,
  }
}

///|
async fn StudioService::moonflow_adapter_exercises(
  self : StudioService,
) -> Array[MoonflowAdapterExercise] {
  let store = @host_store.AtomicStore::new(
    self.root + "/moonflow-adapter/exercises",
  )
  let values : Array[MoonflowAdapterExercise] = []
  for key in store.list_keys(prefix="exercise-", suffix=".json") {
    match store.get_json(key) {
      Some(value) => values.push(@json.from_json(value))
      None => ()
    }
  }
  values
}

///|
async fn StudioService::moonflow_adapter_health_evidence(
  self : StudioService,
) -> Json {
  let exercises = self.moonflow_adapter_exercises()
  let handlers : Array[Json] = []
  for exercise in exercises {
    handlers.push({
      "operation_ref": exercise.operation_ref,
      "invoke": "POST /api/moonflow/adapter/v2/invoke",
      "reconcile": "POST /api/moonflow/adapter/v2/reconcile",
      "exercise_receipt_ref": exercise.result_ref,
      "exercise_output_digest": exercise.output_digest,
    })
  }
  {
    "contract": "mooncast.moonflow-adapter-health-evidence.v1",
    "adapter_id": "mooncast-pack-local-v2",
    "protocol": "moonflow.adapter.v2",
    "pack_id": "mooncast",
    "pack_version": "0.2.0",
    "handlers": handlers,
    "external_effect_authorized": false,
    "publication_authority": false,
  }
}

///|
async fn StudioService::moonflow_adapter_health(self : StudioService) -> Json {
  let seconds = @runtime.wall_clock_ms() / 1000L
  let checked_at = utc_timestamp_from_seconds(seconds)
  let exercises = self.moonflow_adapter_exercises()
  let refs = exercises.map(value => value.operation_ref)
  let evidence = self.moonflow_adapter_health_evidence()
  let evidence_digest = "sha256:" + sha256_text(evidence.stringify())
  let key = "mooncast-pack-local-v2-" + evidence_digest[7:].to_owned() + ".json"
  let store = @host_store.AtomicStore::new(self.root + "/health")
  let stored = store.put_json(key, evidence)
  guard "sha256:" + stored.sha256 == evidence_digest else {
    fail("Mooncast adapter health evidence digest mismatch")
  }
  let health : Json = {
    "contract_id": "moonflow.adapter-health.v1",
    "adapter_id": "mooncast-pack-local-v2",
    "product_id": "mooncast",
    "pack_id": "mooncast",
    "pack_version": "0.2.0",
    "protocol": "moonflow.adapter.v2",
    "status": if refs.is_empty() {
      "degraded"
    } else {
      "healthy"
    },
    "checked_at": checked_at,
    "valid_until": utc_timestamp_from_seconds(seconds + 300L),
    "operation_refs": refs,
    "evidence_ref": "health/" + key,
    "evidence_digest": evidence_digest,
  }
  ignore(store.put_json("mooncast-pack-local-v2-attestation.json", health))
  health
}

///|
async fn StudioService::dispatch_moonflow_adapter_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (Get, ["api", "moonflow", "adapter", "v2", "declaration"]) =>
      Some(json_value_response(200, moonflow_adapter_declaration()))
    (Get, ["api", "moonflow", "adapter", "v2", "pack-projection"]) =>
      Some(json_value_response(200, moonflow_adapter_pack_projection()))
    (Get, ["api", "moonflow", "adapter", "v2", "health"]) =>
      Some(json_value_response(200, self.moonflow_adapter_health()))
    (Get, ["api", "moonflow", "adapter", "v2", "health", "evidence"]) =>
      Some(json_value_response(200, self.moonflow_adapter_health_evidence()))
    (Post, ["api", "moonflow", "adapter", "v2", "invoke"]) => {
      let envelope : MoonflowInvokeEnvelope = decode_body(request)
      Some(json_value_response(200, self.moonflow_invoke(envelope)))
    }
    (Post, ["api", "moonflow", "adapter", "v2", "reconcile"]) => {
      let envelope : MoonflowInvokeEnvelope = decode_body(request)
      Some(json_value_response(200, self.moonflow_reconcile(envelope)))
    }
    _ => None
  }
}

///|
pub fn StudioService::register_moonflow_adapter_routes(
  self : StudioService,
) -> Unit {
  self.register_route_extension(
    RouteExtension::new("/api/moonflow/adapter/v2", async fn(request) {
      self.dispatch_moonflow_adapter_http(request)
    }),
  )
}
