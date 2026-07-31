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
      mime_type: if detected_type == "" {
        "application/octet-stream"
      } else {
        detected_type
      },
      size_bytes: blob.get_size(),
      sha256: "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    }
  })
}
