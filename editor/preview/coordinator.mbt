///|
pub(all) struct SourcePathBinding {
  digest : String
  path : String
  media_kind : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProxyTask {
  source_digest : String
  expected_profile : String
  invocation : @render_exec.ProxyInvocation
} derive(Debug)

///|
pub(all) struct SegmentTask {
  segment_key : String
  range : @plan.TickRange
  output_path : String
  invocation : @render_exec.RenderInvocation
} derive(Debug)

///|
pub(all) struct PreviewWorkOrder {
  contract : String
  project_id : String
  project_revision : Int
  plan_digest : String
  proxy_readiness : Array[@plan.ProxyReadiness]
  proxy_tasks : Array[ProxyTask]
  segment_keys : Array[String]
  cached_segment_paths : Array[String]
  segment_tasks : Array[SegmentTask]
  invalidated_segment_keys : Array[String]
  concat : @render_exec.ConcatInvocation
  publication_authority : Bool
  provider_authority : Bool
} derive(Debug)

///|
pub(all) struct SegmentCommit {
  segment_key : String
  plan_digest : String
  range : @plan.TickRange
  media_digest : String
  bytes : Bytes
  completed_at : String
} derive(Debug, Eq)

///|
fn source_path(
  paths : Array[SourcePathBinding],
  digest : String,
) -> SourcePathBinding raise {
  for value in paths {
    if value.digest == digest {
      return value
    }
  }
  fail("preview source path was not resolved")
}

///|
/// Resolves review proxies without hiding missing work behind synchronous provider calls.
pub async fn prepare_proxy_tasks(
  registry : @media.MediaRegistry,
  ffmpeg : String,
  source_digests : Array[String],
  paths : Array[SourcePathBinding],
  output_root : String,
) -> (Array[@plan.ProxyReadiness], Array[ProxyTask]) {
  let readiness : Array[@plan.ProxyReadiness] = []
  let tasks : Array[ProxyTask] = []
  for digest in source_digests {
    let proxies = registry.list_proxies(digest)
    let ready = proxies.filter(record => {
      record.provenance_refs.contains("mooncast-review-source-proxy@1.0.0")
    })
    if ready.get(0) is Some(record) {
      readiness.push({
        source_digest: digest,
        proxy_digest: record.digest,
        state: "ready",
        cache_hit: true,
        profile: "mooncast-review-source-proxy@1.0.0",
      })
    } else {
      let source = source_path(paths, digest)
      let output = output_root +
        "/proxy-" +
        (if digest.has_prefix("sha256:") {
          digest[7:].to_owned()
        } else {
          digest
        }) +
        ".mp4"
      tasks.push({
        source_digest: digest,
        expected_profile: "mooncast-review-source-proxy@1.0.0",
        invocation: @render_exec.compile_proxy(
          ffmpeg,
          digest,
          source.path,
          output,
          source.media_kind,
        ),
      })
      readiness.push({
        source_digest: digest,
        proxy_digest: "",
        state: "pending",
        cache_hit: false,
        profile: "mooncast-review-source-proxy@1.0.0",
      })
    }
  }
  (readiness, tasks)
}

///|
/// Builds the entire restartable segment/concat work graph in one deterministic pass.
pub async fn prepare_preview(
  cache : @cache.PreviewCache,
  ffmpeg : String,
  plan : @plan.RenderPlan,
  resolved_media : Array[@render_exec.ResolvedMedia],
  proxy_readiness : Array[@plan.ProxyReadiness],
  proxy_tasks : Array[ProxyTask],
  working_root : String,
  final_output_path : String,
) -> PreviewWorkOrder {
  guard plan.ready else { fail("preview render plan is not ready") }
  let projections = @cache.segment_projections(plan)
  let index = cache.load_index()
  let cache_keys = projections.map(item => {
    @plan.cache_projection(item.plan, item.range)
  })
  let dirty = @cache.plan_dirty_ranges(index, cache_keys)
  if !dirty.invalidated_segment_keys.is_empty() {
    cache.invalidate(dirty.invalidated_segment_keys)
  }
  let segment_keys : Array[String] = []
  let segment_paths : Array[String] = []
  let cached_paths : Array[String] = []
  let tasks : Array[SegmentTask] = []
  for projection in projections {
    let path = working_root + "/segment-" + projection.key + ".mp4"
    segment_keys.push(projection.key)
    segment_paths.push(path)
    if cache.get_segment(projection.key) is Some(_) {
      cached_paths.push(path)
    } else {
      tasks.push({
        segment_key: projection.key,
        range: projection.range,
        output_path: path,
        invocation: @render_exec.compile(
          ffmpeg,
          projection.plan,
          resolved_media,
          path,
        ),
      })
    }
  }
  let manifest = working_root +
    "/concat-" +
    plan.plan_digest.replace_all(old=":", new="-") +
    ".txt"
  {
    contract: "mooncast.editor-preview-work-order.v1",
    project_id: plan.project_id,
    project_revision: plan.project_revision,
    plan_digest: plan.plan_digest,
    proxy_readiness,
    proxy_tasks,
    segment_keys,
    cached_segment_paths: cached_paths,
    segment_tasks: tasks,
    invalidated_segment_keys: dirty.invalidated_segment_keys,
    concat: @render_exec.compile_concat(
      ffmpeg, segment_paths, manifest, final_output_path, 600000,
    ),
    publication_authority: false,
    provider_authority: false,
  }
}

///|
/// Commits successful segment bytes to the immutable cache after host-side output verification.
pub async fn commit_segment(
  cache : @cache.PreviewCache,
  value : SegmentCommit,
) -> Unit {
  guard value.media_digest.has_prefix("sha256:") && !value.bytes.is_empty() else {
    fail("segment content receipt is invalid")
  }
  cache.put_segment(
    {
      key: value.segment_key,
      plan_digest: value.plan_digest,
      range: value.range,
      media_digest: value.media_digest,
      size_bytes: value.bytes.length(),
      last_used_at: value.completed_at,
    },
    value.bytes,
  )
}

///|
/// Applies quota after all segment commits and emits the durable preview cache report.
pub async fn finalize_preview_cache(
  cache : @cache.PreviewCache,
  work : PreviewWorkOrder,
  maximum_bytes : Int,
  maximum_segments : Int,
) -> @plan.PreviewCacheReport {
  let evicted = cache.enforce_quota(
    work.segment_keys,
    maximum_bytes,
    maximum_segments,
  )
  let index = cache.load_index()
  let bytes = index.segments.fold(init=0, (total, item) => {
    total + item.size_bytes
  })
  let hits : Array[@plan.TickRange] = []
  let misses = work.segment_tasks.map(task => task.range)
  for key in work.segment_keys {
    if !work.segment_tasks.any(task => task.segment_key == key) {
      for entry in index.segments {
        if entry.key == key {
          hits.push(entry.range)
        }
      }
    }
  }
  @cache.cache_report(
    work.segment_keys,
    hits,
    misses,
    work.proxy_readiness,
    evicted,
    work.invalidated_segment_keys,
    maximum_bytes,
    maximum_segments,
    bytes,
    index.segments.length(),
  )
}
