///|
fn gate_position(value : String) -> Int {
  match value {
    "G0" => 0
    "G1" => 1
    "G2" => 2
    "G3" => 3
    "G4" => 4
    "G5" => 5
    "G6" => 6
    "G7" => 7
    _ => 8
  }
}

///|
fn invalidate(
  snapshot : ProjectSnapshot,
  from_gate : String?,
) -> ProjectSnapshot {
  match from_gate {
    None => snapshot
    Some(gate) => {
      let start = gate_position(gate)
      {
        ..snapshot,
        gate_receipts: snapshot.gate_receipts.filter(receipt => {
          gate_position(receipt.gate.to_string()) < start
        }),
      }
    }
  }
}

///|
/// Pure compatibility operation for evidence sources that live in an
/// application store (for example analytics). It removes only receipts at or
/// after the supplied gate and performs no IO.
pub fn invalidate_from_gate(
  snapshot : ProjectSnapshot,
  gate : String,
) -> ProjectSnapshot {
  invalidate(snapshot, Some(gate))
}

///|
/// Applies an already accepted event without IO or hidden authority.
pub fn apply_event(
  snapshot : ProjectSnapshot,
  event : ProjectEvent,
) -> ProjectSnapshot {
  let state = invalidate(snapshot, event.invalidates_from_gate)
  let next = match event.event_kind {
    "qualification-recorded" =>
      match event.qualification {
        Some(value) => { ..state, qualification: Some(value) }
        None => state
      }
    "creative-artifact-recorded" =>
      match event.creative_artifact {
        Some(value) => {
          let values = state.creative_artifacts.copy()
          values.push(value)
          { ..state, creative_artifacts: values }
        }
        None => state
      }
    "creative-decision-recorded" =>
      match event.creative_decision {
        Some(value) => {
          let values = state.creative_decisions.copy()
          values.push(value)
          { ..state, creative_decisions: values }
        }
        None => state
      }
    "routing-plan-recorded" =>
      match event.routing_plan {
        Some(value) => { ..state, routing_plan: Some(value) }
        None => state
      }
    "routing-decision-recorded" =>
      match event.routing_decision {
        Some(value) => {
          let values = state.routing_decisions.copy()
          values.push(value)
          { ..state, routing_decisions: values }
        }
        None => state
      }
    "generation-attempt-recorded" =>
      match event.generation_attempt {
        Some(value) => {
          let values = state.generation_attempts.copy()
          values.push(value)
          { ..state, generation_attempts: values }
        }
        None => state
      }
    "qc-finding-recorded" =>
      match event.qc_finding {
        Some(value) => {
          let values = state.qc_findings.copy()
          values.push(value)
          { ..state, qc_findings: values }
        }
        None => state
      }
    "qc-decision-recorded" =>
      match event.qc_decision {
        Some(value) => {
          let values = state.qc_decisions.copy()
          values.push(value)
          { ..state, qc_decisions: values }
        }
        None => state
      }
    "master-recorded" =>
      match event.master {
        Some(value) => { ..state, master: Some(value) }
        None => state
      }
    "master-decision-recorded" =>
      match event.master_decision {
        Some(value) => {
          let values = state.master_decisions.copy()
          values.push(value)
          { ..state, master_decisions: values }
        }
        None => state
      }
    "delivery-package-recorded" =>
      match event.delivery_package {
        Some(value) => { ..state, delivery_package: Some(value) }
        None => state
      }
    "delivery-acceptance-recorded" =>
      match event.delivery_acceptance {
        Some(value) => {
          let values = state.delivery_acceptances.copy()
          values.push(value)
          { ..state, delivery_acceptances: values }
        }
        None => state
      }
    "publication-authorization-recorded" =>
      match event.publication_authorization {
        Some(value) => {
          let values = state.publication_authorizations.copy()
          values.push(value)
          { ..state, publication_authorizations: values }
        }
        None => state
      }
    "publication-observation-recorded" =>
      match event.publication_observation {
        Some(value) => {
          let values = state.publication_observations.copy()
          values.push(value)
          { ..state, publication_observations: values }
        }
        None => state
      }
    "performance-review-recorded" =>
      match event.performance_review {
        Some(value) => {
          let values = state.performance_reviews.copy()
          values.push(value)
          { ..state, performance_reviews: values }
        }
        None => state
      }
    "gate-advanced" =>
      match event.gate_receipt {
        Some(value) => {
          let values = state.gate_receipts.copy()
          values.push(value)
          { ..state, gate_receipts: values }
        }
        None => state
      }
    _ => state
  }
  { ..next, revision: next.revision + 1 }
}

///|
pub fn replay(
  initial : ProjectSnapshot,
  events : Array[ProjectEvent],
) -> ProjectSnapshot {
  let mut snapshot = initial
  for event in events {
    snapshot = apply_event(snapshot, event)
  }
  snapshot
}

///|
fn event_from(
  command : ProjectCommand,
  kind : String,
  invalidates : String?,
) -> ProjectEvent {
  {
    schema_version: "mooncast.project-event.v2",
    event_id: command.command_id,
    event_kind: kind,
    recorded_at: command.recorded_at,
    source_digest: command.evidence_digest,
    invalidates_from_gate: invalidates,
    qualification: command.qualification,
    creative_artifact: command.creative_artifact,
    creative_decision: command.creative_decision,
    routing_plan: command.routing_plan,
    routing_decision: command.routing_decision,
    generation_attempt: command.generation_attempt,
    qc_finding: command.qc_finding,
    qc_decision: command.qc_decision,
    master: command.master,
    master_decision: command.master_decision,
    delivery_package: command.delivery_package,
    delivery_acceptance: command.delivery_acceptance,
    publication_authorization: command.publication_authorization,
    publication_observation: command.publication_observation,
    performance_review: command.performance_review,
    gate_receipt: None,
  }
}

///|
fn error_result(
  command : ProjectCommand,
  code : String,
  message : String,
) -> CommandResult {
  {
    schema_version: "mooncast.command-result.v2",
    kernel_version: production_kernel_version,
    command_id: command.command_id,
    ok: false,
    error: Some({ code, message }),
    snapshot: command.snapshot,
    emitted_events: [],
    readiness: None,
    projection: projection(command.snapshot),
    authority: @governance.no_external_authority(),
  }
}

///|
fn success_result(
  command : ProjectCommand,
  events : Array[ProjectEvent],
  readiness? : GateReadiness,
) -> CommandResult {
  let snapshot = replay(command.snapshot, events)
  {
    schema_version: "mooncast.command-result.v2",
    kernel_version: production_kernel_version,
    command_id: command.command_id,
    ok: true,
    error: None,
    snapshot,
    emitted_events: events,
    readiness,
    projection: projection(snapshot),
    authority: @governance.no_external_authority(),
  }
}

///|
fn payload_event(command : ProjectCommand) -> (ProjectEvent, Bool)? {
  match command.command {
    "record_qualification" =>
      Some(
        (
          event_from(command, "qualification-recorded", Some("G0")),
          match command.qualification {
            Some(value) => @governance.qualification_valid(value)
            None => false
          },
        ),
      )
    "record_creative_artifact" =>
      match command.creative_artifact {
        Some(value) =>
          Some(
            (
              event_from(
                command,
                "creative-artifact-recorded",
                Some(@creative.invalidation_for(value).from_gate),
              ),
              @creative.artifact_revision_valid(
                value,
                command.snapshot.creative_artifacts,
              ),
            ),
          )
        None =>
          Some((event_from(command, "creative-artifact-recorded", None), false))
      }
    "record_creative_decision" =>
      Some(
        (
          event_from(command, "creative-decision-recorded", Some("G0")),
          match command.creative_decision {
            Some(value) =>
              @creative.creative_decision_is_current(
                command.snapshot.creative_artifacts,
                value,
              )
            None => false
          },
        ),
      )
    "record_routing_plan" =>
      Some(
        (
          event_from(command, "routing-plan-recorded", Some("G3")),
          match command.routing_plan {
            Some(value) =>
              @governance.routing_plan_valid(value, command.snapshot.graph)
            None => false
          },
        ),
      )
    "record_routing_decision" =>
      Some(
        (
          event_from(command, "routing-decision-recorded", Some("G3")),
          match command.routing_decision {
            Some(value) =>
              @governance.routing_decision_valid(
                command.snapshot.routing_plan,
                value,
              )
            None => false
          },
        ),
      )
    "record_generation_attempt" =>
      Some(
        (
          event_from(command, "generation-attempt-recorded", Some("G4")),
          match command.generation_attempt {
            Some(value) =>
              @governance.generation_attempt_valid(
                value,
                command.snapshot.graph,
                command.snapshot.routing_plan,
              )
            None => false
          },
        ),
      )
    "record_qc_finding" =>
      Some(
        (
          event_from(command, "qc-finding-recorded", Some("G4")),
          match command.qc_finding {
            Some(value) =>
              @governance.qc_finding_valid(
                value,
                command.snapshot.generation_attempts,
              )
            None => false
          },
        ),
      )
    "record_qc_decision" =>
      Some(
        (
          event_from(command, "qc-decision-recorded", Some("G4")),
          match command.qc_decision {
            Some(value) =>
              @governance.qc_decision_valid(value, command.snapshot.qc_findings)
            None => false
          },
        ),
      )
    "record_master" =>
      Some(
        (
          event_from(command, "master-recorded", Some("G5")),
          match command.master {
            Some(value) =>
              @governance.master_record_valid(
                value,
                command.snapshot.graph.target_duration_seconds,
              )
            None => false
          },
        ),
      )
    "record_master_decision" =>
      Some(
        (
          event_from(command, "master-decision-recorded", Some("G5")),
          match command.master_decision {
            Some(value) =>
              @governance.master_decision_valid(command.snapshot.master, value)
            None => false
          },
        ),
      )
    "record_delivery_package" =>
      Some(
        (
          event_from(command, "delivery-package-recorded", Some("G5")),
          match command.delivery_package {
            Some(value) =>
              @governance.delivery_package_valid(
                value,
                command.snapshot.master,
                command.snapshot.master_decisions,
              )
            None => false
          },
        ),
      )
    "record_delivery_acceptance" =>
      Some(
        (
          event_from(command, "delivery-acceptance-recorded", Some("G5")),
          match command.delivery_acceptance {
            Some(value) =>
              @governance.delivery_acceptance_valid(
                command.snapshot.delivery_package,
                value,
              )
            None => false
          },
        ),
      )
    "record_publication_authorization" =>
      Some(
        (
          event_from(command, "publication-authorization-recorded", Some("G6")),
          match command.publication_authorization {
            Some(value) =>
              @governance.publication_authorization_valid(
                command.snapshot.delivery_package,
                value,
              )
            None => false
          },
        ),
      )
    "record_publication_observation" =>
      Some(
        (
          event_from(command, "publication-observation-recorded", Some("G7")),
          match command.publication_observation {
            Some(value) =>
              @governance.publication_observation_valid(
                command.snapshot.delivery_package,
                command.snapshot.publication_authorizations,
                value,
              )
            None => false
          },
        ),
      )
    "record_performance_review" =>
      Some(
        (
          event_from(command, "performance-review-recorded", Some("G7")),
          match command.performance_review {
            Some(value) =>
              @governance.performance_review_valid(
                command.snapshot.delivery_package,
                value,
              )
            None => false
          },
        ),
      )
    _ => None
  }
}

///|
fn command_gate(command : ProjectCommand) -> @governance.Gate? {
  match command.gate {
    Some(value) => @governance.Gate::parse(value)
    None => None
  }
}

///|
/// Validates and handles one host command. It never performs external effects.
pub fn handle(command : ProjectCommand) -> CommandResult {
  if command.schema_version != "mooncast.project-command.v2" {
    return error_result(
      command, "command_schema_unsupported", "expected mooncast.project-command.v2",
    )
  }
  if command.kernel_version != production_kernel_version {
    return error_result(
      command, "kernel_version_unsupported", "kernel version does not match",
    )
  }
  if command.command_id == "" ||
    command.recorded_at == "" ||
    command.evidence_digest == "" {
    return error_result(
      command, "command_evidence_required", "command id, time, and evidence digest are required",
    )
  }
  match command.command {
    "project" => success_result(command, [])
    "readiness" =>
      match command_gate(command) {
        None =>
          error_result(command, "gate_invalid", "gate must be G0 through G7")
        Some(gate) =>
          success_result(
            command,
            [],
            readiness=gate_readiness(command.snapshot, gate),
          )
      }
    "advance_gate" =>
      match command_gate(command) {
        None =>
          error_result(command, "gate_invalid", "gate must be G0 through G7")
        Some(gate) =>
          if next_gate(command.snapshot) != Some(gate) {
            error_result(
              command, "gate_order_invalid", "requested gate is not next",
            )
          } else {
            let ready = gate_readiness(command.snapshot, gate)
            if !ready.ready {
              error_result(
                command,
                "gate_requirements_failed",
                ready.reasons.join(","),
              )
            } else {
              match (command.actor, command.role) {
                (Some(actor), Some(role)) if actor != "" && role != "" => {
                  let event = {
                    ..event_from(command, "gate-advanced", None),
                    gate_receipt: Some({
                      gate,
                      actor,
                      role,
                      evidence_digest: command.evidence_digest,
                      snapshot_revision: command.snapshot.revision,
                      decided_at: command.recorded_at,
                    }),
                  }
                  success_result(command, [event], readiness=ready)
                }
                _ =>
                  error_result(
                    command, "named_reviewer_required", "actor and role are required",
                  )
              }
            }
          }
      }
    _ =>
      match payload_event(command) {
        None =>
          error_result(command, "command_unknown", "command is not supported")
        Some((event, valid)) =>
          if valid {
            success_result(command, [event])
          } else {
            error_result(
              command, "typed_payload_required", "command payload is missing",
            )
          }
      }
  }
}
