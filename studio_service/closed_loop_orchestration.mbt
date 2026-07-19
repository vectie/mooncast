///|
pub async fn StudioService::record_project_qualification(
  self : StudioService,
  project_id : String,
  metadata : ProjectExperienceMetadata,
  recorded_at : String,
) -> ProjectCommandResponse {
  let record = self.get_project(project_id)
  let channel = metadata.channels.get(0).unwrap_or("review-only")
  let customer_id = if metadata.rights_owner.trim() == "" {
    "studio-project:" + project_id
  } else {
    metadata.rights_owner
  }
  let digest = "sha256:" +
    sha256_text(
      project_id + ":" + customer_id + ":" + metadata.objective + ":" + channel,
    )
  let qualification : @governance.ClientQualification = {
    reference: { id: project_id + "-qualification", version: 1, digest },
    customer_id,
    payable_problem: metadata.objective,
    acceptance_method: "Named client accepts the exact 3-8 minute review master",
    distribution_channel: channel,
    payment_path: "contract-milestones",
    repeat_purchase_hypothesis: "Repeat episode or quarterly content operation",
    accepted: metadata.rights_confirmed,
  }
  let command = {
    ..base_command(
      record.snapshot,
      "qualification-" + sha256_text(digest)[:20].to_owned(),
      "record_qualification",
      recorded_at,
      digest,
    ),
    actor: Some(customer_id),
    role: Some("client-sponsor"),
    qualification: Some(qualification),
  }
  self.apply_project_command(project_id, {
    expected_revision: record.snapshot.revision,
    command,
  })
}

///|
pub async fn StudioService::advance_ready_gates(
  self : StudioService,
  project_id : String,
  actor : String,
  role : String,
  evidence_digest : String,
) -> ProjectRecord {
  let named_actor = if actor.trim() == "" { "mooncast-workflow" } else { actor }
  let named_role = if role.trim() == "" {
    "workflow-orchestrator"
  } else {
    role
  }
  for ;; {
    let record = self.get_project(project_id)
    match @kernel.next_gate(record.snapshot) {
      None => return record
      Some(gate) => {
        let readiness = @kernel.gate_readiness(record.snapshot, gate)
        if !readiness.ready {
          return record
        }
        let gate_name = gate.to_string()
        let recorded_at = now_string()
        let evidence = "sha256:" +
          sha256_text(
            project_id +
            ":" +
            gate_name +
            ":" +
            record.snapshot.revision.to_string() +
            ":" +
            evidence_digest,
          )
        let response = self.advance_gate(project_id, {
          expected_revision: record.snapshot.revision,
          command_id: "closed-loop-gate-" +
          gate_name +
          "-" +
          record.snapshot.revision.to_string(),
          recorded_at,
          evidence_digest: evidence,
          gate: gate_name,
          actor: named_actor,
          role: named_role,
        })
        if !response.result.ok {
          return response.project
        }
      }
    }
  }
}

///|
async fn StudioService::auto_advance_response(
  self : StudioService,
  project_id : String,
  response : ProjectCommandResponse,
  actor : String,
  role : String,
  evidence_digest : String,
) -> ProjectCommandResponse {
  if !response.result.ok {
    response
  } else {
    let project = self.advance_ready_gates(
      project_id, actor, role, evidence_digest,
    )
    { ..response, project, }
  }
}

///|
pub async fn StudioService::adopt_pipeline_result(
  self : StudioService,
  project_id : String,
  result : @pipeline_app.RoutedIngestResult,
) -> ProjectRecord {
  match result.project_result {
    None => self.get_project(project_id)
    Some(command_result) =>
      self.with_mutation_lock(() => {
        let record = self.get_project(project_id)
        guard command_result.ok &&
          command_result.snapshot.revision == record.snapshot.revision + 1 else {
          raise Conflict(
            code="pipeline_project_revision_conflict",
            message="routed ingestion no longer follows the canonical project",
          )
        }
        let events = record.events
        for event in command_result.emitted_events {
          events.push(event)
        }
        let updated = {
          ..record,
          updated_at: now_string(),
          snapshot: command_result.snapshot,
          events,
        }
        save_value(self.store, project_key(project_id), updated)
        updated
      })
  }
}
