///|
async test "transcript files import persist trim and render real captioned MP4 with SRT export" {
  let ffmpeg = @env.get_env_var("MOONCAST_FFMPEG_BIN").unwrap_or(
    "/usr/bin/ffmpeg",
  )
  let root = @env.get_env_var("MOONCAST_TRANSCRIPT_EVIDENCE").unwrap_or(
    "/tmp/mooncast-transcript-" + @async.now().to_string(),
  )
  let cases = [
    (
      "whisper-json", "application/json", "interview.json", b"{\"language\":\"en\",\"segments\":[{\"start\":0.25,\"end\":1.5,\"text\":\"Hello, world!\"},{\"start\":2.125,\"end\":4.75,\"text\":\"Second caption\"}]}",
    ),
    (
      "whisper-tsv", "text/tab-separated-values", "interview.tsv", b"start\tend\ttext\n250\t1500\tHello, world!\n2125\t4750\tSecond caption\n",
    ),
    (
      "audacity-labels", "text/plain", "labels.txt", b"0.250000\t1.500000\tHello, world!\n2.125000\t4.750000\tSecond caption\n",
    ),
  ]
  for (id, mime, filename, bytes) in cases {
    let directory = root +
      "/transcript-proof-" +
      id +
      "-" +
      @async.now().to_string()
    let service = StudioService::new(directory)
    let graph = @production_app.episode_production_graph(
      id, "Synthetic offline transcript fixture", 180, 0.0,
    )
    let base = editor_from_production_graph(graph)
    let project = {
      ..base,
      timeline: {
        ..base.timeline,
        output: { ..base.timeline.output, width: 320, height: 180, },
      },
    }
    ignore(
      service.create_editor_project({
        project,
        content_digest: "sha256:fixture",
        recorded_at: "2026-10-08T00:00:00Z",
      }),
    )
    let digest = "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    let request : EditorPrepareIntakeRequest = {
      expected_editor_revision: 0,
      idempotency_key: "transcript-source",
      role: "subtitle",
      file_name: filename,
      mime_type: mime,
      size_bytes: bytes.length(),
      sha256: digest,
      duration_ticks: 5000,
      identity: project.identity_graph[0],
      rights: {
        confirmed: true,
        rights_ref: "rights:synthetic",
        owner: "Synthetic fixture author",
        basis: "original",
        territory: "worldwide",
        channels: ["local-test"],
      },
      source: { kind: "original", source_id: "fixture:" + filename, },
      created_by: "synthetic-editor",
    }
    let prepared = service.prepare_editor_intake(id, request)
    // Exercise the same content-upload route used by the compiled file picker.
    let uploaded = service.dispatch_http({
      request_method: Post,
      path: prepared.upload_url,
      query: None,
      headers: { "Content-Type": mime },
      body: bytes,
    })
    assert_eq(uploaded.status, 201)
    let reopened = StudioService::new(directory)
    assert_eq(reopened.editor_media.bytes(digest).unwrap(), bytes)
    let take = reopened.find_editor_take(id, "take-" + prepared.intake_id)
    let template = take.add_clip_template.unwrap()
    let placed = reopened.dispatch_editor_command(
      id,
      {
        contract: "mooncast.editor-edit-command.v1",
        command_id: "place-transcript",
        expected_revision: 0,
        actor: { actor_id: "synthetic-editor", provenance: "human", },
        operation: @editor_domain.Add(
          track_id=template.track_id,
          clip=template.clip,
        ),
      },
      "sha256:add-fixture",
    )
    let edited = reopened.dispatch_editor_command(
      id,
      {
        contract: "mooncast.editor-edit-command.v1",
        command_id: "trim-transcript",
        expected_revision: placed.revision,
        actor: { actor_id: "synthetic-editor", provenance: "human", },
        operation: @editor_domain.Trim(
          clip_id=template.clip.clip_id,
          source_in_tick=250,
          source_out_tick=4750,
          start_tick=Some(0),
        ),
      },
      "sha256:trim-fixture",
    )
    let plan = @editor_plan.freeze(
      edited.snapshot,
      edited.media_bindings,
      "export",
    )
    assert_true(plan.ready)
    assert_eq(plan.range.duration_ticks, 4500)
    let sidecar = @editor_render.subtitle_sidecar(plan)
    assert_eq(sidecar.cue_count, 2)
    assert_true(sidecar.content.contains("00:00:00,000 --> 00:00:01,250"))
    assert_true(sidecar.content.contains("00:00:01,875 --> 00:00:04,500"))
    let media = reopened.materialize_plan_media(plan)
    assert_eq(media.length(), 1)
    assert_true(media[0].path.has_suffix(".srt"))
    let files = @host_store.AtomicStore::new(directory + "/proof")
    ignore(files.put_blob(filename, bytes))
    ignore(files.put_blob("captions.srt", @utf8.encode(sidecar.content)))
    ignore(files.put_json("edited-project.json", edited.snapshot.to_json()))
    ignore(files.put_json("render-plan.json", plan.to_json()))
    let output = files.prepare_owned_path("captioned.mp4")
    let invocation = @editor_render.compile(ffmpeg, plan, media, output)
    let rendered = @editor_render.execute(invocation)
    ignore(files.put_json("render-receipt.json", rendered.to_json()))
    assert_true(rendered.succeeded, msg="real FFmpeg render must succeed")
    assert_true(files.get_blob("captioned.mp4").unwrap().bytes.length() > 1000)
    let extracted = @process.run_capture({
      executable: ffmpeg,
      arguments: [
        "-v", "error", "-i", output, "-map", "0:s:0", "-f", "srt", "-",
      ],
      working_directory: None,
      timeout_ms: 30000,
      max_output_bytes: 1048576,
    })
    assert_eq(extracted.exit_code, Some(0))
    ignore(files.put_blob("embedded-captions.srt", extracted.stdout))
    let embedded = @editor_media.parse_subtitles(
      extracted.stdout,
      "application/x-subrip",
      4500,
      1000,
    )
    let expected = @editor_media.parse_subtitles(
      @utf8.encode(sidecar.content),
      "application/x-subrip",
      4500,
      1000,
    )
    assert_eq(embedded.cues, expected.cues)
    assert_eq(reopened.editor_media.bytes(digest).unwrap(), bytes)
    // A trim wholly inside a gap remains renderable without a subtitle input.
    let empty_clip = {
      ..plan.tracks[3].clips[0],
      start_tick: 0,
      source_in_tick: 1600,
      source_out_tick: 1800,
      duration_ticks: 200,
    }
    let gap = {
      ..plan,
      range: { start_tick: 0, duration_ticks: 200, },
      tracks: [{ ..plan.tracks[3], clips: [empty_clip], }],
    }
    assert_eq(@editor_render.subtitle_sidecar(gap).cue_count, 0)
    let gap_media = reopened.materialize_plan_media(gap)
    assert_true(gap_media.is_empty())
    let gap_invocation = @editor_render.compile(
      ffmpeg,
      gap,
      gap_media,
      files.prepare_owned_path("gap.mp4"),
    )
    assert_false(gap_invocation.arguments.contains("-i"))
    assert_true(@editor_render.execute(gap_invocation).succeeded)
    println(
      id +
      " retained source, persisted upload, trimmed captions, real MP4 and exact embedded/SRT timings passed: " +
      directory,
    )
  }
}
