///|
pub(all) struct DownloadDescriptor {
  contract : String
  content_key : String
  digest : String
  mime_type : String
  file_name : String
  disposition : String
  size_bytes : Int
  range_supported : Bool
  immutable : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn export_download(
  job : @jobs.EditorJob,
  size_bytes : Int,
) -> DownloadDescriptor raise {
  guard job.kind == "export" && job.state == "succeeded" else {
    fail("only a successful export is downloadable")
  }
  {
    contract: "mooncast.editor-download-descriptor.v1",
    content_key: job.output_ref,
    digest: job.output_digest,
    mime_type: "video/mp4",
    file_name: "mooncast-" + job.project_id + "-" + job.job_id + ".mp4",
    disposition: "attachment",
    size_bytes,
    range_supported: true,
    immutable: true,
    publication_authority: false,
  }
}

///|
pub fn preview_download(
  job : @jobs.EditorJob,
  size_bytes : Int,
) -> DownloadDescriptor raise {
  guard job.kind == "preview" && job.state == "succeeded" else {
    fail("only a successful preview is observable")
  }
  {
    contract: "mooncast.editor-download-descriptor.v1",
    content_key: job.output_ref,
    digest: job.output_digest,
    mime_type: "video/mp4",
    file_name: "preview-" + job.job_id + ".mp4",
    disposition: "inline",
    size_bytes,
    range_supported: true,
    immutable: true,
    publication_authority: false,
  }
}

///|
pub fn media_download(
  value : @media.MediaByteDescriptor,
  file_name : String,
) -> DownloadDescriptor {
  {
    contract: "mooncast.editor-download-descriptor.v1",
    content_key: value.object_key,
    digest: value.digest,
    mime_type: value.mime,
    file_name,
    disposition: "inline",
    size_bytes: value.range.total,
    range_supported: true,
    immutable: value.immutable,
    publication_authority: false,
  }
}
