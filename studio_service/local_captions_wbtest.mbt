///|
async test "local caption endpoint validates position before starting inference" {
  let service = StudioService::new("/tmp/mooncast-local-caption-invalid")
  let response = service.local_caption_response("p", "take", {
    request_method: Post,
    path: "/api/editor/projects/p/takes/take/local-captions",
    query: None,
    headers: Map([]),
    body: b"{\"start_ms\":-1,\"translate\":false}",
  })
  assert_eq(response.status, 422)
  assert_true(@utf8.decode(response.body).contains("24 hours"))
}

///|
async test "local Whisper transcribes real speech from a registered editor source" {
  guard @env.get_env_var("MOONCAST_LOCAL_CAPTION_TEST_AUDIO")
    is Some(audio_path) else {
    return
  }
  let root = @env.get_env_var("MOONCAST_LOCAL_CAPTION_TEST_ROOT").unwrap_or(
    "/tmp/mooncast-local-caption-" + @async.now().to_string(),
  )
  let service = StudioService::new(root)
  let project = editor_from_production_graph(
    @production_app.episode_production_graph(
      "caption-test", "Caption test", 180, 0.0,
    ),
  )
  ignore(
    service.create_editor_project({
      project,
      content_digest: "sha256:fixture",
      recorded_at: "2026-11-23T00:00:00Z",
    }),
  )
  let bytes = @fs.read_file(audio_path).binary()
  let digest = "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
  let prepared = service.prepare_editor_intake("caption-test", {
    expected_editor_revision: 0,
    idempotency_key: "speech-source",
    role: "voice",
    file_name: "speech.wav",
    mime_type: "audio/wav",
    size_bytes: bytes.length(),
    sha256: digest,
    duration_ticks: 8000,
    identity: project.identity_graph[0],
    rights: {
      confirmed: true,
      rights_ref: "rights:test",
      owner: "Synthetic test",
      basis: "original",
      territory: "worldwide",
      channels: ["local-test"],
    },
    source: { kind: "original", source_id: "synthetic:speech", },
    created_by: "local-test",
  })
  let upload = service.dispatch_http({
    request_method: Post,
    path: prepared.upload_url,
    query: None,
    headers: { "Content-Type": "audio/wav" },
    body: bytes,
  })
  assert_eq(upload.status, 201)
  let take = service.find_editor_take(
    "caption-test",
    "take-" + prepared.intake_id,
  )
  let template = take.add_clip_template.unwrap()
  ignore(
    service.dispatch_editor_command(
      "caption-test",
      {
        contract: "mooncast.editor-edit-command.v1",
        command_id: "place-speech",
        expected_revision: 0,
        actor: { actor_id: "local-test", provenance: "human", },
        operation: @editor_domain.Add(
          track_id=template.track_id,
          clip=template.clip,
        ),
      },
      "sha256:place-speech",
    ),
  )
  for translate in [false, true] {
    let started = @async.now()
    let body : Json = { "start_ms": 0, "translate": translate }
    let reply = service.dispatch_http({
      request_method: Post,
      path: "/api/editor/projects/caption-test/takes/take-" +
      prepared.intake_id +
      "/local-captions",
      query: None,
      headers: Map([]),
      body: @utf8.encode(body.stringify()),
    })
    let elapsed = @async.now() - started
    assert_eq(reply.status, 200, msg=@utf8.decode(reply.body))
    let value = @json.parse(@utf8.decode(reply.body))
    guard value is { "text": String(text), "srt": String(srt), .. } else {
      fail("Missing caption result")
    }
    let expected = @env.get_env_var(
      if translate {
        "MOONCAST_LOCAL_CAPTION_TEST_EXPECT_TRANSLATION"
      } else {
        "MOONCAST_LOCAL_CAPTION_TEST_EXPECT_SOURCE"
      },
    ).unwrap_or("moon")
    assert_true(text.to_lower().contains(expected.to_lower()), msg=text)
    assert_true(srt.contains("-->"))
    println(
      "Local caption translated=" +
      translate.to_string() +
      " elapsed_ms=" +
      elapsed.to_string() +
      " text=" +
      text.trim().to_owned(),
    )
    if translate {
      assert_false(
        text.iter().any(c => c is ('\u{4e00}'..<='\u{9fff}')),
        msg="English translation retained Chinese text: " + text,
      )
    }
  }
}
