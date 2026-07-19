/// Mooncast-local production coordination. These operations compose existing
/// provider and governance services for callers such as MoonFlow; they do not
/// own a general agent runtime, grant publication/payment authority, or bypass
/// a named human confirmation.

///|
struct ProductionRunPendingInput {
  expected_project_revision : Int
  expected_execution_revision : Int
  expected_execution_digest : String
  actor_id : String
  human_confirmed : Bool
} derive(FromJson)

///|
struct ProductionShotOutputBinding {
  shot_id : String
  output_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct ProductionBatchQcInput {
  expected_project_revision : Int
  expected_routing_plan_version : Int
  expected_routing_plan_digest : String
  shot_outputs : Array[ProductionShotOutputBinding]
  evidence_digest : String
  note : String
  actor : String
  actor_role : String
  human_confirmed : Bool
} derive(FromJson)

///|
struct ProductionShotRunReceipt {
  shot_id : String
  job_id : String
  action : String
  output_digest : String
  project_revision : Int
  execution_revision : Int
  execution_digest : String
} derive(ToJson)

///|
struct ProductionRunPendingProjection {
  contract : String
  project : Json
  execution : Json
  receipts : Array[ProductionShotRunReceipt]
  executed_shots : Int
  already_complete_shots : Int
  publication_authority : Bool
  payment_effect_performed : Bool
} derive(ToJson)

///|
struct ProductionQcReceipt {
  shot_id : String
  output_digest : String
  dimension : String
  finding_version : Int
  finding_digest : String
  decision_actor : String
  decision_role : String
} derive(ToJson)

///|
struct ProductionBatchQcProjection {
  contract : String
  batch_digest : String
  project : Json
  receipts : Array[ProductionQcReceipt]
  created_receipts : Int
  existing_receipts : Int
  g4_approved : Bool
  publication_authority : Bool
  payment_effect_performed : Bool
} derive(ToJson)

///|
fn exact_current_attempt(
  snapshot : @kernel.ProjectSnapshot,
  shot_id : String,
) -> @governance.GenerationAttempt? {
  latest_successful_attempt(snapshot, shot_id)
}

///|
fn current_qc_finding(
  snapshot : @kernel.ProjectSnapshot,
  shot_id : String,
  output_digest : String,
  dimension : @governance.QcDimension,
) -> @governance.QcFinding? {
  let matches = snapshot.qc_findings.filter(finding => {
    finding.shot_id == shot_id &&
    normalized_digest(finding.attempt_digest) ==
    normalized_digest(output_digest) &&
    finding.dimension == dimension
  })
  if matches.is_empty() {
    None
  } else {
    Some(matches[matches.length() - 1])
  }
}

///|
fn approved_qc_decision(
  snapshot : @kernel.ProjectSnapshot,
  finding : @governance.QcFinding,
) -> @governance.QcDecision? {
  snapshot.qc_decisions
  .iter()
  .find_first(decision => {
    decision.finding == finding.finding &&
    decision.decision == "approved" &&
    decision.actor.trim() != "" &&
    decision.role.trim() != ""
  })
}

///|
fn validate_complete_execution_binding(
  snapshot : @kernel.ProjectSnapshot,
  execution : @execution.RoutedExecution,
) -> Unit raise {
  let shots = @project.flattened_shots(snapshot.graph)
  guard execution.shots.length() == shots.length() else {
    raise Conflict(
      code="workflow_execution_partial_binding",
      message="routed execution must bind the complete current shot set",
    )
  }
  for shot in shots {
    guard execution.shots
      .filter(binding => binding.shot_id == shot.shot_id)
      .length() ==
      1 else {
      raise Conflict(
        code="workflow_execution_partial_binding",
        message="each current shot must have exactly one routed job",
      )
    }
  }
  for binding in execution.shots {
    guard shots.any(shot => shot.shot_id == binding.shot_id) else {
      raise Conflict(
        code="workflow_execution_stale_binding",
        message="routed execution contains a shot outside the current graph",
      )
    }
  }
}

///|
async fn StudioService::run_pending_shots_feature(
  self : StudioService,
  project_id : String,
  execution_id : String,
  input : ProductionRunPendingInput,
) -> ProductionRunPendingProjection {
  let initial = self.get_project(project_id)
  guard input.human_confirmed && input.actor_id.trim() != "" else {
    raise Conflict(
      code="workflow_execution_confirmation_required",
      message="a named human must explicitly confirm the routed batch",
    )
  }
  guard initial.snapshot.revision == input.expected_project_revision &&
    gate_recorded(initial.snapshot, "G3") &&
    initial.snapshot.routing_plan is Some(plan) else {
    raise Conflict(
      code="workflow_project_stale",
      message="batch execution must bind the exact current G3 project",
    )
  }
  guard self.execution_application.load_routed_execution(execution_id)
    is Some(routed) &&
    routed.execution.project_id == project_id &&
    routed.execution.revision == input.expected_execution_revision &&
    normalized_digest(routed.execution.record_digest) ==
    normalized_digest(input.expected_execution_digest) &&
    routed.execution.routing_plan == plan.reference &&
    routed.execution.actor_id == input.actor_id &&
    !routed.execution.publication_authority else {
    raise Conflict(
      code="workflow_execution_stale",
      message="routed execution revision, digest, actor, or routing plan changed",
    )
  }
  validate_complete_execution_binding(initial.snapshot, routed.execution)

  // Preflight every pending provider job before the first external action. This
  // rejects structurally partial batches without executing an early subset.
  for binding in routed.execution.shots {
    let current = exact_current_attempt(initial.snapshot, binding.shot_id)
    if current is None {
      guard self.execution_application.load_job(binding.job_id) is Some(job) &&
        @project.flattened_shots(initial.snapshot.graph)
        .iter()
        .find_first(shot => shot.shot_id == binding.shot_id)
        is Some(shot) &&
        plan.routes
        .iter()
        .find_first(route => {
          route.route_id == binding.route_id &&
          route.shot_ids.contains(binding.shot_id)
        })
        is Some(route) else {
        raise Conflict(
          code="workflow_provider_job_not_runnable",
          message="every pending shot requires one exact routed provider job",
        )
      }
      let expected_source_assets = initial.snapshot.graph.assets.filter(asset => {
        shot.source_asset_ids.contains(asset.asset_id)
      })
      let request_id = routed.execution.execution_id + ":" + binding.shot_id
      let body = job.http_plan.body
      let body_digest = "sha256:" + sha256_text(body.stringify())
      guard job.job.job_id == binding.job_id &&
        job.job.plan.request_id == request_id &&
        job.http_plan.request_id == request_id &&
        job.job.plan.plan_digest == job.job.plan_digest &&
        job.job.plan_digest == job.http_plan.plan_digest &&
        normalized_digest(job.job.plan.input_digest) ==
        normalized_digest(body_digest) &&
        job.job.plan.provider == route.provider &&
        job.http_plan.provider == route.provider &&
        job.job.plan.model == route.model &&
        job.http_plan.model == route.model &&
        job.job.plan.cost_ceiling_cny == binding.cost_ceiling_cny &&
        job.http_plan.cost_ceiling_cny == binding.cost_ceiling_cny &&
        route.cost_ceiling_cny == binding.cost_ceiling_cny &&
        job.job.max_attempts == route.retry_limit &&
        job.job.authority.actor_id == routed.execution.actor_id &&
        job.job.authority.authority_receipt_digest.trim() != "" &&
        job.job.authority.network_authority &&
        !job.job.authority.publication_authority &&
        !job.job.publication_authority &&
        json_member(body, "project_id") == Some(project_id.to_json()) &&
        json_member(body, "project_revision") ==
        Some(routed.execution.project_revision_anchor.to_json()) &&
        json_member(body, "shot") == Some(shot.to_json()) &&
        json_member(body, "source_assets") ==
        Some(expected_source_assets.to_json()) &&
        json_member(body, "route") == Some(route.to_json()) &&
        json_member(body, "publication_authority") == Some(false.to_json()) &&
        (
          job.job.state == "authorized" ||
          job.job.state == "retryable_failure" ||
          job.job.state == "timed_out"
        ) &&
        job.job.attempt_count < job.job.max_attempts else {
        raise Conflict(
          code="workflow_provider_job_not_runnable",
          message="every pending shot requires one exact runnable routed provider job",
        )
      }
    }
  }

  let receipts : Array[ProductionShotRunReceipt] = []
  let mut execution = routed.execution
  let mut complete = 0
  for binding in routed.execution.shots {
    let before = self.get_project(project_id)
    match exact_current_attempt(before.snapshot, binding.shot_id) {
      Some(attempt) => {
        guard attempt.route_plan == plan.reference &&
          attempt.route_id == binding.route_id else {
          raise Conflict(
            code="workflow_shot_output_stale",
            message="existing shot output does not bind the active routed plan",
          )
        }
        complete = complete + 1
      }
      None => {
        guard self.execution_application.load_routed_execution(execution_id)
          is Some(current_execution) &&
          current_execution.execution.revision == execution.revision &&
          normalized_digest(current_execution.execution.record_digest) ==
          normalized_digest(execution.record_digest) else {
          raise Conflict(
            code="workflow_execution_changed_during_run",
            message="routed execution changed during sequential processing",
          )
        }
        guard self.execution_application.load_job(binding.job_id) is Some(job) else {
          raise Conflict(
            code="workflow_provider_job_missing",
            message="provider job disappeared during sequential processing",
          )
        }
        let action = if job.job.state == "authorized" {
          "execute"
        } else {
          "resume"
        }
        let result = self.production_pipeline.routed_action_and_ingest(
          project_id,
          execution_id,
          binding.shot_id,
          action,
          execution.revision,
          input.actor_id,
        )
        guard result.provider_artifact_ingested &&
          !result.publication_effect_performed &&
          !result.external_effect_performed_by_pipeline &&
          result.project_result is Some(_) else {
          raise Conflict(
            code="workflow_provider_output_incomplete",
            message="provider action did not produce a canonical ingestible output",
          )
        }
        let adopted = self.adopt_pipeline_result(project_id, result)
        guard exact_current_attempt(adopted.snapshot, binding.shot_id)
          is Some(attempt) &&
          attempt.route_plan == plan.reference &&
          attempt.route_id == binding.route_id &&
          self.execution_application.load_job(binding.job_id)
          is Some(updated_job) &&
          updated_job.job.artifacts.length() > 0 &&
          normalized_digest(attempt.output_digest) ==
          normalized_digest(updated_job.job.artifacts[0].artifact_digest) else {
          raise Conflict(
            code="workflow_pipeline_adoption_conflict",
            message="canonical project does not exactly match the routed provider output",
          )
        }
        execution = result.execution
        receipts.push({
          shot_id: binding.shot_id,
          job_id: binding.job_id,
          action,
          output_digest: attempt.output_digest,
          project_revision: adopted.snapshot.revision,
          execution_revision: execution.revision,
          execution_digest: execution.record_digest,
        })
      }
    }
  }
  let project = self.get_project(project_id)
  {
    contract: "mooncast.production-coordinator-run-pending-shots.v1",
    project: self.studio_project_projection(project),
    execution: self.routed_execution_projection(execution),
    receipts,
    executed_shots: receipts.length(),
    already_complete_shots: complete,
    publication_authority: false,
    payment_effect_performed: false,
  }
}

///|
fn validate_exact_qc_batch(
  snapshot : @kernel.ProjectSnapshot,
  input : ProductionBatchQcInput,
) -> Array[ProductionShotOutputBinding] raise {
  let shots = @project.flattened_shots(snapshot.graph)
  guard input.shot_outputs.length() == shots.length() else {
    raise Conflict(
      code="workflow_qc_partial_binding",
      message="batch QC must bind the complete current shot set",
    )
  }
  let ordered : Array[ProductionShotOutputBinding] = []
  for shot in shots {
    let bindings = input.shot_outputs.filter(item => {
      item.shot_id == shot.shot_id
    })
    guard bindings.length() == 1 &&
      exact_current_attempt(snapshot, shot.shot_id) is Some(attempt) &&
      normalized_digest(bindings[0].output_digest) ==
      normalized_digest(attempt.output_digest) else {
      raise Conflict(
        code="workflow_qc_stale_binding",
        message="every shot must bind its exact current successful output",
      )
    }
    ordered.push({
      shot_id: shot.shot_id,
      output_digest: normalized_digest(attempt.output_digest),
    })
  }
  for binding in input.shot_outputs {
    guard shots.any(shot => shot.shot_id == binding.shot_id) else {
      raise Conflict(
        code="workflow_qc_stale_binding",
        message="batch QC contains a shot outside the current graph",
      )
    }
  }
  ordered
}

///|
async fn StudioService::confirm_batch_qc_feature(
  self : StudioService,
  project_id : String,
  input : ProductionBatchQcInput,
) -> ProductionBatchQcProjection {
  let initial = self.get_project(project_id)
  guard input.human_confirmed &&
    input.actor.trim() != "" &&
    input.actor_role.trim() != "" &&
    input.note.trim() != "" &&
    input.evidence_digest.trim() != "" &&
    !input.evidence_digest.contains("required") &&
    initial.snapshot.revision == input.expected_project_revision &&
    gate_recorded(initial.snapshot, "G3") &&
    initial.snapshot.routing_plan is Some(plan) &&
    exact_ref(
      plan.reference,
      input.expected_routing_plan_version,
      input.expected_routing_plan_digest,
    ) else {
    raise Conflict(
      code="workflow_qc_confirmation_conflict",
      message="named human QC must bind exact project, routing, evidence, and outputs",
    )
  }
  let bindings = validate_exact_qc_batch(initial.snapshot, input)
  let batch_digest = "sha256:" +
    sha256_text(
      project_id +
      ":" +
      initial.snapshot.revision.to_string() +
      ":" +
      plan.reference.digest +
      ":" +
      bindings.map(item => item.shot_id + "=" + item.output_digest).join("|") +
      ":" +
      input.evidence_digest +
      ":" +
      input.actor +
      ":" +
      input.actor_role +
      ":" +
      input.note,
    )

  // Reject known failing/rejected current evidence before appending any batch
  // receipt. Existing exact approved receipts are preserved idempotently.
  for binding in bindings {
    for dimension in @governance.qc_dimensions() {
      match
        current_qc_finding(
          initial.snapshot,
          binding.shot_id,
          binding.output_digest,
          dimension,
        ) {
        Some(finding) => {
          guard finding.status == "pass" &&
            !initial.snapshot.qc_decisions.any(decision => {
              decision.finding == finding.finding &&
              decision.decision != "approved"
            }) else {
            raise Conflict(
              code="workflow_qc_existing_conflict",
              message="batch QC cannot overwrite an existing failing or rejected finding",
            )
          }
        }
        None => ()
      }
    }
  }

  let receipts : Array[ProductionQcReceipt] = []
  let mut created = 0
  let mut existing = 0
  for binding in bindings {
    for dimension in @governance.qc_dimensions() {
      let before = self.get_project(project_id)
      guard exact_current_attempt(before.snapshot, binding.shot_id)
        is Some(attempt) &&
        normalized_digest(attempt.output_digest) == binding.output_digest else {
        raise Conflict(
          code="workflow_qc_changed_during_confirmation",
          message="shot output changed while batch QC was being recorded",
        )
      }
      let finding = match
        current_qc_finding(
          before.snapshot,
          binding.shot_id,
          binding.output_digest,
          dimension,
        ) {
        Some(value) => value
        None => {
          let evidence = "sha256:" +
            sha256_text(
              batch_digest +
              ":" +
              binding.shot_id +
              ":" +
              qc_dimension_name(dimension) +
              ":" +
              input.evidence_digest,
            )
          let response = self.record_qc_finding_feature(
            project_id,
            binding.shot_id,
            dimension,
            {
              expected_project_revision: before.snapshot.revision,
              expected_attempt_digest: binding.output_digest,
              expected_finding_version: None,
              expected_finding_digest: None,
              status: "pass",
              evidence_digest: evidence,
              note: input.note,
              reported_by: input.actor,
            },
          )
          guard current_qc_finding(
              response.project.snapshot,
              binding.shot_id,
              binding.output_digest,
              dimension,
            )
            is Some(value) else {
            raise Conflict(
              code="workflow_qc_finding_missing",
              message="canonical QC finding was not recorded",
            )
          }
          value
        }
      }
      let after_finding = self.get_project(project_id)
      let decision = match
        approved_qc_decision(after_finding.snapshot, finding) {
        Some(value) => {
          existing = existing + 1
          value
        }
        None => {
          let response = self.record_qc_decision_feature(
            project_id,
            binding.shot_id,
            dimension,
            {
              expected_project_revision: after_finding.snapshot.revision,
              expected_attempt_digest: binding.output_digest,
              expected_finding_version: finding.finding.version,
              expected_finding_digest: finding.finding.digest,
              human_confirmed: true,
              actor: input.actor,
              actor_role: input.actor_role,
              decision: "approve",
              note: input.note + " [batch " + batch_digest + "]",
            },
          )
          guard approved_qc_decision(response.project.snapshot, finding)
            is Some(value) else {
            raise Conflict(
              code="workflow_qc_decision_missing",
              message="canonical named QC decision was not recorded",
            )
          }
          created = created + 1
          value
        }
      }
      receipts.push({
        shot_id: binding.shot_id,
        output_digest: binding.output_digest,
        dimension: qc_dimension_name(dimension),
        finding_version: finding.finding.version,
        finding_digest: finding.finding.digest,
        decision_actor: decision.actor,
        decision_role: decision.role,
      })
    }
  }
  let project = self.get_project(project_id)
  let expected_receipts = bindings.length() *
    @governance.qc_dimensions().length()
  guard receipts.length() == expected_receipts &&
    @project.flattened_shots(project.snapshot.graph).all(shot => {
      @governance.shot_passes_qc(
        shot.shot_id,
        project.snapshot.generation_attempts,
        project.snapshot.qc_findings,
        project.snapshot.qc_decisions,
      )
    }) &&
    gate_recorded(project.snapshot, "G4") else {
    raise Conflict(
      code="workflow_qc_incomplete",
      message="G4 remains closed until every exact shot/dimension receipt exists",
    )
  }
  {
    contract: "mooncast.production-coordinator-batch-qc.v1",
    batch_digest,
    project: self.studio_project_projection(project),
    receipts,
    created_receipts: created,
    existing_receipts: existing,
    g4_approved: true,
    publication_authority: false,
    payment_effect_performed: false,
  }
}

///|
async fn StudioService::dispatch_production_coordinator_http(
  self : StudioService,
  request : @host_http.Request,
) -> @host_http.Response? {
  let segments = path_segments(request.path)
  match (request.request_method, segments) {
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "production-coordinator",
        "routed-executions",
        execution_id,
        "run-pending",
      ],
    ) => {
      let input : ProductionRunPendingInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.run_pending_shots_feature(project_id, execution_id, input),
        ),
      )
    }
    (
      Post,
      [
        "api",
        "v2",
        "projects",
        project_id,
        "production-coordinator",
        "qc-batches",
      ],
    ) => {
      let input : ProductionBatchQcInput = decode_body(request)
      Some(
        json_value_response(
          200,
          self.confirm_batch_qc_feature(project_id, input),
        ),
      )
    }
    _ => None
  }
}

///|
pub fn StudioService::register_production_coordinator_routes(
  self : StudioService,
) -> Unit {
  self.register_route_extension(
    RouteExtension::new("/api/v2/projects", async fn(request) {
      self.dispatch_production_coordinator_http(request)
    }),
  )
}
