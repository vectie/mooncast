///|
struct UtilityConcatProbeStream {
  codec_type : String
  codec_name : String
  profile : String?
  codec_tag_string : String?
  width : Int?
  height : Int?
  pix_fmt : String?
  level : Int?
  sample_rate : String?
  channels : Int?
} derive(FromJson)

///|
struct UtilityConcatProbeFormat {
  duration : String
} derive(FromJson)

///|
struct UtilityConcatProbeDocument {
  streams : Array[UtilityConcatProbeStream]
  format : UtilityConcatProbeFormat
} derive(FromJson)

///|
struct UtilityConcatVideoSignature {
  codec_name : String
  profile : String
  codec_tag_string : String
  width : Int
  height : Int
  pix_fmt : String
  level : Int
} derive(Debug, Eq)

///|
struct UtilityConcatAudioSignature {
  codec_name : String
  sample_rate : Int
  channels : Int
} derive(Debug, Eq)

///|
struct UtilityConcatProbe {
  video : UtilityConcatVideoSignature
  audio : UtilityConcatAudioSignature?
  duration_seconds : Double
} derive(Debug, Eq)

///|
fn utility_concat_job_key(job_id : String) -> String {
  "utility-concat-" + sha256_text(job_id) + ".json"
}

///|
fn utility_concat_input_key(job_id : String, index : Int) -> String {
  "utility-concat-" +
  sha256_text(job_id) +
  "-input-" +
  index.to_string() +
  ".mp4"
}

///|
fn utility_concat_manifest_key(job_id : String) -> String {
  "utility-concat-" + sha256_text(job_id) + "-manifest.txt"
}

///|
fn utility_concat_output_key(job_id : String) -> String {
  "utility-concat-" + sha256_text(job_id) + "-output.mp4"
}

///|
fn utility_concat_normalized_input_key(job_id : String, index : Int) -> String {
  "utility-concat-" +
  sha256_text(job_id) +
  "-normalized-" +
  index.to_string() +
  ".mp4"
}

///|
fn utility_concat_safe_file_name(value : String) -> Bool {
  !value.is_blank() &&
  value.length() <= 255 &&
  !value.contains("/") &&
  !value.contains("\\") &&
  !value.contains("\u{0000}")
}

///|
fn validate_utility_concat_request(
  request : UtilityConcatCreateRequest,
) -> Unit raise {
  guard request.contract == "mooncast.editor-utility-concat-request.v1" &&
    valid_id(request.job_id) &&
    request.idempotency_key == request.job_id &&
    !request.created_by.is_blank() &&
    request.inputs.length() > 0 &&
    request.inputs.length() <= 512 else {
    raise Invalid(
      code="utility_concat_request_invalid",
      message="utility concat identity, actor, or input count is invalid",
    )
  }
  let mut total_size = 0
  for input in request.inputs {
    guard utility_concat_safe_file_name(input.file_name) &&
      input.mime_type == "video/mp4" &&
      input.size_bytes > 0 &&
      input.size_bytes <= 67108864 &&
      input.sha256.has_prefix("sha256:") &&
      input.sha256.length() == 71 else {
      raise Invalid(
        code="utility_concat_input_invalid",
        message="utility concat accepts bounded digest-pinned MP4 inputs only",
      )
    }
    total_size += input.size_bytes
    guard total_size <= 1000000000 else {
      raise Invalid(
        code="utility_concat_size_invalid",
        message="utility concat inputs exceed the one-gigabyte job limit",
      )
    }
  }
}

///|
pub async fn StudioService::create_utility_concat(
  self : StudioService,
  request : UtilityConcatCreateRequest,
) -> UtilityConcatJob {
  validate_utility_concat_request(request)
  self.with_mutation_lock(() => {
    let key = utility_concat_job_key(request.job_id)
    let request_digest = "sha256:" + sha256_text(request.to_json().stringify())
    let existing : UtilityConcatJob? = load_value(self.store, key)
    match existing {
      Some(value) => {
        guard value.request_digest == request_digest else {
          raise Conflict(
            code="utility_concat_idempotency_conflict",
            message="utility concat job id already binds another request",
          )
        }
        value
      }
      None => {
        let timestamp = now_string()
        let inputs = request.inputs.mapi((index, input) => {
          index,
          file_name: input.file_name,
          mime_type: input.mime_type,
          size_bytes: input.size_bytes,
          sha256: normalized_digest(input.sha256),
          uploaded: false,
        })
        let job : UtilityConcatJob = {
          contract: "mooncast.editor-utility-concat-job.v1",
          job_id: request.job_id,
          idempotency_key: request.idempotency_key,
          request_digest,
          state: "awaiting-inputs",
          inputs,
          uploaded_count: 0,
          expected_count: inputs.length(),
          output_digest: "",
          output_size: 0,
          media_url: "",
          error: "",
          created_by: request.created_by,
          created_at: timestamp,
          updated_at: timestamp,
          publication_authority: false,
          provider_authority: false,
        }
        save_value(self.store, key, job)
        job
      }
    }
  })
}

///|
pub async fn StudioService::get_utility_concat(
  self : StudioService,
  job_id : String,
) -> UtilityConcatJob {
  let job : UtilityConcatJob? = load_value(
    self.store,
    utility_concat_job_key(job_id),
  )
  match job {
    Some(value) => value
    None => raise NotFound(entity="utility_concat", id=job_id)
  }
}

///|
pub async fn StudioService::upload_utility_concat_input(
  self : StudioService,
  job_id : String,
  index : Int,
  bytes : Bytes,
) -> UtilityConcatJob {
  self.with_mutation_lock(() => {
    let job = self.get_utility_concat(job_id)
    guard job.state == "awaiting-inputs" || job.state == "ready" else {
      raise Conflict(
        code="utility_concat_not_uploadable",
        message="utility concat inputs are immutable after execution starts",
      )
    }
    guard index >= 0 && job.inputs.get(index) is Some(expected) else {
      raise Invalid(
        code="utility_concat_index_invalid",
        message="utility concat input index is outside the frozen request",
      )
    }
    let digest = "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    guard bytes.length() == expected.size_bytes && digest == expected.sha256 else {
      raise Invalid(
        code="utility_concat_content_mismatch",
        message="utility concat input bytes do not match frozen size and digest",
      )
    }
    let input_key = utility_concat_input_key(job_id, index)
    if expected.uploaded {
      guard self.editor_render_files.get_blob(input_key) is Some(existing) &&
        existing.bytes.length() == expected.size_bytes &&
        "sha256:" + existing.sha256 == expected.sha256 else {
        raise Conflict(
          code="utility_concat_input_integrity_failed",
          message="previously uploaded utility concat input is missing or changed",
        )
      }
      return job
    }
    ignore(self.editor_render_files.put_blob(input_key, bytes))
    let inputs = job.inputs.copy()
    inputs[index] = { ..expected, uploaded: true }
    let uploaded_count = inputs.filter(input => input.uploaded).length()
    let updated = {
      ..job,
      state: if uploaded_count == inputs.length() {
        "ready"
      } else {
        "awaiting-inputs"
      },
      inputs,
      uploaded_count,
      updated_at: now_string(),
    }
    save_value(self.store, utility_concat_job_key(job_id), updated)
    updated
  })
}

///|
async fn probe_utility_concat_input(path : String) -> UtilityConcatProbe {
  let result = @process.run_capture({
    executable: bundled_ffprobe,
    arguments: [
      "-v", "error", "-show_streams", "-show_format", "-of", "json", path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 1048576,
  })
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail(utility_concat_process_failure("input probe", result))
  }
  let document : UtilityConcatProbeDocument = @json.from_json(
    @json.parse(@utf8.decode(result.stdout)),
  )
  let videos = document.streams.filter(stream => stream.codec_type == "video")
  let audios = document.streams.filter(stream => stream.codec_type == "audio")
  guard videos.length() == 1 && audios.length() <= 1 else {
    fail(
      "utility concat requires one video stream and at most one audio stream",
    )
  }
  let stream = videos[0]
  guard (stream.codec_name == "hevc" || stream.codec_name == "h264") &&
    stream.width is Some(width) &&
    stream.height is Some(height) &&
    width > 0 &&
    height > 0 else {
    fail("utility concat input video stream is unsupported")
  }
  let duration = @string.parse_double(document.format.duration) catch {
    _ => fail("utility concat input duration is invalid")
  }
  guard duration > 0.0 else { fail("utility concat input duration is empty") }
  {
    video: {
      codec_name: stream.codec_name,
      profile: stream.profile.unwrap_or(""),
      codec_tag_string: stream.codec_tag_string.unwrap_or(""),
      width,
      height,
      pix_fmt: stream.pix_fmt.unwrap_or(""),
      level: stream.level.unwrap_or(0),
    },
    audio: match audios.get(0) {
      None => None
      Some(audio) => {
        let sample_rate = match audio.sample_rate {
          Some(value) => @string.parse_int(value) catch { _ => 0 }
          None => 0
        }
        let channels = audio.channels.unwrap_or(0)
        guard sample_rate > 0 && channels > 0 else {
          fail("utility concat input audio metadata is invalid")
        }
        Some({ codec_name: audio.codec_name, sample_rate, channels })
      }
    },
    duration_seconds: duration,
  }
}

///|
fn utility_concat_manifest(paths : Array[String]) -> String raise {
  guard !paths.is_empty() else { fail("utility concat manifest is empty") }
  let lines : Array[String] = ["ffconcat version 1.0"]
  for path in paths {
    guard !path.contains("\n") && !path.contains("\r") else {
      fail("utility concat input path is unsafe")
    }
    lines.push("file '" + path.replace_all(old="'", new="\\'") + "'")
  }
  lines.join("\n") + "\n"
}

///|
fn UtilityConcatJob::failed(
  self : UtilityConcatJob,
  message : String,
) -> UtilityConcatJob {
  {
    ..self,
    state: "failed",
    output_digest: "",
    output_size: 0,
    media_url: "",
    error: message,
    updated_at: now_string(),
  }
}

///|
fn utility_concat_process_failure(
  stage : String,
  result : @process.CommandResult,
) -> String {
  let detail = (@utf8.decode(result.stderr) catch {
      _ => "(ffmpeg returned non-UTF-8 diagnostics)"
    })
    .trim()
    .to_owned()
  let bounded_detail = if detail.length() > 4000 {
    detail[:4000].to_owned() + "…"
  } else {
    detail
  }
  let reason = if result.timed_out {
    "timed out"
  } else if result.output_truncated {
    "diagnostics exceeded the output limit"
  } else {
    "exited with code " +
    result.exit_code.map_or("unknown", code => code.to_string())
  }
  if bounded_detail.is_empty() {
    stage + " " + reason
  } else {
    stage + " " + reason + ": " + bounded_detail
  }
}

///|
async fn StudioService::normalize_utility_concat_audio(
  self : StudioService,
  job_id : String,
  index : Int,
  source_path : String,
  probe : UtilityConcatProbe,
) -> String {
  let output_key = utility_concat_normalized_input_key(job_id, index)
  ignore(self.editor_render_files.remove(output_key))
  let output_path = self.editor_render_files.prepare_owned_path(output_key)
  let arguments : Array[String] = [
    "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", source_path,
  ]
  match probe.audio {
    Some(_) =>
      arguments.append([
        "-map", "0:v:0", "-map", "0:a:0", "-c:v", "copy", "-c:a", "aac", "-profile:a",
        "aac_low", "-ar", "48000", "-ac", "2", "-b:a", "192k", "-movflags", "+faststart",
        output_path,
      ])
    None =>
      arguments.append([
        "-f",
        "lavfi",
        "-i",
        "anullsrc=channel_layout=stereo:sample_rate=48000",
        "-map",
        "0:v:0",
        "-map",
        "1:a:0",
        "-c:v",
        "copy",
        "-c:a",
        "aac",
        "-profile:a",
        "aac_low",
        "-ar",
        "48000",
        "-ac",
        "2",
        "-b:a",
        "192k",
        "-t",
        probe.duration_seconds.to_string(),
        "-movflags",
        "+faststart",
        output_path,
      ])
  }
  let result = @process.run_capture({
    executable: bundled_ffmpeg,
    arguments,
    working_directory: None,
    timeout_ms: 600000,
    max_output_bytes: 65536,
  })
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail(utility_concat_process_failure("audio normalization", result))
  }
  let normalized = probe_utility_concat_input(output_path)
  guard normalized.video == probe.video &&
    normalized.audio is Some(audio) &&
    audio.codec_name == "aac" &&
    audio.sample_rate == 48000 &&
    audio.channels == 2 else {
    fail("audio normalization output verification failed")
  }
  @fs.realpath(output_path)
}

///|
async fn StudioService::execute_utility_concat(
  self : StudioService,
  job : UtilityConcatJob,
) -> UtilityConcatJob {
  let paths : Array[String] = []
  let probes : Array[UtilityConcatProbe] = []
  for input in job.inputs {
    guard input.uploaded else { fail("utility concat input is missing") }
    let key = utility_concat_input_key(job.job_id, input.index)
    guard self.editor_render_files.get_blob(key) is Some(blob) &&
      blob.bytes.length() == input.size_bytes &&
      "sha256:" + blob.sha256 == input.sha256 else {
      fail("utility concat input integrity check failed")
    }
    let path = @fs.realpath(self.editor_render_files.owned_path(key))
    paths.push(path)
    probes.push(probe_utility_concat_input(path))
  }
  guard probes.get(0) is Some(first) &&
    probes.all(probe => probe.video == first.video) else {
    fail("utility concat video streams are not copy-compatible")
  }
  let has_audio = probes.any(probe => probe.audio is Some(_))
  let concat_paths : Array[String] = if has_audio {
    let normalized : Array[String] = []
    for index, path in paths {
      normalized.push(
        self.normalize_utility_concat_audio(
          job.job_id,
          index,
          path,
          probes[index],
        ),
      )
    }
    normalized
  } else {
    paths
  }
  let manifest = utility_concat_manifest(concat_paths)
  let manifest_key = utility_concat_manifest_key(job.job_id)
  ignore(
    self.editor_render_files.put_blob(manifest_key, @utf8.encode(manifest)),
  )
  let output_key = utility_concat_output_key(job.job_id)
  ignore(self.editor_render_files.remove(output_key))
  let output_path = self.editor_render_files.prepare_owned_path(output_key)
  let arguments : Array[String] = [
    "-hide_banner",
    "-loglevel",
    "error",
    "-nostdin",
    "-y",
    "-f",
    "concat",
    "-safe",
    "0",
    "-i",
    self.editor_render_files.owned_path(manifest_key),
    "-map",
    "0:v:0",
  ]
  if has_audio {
    arguments.append(["-map", "0:a:0"])
  }
  arguments.append(["-c", "copy", "-movflags", "+faststart", output_path])
  let result = @process.run_capture({
    executable: bundled_ffmpeg,
    arguments,
    working_directory: None,
    timeout_ms: 600000,
    max_output_bytes: 65536,
  })
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail(utility_concat_process_failure("final concat", result))
  }
  guard self.editor_render_files.get_blob(output_key) is Some(output) &&
    !output.bytes.is_empty() else {
    fail("utility concat output is missing")
  }
  let output_probe = probe_utility_concat_input(output_path)
  let expected_duration = probes.fold(init=0.0, (sum, probe) => {
    sum + probe.duration_seconds
  })
  let output_audio_valid = if has_audio {
    output_probe.audio is Some(audio) &&
    audio.codec_name == "aac" &&
    audio.sample_rate == 48000 &&
    audio.channels == 2
  } else {
    output_probe.audio is None
  }
  let duration_tolerance = Double::max(2.0, probes.length().to_double() * 0.1)
  guard output_probe.video == first.video &&
    output_audio_valid &&
    (output_probe.duration_seconds - expected_duration).abs() <=
    duration_tolerance else {
    fail("utility concat output verification failed")
  }
  {
    ..job,
    state: "succeeded",
    output_digest: "sha256:" + output.sha256,
    output_size: output.bytes.length(),
    media_url: "/api/editor/utility-concats/" + job.job_id + "/media",
    error: "",
    updated_at: now_string(),
  }
}

///|
pub async fn StudioService::run_utility_concat(
  self : StudioService,
  job_id : String,
) -> UtilityConcatJob {
  let (running, should_execute) = self.with_mutation_lock(() => {
    let job = self.get_utility_concat(job_id)
    if job.state == "succeeded" {
      return (job, false)
    }
    guard job.state == "ready" || job.state == "failed" else {
      raise Conflict(
        code="utility_concat_not_ready",
        message="all utility concat inputs must be uploaded before execution",
      )
    }
    let running = {
      ..job,
      state: "running",
      error: "",
      updated_at: now_string(),
    }
    save_value(self.store, utility_concat_job_key(job_id), running)
    (running, true)
  })
  if !should_execute {
    return running
  }
  let terminal = try self.execute_utility_concat(running) catch {
    error =>
      running.failed("utility concat execution failed: \{to_repr(error)}")
  } noraise {
    completed => completed
  }
  self.with_mutation_lock(() => {
    let current = self.get_utility_concat(job_id)
    guard current == running else {
      raise Conflict(
        code="utility_concat_state_changed",
        message="utility concat state changed while execution was in progress",
      )
    }
    save_value(self.store, utility_concat_job_key(job_id), terminal)
    terminal
  })
}

///|
pub async fn StudioService::resolve_utility_concat_media(
  self : StudioService,
  job_id : String,
) -> Bytes {
  let job = self.get_utility_concat(job_id)
  guard job.state == "succeeded" else {
    raise Conflict(
      code="utility_concat_incomplete",
      message="utility concat output is not ready",
    )
  }
  guard self.editor_render_files.get_blob(utility_concat_output_key(job_id))
    is Some(blob) &&
    !blob.bytes.is_empty() &&
    "sha256:" + blob.sha256 == job.output_digest &&
    blob.bytes.length() == job.output_size else {
    raise Invalid(
      code="utility_concat_output_integrity_failed",
      message="utility concat output is missing or does not match its receipt",
    )
  }
  blob.bytes
}
