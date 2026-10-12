///|
fn cover_fixture_outputs(
  base : @execution_domain.DeliveryOutputSpec,
) -> Array[@execution_domain.DeliveryOutputSpec] {
  let first = {
    ..base,
    output_id: "cover-start",
    kind: "cover-frame",
    container: "png",
    codec: "png",
    source_output_id: Some("master"),
    timestamp_seconds: Some(1.25),
    subtitle_mode: "none",
  }
  [
    first,
    {
      ..first,
      output_id: "cover-later",
      container: "jpg",
      codec: "mjpeg",
      timestamp_seconds: Some(7.0),
    },
    {
      ..first,
      output_id: "cover-portrait",
      source_output_id: Some("portrait"),
      timestamp_seconds: Some(9.0),
    },
  ]
}

///|
async fn assert_real_cover_outputs(
  service : DeliveryFactoryService,
  files : @store.AtomicStore,
  inputs : @store.AtomicStore,
  built : DeliveryFactoryRecord,
  request : DeliveryBuildRequest,
  ffmpeg : String,
) -> Unit {
  let id = built.build.build_id
  let covers = built.build.artifacts.filter(artifact => {
    artifact.kind == "cover-frame"
  })
  assert_eq(covers.length(), 3)
  assert_eq(service.acceptance(id), None)
  let archive = files.owned_path(built.build.archive.unwrap().filename)
  for
    output in request.profile.outputs.filter(output => {
      output.kind == "cover-frame"
    }) {
    let selected = service
      .verified_cover_frame(
        request.project_id,
        id,
        output.output_id,
        covers
        .iter()
        .find_first(artifact => artifact.artifact_id == output.output_id)
        .unwrap().digest
        .strip_prefix("sha256:")
        .unwrap()
        .to_owned(),
      )
      .unwrap()
    let (artifact, blob) = selected
    let expected_path = inputs.prepare_owned_path(
      "expected-" + output.output_id + "." + output.container,
    )
    let source_path = if output.source_output_id == Some("portrait") {
      files.owned_path(id + "-portrait.mp4")
    } else {
      request.master_path
    }
    let expected = @host_process.run_capture({
      executable: ffmpeg,
      arguments: [
        "-v",
        "error",
        "-y",
        "-ss",
        output.timestamp_seconds.unwrap().to_string(),
        "-i",
        source_path,
        "-frames:v",
        "1",
        expected_path,
      ],
      working_directory: None,
      timeout_ms: 30000,
      max_output_bytes: 8192,
    })
    assert_eq(expected.exit_code, Some(0))
    assert_eq(
      blob.bytes,
      inputs
      .get_blob("expected-" + output.output_id + "." + output.container)
      .unwrap().bytes,
    )
    let zipped = @host_process.run_capture({
      executable: "/usr/bin/unzip",
      arguments: ["-p", archive, artifact.filename],
      working_directory: None,
      timeout_ms: 30000,
      max_output_bytes: 16777216,
    })
    assert_eq(zipped.exit_code, Some(0))
    assert_eq(zipped.stdout, blob.bytes)
    assert_eq(artifact.digest, "sha256:" + blob.sha256)
    assert_eq(artifact.bytes, blob.bytes.length())
    for
      (project, cover, digest) in [
        ("foreign-project", output.output_id, blob.sha256),
        (request.project_id, "master", blob.sha256),
        (request.project_id, output.output_id, "stale-digest"),
        (request.project_id, "../cover-start", blob.sha256),
      ] {
      assert_eq(service.verified_cover_frame(project, id, cover, digest), None)
    }
    ignore(files.put_blob(artifact.filename, b"tampered image"))
    assert_eq(
      service.verified_cover_frame(
        request.project_id,
        id,
        output.output_id,
        blob.sha256,
      ),
      None,
    )
    ignore(files.put_blob(artifact.filename, blob.bytes))
    assert_true(
      service.verified_cover_frame(
        request.project_id,
        id,
        output.output_id,
        blob.sha256,
      )
      is Some(_),
    )
  }
  let cover = cover_fixture_outputs(request.profile.outputs[0])[0]
  for
    invalid in [
      { ..cover, timestamp_seconds: Some(12.0), },
      { ..cover, timestamp_seconds: Some(12.001), },
      { ..cover, timestamp_seconds: Some(-1.0), },
      { ..cover, timestamp_seconds: Some(0.0 / 0.0), },
      { ..cover, timestamp_seconds: Some(1.0 / 0.0), },
      { ..cover, source_output_id: Some("selected-cut"), },
      { ..cover, in_seconds: Some(1.0), out_seconds: Some(3.0), },
      { ..cover, container: "svg", },
      { ..cover, output_id: "MASTER", },
      { ..cover, output_id: "../cover", },
      { ..cover, output_id: "", },
    ] {
    let profile = {
      ..request.profile,
      outputs: [request.profile.outputs[0], invalid],
    }
    assert_false(delivery_profile_valid(profile, 12.0))
    try service.create({ ..request, profile, }) catch {
      _ => ()
    } noraise {
      _ => fail("Invalid cover profile must reject before execution")
    }
  }
  for duration in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    try
      service.create({ ..request, master_duration_seconds: duration, })
    catch {
      _ => ()
    } noraise {
      _ => fail("Nonfinite duration must reject")
    }
  }
  let too_many = {
    ..request.profile,
    outputs: Array::makei(9, i => { ..cover, output_id: "cover-\{i}", }),
  }
  assert_false(delivery_profile_valid(too_many, 12.0))
  assert_false(
    delivery_profile_valid(
      {
        ..request.profile,
        outputs: [cover, { ..cover, output_id: "COVER-START", }],
      },
      12.0,
    ),
  )
  let changed = service.create({
    ..request,
    profile: {
      ..request.profile,
      profile_digest: "synthetic-new-cover-time",
      outputs: [
        request.profile.outputs[0],
        { ..cover, timestamp_seconds: Some(2.5), },
      ],
    },
  })
  assert_true(changed.build.build_id != id)
  assert_eq(
    service.verified_cover_frame(
      request.project_id,
      changed.build.build_id,
      cover.output_id,
      covers[0].digest,
    ),
    None,
  )
  assert_eq(service.load(id).unwrap().build, built.build)
  let failing = { ..service, ffmpeg_executable: "/usr/bin/false", }
  let failure_request = {
    ..request,
    profile: {
      ..request.profile,
      profile_digest: "synthetic-cover-retry",
      outputs: [request.profile.outputs[0], cover],
    },
  }
  let attempt = failing.create(failure_request)
  let failed = failing.build(
    attempt.build.build_id,
    attempt.build.revision,
    attempt.build.record_digest,
    "synthetic-economics",
  )
  assert_eq(failed.build.state, "failed")
  assert_eq(
    service.verified_cover_frame(
      request.project_id,
      failed.build.build_id,
      cover.output_id,
      covers[0].digest,
    ),
    None,
  )
  let retried = service.retry(
    failed.build.build_id,
    failed.build.revision,
    failed.build.record_digest,
    "synthetic-economics",
  )
  assert_eq(retried.build.state, "completed")
  assert_eq(retried.build.profile, failed.build.profile)
  assert_true(retried.build.attempt_count > failed.build.attempt_count)
  let retry_cover = retried.build.artifacts
    .iter()
    .find_first(artifact => artifact.kind == "cover-frame")
    .unwrap()
  assert_true(
    service.verified_cover_frame(
      request.project_id,
      retried.build.build_id,
      retry_cover.artifact_id,
      normalized_sha256(retry_cover.digest),
    )
    is Some(_),
  )
  assert_eq(service.load(id).unwrap().build, built.build)
  ignore(
    inputs.put_json("cover-verification.json", {
      "fixture": "SYNTHETIC ONLY",
      "build_id": id,
      "cover_artifacts": covers.to_json(),
      "cover_specs": request.profile.outputs
      .filter(output => output.kind == "cover-frame")
      .to_json(),
      "real_png_jpg": true,
      "independent_timestamp_extraction_equal": true,
      "zip_member_bytes_equal": true,
      "preview_without_acceptance": true,
      "cross_project_and_tamper_rejected": true,
      "failed_build_retry_preserves_profile": true,
      "publication_authority": false,
    }),
  )
  println(
    "Synthetic cover fixture: " + inputs.owned_path("cover-verification.json"),
  )
}
