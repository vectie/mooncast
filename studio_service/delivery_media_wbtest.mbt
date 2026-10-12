///|
async fn media_fixture_get(
  service : StudioService,
  path : String,
  headers? : Map[String, String] = {},
) -> @host_http.Response {
  service.dispatch_http({
    request_method: Get,
    path,
    query: None,
    headers,
    body: b"",
  })
}

///|
async test "individual delivery videos range downloads sidecars historical reads and retry preserve exact retained bytes" {
  let root = @env.get_env_var("MOONCAST_TRANSCRIPT_FIXTURE_ROOT").unwrap_or(
    "/tmp/mooncast-media-route-" + @runtime.new_id(prefix="fixture"),
  )
  let inputs = @host_store.AtomicStore::new(root + "/inputs")
  let files = @host_store.AtomicStore::new(
    root + "/application/delivery/outputs",
  )
  let ffmpeg = @env.get_env_var("MOONCAST_FFMPEG_BIN").unwrap_or(
    "/usr/bin/ffmpeg",
  )
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
      "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=24:duration=4",
      "-c:v", "libx264", "-preset", "ultrafast", "-threads", "1", master_path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 8192,
  })
  assert_eq(made.exit_code, Some(0))
  let master = inputs.get_blob("synthetic-master.mp4").unwrap()
  let srt = inputs.put_blob(
    "source.srt",
    @utf8.encode(
      "1\n00:00:00,000 --> 00:00:01,000\nEarly caption\n\n2\n00:00:02,000 --> 00:00:04,000\nLater caption\n你好 🌙 &\n",
    ),
  )
  let base = delivery_output(
    "master", "source-master", 320, 240, "sidecar", "synthetic-metadata",
  )
  let portrait = {
    ..base,
    output_id: "portrait",
    kind: "platform-variant",
    width: 240,
    height: 320,
    orientation: Some("vertical"),
    framing_policy: Some("crop"),
  }
  let early = {
    ..base,
    output_id: "early",
    kind: "channel-cut",
    source_output_id: Some("master"),
    in_seconds: Some(0.0),
    out_seconds: Some(1.0),
  }
  let later = {
    ..portrait,
    output_id: "later",
    kind: "channel-cut",
    source_output_id: Some("portrait"),
    in_seconds: Some(2.0),
    out_seconds: Some(4.0),
  }
  let request : @execution_app.DeliveryBuildRequest = {
    contract: "mooncast.delivery-build-request.v1",
    project_id: "media-route-project",
    expected_project_revision: 1,
    master_path,
    master_sha256: master.sha256,
    master_promotion_digest: "synthetic-promoted-master",
    master_duration_seconds: 4.0,
    delivery_version: 1,
    delivery_digest: "synthetic-delivery",
    profile: {
      contract: "mooncast.delivery-build-profile.v1",
      profile_version: 1,
      profile_digest: "synthetic-media-profile",
      outputs: [base, portrait, early, later],
      include_provenance_manifest: true,
      include_rights_ledger: true,
      include_acceptance_receipt: true,
    },
    subtitle_path: Some(inputs.owned_path("source.srt")),
    project_metadata: Some({ "fixture": true }),
    provenance_manifest: Some({
      "caption_selection": {
        "contract": "mooncast.delivery-caption-selection.v1",
        "project_id": "media-route-project",
        "sha256": "sha256:" + srt.sha256,
        "master_sha256": master.sha256,
        "language": "en",
        "source_clips": [{ "rights_owner": "synthetic-fixture" }],
      },
    }),
    rights_ledger: Some({ "rights_owner": "synthetic-fixture" }),
    acceptance_receipt: Some({ "state": "awaiting-client-acceptance" }),
    ai_label: Some("SYNTHETIC TEST ONLY"),
    g5_accepted: true,
    client_accepted: false,
    evidence_digest: "synthetic-test",
    created_at: "2026-10-07T00:00:00Z",
  }
  let queued = service.delivery_application.create(request)
  assert_true(delivery_videos(queued.build).is_empty())
  assert_eq(
    media_fixture_get(
      service,
      "/api/v2/projects/media-route-project/delivery-builds/" +
      queued.build.build_id +
      "/media/master/" +
      master.sha256,
    ).status,
    404,
  )
  let built = service.delivery_application.build(
    queued.build.build_id,
    queued.build.revision,
    queued.build.record_digest,
    "synthetic-economics",
  )
  assert_eq(built.build.state, "completed")
  let projection = delivery_build_projection(built.build)
  assert_eq(projection.videos.length(), 4)
  let video_bytes : Array[Bytes] = []
  for video in projection.videos {
    let saved = files.get_blob(video.name).unwrap()
    video_bytes.push(saved.bytes)
    assert_true(video.preview_url.has_suffix(saved.sha256))
    for
      (url, disposition) in [
        (video.preview_url, "inline"),
        (video.download_url, "attachment"),
      ] {
      let response = media_fixture_get(service, url)
      assert_eq(response.status, 200)
      assert_eq(response.body, saved.bytes)
      assert_eq(response.headers.get("Content-Type"), Some("video/mp4"))
      assert_eq(
        response.headers.get("Content-Disposition"),
        Some(disposition + "; filename=\"" + video.name + "\""),
      )
      assert_eq(response.headers.get("Accept-Ranges"), Some("bytes"))
      assert_eq(response.headers.get("X-Content-Type-Options"), Some("nosniff"))
      let partial = media_fixture_get(service, url, headers={
        "range": "bytes=7-31",
      })
      assert_eq(partial.status, 206)
      assert_eq(partial.body, saved.bytes[7:32].to_owned())
      assert_eq(
        partial.headers.get("Content-Range"),
        Some("bytes 7-31/" + saved.bytes.length().to_string()),
      )
      let resumed = media_fixture_get(service, url, headers={
        "range": "bytes=32-",
      })
      assert_eq(resumed.status, 206)
      assert_eq(resumed.body, saved.bytes[32:].to_owned())
      let suffix = media_fixture_get(service, url, headers={
        "range": "bytes=-17",
      })
      assert_eq(suffix.body, saved.bytes[saved.bytes.length() - 17:].to_owned())
      let invalid = media_fixture_get(service, url, headers={
        "range": "bytes=999999999-",
      })
      assert_eq(invalid.status, 416)
      assert_eq(
        invalid.headers.get("Content-Range"),
        Some("bytes */" + saved.bytes.length().to_string()),
      )
      let cached = media_fixture_get(service, url, headers={
        "if-none-match": response.headers.get("ETag").unwrap(),
      })
      assert_eq(cached.status, 304)
      assert_true(cached.body.is_empty())
    }
    let captions = video.captions.unwrap()
    let caption_bytes = files.get_blob(captions.name).unwrap().bytes
    let download = media_fixture_get(service, captions.download_url)
    assert_eq(download.body, caption_bytes)
    assert_eq(
      download.headers.get("Content-Type"),
      Some("application/x-subrip; charset=utf-8"),
    )
    assert_eq(
      download.headers.get("Content-Disposition"),
      Some("attachment; filename=\"" + captions.name + "\""),
    )
    let preview = @json.parse(
      @utf8.decode(media_fixture_get(service, captions.preview_url).body),
    )
    assert_eq(json_member(preview, "sha256"), Some(captions.sha256.to_json()))
    assert_eq(
      json_member(preview, "content"),
      Some(@utf8.decode(caption_bytes).to_json()),
    )
    if video.output_id == "early" {
      assert_true(@utf8.decode(caption_bytes).contains("Early caption"))
      assert_false(@utf8.decode(caption_bytes).contains("Later caption"))
    }
    if video.output_id == "later" {
      assert_true(
        @utf8.decode(caption_bytes).contains("00:00:00,000 --> 00:00:02,000"),
      )
      assert_false(@utf8.decode(caption_bytes).contains("Early caption"))
      assert_eq(video.source_output_id, "portrait")
      assert_eq(video.in_seconds, Some(2.0))
      assert_eq(video.out_seconds, Some(4.0))
    }
  }
  for i in 0..<video_bytes.length() {
    for j in (i + 1)..<video_bytes.length() {
      assert_false(video_bytes[i] == video_bytes[j])
    }
  }
  let early_video = projection.videos[2]
  let later_video = projection.videos[3]
  for
    bad_url in [
      early_video.preview_url + "bad",
      early_video.preview_url.replace(
        old="media-route-project",
        new="foreign-project",
      ),
      early_video.preview_url.replace(old="/early/", new="/later/"),
      later_video.captions.unwrap().preview_url.replace(
        old="/later/captions/",
        new="/early/captions/",
      ),
      later_video.captions.unwrap().preview_url.replace(
        old=later_video.captions.unwrap().sha256
          .strip_prefix("sha256:")
          .unwrap()
          .to_owned(),
        new=srt.sha256,
      ),
    ] {
    assert_eq(media_fixture_get(service, bad_url).status, 404)
  }
  let archive = files.get_blob(built.build.archive.unwrap().filename).unwrap()
  let old_video = files.get_blob(early_video.name).unwrap()
  ignore(files.put_blob(early_video.name, b"interrupted or corrupted"))
  assert_eq(
    media_fixture_get(service, early_video.preview_url, headers={
      "range": "bytes=0-3",
      "if-none-match": @host_http.etag(old_video.bytes),
    }).status,
    404,
  )
  ignore(files.put_blob(early_video.name, old_video.bytes))
  assert_eq(
    media_fixture_get(service, early_video.preview_url).body,
    old_video.bytes,
  )
  let caption = later_video.captions.unwrap()
  let old_caption = files.get_blob(caption.name).unwrap()
  ignore(files.put_blob(caption.name, b"corrupted captions"))
  assert_eq(media_fixture_get(service, caption.preview_url).status, 404)
  assert_eq(media_fixture_get(service, caption.download_url).status, 404)
  ignore(files.put_blob(caption.name, old_caption.bytes))
  assert_eq(
    media_fixture_get(service, caption.download_url).body,
    old_caption.bytes,
  )
  // Replace the original input and build a newer master. Historical URLs read
  // only retained artifacts, not the request's original path or current master.
  let newer = @process.run_capture({
    executable: ffmpeg,
    arguments: [
      "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=red:size=320x240:rate=24:duration=4",
      "-c:v", "libx264", "-preset", "ultrafast", "-threads", "1", master_path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 8192,
  })
  assert_eq(newer.exit_code, Some(0))
  let new_master = inputs.get_blob("synthetic-master.mp4").unwrap()
  assert_false(new_master.sha256 == master.sha256)
  let fresh = service.delivery_application.create({
    ..request,
    expected_project_revision: 2,
    master_sha256: new_master.sha256,
    master_promotion_digest: "new-master-promotion",
    delivery_version: 2,
    profile: {
      ..request.profile,
      outputs: [{ ..base, subtitle_mode: "none", }],
      profile_digest: "new-master-profile",
    },
    subtitle_path: None,
    provenance_manifest: Some({ "fixture": true }),
  })
  let fresh_built = service.delivery_application.build(
    fresh.build.build_id,
    fresh.build.revision,
    fresh.build.record_digest,
    "new-economics",
  )
  assert_eq(fresh_built.build.state, "completed")
  assert_eq(
    media_fixture_get(service, early_video.preview_url).body,
    old_video.bytes,
  )
  assert_eq(
    media_fixture_get(service, caption.download_url).body,
    old_caption.bytes,
  )
  assert_eq(
    files.get_blob(built.build.archive.unwrap().filename).unwrap().bytes,
    archive.bytes,
  )
  assert_eq(service.delivery_application.acceptance(built.build.build_id), None)
  assert_false(
    service.delivery_application.load(built.build.build_id).unwrap().publication_effect_performed,
  )
  // Retain the actual wire, unchanged, for compiled-UI transport verification.
  let builds_wire = media_fixture_get(
    service, "/api/v2/projects/media-route-project/delivery-builds",
  )
  assert_eq(builds_wire.status, 200)
  ignore(inputs.put_blob("delivery-builds.native.json", builds_wire.body))
  let captions_wire = media_fixture_get(service, caption.preview_url)
  assert_eq(captions_wire.status, 200)
  ignore(inputs.put_blob("delivery-caption.native.json", captions_wire.body))
  ignore(
    inputs.put_json("route-verification.json", {
      "fixture": "SYNTHETIC ONLY",
      "build": projection.to_json(),
      "newer_build": delivery_build_projection(fresh_built.build).to_json(),
      "distinct_actual_media": true,
      "range_resume_206_416_etag_verified": true,
      "exact_sidecars_verified": true,
      "historical_bytes_unchanged": true,
      "no_acceptance_or_publication": true,
    }),
  )
  println("Synthetic delivery media route fixture: " + root)
}
