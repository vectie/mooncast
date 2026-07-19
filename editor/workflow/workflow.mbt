///|
pub(all) struct RenderRun {
  contract : String
  job : @jobs.EditorJob
  receipt : @render_exec.RenderReceipt
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Executes one already-authorized local render attempt and durably records its state.
/// Output hashing/storage is deliberately a subsequent content-store operation.
pub async fn run_render(
  repository : @editor_store.EditorRepository,
  queued : @jobs.EditorJob,
  invocation : @render_exec.RenderInvocation,
  started_at : String,
  finished_at : String,
  output_digest : String,
  output_ref : String,
) -> RenderRun {
  let running = queued.start(started_at)
  @jobs.save(repository, running)
  let receipt = @render_exec.execute(invocation)
  let terminal = if receipt.succeeded {
    guard output_digest.has_prefix("sha256:") && !output_ref.is_blank() else {
      fail("successful renderer requires a content-store receipt")
    }
    running.succeed(output_digest, output_ref, finished_at)
  } else {
    running.fail(
      if receipt.timed_out {
        "render-timeout"
      } else {
        "render-failed"
      },
      receipt.stderr_tail,
      finished_at,
    )
  }
  @jobs.save(repository, terminal)
  { contract: "mooncast.editor-render-run.v1", job: terminal, receipt }
}

///|
pub async fn run_proxy(
  repository : @editor_store.EditorRepository,
  queued : @jobs.EditorJob,
  invocation : @render_exec.ProxyInvocation,
  started_at : String,
  finished_at : String,
  proxy_digest : String,
  proxy_ref : String,
) -> RenderRun {
  let running = queued.start(started_at)
  @jobs.save(repository, running)
  let receipt = @render_exec.execute_proxy(invocation)
  let terminal = if receipt.succeeded {
    guard proxy_digest.has_prefix("sha256:") && !proxy_ref.is_blank() else {
      fail("successful proxy requires a content-store receipt")
    }
    running.succeed(proxy_digest, proxy_ref, finished_at)
  } else {
    running.fail(
      if receipt.timed_out {
        "proxy-timeout"
      } else {
        "proxy-failed"
      },
      receipt.stderr_tail,
      finished_at,
    )
  }
  @jobs.save(repository, terminal)
  { contract: "mooncast.editor-render-run.v1", job: terminal, receipt }
}

///|
/// Runs and probes a delivery render before a job may become successful.
pub async fn run_verified_render(
  repository : @editor_store.EditorRepository,
  queued : @jobs.EditorJob,
  invocation : @render_exec.RenderInvocation,
  ffprobe : String,
  expected : @render_exec.OutputExpectation,
  started_at : String,
  finished_at : String,
  output_digest : String,
  output_size : Int,
  output_ref : String,
) -> (RenderRun, @render_exec.OutputInspection?) {
  let running = queued.start(started_at)
  @jobs.save(repository, running)
  let receipt = @render_exec.execute(invocation)
  if !receipt.succeeded {
    let failed = running.fail(
      if receipt.timed_out {
        "render-timeout"
      } else {
        "render-failed"
      },
      receipt.stderr_tail,
      finished_at,
    )
    @jobs.save(repository, failed)
    return (
      { contract: "mooncast.editor-render-run.v1", job: failed, receipt },
      None,
    )
  }
  let inspection = @render_exec.inspect_render_output(
    ffprobe,
    invocation.output_path,
    output_digest,
    output_size,
    expected,
  )
  guard inspection.passed else { fail("render output inspection failed") }
  let succeeded = running.succeed(output_digest, output_ref, finished_at)
  @jobs.save(repository, succeeded)
  (
    { contract: "mooncast.editor-render-run.v1", job: succeeded, receipt },
    Some(inspection),
  )
}

///|
/// Registers a verified proxy with immutable lineage after the host returns exact bytes.
pub async fn register_proxy(
  registry : @media.MediaRegistry,
  invocation : @render_exec.ProxyInvocation,
  bytes : Bytes,
  mime : String,
  duration : Double?,
  created_at : String,
) -> @media.MediaObjectRecord {
  guard !bytes.is_empty() else { fail("proxy output is empty") }
  guard registry.get(invocation.source_digest) is Some(original) else {
    fail("proxy original is missing")
  }
  let provenance = original.provenance_refs.copy()
  provenance.push(invocation.profile)
  registry.ingest(
    bytes,
    mime,
    duration,
    "proxy",
    Some(invocation.source_digest),
    original.source_refs,
    provenance,
    original.rights_refs,
    created_at,
  )
}

///|
/// Executes the final concat operation for an already-running preview job.
pub async fn run_concat(
  repository : @editor_store.EditorRepository,
  running : @jobs.EditorJob,
  invocation : @render_exec.ConcatInvocation,
  finished_at : String,
  output_digest : String,
  output_ref : String,
) -> RenderRun {
  guard running.state == "running" else {
    fail("concat requires a running preview job")
  }
  let receipt = @render_exec.execute_concat(invocation)
  let terminal = if receipt.succeeded {
    guard output_digest.has_prefix("sha256:") && !output_ref.is_blank() else {
      fail("concat requires a content receipt")
    }
    running.succeed(output_digest, output_ref, finished_at)
  } else {
    running.fail(
      if receipt.timed_out {
        "concat-timeout"
      } else {
        "concat-failed"
      },
      receipt.stderr_tail,
      finished_at,
    )
  }
  @jobs.save(repository, terminal)
  { contract: "mooncast.editor-render-run.v1", job: terminal, receipt }
}

///|
/// Runs FFprobe for one immutable registered source.
pub async fn analyze_source(
  registry : @media.MediaRegistry,
  ffprobe : String,
  source_digest : String,
  source_path : String,
  analysis_id : String,
) -> @media.MediaAnalysis {
  guard registry.get(source_digest) is Some(record) else {
    fail("analysis source is not registered")
  }
  let provisional_digest = "analysis:" + source_digest
  @media.probe(
    ffprobe,
    source_path,
    source_digest,
    record.size,
    record.mime,
    analysis_id,
    provisional_digest,
  )
}

///|
/// Binds already-executed thumbnail/waveform outputs into the durable analysis record.
pub async fn complete_source_analysis(
  registry : @media.MediaRegistry,
  probed : @media.MediaAnalysis,
  thumbnail_bytes : Bytes?,
  thumbnail_mime : String?,
  thumbnail_width : Int?,
  thumbnail_height : Int?,
  waveform_pcm : Bytes?,
  created_at : String,
) -> @media.MediaAnalysis {
  registry.complete_analysis(
    probed, thumbnail_bytes, thumbnail_mime, thumbnail_width, thumbnail_height, waveform_pcm,
    created_at,
  )
}
