///|
fn acceptance_adapter(
  capability : String,
  provider : String,
  model : String,
) -> @execution_app.ProviderAdapterConfig {
  {
    adapter_id: "acceptance-" + capability,
    capability,
    provider,
    endpoint: "https://fixture.invalid/" + capability,
    model,
    api_style: "mooncast-deterministic-ffmpeg-v1",
    secret_refs: {},
    timeout_seconds: 120,
    max_response_bytes: 67108864,
    default_parameters: {},
    commercial_use: "validation-only",
    network_authority: false,
  }
}

///|
async fn acceptance_approve_creative(
  service : StudioService,
  project_id : String,
  kind : @creative.ArtifactKind,
  actor : String,
  role : String,
) -> Unit {
  let record = service.get_project(project_id)
  guard current_creative(record.snapshot, kind) is Some(artifact) else {
    fail("creative artifact missing")
  }
  let response = service.record_creative_decision(project_id, {
    expected_revision: record.snapshot.revision,
    command_id: "acceptance-approve-" + kind.to_string(),
    recorded_at: "2026-07-19T12:10:00+08:00",
    evidence_digest: "sha256:acceptance-" + kind.to_string(),
    decision: {
      artifact: artifact.reference,
      decision: "approved",
      actor,
      role,
      decided_at: "2026-07-19T12:10:00+08:00",
      note: "Acceptance fixture named-human approval",
    },
  })
  assert_true(response.result.ok)
}

///|
async fn acceptance_approve_master(
  service : StudioService,
  project_id : String,
  kind : String,
  actor : String,
  role : String,
) -> Unit {
  let record = service.get_project(project_id)
  guard record.snapshot.master is Some(master) else {
    fail("canonical master missing")
  }
  let response = service.record_master_decision_feature(project_id, kind, {
    expected_project_revision: record.snapshot.revision,
    expected_master_version: master.reference.version,
    expected_master_digest: master.reference.digest,
    human_confirmed: true,
    actor,
    actor_role: role,
    decision: "approve",
    note: "Acceptance fixture exact master approval",
  })
  assert_true(response.result.ok)
}

///|
fn acceptance_asset_spec(
  asset_id : String,
  kind : String,
  capability : String,
  shot_ids : Array[String],
) -> @asset_factory.ReusableAssetSpec {
  {
    asset_id,
    asset_version: 1,
    kind,
    capability,
    title: "Acceptance " + asset_id,
    intent: {
      source_id: "moonwiki-" + asset_id,
      source_version: "1",
      source_digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
      provenance_ref: "moonwiki://acceptance/" + asset_id,
    },
    prompt_digest: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    source_asset_refs: [],
    rights_refs: ["rights://acceptance/" + asset_id],
    continuity_key: "acceptance:" + asset_id,
    provider_adapter_id: "acceptance-" + capability,
    provider: "mooncast-local",
    model: "deterministic-" + capability + "-v1",
    permitted_data_class: "rights-cleared-validation",
    variant_limit: 1,
    retry_limit: 2,
    cost_ceiling_cny: 0.0,
    dependent_shot_ids: shot_ids,
  }
}

///|
async test "Studio to Cut Editor to Client Review produces a governed 180 second episode" {
  let root = "/tmp/mooncast-ui-to-ui-validation-" + @async.now().to_string()
  let video_provider = "mooncast-local"
  let video_model = "deterministic-video-v1"
  let catalog : @execution_app.ProviderCatalog = {
    contract: "mooncast.provider-catalog.v1",
    adapters: [
      acceptance_adapter("image", "mooncast-local", "deterministic-image-v1"),
      acceptance_adapter("voice", "mooncast-local", "deterministic-voice-v1"),
      acceptance_adapter("music", "mooncast-local", "deterministic-music-v1"),
      acceptance_adapter("video", video_provider, video_model),
    ],
    authority_actors: ["acceptance-producer", "creative-director"],
  }
  let service = StudioService::new(root, provider_catalog=catalog)
  let packet = needs_packet_fixture()
  let validation = @intake.validate_intake(packet)
  ignore(
    service.needs_intake.import_packet(packet, "2026-07-19T12:01:00+08:00"),
  )
  ignore(
    service.needs_intake.record_decision(packet.packet_id, {
      packet_version: packet.packet_version,
      expected_provenance_digest: validation.provenance_digest,
      decision: "approve",
      actor: "creative-director",
      actor_role: "creative-director",
      note: "Approved exact MoonWiki needs packet",
      decided_at: "2026-07-19T12:02:00+08:00",
      human_confirmed: true,
    }),
  )
  ignore(
    service.seed_project_from_intake(packet.packet_id, {
      packet_version: packet.packet_version,
      expected_provenance_digest: validation.provenance_digest,
      project_id: "acceptance-episode",
      recorded_at: "2026-07-19T12:03:00+08:00",
    }),
  )
  let project_id = "acceptance-episode"
  acceptance_approve_creative(
    service,
    project_id,
    @creative.Brief,
    "creative-director",
    "creative-director",
  )
  acceptance_approve_creative(
    service,
    project_id,
    @creative.RightsLedger,
    "rights-reviewer",
    "rights-compliance",
  )
  acceptance_approve_creative(
    service,
    project_id,
    @creative.IpBible,
    "creative-director",
    "creative-director",
  )
  acceptance_approve_creative(
    service,
    project_id,
    @creative.Script,
    "creative-director",
    "creative-director",
  )
  acceptance_approve_creative(
    service,
    project_id,
    @creative.ClaimsLedger,
    "claims-reviewer",
    "rights-compliance",
  )
  let after_g2 = service.get_project(project_id)
  assert_true(gate_recorded(after_g2.snapshot, "G2"))
  let shot_ids = @project.flattened_shots(after_g2.snapshot.graph).map(shot => {
    shot.shot_id
  })
  assert_eq(shot_ids.length(), 15)
  let plan_base : @asset_factory.AssetFactoryPlan = {
    contract: "mooncast.asset-factory-plan.v1",
    plan: { id: "acceptance-assets", version: 1, digest: "" },
    project_id,
    project_revision: after_g2.snapshot.revision,
    specs: [
      acceptance_asset_spec("hero", "character", "image", shot_ids),
      acceptance_asset_spec("narrator", "voice", "voice", shot_ids),
      acceptance_asset_spec("score", "music", "music", shot_ids),
    ],
    total_cost_ceiling_cny: 0.0,
    created_at: "2026-07-19T12:20:00+08:00",
    publication_authority: false,
    provider_execution_authority: false,
  }
  let asset_plan = {
    ..plan_base,
    plan: { ..plan_base.plan, digest: @asset_factory.plan_digest(plan_base) },
  }
  ignore(
    service.asset_factory.record_plan(
      asset_plan,
      after_g2.snapshot.graph,
      after_g2.snapshot.revision,
    ),
  )
  ignore(
    service.asset_factory.decide_plan(project_id, {
      expected_plan_version: 1,
      expected_plan_digest: asset_plan.plan.digest,
      decision: "approve",
      actor: "creative-director",
      actor_role: "creative-director",
      note: "Approved exact reusable asset plan",
      decided_at: "2026-07-19T12:21:00+08:00",
      human_confirmed: true,
    }),
  )
  let variants = service.asset_factory.run_pending(project_id, {
    expected_plan_version: 1,
    expected_plan_digest: asset_plan.plan.digest,
    actor: "creative-director",
    human_confirmed: true,
    network_authority: true,
  })
  assert_eq(variants.length(), 3)
  for variant in variants {
    for dimension in @asset_factory.required_qc_dimensions() {
      ignore(
        service.asset_factory.record_finding({
          variant_id: variant.variant_id,
          dimension,
          status: "pass",
          evidence_digest: variant.output_digest.unwrap() + ":" + dimension,
          reviewer: "continuity-reviewer",
          reviewer_role: "human-reviewer",
          reviewed_at: "2026-07-19T12:22:00+08:00",
          human_confirmed: true,
        }),
      )
    }
    ignore(
      service.asset_factory.approve_asset({
        asset_id: variant.asset_id,
        asset_version: variant.asset_version,
        variant_id: variant.variant_id,
        actor: "creative-director",
        actor_role: "creative-director",
        approved_at: "2026-07-19T12:23:00+08:00",
        human_confirmed: true,
      }),
    )
  }
  ignore(
    service.asset_factory.bind_approved_assets(
      project_id,
      asset_plan.project_revision,
      shot_ids,
      "2026-07-19T12:24:00+08:00",
    ),
  )
  let approved_assets = service.asset_factory.workspace(project_id).approved_assets.map(value => {
      value.reference
    },
  )
  let canonical = service.get_project(project_id)
  let bible = current_creative(canonical.snapshot, @creative.IpBible).unwrap()
  let script = current_creative(canonical.snapshot, @creative.Script).unwrap()
  let storyboard = current_creative(canonical.snapshot, @creative.Storyboard).unwrap()
  let panels : Array[@animatic.StoryboardPanel] = []
  for episode in canonical.snapshot.graph.episodes {
    for scene in episode.scenes {
      for shot in scene.shots {
        panels.push({
          panel_id: "panel-" + shot.shot_id,
          scene_id: scene.scene_id,
          shot_id: shot.shot_id,
          order: shot.order,
          duration_ms: shot.duration_ms,
          caption: "Evidence-bound scene " + shot.order.to_string(),
          visual_asset_ids: ["hero"],
          transition: "cut",
        })
      }
    }
  }
  let animatic_base : @animatic.AnimaticPlan = {
    contract: "mooncast.animatic-plan.v1",
    reference: { id: "acceptance-animatic-plan", version: 1, digest: "" },
    project_id,
    project_revision: canonical.snapshot.revision,
    bible: bible.reference,
    script: script.reference,
    storyboard: storyboard.reference,
    panels,
    approved_assets,
    temporary_voice_asset_ids: ["narrator"],
    temporary_music_asset_ids: ["score"],
    caption_language: "zh-CN",
    provider: "mooncast-native-storyboard",
    model: "deterministic-animatic-v1",
    cost_ceiling_cny: 10.0,
    retry_limit: 2,
    created_at: "2026-07-19T12:30:00+08:00",
    process_authority: false,
    publication_authority: false,
  }
  let animatic_plan = {
    ..animatic_base,
    reference: {
      ..animatic_base.reference,
      digest: @animatic.plan_digest(animatic_base),
    },
  }
  ignore(service.record_animatic_plan(project_id, { plan: animatic_plan }))
  let rendered = service.animatic.render(project_id, {
    expected_plan_version: 1,
    expected_plan_digest: animatic_plan.reference.digest,
    actor: "creative-director",
    rendered_at: "2026-07-19T12:31:00+08:00",
    human_confirmed: true,
    process_authority: true,
  })
  assert_eq(rendered.duration_seconds, 180)
  ignore(
    service.approve_rendered_animatic(project_id, {
      expected_render_version: rendered.reference.version,
      expected_render_digest: rendered.reference.digest,
      actor: "creative-director",
      actor_role: "creative-director",
      note: "Approved exact rendered 180 second animatic",
      approved_at: "2026-07-19T12:32:00+08:00",
      human_confirmed: true,
    }),
  )
  acceptance_approve_creative(
    service,
    project_id,
    @creative.Storyboard,
    "creative-director",
    "creative-director",
  )
  let before_routing = service.get_project(project_id)
  let route : @governance.ModelRoute = {
    route_id: "acceptance-video-route",
    shot_ids,
    asset_kind: "video",
    provider: video_provider,
    model: video_model,
    model_version: "1",
    permitted_data_class: "rights-cleared-validation",
    cost_ceiling_cny: 1.0,
    fallback_route_ids: [],
    retry_limit: 2,
  }
  let planned = service.record_routing_plan_feature(project_id, {
    expected_project_revision: before_routing.snapshot.revision,
    expected_plan_version: None,
    expected_plan_digest: None,
    routes: [route],
    total_cost_ceiling_cny: 15.0,
    actor: "acceptance-producer",
    human_confirmed: true,
  })
  let routing = planned.project.snapshot.routing_plan.unwrap()
  let producer_decision = service.record_routing_decision_feature(project_id, {
    expected_project_revision: planned.project.snapshot.revision,
    expected_plan_version: routing.reference.version,
    expected_plan_digest: routing.reference.digest,
    human_confirmed: true,
    actor: "acceptance-producer",
    actor_role: "producer",
    decision: "approve",
    note: "Approved exact local validation route",
  })
  let finance_decision = service.record_routing_decision_feature(project_id, {
    expected_project_revision: producer_decision.project.snapshot.revision,
    expected_plan_version: routing.reference.version,
    expected_plan_digest: routing.reference.digest,
    human_confirmed: true,
    actor: "acceptance-finance",
    actor_role: "finance",
    decision: "approve",
    note: "Approved exact validation ceiling",
  })
  assert_true(gate_recorded(finance_decision.project.snapshot, "G3"))
  let asset_map = service.approved_asset_map(
    project_id,
    finance_decision.project.snapshot.revision,
  )
  let exact_animatic = service.approved_rendered_animatic(project_id).unwrap()
  let routed = service.execution_application.create_routed_from_catalog(
    finance_decision.project.snapshot.graph,
    routing,
    "acceptance-producer",
    "sha256:acceptance-production-binding",
    true,
    approved_assets_by_shot=asset_map,
    approved_animatic_digest=exact_animatic.rendered.video_digest,
  ) catch {
    error => fail("\{Repr(error)}")
  }
  let run = service.run_pending_shots_feature(
    project_id,
    routed.execution.execution_id,
    {
      expected_project_revision: finance_decision.project.snapshot.revision,
      expected_execution_revision: routed.execution.revision,
      expected_execution_digest: routed.execution.record_digest,
      actor_id: "acceptance-producer",
      human_confirmed: true,
    },
  )
  assert_eq(run.executed_shots, 15)
  let generated = service.get_project(project_id)
  let output_bindings = generated.snapshot.generation_attempts.map(attempt => {
    shot_id: attempt.shot_id,
    output_digest: attempt.output_digest,
  })
  let qc = service.confirm_batch_qc_feature(project_id, {
    expected_project_revision: generated.snapshot.revision,
    expected_routing_plan_version: routing.reference.version,
    expected_routing_plan_digest: routing.reference.digest,
    shot_outputs: output_bindings,
    evidence_digest: "sha256:acceptance-human-qc-batch",
    note: "Reviewed technical continuity safety claims and rights evidence",
    actor: "acceptance-qc-reviewer",
    actor_role: "human-reviewer",
    human_confirmed: true,
  })
  assert_true(qc.g4_approved)
  let imported = service.import_editor_from_canonical_project(project_id)
  assert_eq(timeline_duration(imported.snapshot), 180000)
  let restarted = StudioService::new(root, provider_catalog=catalog)
  let opened = restarted.get_editor_project(project_id)
  assert_eq(timeline_duration(opened.snapshot), 180000)
  let export_job_id = "acceptance-master-export"
  let export_job = restarted.create_editor_export(project_id, {
    idempotency_key: export_job_id,
    export_request: {
      job_id: export_job_id,
      request_id: export_job_id,
      expected_editor_revision: opened.revision,
      quality: "original",
      range: { start_tick: 0, duration_ticks: 180000 },
      max_attempts: 2,
      spec: {
        width: 320,
        height: 180,
        fps: { numerator: 24, denominator: 1 },
        container: "mp4",
        video_codec: "h264",
        audio_codec: "aac",
        subtitle_mode: "embedded-and-sidecar",
        ai_label_mode: "retain-visible",
        retain_sources: true,
        cost_ceiling: "10.0",
      },
    },
  })
  assert_eq(export_job.job.state, "succeeded")
  guard export_job.export_receipt is Some(export_receipt) &&
    opened.production_source is Some(production_source) else {
    fail("completed export and exact production source are required")
  }
  let before_promotion = restarted.get_project(project_id)
  let promotion = restarted.promote_editor_master(project_id, export_job_id, {
    request: {
      job_id: export_job_id,
      expected_project_revision: before_promotion.snapshot.revision,
      actor: "creative-director",
      authority_ref: "authority://acceptance/master-promotion",
    },
    production_source,
    master_id: "acceptance-master-1",
    subtitle_ref: "/api/editor/projects/acceptance-episode/exports/acceptance-master-export/subtitles",
    promoted_at: "2026-07-19T13:00:00+08:00",
  })
  assert_eq(promotion.digest, export_receipt.digest)
  let master_path = restarted.editor_export_path_for_digest(
    project_id,
    promotion.digest,
  )
  assert_true(@fs.exists(master_path))
  acceptance_approve_master(
    restarted, project_id, "technical-qc", "technical-reviewer", "technical-qc",
  )
  acceptance_approve_master(
    restarted, project_id, "creative-director", "creative-director", "creative-director",
  )
  acceptance_approve_master(
    restarted, project_id, "rights-compliance", "rights-reviewer", "rights-compliance",
  )
  let before_delivery = restarted.get_project(project_id)
  let canonical_master = before_delivery.snapshot.master.unwrap()
  let delivery_response = restarted.record_delivery_package_feature(
    project_id,
    {
      expected_project_revision: before_delivery.snapshot.revision,
      expected_master_version: canonical_master.reference.version,
      expected_master_digest: canonical_master.reference.digest,
      expected_delivery_version: None,
      expected_delivery_digest: None,
      destination_ids: ["client-review"],
      manifest_digest: "sha256:acceptance-delivery-manifest",
      rights_ledger_digest: "sha256:acceptance-rights-ledger",
      human_confirmed: true,
      actor: "delivery-producer",
    },
  )
  let delivery = delivery_response.project.snapshot.delivery_package.unwrap()
  let queued_build = restarted.create_delivery_from_ui(project_id, {
    expected_project_revision: delivery_response.project.snapshot.revision,
    expected_master_sha256: canonical_master.video_digest,
    expected_delivery_version: delivery.reference.version,
    expected_delivery_digest: delivery.reference.digest,
    profile: {
      contract: "mooncast.delivery-build-profile.v1",
      version: 1,
      include_source_master: true,
      variants: [],
      cuts: [],
      covers: [],
      include_subtitles: false,
      include_metadata: true,
      include_provenance_rights_ai_manifest: true,
    },
  })
  let completed_build = restarted.run_delivery_action_from_ui(
    project_id,
    queued_build.build_id,
    "build",
    {
      expected_build_revision: queued_build.revision,
      expected_record_digest: queued_build.record_digest,
      actor: "delivery-producer",
    },
  )
  assert_eq(completed_build.state, "completed")
  let portal = restarted.create_client_portal_from_ui(project_id, {
    expected_project_revision: delivery_response.project.snapshot.revision,
    expected_master_sha256: canonical_master.video_digest,
    build_id: completed_build.build_id,
    expected_build_digest: completed_build.build_digest,
    expected_build_record_digest: completed_build.record_digest,
    client_name: "Acceptance Client",
    brand_name: "Mooncast Acceptance",
    brand_accent: "#5b5ce2",
    expires_at: "2099-12-31T23:59:59+08:00",
    human_confirmed: true,
    actor: "delivery-producer",
    actor_role: "delivery-producer",
  })
  assert_true(portal.raw_token_returned_once)
  let token = portal.client_url[8:].to_owned()
  let client_surface = restarted.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/client/" + token,
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(client_surface.status, 200)
  ignore(
    restarted.record_client_annotation_from_ui(token, {
      expected_master_sha256: completed_build.master_sha256,
      expected_build_digest: completed_build.build_digest,
      timecode_seconds: 24.0,
      author: "Acceptance Client",
      body: "Reviewed exact episode timing and visual continuity",
    }),
  )
  ignore(
    restarted.record_client_decision_from_ui(token, {
      expected_master_sha256: completed_build.master_sha256,
      expected_build_digest: completed_build.build_digest,
      human_confirmed: true,
      actor: "Acceptance Client",
      decision: "accept",
      note: "Accepted exact master and delivery package",
    }),
  )
  let accepted = restarted.get_project(project_id)
  assert_true(gate_recorded(accepted.snapshot, "G5"))
  let studio_surface = restarted.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/v2/projects/" + project_id,
    query: None,
    headers: {},
    body: b"",
  })
  let editor_surface = restarted.dispatch_http({
    request_method: @host_http.Get,
    path: "/api/editor/projects/" + project_id,
    query: None,
    headers: {},
    body: b"",
  })
  assert_eq(studio_surface.status, 200)
  assert_eq(editor_surface.status, 200)
  let source_ref : @handoff.RecordRef = {
    record_id: project_id +
    "-production-source-r" +
    production_source.production_revision.to_string(),
    record_version: production_source.production_revision.to_string(),
    record_digest: production_source.binding_digest,
    provenance_ref: production_source.provenance_ref,
  }
  let handoff = restarted.submit_editor_handoff_request(
    project_id,
    export_job_id,
    {
      candidate_id: Some("acceptance-deliverable"),
      candidate_version: Some("1"),
      workflow_ref: {
        record_id: "moonflow-acceptance-workflow",
        record_version: "1",
        record_digest: "sha256:acceptance-workflow",
        provenance_ref: "moonflow://acceptance/workflow",
      },
      ability_ref: {
        record_id: "mooncode-acceptance-ability",
        record_version: "1",
        record_digest: "sha256:acceptance-ability",
        provenance_ref: "mooncode://acceptance/ability",
      },
      intake_authority_ref: source_ref,
      episode_id: production_source.episode_id,
      submitted_at: Some("2026-07-19T13:30:00+08:00"),
    },
  )
  assert_true(handoff.created)
  assert_true(
    restarted.handoff_outbox.get(
      "bookkeeper-ingress-bundle", "acceptance-deliverable-moonflow-handoff",
    )
    is Some(_),
  )
  println("mooncast acceptance root: " + root)
  println("mooncast acceptance master: " + master_path)
}
