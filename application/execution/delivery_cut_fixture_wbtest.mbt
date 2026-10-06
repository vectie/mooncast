///|
async test "actual trimmed media ZIP captions align and previous archive stays immutable" {
  let ffmpeg = @env.get_env_var("MOONCAST_FFMPEG_BIN").unwrap_or(
    "/usr/bin/ffmpeg",
  )
  let ffprobe = @env.get_env_var("MOONCAST_FFPROBE_BIN").unwrap_or(
    "/usr/bin/ffprobe",
  )
  let root = "/tmp/mooncast-cut-caption-" + @runtime.new_id(prefix="fixture")
  let inputs = @store.AtomicStore::new(root + "/inputs")
  let files = @store.AtomicStore::new(root + "/outputs")
  let source_srt = @utf8.encode(
    "1\n00:00:00,000 --> 00:00:02,000\nBefore cut\n\n2\n00:00:02,000 --> 00:00:04,000\n跨越开始\nSecond line unchanged\n\n3\n00:00:04,500 --> 00:00:05,250\nInside\n\n4\n00:00:05,750 --> 00:00:08,000\nCrossing end\n\n5\n00:00:08,000 --> 00:00:10,000\nAfter cut\n",
  )
  let source_blob = inputs.put_blob("source.srt", source_srt)
  let master_path = inputs.prepare_owned_path("master.mp4")
  let made = @host_process.run_capture({
    executable: ffmpeg,
    arguments: [
      "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=24:duration=12",
      "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100:duration=12", "-c:v",
      "libx264", "-preset", "ultrafast", "-threads", "1", "-c:a", "aac", "-shortest",
      master_path,
    ],
    working_directory: None,
    timeout_ms: 120000,
    max_output_bytes: 8192,
  })
  assert_eq(made.exit_code, Some(0))
  let master = inputs.get_blob("master.mp4").unwrap()
  let service = DeliveryFactoryService::new(
    root + "/state",
    root + "/outputs",
    ffmpeg,
  )
  let output : @execution_domain.DeliveryOutputSpec = {
    output_id: "master",
    kind: "source-master",
    container: "mp4",
    codec: "libx264",
    width: 320,
    height: 240,
    subtitle_mode: "sidecar",
    metadata_digest: "sha256:synthetic-caption-output",
    source_output_id: None,
    orientation: None,
    framing_policy: None,
    in_seconds: None,
    out_seconds: None,
    timestamp_seconds: None,
  }
  let selection : Json = {
    "contract": "mooncast.delivery-caption-selection.v1",
    "project_id": "synthetic-cut-project",
    "sha256": "sha256:" + source_blob.sha256,
    "master_sha256": master.sha256,
    "language": "zh-Hans",
    "source_clips": [
      {
        "rights_owner": "synthetic-fixture-owner",
        "rights_digest": "sha256:fixture-rights",
      },
    ],
  }
  let request : DeliveryBuildRequest = {
    contract: "mooncast.delivery-build-request.v1",
    project_id: "synthetic-cut-project",
    expected_project_revision: 1,
    master_path,
    master_sha256: master.sha256,
    master_promotion_digest: "synthetic-promoted-master",
    master_duration_seconds: 12.0,
    delivery_version: 1,
    delivery_digest: "synthetic-delivery",
    profile: {
      contract: "mooncast.delivery-build-profile.v1",
      profile_version: 1,
      profile_digest: "synthetic-original-profile",
      outputs: [output],
      include_provenance_manifest: true,
      include_rights_ledger: true,
      include_acceptance_receipt: true,
    },
    subtitle_path: Some(inputs.owned_path("source.srt")),
    project_metadata: Some({ "fixture": true }),
    provenance_manifest: Some({ "caption_selection": selection }),
    rights_ledger: Some({ "rights_owner": "synthetic-fixture-owner" }),
    acceptance_receipt: Some({ "state": "awaiting-named-client-acceptance" }),
    ai_label: Some("SYNTHETIC TEST ONLY"),
    g5_accepted: true,
    client_accepted: false,
    evidence_digest: "synthetic-fixture",
    created_at: "2026-10-04T23:00:00Z",
  }
  let queued = service.create(request)
  let original = service.build(
    queued.build.build_id,
    queued.build.revision,
    queued.build.record_digest,
    "synthetic-economics",
  )
  assert_eq(original.build.state, "completed")
  let original_archive = files
    .get_blob(original.build.archive.unwrap().filename)
    .unwrap()
  let cut = {
    ..output,
    output_id: "selected-cut",
    kind: "channel-cut",
    source_output_id: Some("master"),
    in_seconds: Some(3.0),
    out_seconds: Some(6.0),
  }
  let portrait = {
    ..output,
    output_id: "portrait",
    kind: "platform-variant",
    width: 240,
    height: 320,
    orientation: Some("vertical"),
    framing_policy: Some("crop"),
  }
  let portrait_cut = {
    ..cut,
    output_id: "portrait-cut",
    source_output_id: Some("portrait"),
  }
  let cut_request = {
    ..request,
    profile: {
      ..request.profile,
      profile_digest: "synthetic-trimmed-profile",
      outputs: [output, portrait, cut, portrait_cut],
    },
  }
  let cut_queued = service.create(cut_request)
  let cut_build = service.build(
    cut_queued.build.build_id,
    cut_queued.build.revision,
    cut_queued.build.record_digest,
    "synthetic-economics",
  )
  assert_eq(cut_build.build.state, "completed")
  let id = cut_build.build.build_id
  let cut_video = files.owned_path(id + "-selected-cut.mp4")
  let probe = @host_process.run_capture({
    executable: ffprobe,
    arguments: [
      "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", cut_video,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 8192,
  })
  assert_eq(probe.exit_code, Some(0))
  assert_eq(@utf8.decode(probe.stdout).trim(), "3.000000")
  let expected = @utf8.encode(
    "1\n00:00:00,000 --> 00:00:01,000\n跨越开始\nSecond line unchanged\n\n2\n00:00:01,500 --> 00:00:02,250\nInside\n\n3\n00:00:02,750 --> 00:00:03,000\nCrossing end\n",
  )
  let cut_sidecars = cut_build.build.artifacts.filter(item => {
    item.kind == "subtitle-sidecar"
  })
  // This assertion fails against source-current: it shipped only the master SRT.
  assert_eq(cut_sidecars.length(), 3)
  let name = id + "-selected-cut-subtitles.srt"
  assert_eq(files.get_blob(name).unwrap().bytes, expected)
  assert_eq(
    files.get_blob(id + "-portrait-cut-subtitles.srt").unwrap().bytes,
    expected,
  )
  let archive_path = files.owned_path(cut_build.build.archive.unwrap().filename)
  let zipped = @host_process.run_capture({
    executable: "/usr/bin/unzip",
    arguments: ["-p", archive_path, name],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 8192,
  })
  assert_eq(zipped.exit_code, Some(0))
  assert_eq(zipped.stdout, expected)
  let subtitle_manifest = files.get_json(id + "-subtitles.json").unwrap()
  assert_true(subtitle_manifest.stringify().contains("contiguous-trim"))
  assert_true(subtitle_manifest.stringify().contains("zh-Hans"))
  assert_true(subtitle_manifest.stringify().contains("fixture-rights"))
  assert_eq(inputs.get_blob("source.srt").unwrap().bytes, source_srt)
  assert_eq(inputs.get_blob("master.mp4").unwrap().bytes, master.bytes)
  assert_eq(
    files.get_blob(original.build.archive.unwrap().filename).unwrap().bytes,
    original_archive.bytes,
  )
  ignore(
    inputs.put_json("verification.json", {
      "fixture": "synthetic only",
      "cut_duration_seconds": 3,
      "cut_range_seconds": [3, 6],
      "cut_srt_sha256": sha256(expected),
      "original_archive_sha256": original_archive.sha256,
      "original_master_sha256": master.sha256,
      "original_srt_sha256": source_blob.sha256,
      "cut_build_id": id,
      "original_build_id": original.build.build_id,
      "publication_authority": false,
    }),
  )
  println("Synthetic cut-caption fixture: " + root)
}
