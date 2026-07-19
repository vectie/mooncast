///|
pub(all) struct PreviewRequest {
  session_id : String
  project_id : String
  project_revision : Int
  timeline_id : String
  timeline_revision : Int
  quality : String
  plan_digest : String
  spec_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreviewAuthority {
  contract : String
  schema_version : Int
  project_id : String
  job_id : String
  session_id : String
  project_revision : Int
  timeline_id : String
  timeline_revision : Int
  request : PreviewRequest
  request_digest : String
  plan_digest : String
  spec_digest : String
  provenance_digest : String
  snapshot_digest : String
  command_prefix_digest : String
  created_at : String
  publication_authority : Bool
  provider_authority : Bool
  anchor_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn preview_authority(
  request : PreviewRequest,
  job_id : String,
  request_digest : String,
  provenance_digest : String,
  snapshot_digest : String,
  command_prefix_digest : String,
  created_at : String,
  anchor_digest : String,
) -> PreviewAuthority raise {
  guard request.session_id == job_id else {
    fail("preview session and job identity must match")
  }
  {
    contract: "mooncast.editor-preview-authority.v1",
    schema_version: 1,
    project_id: request.project_id,
    job_id,
    session_id: request.session_id,
    project_revision: request.project_revision,
    timeline_id: request.timeline_id,
    timeline_revision: request.timeline_revision,
    request,
    request_digest,
    plan_digest: request.plan_digest,
    spec_digest: request.spec_digest,
    provenance_digest,
    snapshot_digest,
    command_prefix_digest,
    created_at,
    publication_authority: false,
    provider_authority: false,
    anchor_digest,
  }
}

///|
pub fn verify_preview_authority(
  value : PreviewAuthority,
  project_id : String,
  job_id : String,
  project_revision : Int,
  timeline_id : String,
  timeline_revision : Int,
  snapshot_digest : String,
  command_prefix_digest : String,
) -> Unit raise {
  guard value.contract == "mooncast.editor-preview-authority.v1" &&
    value.schema_version == 1 else {
    fail("unsupported preview authority")
  }
  guard value.project_id == project_id &&
    value.job_id == job_id &&
    value.session_id == job_id else {
    fail("preview authority identity mismatch")
  }
  guard value.project_revision == project_revision &&
    value.timeline_id == timeline_id &&
    value.timeline_revision == timeline_revision else {
    fail("preview authority revision mismatch")
  }
  guard value.snapshot_digest == snapshot_digest &&
    value.command_prefix_digest == command_prefix_digest else {
    fail("preview authority history mismatch")
  }
  guard !value.publication_authority && !value.provider_authority else {
    fail("preview authority cannot grant external effects")
  }
}
