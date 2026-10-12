///|
async fn assert_cut_caption_delivery(
  service : StudioService,
  project_id : String,
  root : String,
  original_archive : @host_store.StoredBlob,
  original_archive_name : String,
) -> Unit {
  let selected = service.verified_delivery_captions(project_id)
  let cut = delivery_caption_cut("1000", "4000")
  let cut_selected = service.verified_delivery_cut_captions(project_id, cut)
  let portrait_selected = service.verified_delivery_cut_captions(
    project_id,
    delivery_caption_cut("13000", "16750"),
  )
  let page = service.dispatch_http({
    request_method: Get,
    path: "/api/v2/projects/" +
    project_id +
    "/delivery-captions/cut/1000/4000/view",
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(page.status, 200)
  assert_true(
    @utf8.decode(page.body).contains("Selected captions for this cut"),
  )
  assert_true(
    @utf8.decode(page.body).contains(
      workspace_html_escape(@utf8.decode(cut_selected.bytes)),
    ),
  )
  let download = service.dispatch_http({
    request_method: Get,
    path: ledger_text(cut_selected.metadata, "download_url"),
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(download.status, 200)
  assert_eq(download.body, cut_selected.bytes)
  assert_true(
    service.dispatch_http({
      request_method: Get,
      path: "/api/v2/projects/" +
      project_id +
      "/delivery-captions/cut/1000/4000/stale/download",
      query: None,
      headers: {},
      body: b"",
    }).status >=
    400,
  )
  let invalid_page = service.dispatch_http({
    request_method: Get,
    path: "/api/v2/projects/" +
    project_id +
    "/delivery-captions/cut/4000/4000/view",
    query: None,
    headers: {},
    body: b"",
  })
  assert_true(@utf8.decode(invalid_page.body).contains("positive duration"))
  assert_false(
    @utf8.decode(invalid_page.body).contains("Download selected SRT"),
  )
  let canonical = service.get_project(project_id)
  let master = canonical.snapshot.master.unwrap()
  let delivery = canonical.snapshot.delivery_package.unwrap()
  let input : DeliveryCreateInput = {
    expected_project_revision: canonical.snapshot.revision,
    expected_master_sha256: master.video_digest,
    expected_delivery_version: delivery.reference.version,
    expected_delivery_digest: delivery.reference.digest,
    profile: {
      contract: "mooncast.delivery-build-profile.v1",
      version: 1,
      include_source_master: true,
      variants: [
        {
          variant_id: "vertical-1080p",
          orientation: "vertical",
          width: 240,
          height: 320,
          policy: "crop",
        },
      ],
      cuts: [
        {
          cut_id: "selected-cut",
          channel: "review-only",
          source_variant: "master",
          in_seconds: 1.0,
          out_seconds: 4.0,
        },
        {
          cut_id: "portrait-teaser",
          channel: "shorts-review",
          source_variant: "vertical-1080p",
          in_seconds: 13.0,
          out_seconds: 16.75,
        },
      ],
      covers: [],
      include_subtitles: true,
      include_metadata: true,
      include_provenance_rights_ai_manifest: true,
    },
  }
  for
    invalid in [
      {
        ..input,
        profile: {
          ..input.profile,
          cuts: [input.profile.cuts[0], input.profile.cuts[0]],
        },
      },
      {
        ..input,
        profile: {
          ..input.profile,
          cuts: [{ ..input.profile.cuts[0], out_seconds: 181.0, }],
        },
      },
    ] {
    let rejected = service.dispatch_http({
      request_method: Post,
      path: "/api/v2/projects/" + project_id + "/delivery-builds",
      query: None,
      headers: {},
      body: @utf8.encode(invalid.to_json().stringify()),
    })
    assert_true(rejected.status >= 400)
  }
  let created = service.dispatch_http({
    request_method: Post,
    path: "/api/v2/projects/" + project_id + "/delivery-builds",
    query: None,
    headers: {},
    body: @utf8.encode(input.to_json().stringify()),
  })
  assert_eq(created.status, 201)
  let response_json = @json.parse(@utf8.decode(created.body))
  let projection = delivery_build_projection(
    service.delivery_application
    .load(ledger_text(response_json, "build_id"))
    .unwrap().build,
  )
  let complete = service.run_delivery_action_from_ui(
    project_id,
    projection.build_id,
    "build",
    {
      expected_build_revision: projection.revision,
      expected_record_digest: projection.record_digest,
      actor: "synthetic-cut-producer",
    },
  )
  assert_eq(complete.state, "completed")
  let files = @host_store.AtomicStore::new(
    root + "/application/delivery/outputs",
  )
  let caption_name = complete.build_id + "-selected-cut-subtitles.srt"
  assert_eq(files.get_blob(caption_name).unwrap().bytes, cut_selected.bytes)
  assert_eq(
    files
    .get_blob(complete.build_id + "-portrait-teaser-subtitles.srt")
    .unwrap().bytes,
    portrait_selected.bytes,
  )
  assert_true(cut_selected.bytes != portrait_selected.bytes)
  let built_record = service.delivery_application
    .load(complete.build_id)
    .unwrap()
  let portrait_output = built_record.request.profile.outputs
    .iter()
    .find_first(output => output.output_id == "portrait-teaser")
    .unwrap()
  assert_eq(portrait_output.width, 240)
  assert_eq(portrait_output.height, 320)
  let metadata = files.get_json(complete.build_id + "-metadata.json").unwrap()
  assert_eq(
    json_member(metadata, "delivery_profile"),
    Some(input.profile.to_json()),
  )
  assert_eq(
    service.verified_delivery_captions(project_id).bytes,
    selected.bytes,
  )
  assert_eq(
    files.get_blob(original_archive_name).unwrap().bytes,
    original_archive.bytes,
  )
  let evidence = @host_store.AtomicStore::new(root + "/cut-caption-evidence")
  ignore(evidence.put_blob("cut-preview.html", page.body))
  ignore(evidence.put_blob("selected-cut-subtitles.srt", cut_selected.bytes))
  ignore(evidence.put_json("caption-selection.json", cut_selected.metadata))
  ignore(
    evidence.put_json(
      "build.json",
      service.delivery_application.load(complete.build_id).unwrap().to_json(),
    ),
  )
}
