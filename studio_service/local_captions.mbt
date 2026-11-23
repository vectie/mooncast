///|
priv struct LocalCaptionRequest {
  start_ms : Int32
  duration_ms : Int32?
  translate : Bool
} derive(FromJson)

///|
let local_caption_slots : @semaphore.Semaphore = @semaphore.Semaphore(1)

///|
fn local_caption_model() -> String {
  @env.get_env_var("MOONCAST_WHISPER_MODEL").unwrap_or(
    match @env.get_env_var("LEPUSA_APP_DIR") {
      Some(root) => root + "/Resources/models/ggml-base.bin"
      None => ".tools/whisper/ggml-base.bin"
    },
  )
}

///|
fn local_caption_executable() -> String {
  @env.get_env_var("MOONCAST_WHISPER_BIN").unwrap_or(
    match @env.get_env_var("LEPUSA_APP_DIR") {
      Some(root) => root + "/MacOS/tools/whisper/bin/whisper-cli"
      None => "/opt/homebrew/bin/whisper-cli"
    },
  )
}

///|
async fn StudioService::local_caption_response(
  self : StudioService,
  project_id : String,
  take_id : String,
  request : @host_http.Request,
) -> @host_http.Response {
  try {
    guard local_caption_slots.try_acquire() else {
      fail(
        "Local speech model is busy. Retry when the current caption finishes.",
      )
    }
    defer local_caption_slots.release()
    let input : LocalCaptionRequest = @json.from_json(
      @json.parse(@utf8.decode(request.body)),
    )
    guard input.start_ms >= 0 && input.start_ms <= 86400000 else {
      fail("Caption position must be within 24 hours.")
    }
    let model_path = local_caption_model()
    let duration_ms = input.duration_ms.unwrap_or(8000)
    guard duration_ms > 0 && duration_ms <= 8000 else {
      fail("Caption windows must be between 1 and 8000 milliseconds.")
    }
    guard @fs.exists(model_path) else {
      fail(
        "Local speech model is missing. Set MOONCAST_WHISPER_MODEL to a multilingual whisper.cpp model file and restart Mooncast.",
      )
    }
    let take = self.find_editor_take(project_id, take_id)
    guard take.mime_type.has_prefix("video/") ||
      take.mime_type.has_prefix("audio/") else {
      fail("Choose a video or audio source for captions.")
    }
    let source = self.materialize_media(take.media_digest, ".media")
    let key = "local-caption-" +
      @async.now().to_string() +
      "-" +
      sha256_text(project_id + take_id + input.start_ms.to_string())[:12].to_owned()
    let wav_key = key + ".wav"
    let wav = self.editor_render_files.prepare_owned_path(wav_key)
    let output = self.editor_render_files.prepare_owned_path(key)
    defer {
      ignore(self.editor_render_files.remove(wav_key))
      ignore(self.editor_render_files.remove(key + ".srt"))
      ignore(self.editor_render_files.remove(key + ".txt"))
    }
    let decoded = @process.run_capture({
      executable: bundled_ffmpeg,
      arguments: [
        "-nostdin",
        "-v",
        "error",
        "-y",
        "-ss",
        (input.start_ms.to_double() / 1000.0).to_string(),
        "-i",
        source,
        "-t",
        (duration_ms.to_double() / 1000.0).to_string(),
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        "-c:a",
        "pcm_s16le",
        wav,
      ],
      working_directory: None,
      timeout_ms: 30000,
      max_output_bytes: 8192,
    })
    guard decoded.exit_code == Some(0) && !decoded.timed_out else {
      fail("Could not decode source audio for local captions.")
    }
    let arguments = [
      "-m", model_path, "-f", wav, "-l", "auto", "-osrt", "-otxt", "-of", output,
      "-np", "-t", "4",
    ]
    if input.translate {
      arguments.push("-tr")
    }
    let executable = local_caption_executable()
    let command = match @env.get_env_var("LEPUSA_APP_DIR") {
      Some(root) =>
        (
          "/usr/bin/env",
          [
            "GGML_BACKEND_PATH=" + root + "/Resources/tools/whisper/lib",
            executable,
            ..arguments,
          ],
        )
      None => (executable, arguments)
    }
    let result = @process.run_capture({
      executable: command.0,
      arguments: command.1,
      working_directory: None,
      timeout_ms: 90000,
      max_output_bytes: 65536,
    })
    guard result.exit_code == Some(0) && !result.timed_out else {
      fail(
        "Local Whisper could not process this audio. Check the configured executable and model.",
      )
    }
    let text = self.editor_render_files
      .get_blob(key + ".txt")
      .map(blob => @utf8.decode(blob.bytes))
      .unwrap_or("")
    let srt = self.editor_render_files
      .get_blob(key + ".srt")
      .map(blob => @utf8.decode(blob.bytes))
      .unwrap_or("")
    let body : Json = {
      "text": text,
      "srt": srt,
      "start_ms": input.start_ms,
      "duration_ms": duration_ms,
      "translated": input.translate,
    }
    @host_http.json_response(200, "OK", body.stringify())
  } catch {
    error => {
      let body : Json = { "error": error.to_string() }
      @host_http.json_response(422, "Unprocessable Content", body.stringify())
    }
  }
}
