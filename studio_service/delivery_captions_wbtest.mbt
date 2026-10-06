///|
async test "delivery captions missing state gives a concrete repair action" {
  let service = StudioService::new(
    "/tmp/mooncast-caption-missing-" + @async.now().to_string(),
  )
  let graph = @production_app.episode_production_graph(
    "caption-empty", "SYNTHETIC caption fixture", 180, 5000.0,
  )
  ignore(service.create_project(graph, "2026-10-04T00:00:00Z"))
  let response = service.dispatch_http({
    request_method: Get,
    path: "/api/v2/projects/caption-empty/delivery-captions/view",
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(response.status, 200)
  let html = @utf8.decode(response.body)
  assert_true(html.contains("Verified captions need attention"))
  assert_true(html.contains("Open Cut Editor"))
  assert_false(html.contains("Download selected SRT"))
  assert_true(
    service.dispatch_http({
      request_method: Get,
      path: "/api/v2/projects/caption-empty/delivery-captions/download",
      query: None,
      headers: {},
      body: b"",
    }).status >=
    400,
  )
}

///|
async fn assert_caption_provenance_rejections(
  service : StudioService,
  project_id : String,
  job_id : String,
) -> Unit {
  let promotion = service.latest_editor_promotion(project_id).unwrap()
  let promotion_key = editor_latest_promotion_key(project_id)
  save_value(service.store, promotion_key, {
    ..promotion,
    digest: "sha256:stale-export",
  })
  try service.verified_delivery_captions(project_id) catch {
    _ => ()
  } noraise {
    _ => fail("Stale export promotion must not select captions")
  }
  save_value(service.store, promotion_key, {
    ..promotion,
    project_id: "foreign-project",
  })
  // A foreign index is ignored; the immutable exact-project receipt remains
  // a valid migration fallback. No foreign caption is substituted.
  assert_eq(
    ledger_text(
      service.verified_delivery_captions(project_id).metadata,
      "project_id",
    ),
    project_id,
  )
  let historical_key = editor_promotion_key(project_id, promotion.master_id)
  save_value(service.store, historical_key, {
    ..promotion,
    project_id: "foreign-project",
  })
  try service.verified_delivery_captions(project_id) catch {
    _ => ()
  } noraise {
    _ => fail("Foreign export promotion must not select captions")
  }
  save_value(service.store, historical_key, promotion)
  save_value(service.store, promotion_key, promotion)
  let job = service.get_editor_job(project_id, job_id)
  let tracks = job.render_plan.tracks.map(track => {
    ..track,
    clips: track.clips.map(clip => {
      match clip.local_media {
        Some(binding) if binding.role == "subtitle" =>
          {
            ..clip,
            local_media: Some({ ..binding, project_id: "foreign-project", }),
          }
        _ => clip
      }
    }),
  })
  save_value(service.store, editor_job_key(project_id, job_id), {
    ..job,
    render_plan: { ..job.render_plan, tracks, },
  })
  try service.verified_delivery_captions(project_id) catch {
    _ => ()
  } noraise {
    _ => fail("Foreign subtitle asset must not be selected")
  }
  save_value(service.store, editor_job_key(project_id, job_id), job)
  let key = editor_subtitle_key(project_id, job_id)
  let original = service.editor_render_files.get_blob(key).unwrap()
  ignore(service.editor_render_files.remove(key))
  try service.verified_delivery_captions(project_id) catch {
    _ => ()
  } noraise {
    _ => fail("Missing subtitle bytes must not be selected")
  }
  ignore(service.editor_render_files.put_blob(key, original.bytes))
  assert_eq(
    service.verified_delivery_captions(project_id).bytes,
    original.bytes,
  )
}
