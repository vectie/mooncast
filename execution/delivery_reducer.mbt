///|
pub fn apply_delivery_event(
  build : DeliveryBuild,
  event : DeliveryBuildEvent,
) -> DeliveryBuild {
  let updated = match event.kind {
    "build-started" =>
      { ..build, state: "building", attempt_count: build.attempt_count + 1 }
    "build-completed" =>
      {
        ..build,
        state: "completed",
        artifacts: event.artifacts,
        archive: event.archive,
        economics_receipt_digest: event.economics_receipt_digest,
        last_error_code: None,
      }
    "build-failed" =>
      { ..build, state: "failed", last_error_code: event.error_code }
    "build-cancelled" => { ..build, state: "cancelled" }
    "build-retried" => { ..build, state: "queued", last_error_code: None }
    "build-invalidated" => { ..build, state: "invalidated" }
    "build-recovered" =>
      { ..build, state: "queued", recovery_count: build.recovery_count + 1 }
    _ => build
  }
  { ..updated, revision: updated.revision + 1, updated_at: event.recorded_at }
}

///|
pub fn replay_delivery_build(
  initial : DeliveryBuild,
  events : Array[DeliveryBuildEvent],
) -> DeliveryBuild {
  let mut build = initial
  for event in events {
    build = apply_delivery_event(build, event)
  }
  build
}

///|
fn delivery_failure(
  command : DeliveryBuildCommand,
  code : String,
) -> DeliveryBuildResult {
  {
    contract: "mooncast.delivery-build-result.v1",
    command_id: command.command_id,
    ok: false,
    error_code: Some(code),
    build: command.build,
    events: [],
    external_effect_performed: false,
    publication_authority: false,
  }
}

///|
pub fn reduce_delivery_command(
  command : DeliveryBuildCommand,
) -> DeliveryBuildResult {
  if command.contract != "mooncast.delivery-build-command.v1" {
    return delivery_failure(command, "contract_unsupported")
  }
  if command.expected_revision != command.build.revision {
    return delivery_failure(command, "delivery_build_revision_conflict")
  }
  if command.build.publication_authority {
    return delivery_failure(command, "publication_authority_forbidden")
  }
  let kind = match command.action {
    "start" if command.build.state == "queued" => Some("build-started")
    "complete" if command.build.state == "building" &&
      command.artifacts.length() > 0 &&
      command.archive is Some(_) &&
      command.economics_receipt_digest is Some(_) => Some("build-completed")
    "fail" if command.build.state == "building" => Some("build-failed")
    "cancel" if command.build.state == "queued" ||
      command.build.state == "building" => Some("build-cancelled")
    "retry" if command.build.state == "failed" => Some("build-retried")
    "invalidate" if command.build.state != "invalidated" =>
      Some("build-invalidated")
    "recover" if command.build.state == "building" => Some("build-recovered")
    _ => None
  }
  match kind {
    None => delivery_failure(command, "delivery_build_transition_invalid")
    Some(event_kind) => {
      let event : DeliveryBuildEvent = {
        contract: "mooncast.delivery-build-event.v1",
        event_id: command.command_id,
        kind: event_kind,
        recorded_at: command.recorded_at,
        evidence_digest: command.evidence_digest,
        artifacts: command.artifacts,
        archive: command.archive,
        economics_receipt_digest: command.economics_receipt_digest,
        error_code: command.error_code,
      }
      {
        contract: "mooncast.delivery-build-result.v1",
        command_id: command.command_id,
        ok: true,
        error_code: None,
        build: apply_delivery_event(command.build, event),
        events: [event],
        external_effect_performed: false,
        publication_authority: false,
      }
    }
  }
}

///|
pub fn authorize_publication(
  build : DeliveryBuild,
  acceptance : DeliveryBuildAcceptance,
  destination_id : String,
  actor : String,
  authorized_at : String,
) -> PublicationAuthorityRequest? {
  if build.state != "completed" ||
    acceptance.decision != "accept" ||
    acceptance.build_digest != build.build_digest ||
    acceptance.build_record_digest != build.record_digest ||
    destination_id == "" ||
    actor == "" {
    return None
  }
  Some({
    contract: "mooncast.publication-authority-request.v1",
    project_id: build.project_id,
    build_digest: build.build_digest,
    acceptance_receipt_digest: acceptance.receipt_digest,
    destination_id,
    actor,
    authorized_at,
    external_effect_performed: false,
    publication_performed: false,
  })
}
