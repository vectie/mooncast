///|
async test "prebuild playback verifies exact promotion and retained MP4 GET HEAD ranges without delivery writes" {
  let root = "/tmp/mooncast-prebuild-" + @runtime.new_id(prefix="fixture")
  let service = StudioService::new(root)
  let project_id = "prebuild-range-project"
  let created = service.create_project(
    @production_app.episode_production_graph(
      project_id, "SYNTHETIC prebuild range fixture", 180, 5000.0,
    ),
    "2026-10-07T00:00:00Z",
  )
  let inputs = @host_store.AtomicStore::new(root + "/inputs")
  let media_path = inputs.prepare_owned_path("tiny-promoted-master.mp4")
  let made = @process.run_capture({
    executable: @env.get_env_var("MOONCAST_FFMPEG_BIN").unwrap_or(
      "/usr/bin/ffmpeg",
    ),
    arguments: [
      "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24:duration=4",
      "-c:v", "libx264", "-preset", "ultrafast", "-threads", "1", "-pix_fmt", "yuv420p",
      "-movflags", "+faststart", media_path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 8192,
  })
  assert_eq(made.exit_code, Some(0))
  let media = inputs.get_blob("tiny-promoted-master.mp4").unwrap()
  let sha256 = "sha256:" + media.sha256
  let plan : @editor_plan.RenderPlan = {
    contract: "mooncast.editor-render-plan.v1",
    project_id,
    timeline_id: "synthetic-timeline",
    project_revision: 1,
    timeline_revision: 1,
    timebase: { ticks_per_second: 1000, },
    output: {
      preset: "fixture",
      orientation: "horizontal",
      width: 160,
      height: 90,
      fps: { numerator: 24, denominator: 1, },
      background: "#000000",
    },
    range: { start_tick: 0, duration_ticks: 4000, },
    quality: "original",
    tracks: [],
    transitions: [],
    audio_buses: [],
    delivery_audio: {
      target_lufs: -14.0,
      true_peak_limit_dbtp: -1.0,
      limiter_enabled: true,
      delivery_audio_digest: "synthetic-audio",
    },
    findings: [],
    ready: true,
    publication_authority: false,
    plan_digest: "synthetic-retained-export-plan",
  }
  let job_id = "exact-promoted-export"
  let job : EditorJobView = {
    job: {
      ..@editor_jobs.EditorJob::queued(
        job_id,
        project_id,
        "export",
        plan.plan_digest,
        "synthetic-request",
        "2026-10-07T00:00:00Z",
      ),
      state: "succeeded",
      output_digest: sha256,
    },
    render_plan: plan,
    render_receipt: None,
    export_receipt: Some({
      digest: sha256,
      size: media.bytes.length(),
      output_ref: "synthetic-export",
      provider_ref: "local-fixture",
      provider_version: "fixture-v1",
      plan_digest: plan.plan_digest,
      spec_digest: "fixture-spec",
      test_only: true,
      publication_authority: false,
    }),
    export_spec: None,
    export_request: None,
    media_url: None,
    publication_authority: false,
  }
  save_value(service.store, editor_job_key(project_id, job_id), job)
  ignore(
    service.editor_render_files.put_blob(
      editor_render_key(project_id, job_id),
      media.bytes,
    ),
  )
  let promotion : @editor_integration.MasterPromotionReceipt = {
    contract: "mooncast.editor-master-promotion.v1",
    master_id: "fixture-promotion",
    project_id,
    project_revision: created.snapshot.revision,
    editor_revision: 1,
    job_id,
    digest: sha256,
    size: media.bytes.length(),
    video_ref: "synthetic-export",
    subtitle_ref: "synthetic-caption",
    plan_digest: plan.plan_digest,
    actor: "synthetic-reviewer",
    authority_ref: "fixture://only",
    promoted_at: "2026-10-07T00:00:00Z",
    publication_authority: false,
  }
  save_value(
    service.store,
    editor_promotion_key(project_id, promotion.master_id),
    promotion,
  )
  // The newest indexed job is deliberately unrelated. It must not be guessed.
  save_value(service.store, editor_latest_promotion_key(project_id), {
    ..promotion,
    job_id: "newest-unpromoted",
    digest: "sha256:other",
    promoted_at: "2026-10-08T00:00:00Z",
  })
  let master : @governance.Master = {
    reference: {
      id: "canonical-master",
      version: 1,
      digest: "sha256:canonical-reference",
    },
    duration_seconds: 4,
    video_digest: sha256,
    audio_digest: sha256,
    subtitle_digest: "sha256:fixture-caption",
    provenance_digest: "sha256:fixture-provenance",
    ai_label: "SYNTHETIC TEST ONLY",
  }
  let promoted = {
    ..created,
    snapshot: { ..created.snapshot, master: Some(master), },
  }
  save_value(service.store, project_key(project_id), promoted)
  let before : Array[(String, Bytes)] = []
  for key in service.store.list_keys(prefix="", suffix=".json") {
    before.push((key, service.store.get_blob(key).unwrap().bytes))
  }
  let projection = media_fixture_get(
    service,
    "/api/v2/projects/" + project_id + "/promoted-master/playback",
  )
  assert_eq(projection.status, 200)
  let value = @json.parse(@utf8.decode(projection.body))
  guard value
    is {
      "media_url": String(url),
      "job_id": "exact-promoted-export",
      "master_sha256": String(digest),
      ..
    } else {
    fail("Missing exact playback projection")
  }
  assert_eq(digest, sha256)
  let (path, query) = @host_http.split_target(url)
  for method in [@host_http.Get, Head] {
    let full = service.dispatch_http({
      request_method: method,
      path,
      query,
      headers: {},
      body: b"",
    })
    assert_eq(full.status, 200)
    assert_eq(full.headers.get("Content-Type"), Some("video/mp4"))
    let range = service.dispatch_http({
      request_method: method,
      path,
      query,
      headers: { "range": "bytes=8-39" },
      body: b"",
    })
    assert_eq(range.status, 206)
    assert_eq(
      range.headers.get("Content-Range"),
      Some("bytes 8-39/" + media.bytes.length().to_string()),
    )
    // dispatch_http handles semantic response bodies; the actual native socket
    // strips HEAD bodies. Socket verification checks wire-level emptiness.
    if method == @host_http.Get {
      assert_eq(full.body, media.bytes)
      assert_eq(range.body, media.bytes[8:40].to_owned())
    }
  }
  let invalid = service.dispatch_http({
    request_method: Get,
    path,
    query,
    headers: { "range": "bytes=9999999-" },
    body: b"",
  })
  assert_eq(invalid.status, 416)
  assert_true(service.delivery_application.list(project_id).is_empty())
  for (key, bytes) in before {
    assert_eq(service.store.get_blob(key).unwrap().bytes, bytes)
  }
  assert_eq(
    service.store.list_keys(prefix="", suffix=".json").length(),
    before.length(),
  )
  save_value(service.store, editor_job_key(project_id, job_id), {
    ..job,
    job: { ..job.job, state: "running", },
  })
  assert_true(
    media_fixture_get(
      service,
      "/api/v2/projects/" + project_id + "/promoted-master/playback",
    ).status >=
    400,
  )
  save_value(service.store, editor_job_key(project_id, job_id), job)
  ignore(
    service.editor_render_files.put_blob(
      editor_render_key(project_id, job_id),
      b"corrupted",
    ),
  )
  assert_true(
    media_fixture_get(
      service,
      "/api/v2/projects/" + project_id + "/promoted-master/playback",
    ).status >=
    400,
  )
  ignore(
    service.editor_render_files.put_blob(
      editor_render_key(project_id, job_id),
      media.bytes,
    ),
  )
  save_value(service.store, project_key(project_id), {
    ..promoted,
    snapshot: {
      ..promoted.snapshot,
      master: Some({ ..master, video_digest: "sha256:changed", }),
    },
  })
  assert_eq(
    service.dispatch_http({
      request_method: Get,
      path,
      query,
      headers: {},
      body: b"",
    }).status,
    409,
  )
  save_value(service.store, project_key(project_id), promoted)
  save_value(service.store, editor_job_key(project_id, job_id), {
    ..job,
    job: { ..job.job, job_id: "foreign-job", },
  })
  assert_true(
    media_fixture_get(
      service,
      "/api/v2/projects/" + project_id + "/promoted-master/playback",
    ).status >=
    400,
  )
  assert_eq(
    service.dispatch_http({
      request_method: Get,
      path,
      query,
      headers: {},
      body: b"",
    }).status,
    409,
  )
  save_value(service.store, editor_job_key(project_id, job_id), job)
  let receipt_key = editor_promotion_key(project_id, promotion.master_id)
  save_value(service.store, receipt_key, { ..promotion, project_id: "foreign", })
  assert_true(
    media_fixture_get(
      service,
      "/api/v2/projects/" + project_id + "/promoted-master/playback",
    ).status >=
    400,
  )
  save_value(service.store, receipt_key, promotion)
  let ambiguous_key = editor_promotion_key(project_id, "ambiguous")
  save_value(service.store, ambiguous_key, {
    ..promotion,
    job_id: "another-matching-export",
  })
  assert_eq(
    media_fixture_get(
      service,
      "/api/v2/projects/" + project_id + "/promoted-master/playback",
    ).status,
    409,
  )
  ignore(service.store.remove(ambiguous_key))
  ignore(
    service.editor_render_files.remove(editor_render_key(project_id, job_id)),
  )
  assert_true(
    media_fixture_get(
      service,
      "/api/v2/projects/" + project_id + "/promoted-master/playback",
    ).status >=
    400,
  )
  ignore(
    service.editor_render_files.put_blob(
      editor_render_key(project_id, job_id),
      media.bytes,
    ),
  )
  ignore(inputs.put_json("playback-verification.json", value))
  println("Synthetic prebuild master fixture: " + root)
}
