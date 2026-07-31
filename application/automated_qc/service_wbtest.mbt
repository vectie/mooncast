///|
fn analyzer_adapter() -> @execution_app.ProviderAdapterConfig {
  {
    adapter_id: "fixture-qc-identity",
    capability: "qc-identity",
    provider: "fixture-qc",
    endpoint: "https://fixture.invalid/qc",
    model: "fixture-identity-v1",
    api_style: "mooncast-deterministic-ffmpeg-v1",
    secret_refs: {},
    timeout_seconds: 10,
    max_response_bytes: 1048576,
    default_parameters: {},
    commercial_use: "validation-only",
    network_authority: false,
  }
}

///|
fn analyzer_task(
  analyzer : String,
  version : Int,
  mode : String,
) -> @qc_domain.AnalyzerTask {
  let semantic = mode == "external-semantic"
  let base : @qc_domain.AnalyzerTask = {
    contract: "mooncast.qc-analyzer-task.v1",
    reference: { id: "qc-" + analyzer, version, digest: "" },
    project_id: "qc-project",
    project_revision: 4,
    shot_id: "shot-1",
    attempt_digest: "sha256:attempt-output",
    source_artifact_digest: "sha256:source-artifact",
    analyzer,
    execution_mode: mode,
    expected_duration_ms: 1000,
    duration_tolerance_ms: 100,
    subtitle_track_digest: None,
    subtitle_cue_count: 0,
    subtitle_last_end_ms: 0,
    subtitle_safe_area_ratio: 0.9,
    identity_refs: if analyzer == "identity" {
      ["asset:hero:v1"]
    } else {
      []
    },
    continuity_refs: [],
    rights_refs: ["rights://cleared/qc"],
    provider_adapter_id: if semantic {
      Some("fixture-qc-identity")
    } else {
      None
    },
    provider: if semantic {
      Some("fixture-qc")
    } else {
      None
    },
    model: if semantic {
      Some("fixture-identity-v1")
    } else {
      None
    },
    permitted_data_class: "rights-cleared-validation",
    cost_ceiling_cny: if semantic {
      2.0
    } else {
      0.0
    },
    retry_limit: 2,
    created_at: "2026-07-19T12:00:00+08:00",
    provider_execution_authority: false,
    publication_authority: false,
  }
  {
    ..base,
    reference: { ..base.reference, digest: @qc_domain.task_digest(base) },
  }
}

///|
async test "local technical and external semantic analyzers persist evidence without decisions" {
  let root = "/tmp/mooncast-automated-qc-" + @async.now().to_string()
  let fixture_media = @store.AtomicStore::new(root + "/fixture")
  let path = fixture_media.prepare_owned_path("one-second.mp4")
  let generated = @host_process.run_capture({
    executable: ".tools/ffmpeg/darwin_arm64/ffmpeg",
    arguments: [
      "-hide_banner", "-nostdin", "-y", "-f", "lavfi", "-i", "color=c=blue:s=320x180:d=1",
      "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-c:v", "libx264", "-pix_fmt",
      "yuv420p", "-c:a", "aac", "-shortest", path,
    ],
    working_directory: None,
    timeout_ms: 30000,
    max_output_bytes: 1048576,
  })
  assert_eq(generated.exit_code, Some(0))
  let blob = fixture_media.get_blob("one-second.mp4").unwrap()
  let execution = @execution_app.ProviderExecutionService::new(
    root + "/execution",
    root + "/artifacts",
    {
      contract: "mooncast.provider-catalog.v1",
      adapters: [analyzer_adapter()],
      authority_actors: ["qc-observer"],
    },
  )
  let service = AnalyzerService::new(
    root + "/qc",
    execution,
    ".tools/ffmpeg/darwin_arm64/ffmpeg",
    ".tools/ffmpeg/darwin_arm64/ffprobe",
  )
  let codec = analyzer_task("codec", 1, "local-technical")
  ignore(service.record_task(codec))
  let codec_receipt = service.run(codec, Some(blob.bytes), {
    expected_task_version: 1,
    expected_task_digest: codec.reference.digest,
    actor: "qc-observer",
    human_confirmed: true,
    network_authority: false,
  })
  assert_eq(codec_receipt.finding.status, "pass")
  assert_false(codec_receipt.human_decision_performed)
  let duration = analyzer_task("duration", 2, "local-technical")
  ignore(service.record_task(duration))
  let duration_receipt = service.run(duration, Some(blob.bytes), {
    expected_task_version: 2,
    expected_task_digest: duration.reference.digest,
    actor: "qc-observer",
    human_confirmed: true,
    network_authority: false,
  })
  assert_eq(duration_receipt.finding.status, "pass")
  let identity = analyzer_task("identity", 3, "external-semantic")
  ignore(service.record_task(identity))
  let identity_receipt = service.run(identity, None, {
    expected_task_version: 3,
    expected_task_digest: identity.reference.digest,
    actor: "qc-observer",
    human_confirmed: true,
    network_authority: true,
  })
  assert_eq(identity_receipt.finding.status, "pass")
  assert_true(identity_receipt.provider_job_id is Some(_))
  assert_false(identity_receipt.human_decision_performed)
  let workspace = service.workspace("qc-project")
  assert_eq(workspace.receipts.length(), 3)
  assert_eq(workspace.human_decisions, 0)
}
