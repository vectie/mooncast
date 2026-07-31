///|
extern "js" fn selected_video_blobs(input_id : String) -> Array[@dom.Blob] =
  #|(inputId) => Array.from(document.getElementById(inputId)?.files || []).sort((left, right) =>
  #|  String(left.name || "").localeCompare(String(right.name || ""), "en")
  #|)

///|
extern "js" fn selected_blob_name(blob : @dom.Blob) -> String =
  #|(blob) => String(blob.name || "video.mp4")

///|
fn selected_utility_concat_files() -> Array[UtilityConcatInput] {
  selected_video_blobs("utility-concat-files").map(blob => {
    let mime = blob.get_type()
    {
      blob,
      file_name: selected_blob_name(blob),
      mime_type: if mime == "" {
        "video/mp4"
      } else {
        mime
      },
      size_bytes: blob.get_size(),
      sha256: "",
    }
  })
}

///|
fn utility_concat_total_bytes(files : Array[UtilityConcatInput]) -> Int64 {
  files.fold(init=0L, (total, file) => total + Int64::from_int(file.size_bytes))
}

///|
fn utility_concat_job_id(files : Array[UtilityConcatInput]) -> String {
  let identity = files
    .map(file => {
      file.file_name +
      "\u{0000}" +
      file.size_bytes.to_string() +
      "\u{0000}" +
      file.sha256
    })
    .join("\n")
  "utility-concat-" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(identity)))[:20].to_owned()
}

///|
fn UtilityConcatJob::next_pending_input(
  self : UtilityConcatJob,
) -> UtilityConcatJobInput? {
  for input in self.inputs {
    if !input.uploaded {
      return Some(input)
    }
  }
  None
}

///|
fn UtilityConcatJobInput::matches_local(
  self : UtilityConcatJobInput,
  file : UtilityConcatInput,
) -> Bool {
  self.file_name == file.file_name &&
  self.mime_type == file.mime_type &&
  self.size_bytes == file.size_bytes &&
  self.sha256 == file.sha256
}

///|
fn utility_concat_create_body(
  files : Array[UtilityConcatInput],
  job_id : String,
) -> Json {
  {
    "contract": "mooncast.editor-utility-concat-request.v1".to_json(),
    "job_id": job_id.to_json(),
    "idempotency_key": job_id.to_json(),
    "inputs": Json::array(
      files.map(file => {
        Json::object({
          "file_name": file.file_name.to_json(),
          "mime_type": file.mime_type.to_json(),
          "size_bytes": file.size_bytes.to_json(),
          "sha256": file.sha256.to_json(),
        })
      }),
    ),
    "created_by": "rabbita-editor-operator".to_json(),
  }
}

///|
fn hash_utility_concat_file(
  dispatch : @rabbita.Emit[Msg],
  index : Int,
  file : UtilityConcatInput,
) -> @rabbita.Cmd {
  @rabbita.attempt(result => dispatch(UtilityConcatFileHashed(index, result)), async fn() {
    let bytes = file.blob.bytes()
    "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
  })
}

///|
fn create_utility_concat(
  dispatch : @rabbita.Emit[Msg],
  files : Array[UtilityConcatInput],
) -> @rabbita.Cmd {
  let job_id = utility_concat_job_id(files)
  @http.post("/api/editor/utility-concats")
  .with_json(utility_concat_create_body(files, job_id))
  .expect_json(result => dispatch(UtilityConcatCreated(result)))
}

///|
fn upload_utility_concat_input(
  dispatch : @rabbita.Emit[Msg],
  job_id : String,
  index : Int,
  file : UtilityConcatInput,
) -> @rabbita.Cmd {
  @http.post(
    "/api/editor/utility-concats/" + job_id + "/inputs/" + index.to_string(),
  )
  .with_blob(file.blob)
  .expect_json(result => dispatch(UtilityConcatInputUploaded(result)))
}

///|
fn run_utility_concat(
  dispatch : @rabbita.Emit[Msg],
  job_id : String,
) -> @rabbita.Cmd {
  @http.post("/api/editor/utility-concats/" + job_id + "/run")
  .with_json(Json::object({}))
  .expect_json(result => dispatch(UtilityConcatFinished(result)))
}

///|
fn utility_concat_progress(model : Model) -> String {
  let state = model.utility_concat
  match state.phase {
    "hashing" =>
      "Hashing \{state.completed}/\{state.files.length()} selected videos…"
    "creating" => "Freezing ordered source manifest…"
    "uploading" =>
      "Uploading \{state.completed}/\{state.files.length()} exact videos…"
    "running" => "Combining exact sources without re-encoding…"
    "succeeded" =>
      "Combined \{state.files.length()} videos · \{state.output_size} bytes"
    "failed" => state.error
    _ => "Choose MP4 videos. File-name order is the concat order."
  }
}

///|
fn utility_concat_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let state = model.utility_concat
  @html.details(class="workflow-drawer", open=true) <| [
    @html.summary <| [
      @html.strong("Quick combine local videos"),
      @html.span(
        "Project-free · ordered · immutable · no publication authority",
      ),
    ],
    @html.div(class="workflow-grid") <| [
      @html.label(class="wide") <| [
        @html.span("Local MP4 videos"),
        @html.input(
          input_type=@html.File,
          accept="video/mp4,.mp4",
          multiple=true,
          id="utility-concat-files",
          on_change=dispatch.map(_ => {
            UtilityConcatFilesSelected(selected_utility_concat_files())
          }),
        ),
      ],
      @html.p(
        class="wide microcopy",
        "\{state.files.length()} files · \{utility_concat_total_bytes(state.files)} bytes · sorted by safe file name",
      ),
      @html.ol(class="wide evidence-list") <| state.files.map(file => {
        let digest = if file.sha256 == "" { "" } else { " · " + file.sha256 }
        @html.li("\{file.file_name} · \{file.size_bytes} bytes" + digest)
      }),
      @html.p(class="wide", utility_concat_progress(model)),
      if state.error == "" {
        @html.nothing
      } else {
        @html.p(class="wide error", state.error)
      },
      @html.button(
        class="primary",
        type_="button",
        disabled=state.files.is_empty() ||
          state.phase == "hashing" ||
          state.phase == "creating" ||
          state.phase == "uploading" ||
          state.phase == "running",
        on_click=dispatch(StartUtilityConcat),
        "Combine selected videos",
      ),
      if state.media_url == "" {
        @html.nothing
      } else {
        @html.a(
          class="primary",
          href=state.media_url,
          download="mooncast-" + state.job_id + ".mp4",
          "Download combined video",
        )
      },
      if state.output_digest == "" {
        @html.nothing
      } else {
        @html.code(class="wide", state.output_digest)
      },
    ],
  ]
}
