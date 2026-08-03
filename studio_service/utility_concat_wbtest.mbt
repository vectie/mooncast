///|
async fn utility_concat_fixture(
  path : String,
  color : String,
  frame_rate? : Int = 30,
  audio_sample_rate? : Int = 0,
) -> Bytes {
  let arguments : Array[String] = [
    "-hide_banner",
    "-loglevel",
    "error",
    "-nostdin",
    "-y",
    "-f",
    "lavfi",
    "-i",
    "color=c=" + color + ":s=64x64:r=" + frame_rate.to_string() + ":d=0.4",
  ]
  if audio_sample_rate > 0 {
    arguments.append([
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=880:sample_rate=" +
      audio_sample_rate.to_string() +
      ":duration=0.4",
    ])
  }
  if audio_sample_rate == 0 {
    arguments.push("-an")
  }
  arguments.append([
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
  ])
  if audio_sample_rate > 0 {
    arguments.append([
      "-map",
      "0:v:0",
      "-map",
      "1:a:0",
      "-c:a",
      "aac",
      "-ar",
      audio_sample_rate.to_string(),
      "-ac",
      "2",
      "-shortest",
    ])
  }
  arguments.push(path)
  let generated = @process.run_capture({
    executable: bundled_ffmpeg,
    arguments,
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 1048576,
  })
  guard generated.exit_code == Some(0) &&
    !generated.timed_out &&
    !generated.output_truncated else {
    fail("could not generate utility concat fixture")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  file.read_exactly_at(size.to_int(), position=0)
}

///|
fn utility_concat_fixture_digest(bytes : Bytes) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
async fn utility_concat_run_fixture_job(
  root : String,
  job_id : String,
  inputs : Array[(String, Bytes)],
) -> (StudioService, UtilityConcatJob) {
  let service = StudioService::new(root)
  ignore(
    service.create_utility_concat({
      contract: "mooncast.editor-utility-concat-request.v1",
      job_id,
      idempotency_key: job_id,
      inputs: inputs.map(item => {
        file_name: item.0,
        mime_type: "video/mp4",
        size_bytes: item.1.length(),
        sha256: utility_concat_fixture_digest(item.1),
      }),
      created_by: "utility-concat-test",
    }),
  )
  for index, item in inputs {
    ignore(service.upload_utility_concat_input(job_id, index, item.1))
  }
  (service, service.run_utility_concat(job_id))
}

///|
async test "utility concat freezes upload order and produces verified silent MP4" {
  let nonce = @async.now().to_string()
  let root = "/tmp/mooncast-utility-concat-" + nonce
  let first = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-first-" + nonce + ".mp4",
    "red",
  )
  let second = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-second-" + nonce + ".mp4",
    "blue",
  )
  let service = StudioService::new(root)
  let job_id = "utility-concat-test-" + nonce
  let created = service.create_utility_concat({
    contract: "mooncast.editor-utility-concat-request.v1",
    job_id,
    idempotency_key: job_id,
    inputs: [
      {
        file_name: "first.mp4",
        mime_type: "video/mp4",
        size_bytes: first.length(),
        sha256: utility_concat_fixture_digest(first),
      },
      {
        file_name: "second.mp4",
        mime_type: "video/mp4",
        size_bytes: second.length(),
        sha256: utility_concat_fixture_digest(second),
      },
    ],
    created_by: "utility-concat-test",
  })
  assert_eq(created.state, "awaiting-inputs")
  assert_eq(created.uploaded_count, 0)
  assert_eq(created.expected_count, 2)
  assert_false(created.publication_authority)
  assert_false(created.provider_authority)

  let partly_uploaded = service.upload_utility_concat_input(job_id, 1, second)
  assert_eq(partly_uploaded.state, "awaiting-inputs")
  assert_eq(partly_uploaded.uploaded_count, 1)
  assert_false(partly_uploaded.inputs[0].uploaded)
  assert_true(partly_uploaded.inputs[1].uploaded)

  let ready = service.upload_utility_concat_input(job_id, 0, first)
  assert_eq(ready.state, "ready")
  assert_eq(ready.uploaded_count, 2)
  assert_eq(ready.inputs[0].file_name, "first.mp4")
  assert_eq(ready.inputs[1].file_name, "second.mp4")

  let completed = service.run_utility_concat(job_id)
  assert_eq(completed.state, "succeeded")
  assert_true(completed.output_size > 0)
  assert_true(completed.output_digest.has_prefix("sha256:"))
  assert_eq(
    completed.media_url,
    "/api/editor/utility-concats/" + job_id + "/media",
  )
  assert_eq(completed.error, "")
  assert_false(completed.publication_authority)
  assert_false(completed.provider_authority)

  let output = service.resolve_utility_concat_media(job_id)
  assert_eq(output.length(), completed.output_size)
  assert_eq(utility_concat_fixture_digest(output), completed.output_digest)

  let replay = service.create_utility_concat({
    contract: "mooncast.editor-utility-concat-request.v1",
    job_id,
    idempotency_key: job_id,
    inputs: [
      {
        file_name: "first.mp4",
        mime_type: "video/mp4",
        size_bytes: first.length(),
        sha256: utility_concat_fixture_digest(first),
      },
      {
        file_name: "second.mp4",
        mime_type: "video/mp4",
        size_bytes: second.length(),
        sha256: utility_concat_fixture_digest(second),
      },
    ],
    created_by: "utility-concat-test",
  })
  assert_true(replay == completed)
}

///|
async test "utility concat preserves mixed frame-rate video and normalizes audio" {
  let nonce = @async.now().to_string()
  let root = "/tmp/mooncast-utility-concat-mixed-audio-" + nonce
  let first = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-30fps-44100-" + nonce + ".mp4",
    "purple",
    frame_rate=30,
    audio_sample_rate=44100,
  )
  let second = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-60fps-48000-" + nonce + ".mp4",
    "orange",
    frame_rate=60,
    audio_sample_rate=48000,
  )
  let (service, completed) = utility_concat_run_fixture_job(
    root,
    "utility-concat-mixed-audio-" + nonce,
    [("first.mp4", first), ("second.mp4", second)],
  )
  assert_eq(completed.state, "succeeded")
  let output = probe_utility_concat_input(
    service.editor_render_files.owned_path(
      utility_concat_output_key(completed.job_id),
    ),
  )
  assert_true(output.video.codec_name == "h264")
  assert_true(
    output.audio is Some(audio) &&
    audio.codec_name == "aac" &&
    audio.sample_rate == 48000 &&
    audio.channels == 2,
  )
}

///|
async test "utility concat canonicalizes manifest entries for a relative data root" {
  let nonce = @async.now().to_string()
  let first = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-relative-first-" + nonce + ".mp4",
    "white",
  )
  let second = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-relative-second-" + nonce + ".mp4",
    "gray",
  )
  let (_, completed) = utility_concat_run_fixture_job(
    "_build/test-data/mooncast-utility-concat-relative-" + nonce,
    "utility-concat-relative-" + nonce,
    [("first.mp4", first), ("second.mp4", second)],
  )
  assert_eq(completed.state, "succeeded")
  assert_true(completed.output_size > 0)
}

///|
async test "utility concat supplies canonical silence for mixed audio presence" {
  let nonce = @async.now().to_string()
  let root = "/tmp/mooncast-utility-concat-mixed-silence-" + nonce
  let audible = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-audible-" + nonce + ".mp4",
    "cyan",
    frame_rate=30,
    audio_sample_rate=44100,
  )
  let silent = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-silent-" + nonce + ".mp4",
    "black",
    frame_rate=60,
  )
  let (service, completed) = utility_concat_run_fixture_job(
    root,
    "utility-concat-mixed-silence-" + nonce,
    [("audible.mp4", audible), ("silent.mp4", silent)],
  )
  assert_eq(completed.state, "succeeded")
  let output = probe_utility_concat_input(
    service.editor_render_files.owned_path(
      utility_concat_output_key(completed.job_id),
    ),
  )
  assert_true(
    output.audio is Some(audio) &&
    audio.codec_name == "aac" &&
    audio.sample_rate == 48000 &&
    audio.channels == 2,
  )
}

///|
async test "utility concat persists actionable execution failure details" {
  let nonce = @async.now().to_string()
  let root = "/tmp/mooncast-utility-concat-failure-" + nonce
  let service = StudioService::new(root)
  let job_id = "utility-concat-failure-" + nonce
  let invalid_mp4 = b"not an mp4"
  ignore(
    service.create_utility_concat({
      contract: "mooncast.editor-utility-concat-request.v1",
      job_id,
      idempotency_key: job_id,
      inputs: [
        {
          file_name: "invalid.mp4",
          mime_type: "video/mp4",
          size_bytes: invalid_mp4.length(),
          sha256: utility_concat_fixture_digest(invalid_mp4),
        },
      ],
      created_by: "utility-concat-test",
    }),
  )
  ignore(service.upload_utility_concat_input(job_id, 0, invalid_mp4))
  let failed = service.run_utility_concat(job_id)
  assert_eq(failed.state, "failed")
  assert_true(failed.error.contains("input probe exited with code"))
  assert_true(failed.error.contains("Invalid data found when processing input"))
  assert_true(service.get_utility_concat(job_id) == failed)
}

///|
async test "utility concat HTTP workflow returns range-capable MP4" {
  let nonce = @async.now().to_string()
  let root = "/tmp/mooncast-utility-concat-http-" + nonce
  let first = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-http-first-" + nonce + ".mp4",
    "yellow",
  )
  let second = utility_concat_fixture(
    "/tmp/mooncast-utility-concat-http-second-" + nonce + ".mp4",
    "green",
  )
  let service = StudioService::new(root)
  let job_id = "utility-concat-http-" + nonce
  let request : UtilityConcatCreateRequest = {
    contract: "mooncast.editor-utility-concat-request.v1",
    job_id,
    idempotency_key: job_id,
    inputs: [
      {
        file_name: "first.mp4",
        mime_type: "video/mp4",
        size_bytes: first.length(),
        sha256: utility_concat_fixture_digest(first),
      },
      {
        file_name: "second.mp4",
        mime_type: "video/mp4",
        size_bytes: second.length(),
        sha256: utility_concat_fixture_digest(second),
      },
    ],
    created_by: "utility-concat-http-test",
  }
  let created = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/editor/utility-concats",
    query: None,
    headers: { "content-type": "application/json" },
    body: @utf8.encode(request.to_json().stringify()),
  })
  assert_eq(created.status, 201)
  let created_job : UtilityConcatJob = @json.from_json(
    @json.parse(@utf8.decode(created.body)),
  )
  assert_eq(created_job.state, "awaiting-inputs")

  for index, bytes in [first, second] {
    let uploaded = service.dispatch_http({
      request_method: @host_http.Post,
      path: "/api/editor/utility-concats/" +
      job_id +
      "/inputs/" +
      index.to_string(),
      query: None,
      headers: { "content-type": "video/mp4" },
      body: bytes,
    })
    assert_eq(uploaded.status, 201)
  }
  let run = service.dispatch_http({
    request_method: @host_http.Post,
    path: "/api/editor/utility-concats/" + job_id + "/run",
    query: None,
    headers: { "content-type": "application/json" },
    body: b"{}",
  })
  assert_eq(run.status, 200)
  let completed : UtilityConcatJob = @json.from_json(
    @json.parse(@utf8.decode(run.body)),
  )
  assert_eq(completed.state, "succeeded")

  let status = service.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/editor/utility-concats/" + job_id,
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(status.status, 200)
  let durable : UtilityConcatJob = @json.from_json(
    @json.parse(@utf8.decode(status.body)),
  )
  assert_true(durable == completed)

  let media = service.dispatch_http({
    request_method: @host_http.Get,
    path: completed.media_url,
    query: None,
    headers: { "range": "bytes=0-31" },
    body: b"",
  })
  assert_eq(media.status, 206)
  assert_true(media.headers.get("Content-Type") == Some("video/mp4"))
  assert_true(media.headers.get("Accept-Ranges") == Some("bytes"))
  assert_true(
    media.headers.get("Content-Disposition") ==
    Some("attachment; filename=\"mooncast-" + completed.job_id + ".mp4\""),
  )
  assert_eq(media.body.length(), 32)
}
