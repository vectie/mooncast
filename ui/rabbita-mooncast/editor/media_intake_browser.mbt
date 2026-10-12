///|
fn selected_local_media_blob() -> @dom.Blob? {
  selected_video_blobs("media-intake-file").get(0)
}

///|
fn prepare_local_media_blob(
  dispatch : @rabbita.Emit[Msg],
  blob : @dom.Blob,
) -> @rabbita.Cmd {
  @rabbita.attempt(result => dispatch(IntakeFilePrepared(result)), async fn() {
    let bytes = blob.bytes()
    let detected_type = blob.get_type()
    {
      blob,
      file_name: selected_blob_name(blob),
      mime_type: local_media_mime(selected_blob_name(blob), detected_type),
      size_bytes: blob.get_size(),
      sha256: "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    }
  })
}

///|
fn local_media_mime(file_name : String, detected_type : String) -> String {
  let name = file_name.to_lower()
  if name.has_suffix(".json") {
    "application/json"
  } else if name.has_suffix(".tsv") {
    "text/tab-separated-values"
  } else if name.has_suffix(".srt") {
    "application/x-subrip"
  } else if name.has_suffix(".vtt") {
    "text/vtt"
  } else if name.has_suffix(".txt") {
    "text/plain"
  } else if detected_type == "" {
    "application/octet-stream"
  } else {
    detected_type
  }
}
