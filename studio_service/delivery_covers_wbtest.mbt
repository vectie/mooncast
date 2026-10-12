///|
async test "cover preview HTTP serves exact completed images before acceptance and rejects tampering" {
  let root = "/tmp/mooncast-cover-route-" + @runtime.new_id(prefix="fixture")
  let inputs = @host_store.AtomicStore::new(root + "/inputs")
  let ffmpeg = @env.get_env_var("MOONCAST_FFMPEG_BIN").unwrap_or(
    "/usr/bin/ffmpeg",
  )
  // The host ships a platform bundle. This synthetic test injects the actual
  // local test tool through the same delivery factory, without a Mac claim.
  let service = {
    ..StudioService::new(root),
    delivery_application: @execution_app.DeliveryFactoryService::new(
      root + "/application/delivery/state",
      root + "/application/delivery/outputs",
      ffmpeg,
    ),
  }
  let master_path = inputs.prepare_owned_path("synthetic-master.mp4")
  let made = @process.run_capture({
    executable: ffmpeg,
    arguments: [
      "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=24:duration=2",
      "-c:v", "libx264", "-preset", "ultrafast", "-threads", "1", master_path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 8192,
  })
  assert_eq(made.exit_code, Some(0))
  let master = inputs.get_blob("synthetic-master.mp4").unwrap()
  let base = delivery_output(
    "master", "source-master", 320, 240, "none", "synthetic-metadata",
  )
  let cover = {
    ..base,
    output_id: "poster",
    kind: "cover-frame",
    container: "png",
    codec: "png",
    source_output_id: Some("master"),
    timestamp_seconds: Some(0.25),
  }
  let queued = service.delivery_application.create({
    contract: "mooncast.delivery-build-request.v1",
    project_id: "cover-route-project",
    expected_project_revision: 1,
    master_path,
    master_sha256: master.sha256,
    master_promotion_digest: "synthetic-promoted-master",
    master_duration_seconds: 2.0,
    delivery_version: 1,
    delivery_digest: "synthetic-delivery",
    profile: {
      contract: "mooncast.delivery-build-profile.v1",
      profile_version: 1,
      profile_digest: "synthetic-cover-profile",
      outputs: [base, cover],
      include_provenance_manifest: true,
      include_rights_ledger: true,
      include_acceptance_receipt: true,
    },
    subtitle_path: None,
    project_metadata: Some({ "fixture": true }),
    provenance_manifest: Some({ "fixture": true }),
    rights_ledger: Some({ "rights_owner": "synthetic-test" }),
    acceptance_receipt: Some({ "state": "awaiting-client-acceptance" }),
    ai_label: Some("SYNTHETIC TEST ONLY"),
    g5_accepted: true,
    client_accepted: false,
    evidence_digest: "synthetic-test",
    created_at: "2026-10-06T12:00:00Z",
  })
  assert_true(delivery_cover_frames(queued.build).is_empty())
  let built = service.delivery_application.build(
    queued.build.build_id,
    queued.build.revision,
    queued.build.record_digest,
    "synthetic-economics",
  )
  assert_eq(built.build.state, "completed")
  assert_eq(service.delivery_application.acceptance(built.build.build_id), None)
  let projection = delivery_build_projection(built.build)
  assert_eq(projection.cover_frames.length(), 1)
  let frame = projection.cover_frames[0]
  assert_eq(frame.cover_id, "poster")
  assert_eq(frame.timestamp_seconds, 0.25)
  assert_eq(frame.source_variant, "master")
  let files = @host_store.AtomicStore::new(
    root + "/application/delivery/outputs",
  )
  let blob = files.get_blob(frame.name).unwrap()
  assert_true(frame.preview_url.has_suffix("/" + blob.sha256))
  for suffix in ["", "/download"] {
    let response = service.dispatch_http({
      request_method: Get,
      path: frame.preview_url + suffix,
      query: None,
      headers: {},
      body: b"",
    })
    assert_eq(response.status, 200)
    assert_eq(response.body, blob.bytes)
    assert_eq(response.headers.get("Content-Type"), Some("image/png"))
    assert_eq(response.headers.get("X-Content-Type-Options"), Some("nosniff"))
    assert_true(
      response.headers
      .get("Content-Disposition")
      .unwrap()
      .has_prefix(if suffix == "" { "inline" } else { "attachment" }),
    )
  }
  for
    path in [
      frame.preview_url.replace(
        old="cover-route-project",
        new="foreign-project",
      ),
      frame.preview_url.replace(old="/poster/", new="/master/"),
      frame.preview_url + "bad-digest",
    ] {
    assert_eq(
      service.dispatch_http({
        request_method: Get,
        path,
        query: None,
        headers: {},
        body: b"",
      }).status,
      404,
    )
  }
  ignore(files.put_blob(frame.name, b"tampered"))
  let corrupt = service.dispatch_http({
    request_method: Get,
    path: frame.preview_url,
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(corrupt.status, 404)
  assert_false(corrupt.body == b"tampered")
  ignore(files.put_blob(frame.name, blob.bytes))
  assert_eq(
    service.dispatch_http({
      request_method: Get,
      path: frame.preview_url,
      query: None,
      headers: {},
      body: b"",
    }).body,
    blob.bytes,
  )
  assert_eq(service.delivery_application.acceptance(built.build.build_id), None)
  assert_false(
    service.delivery_application.load(built.build.build_id).unwrap().publication_effect_performed,
  )
  ignore(
    inputs.put_json("route-verification.json", {
      "fixture": "SYNTHETIC ONLY",
      "build": projection.to_json(),
      "preview_and_download_bytes_match": true,
      "no_acceptance_required": true,
      "tamper_and_foreign_rejected": true,
    }),
  )
  println("Synthetic cover route fixture: " + root)
}
