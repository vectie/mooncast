///|
pub(all) struct MasterTimelineEntry {
  shot_id : String
  asset_id : String
  asset_sha256 : String
  duration_seconds : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterMedia {
  duration_seconds : Double
  width : Int
  height : Int
  video_codec : String
  audio_codec : String
  format_name : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterLabels {
  explicit : String
  implicit : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterQc {
  status : String
  checks : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterPromotionEvidence {
  actor : String
  authority_ref : String
  promoted_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MasterProvenance {
  contract : String
  master_id : String
  project_id : String
  sha256 : String
  video_url : String
  subtitle_url : String
  provenance_url : String
  timeline : Array[MasterTimelineEntry]
  media : MasterMedia
  labels : MasterLabels
  qc : MasterQc
  editor_export_digest : String
  timeline_id : String
  project_revision : Int
  timeline_revision : Int
  plan_digest : String
  local_media_bindings : Array[@domain.LocalMediaBinding]
  promotion : MasterPromotionEvidence
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ShotAttemptBinding {
  shot_id : String
  attempt_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RegisterMasterHandoff {
  contract : String
  project_id : String
  expected_project_revision : Int
  source : String
  master : MasterProvenance
  shot_attempt_digests : Array[ShotAttemptBinding]
  supersedes_master_digest : String?
  invalidate_from_gate : String
  reset_reviews : Bool
  next_stage : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn register_master_handoff(
  project_id : String,
  expected_project_revision : Int,
  master : MasterProvenance,
  shot_attempt_digests : Array[ShotAttemptBinding],
  supersedes_master_digest : String?,
) -> RegisterMasterHandoff raise {
  guard master.contract == "mooncast.master-provenance.v2" &&
    master.project_id == project_id else {
    fail("master provenance identity mismatch")
  }
  guard master.sha256.length() == 64 && !shot_attempt_digests.is_empty() else {
    fail("master and shot lineage are required")
  }
  {
    contract: "mooncast.editor-register-master-handoff.v1",
    project_id,
    expected_project_revision,
    source: "editor-production-export",
    master,
    shot_attempt_digests,
    supersedes_master_digest,
    invalidate_from_gate: "G5",
    reset_reviews: true,
    next_stage: "assets-ready",
    publication_authority: false,
  }
}

///|
/// Typed copy of the generic production `VersionRef` wire contract.
/// It is declared here so editor code never imports production-domain packages.
pub(all) struct ProductionVersionRef {
  id : String
  version : Int
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Exact payload accepted by the Mooncast v2 production register-master command.
pub(all) struct ProductionMasterRecord {
  reference : ProductionVersionRef
  duration_seconds : Int
  video_digest : String
  audio_digest : String
  subtitle_digest : String
  provenance_digest : String
  ai_label : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProductionActionContext {
  command_id : String
  expected_revision : Int
  recorded_at : String
  evidence_digest : String
  actor : String?
  role : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Host-facing call descriptor for `ProjectRepository::register_master`.
pub(all) struct ProductionRegisterMasterRequest {
  contract : String
  project_id : String
  context : ProductionActionContext
  master : ProductionMasterRecord
  source : String
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Projects an immutable editor master into the exact production application request.
pub fn production_register_master_request(
  handoff : RegisterMasterHandoff,
  command_id : String,
  master_version : Int,
  master_digest : String,
  audio_digest : String,
  subtitle_digest : String,
  provenance_digest : String,
) -> ProductionRegisterMasterRequest raise {
  guard handoff.contract == "mooncast.editor-register-master-handoff.v1" &&
    handoff.source == "editor-production-export" else {
    fail("invalid editor master handoff")
  }
  guard master_version > 0 &&
    master_digest.has_prefix("sha256:") &&
    audio_digest.has_prefix("sha256:") &&
    subtitle_digest.has_prefix("sha256:") &&
    provenance_digest.has_prefix("sha256:") else {
    fail("production master digests are incomplete")
  }
  {
    contract: "mooncast.production-register-master-request.v2",
    project_id: handoff.project_id,
    context: {
      command_id,
      expected_revision: handoff.expected_project_revision,
      recorded_at: handoff.master.promotion.promoted_at,
      evidence_digest: handoff.master.editor_export_digest,
      actor: Some(handoff.master.promotion.actor),
      role: Some("editor-master-approver"),
    },
    master: {
      reference: {
        id: handoff.master.master_id,
        version: master_version,
        digest: master_digest,
      },
      duration_seconds: handoff.master.media.duration_seconds.to_int(),
      video_digest: "sha256:" + handoff.master.sha256,
      audio_digest,
      subtitle_digest,
      provenance_digest,
      ai_label: handoff.master.labels.explicit,
    },
    source: handoff.source,
    publication_authority: false,
  }
}

///|
pub(all) struct MasterPromotionBundle {
  contract : String
  promotion : MasterPromotionReceipt
  editor_handoff : RegisterMasterHandoff
  production_request : ProductionRegisterMasterRequest
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One exact, inert handoff bundle from successful editor export to production registration.
pub fn promote_master_bundle(
  project_id : String,
  current_project_revision : Int,
  editor_revision : Int,
  request : MasterPromotionRequest,
  export_receipt : ExportReceipt,
  master : MasterProvenance,
  shot_attempt_digests : Array[ShotAttemptBinding],
  supersedes_master_digest : String?,
  command_id : String,
  master_version : Int,
  master_digest : String,
  audio_digest : String,
  subtitle_digest : String,
  provenance_digest : String,
) -> MasterPromotionBundle raise {
  guard export_receipt.digest.has_prefix("sha256:") &&
    master.sha256 == export_receipt.digest[7:].to_owned() else {
    fail("master provenance does not bind editor export")
  }
  let promotion = promote_master(
    project_id,
    current_project_revision,
    editor_revision,
    request,
    export_receipt,
    master.master_id,
    master.subtitle_url,
    master.promotion.promoted_at,
  )
  let editor_handoff = register_master_handoff(
    project_id, current_project_revision, master, shot_attempt_digests, supersedes_master_digest,
  )
  let production_request = production_register_master_request(
    editor_handoff, command_id, master_version, master_digest, audio_digest, subtitle_digest,
    provenance_digest,
  )
  {
    contract: "mooncast.editor-master-promotion-bundle.v1",
    promotion,
    editor_handoff,
    production_request,
    publication_authority: false,
  }
}

///|
pub(all) struct RecordRef {
  record_id : String
  record_version : String
  record_digest : String
  provenance_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AuthoritativeDeliveryBindings {
  delivery_id : String
  delivery_digest : String
  delivery_state : String
  publication_status : String
  output_sha256 : String
  master_digest : String
  source_bindings_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MoonFlowCandidateRequest {
  candidate_id : String
  candidate_version : String
  idempotency_key : String
  project_id : String
  episode_id : String
  expected_project_revision : Int
  workflow_ref : RecordRef
  ability_ref : RecordRef
  intake_authority_ref : RecordRef
  submitted_at : String
  duration_seconds : Int
  lineage_evidence_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MoonFlowHandoffCandidate {
  contract : String
  generic_contract : String
  record_id : String
  record_version : String
  workflow_ref : RecordRef
  terminal_receipt_ref : RecordRef
  ability_ref : RecordRef
  intake_authority_ref : RecordRef
  source_bindings_digest : String
  lineage_evidence_digest : String
  editor_output_digest : String
  artifact_evidence_digest : String
  output_sha256 : String
  duration_seconds : Int
  submitted_at : String
  publication_authority : Bool
  external_effect_authorized : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn materialize_handoff_candidate(
  request : MoonFlowCandidateRequest,
  bindings : AuthoritativeDeliveryBindings,
  editor_export : @export.ExportEnvelope,
  editor_output_digest : String,
  artifact_evidence_digest : String,
) -> MoonFlowHandoffCandidate raise {
  guard request.duration_seconds >= 180 && request.duration_seconds <= 480 else {
    fail("MoonFlow candidate must be a 3-8 minute episode")
  }
  guard editor_export.result.state == "succeeded" &&
    !editor_export.request.publication_authority &&
    !editor_export.result.publication_authority else {
    fail("successful inert editor export is required")
  }
  guard editor_export.request.project_id == request.project_id &&
    editor_export.request.project_revision == request.expected_project_revision else {
    fail("MoonFlow handoff editor export is stale")
  }
  guard bindings.delivery_state == "delivered" &&
    bindings.publication_status == "not_published" else {
    fail("delivery is not eligible for MoonFlow handoff")
  }
  guard !bindings.delivery_id.is_blank() &&
    bindings.output_sha256.length() == 64 else {
    fail("authoritative delivery binding is invalid")
  }
  guard bindings.master_digest == editor_output_digest ||
    "sha256:" + bindings.output_sha256 == editor_output_digest else {
    fail("delivered master does not match editor export")
  }
  {
    contract: "mooncast.moonflow-final-deliverable-candidate.v1",
    generic_contract: "orchestration-final-deliverable-candidate-v1",
    record_id: request.candidate_id,
    record_version: request.candidate_version,
    workflow_ref: request.workflow_ref,
    terminal_receipt_ref: {
      record_id: bindings.delivery_id,
      record_version: "1",
      record_digest: bindings.delivery_digest,
      provenance_ref: "mooncast:delivery-package:v2",
    },
    ability_ref: request.ability_ref,
    intake_authority_ref: request.intake_authority_ref,
    source_bindings_digest: bindings.source_bindings_digest,
    lineage_evidence_digest: request.lineage_evidence_digest,
    editor_output_digest,
    artifact_evidence_digest,
    output_sha256: bindings.output_sha256,
    duration_seconds: request.duration_seconds,
    submitted_at: request.submitted_at,
    publication_authority: false,
    external_effect_authorized: false,
  }
}
