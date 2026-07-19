///|
pub(all) struct SegmentEntry {
  key : String
  plan_digest : String
  range : @plan.TickRange
  media_digest : String
  size_bytes : Int
  last_used_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CacheIndex {
  contract : String
  version : Int
  segments : Array[SegmentEntry]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DirtyRangePlan {
  contract : String
  requested : Array[@plan.TickRange]
  reusable : Array[@plan.TickRange]
  dirty : Array[@plan.TickRange]
  invalidated_segment_keys : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SegmentProjection {
  key : String
  range : @plan.TickRange
  plan : @plan.RenderPlan
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct PreviewCache {
  index_store : @host_store.AtomicStore
  segment_store : @host_store.AtomicStore
}

///|
pub fn PreviewCache::new(root : String) -> PreviewCache {
  {
    index_store: @host_store.AtomicStore::new(root + "/index"),
    segment_store: @host_store.AtomicStore::new(
      root + "/segments",
      max_read_bytes=1073741824,
    ),
  }
}

///|
pub async fn PreviewCache::load_index(self : PreviewCache) -> CacheIndex {
  match self.index_store.get_json("preview-cache.json") {
    None =>
      {
        contract: "mooncast.editor-preview-segment-cache.v1",
        version: 1,
        segments: [],
      }
    Some(value) => @json.from_json(value)
  }
}

///|
pub async fn PreviewCache::save_index(
  self : PreviewCache,
  value : CacheIndex,
) -> Unit {
  ignore(self.index_store.put_json("preview-cache.json", value.to_json()))
}

///|
fn overlaps(left : @plan.TickRange, right : @plan.TickRange) -> Bool {
  left.start_tick < right.start_tick + right.duration_ticks &&
  right.start_tick < left.start_tick + left.duration_ticks
}

///|
fn slice_curve(
  points : Array[@domain.KeyframePoint],
  offset : Int,
  duration : Int,
  fallback : Double,
) -> Array[@domain.KeyframePoint] {
  if points.is_empty() {
    return []
  }
  let result : Array[@domain.KeyframePoint] = [
    {
      tick: 0,
      value: @domain.sample_curve(points, offset, fallback),
      interpolation: points[0].interpolation,
    },
  ]
  for point in points {
    if point.tick > offset && point.tick < offset + duration {
      result.push({ ..point, tick: point.tick - offset })
    }
  }
  result.push({
    tick: duration,
    value: @domain.sample_curve(points, offset + duration, fallback),
    interpolation: points[points.length() - 1].interpolation,
  })
  result
}

///|
fn slice_keyframes(
  clip : @plan.FrozenClip,
  offset : Int,
  duration : Int,
) -> @domain.KeyframeSet {
  let value = clip.keyframes
  let settings = clip.settings
  {
    opacity: slice_curve(value.opacity, offset, duration, settings.opacity),
    scale: slice_curve(value.scale, offset, duration, settings.scale),
    position_x: slice_curve(
      value.position_x,
      offset,
      duration,
      settings.position_x,
    ),
    position_y: slice_curve(
      value.position_y,
      offset,
      duration,
      settings.position_y,
    ),
    brightness: slice_curve(
      value.brightness,
      offset,
      duration,
      settings.brightness,
    ),
    contrast: slice_curve(value.contrast, offset, duration, settings.contrast),
    saturation: slice_curve(
      value.saturation,
      offset,
      duration,
      settings.saturation,
    ),
    gamma: slice_curve(value.gamma, offset, duration, settings.gamma),
    volume_db: slice_curve(
      value.volume_db,
      offset,
      duration,
      settings.volume_db,
    ),
    pan: slice_curve(value.pan, offset, duration, settings.pan),
  }
}

///|
fn slice_clip(
  clip : @plan.FrozenClip,
  start : Int,
  end_tick : Int,
) -> @plan.FrozenClip? {
  let clip_end = clip.start_tick + clip.duration_ticks
  let left = Int::max(start, clip.start_tick)
  let right = Int::min(end_tick, clip_end)
  if right <= left {
    return None
  }
  let offset = left - clip.start_tick
  let duration = right - left
  Some({
    ..clip,
    start_tick: left,
    duration_ticks: duration,
    source_in_tick: clip.source_in_tick + offset,
    source_out_tick: clip.source_in_tick + offset + duration,
    keyframes: slice_keyframes(clip, offset, duration),
  })
}

///|
pub fn segment_projections(
  value : @plan.RenderPlan,
) -> Array[SegmentProjection] raise {
  let range_start = value.range.start_tick
  let range_end = range_start + value.range.duration_ticks
  let boundaries : Array[Int] = [range_start, range_end]
  for track in value.tracks {
    if track.kind == "video" {
      for clip in track.clips {
        let start = clip.start_tick
        let end_tick = start + clip.duration_ticks
        let inside_transition = (tick : Int) => {
          value.transitions.any(transition => {
            transition.kind != "cut" &&
            tick > transition.range.start_tick &&
            tick < transition.range.start_tick + transition.range.duration_ticks
          })
        }
        if start > range_start && start < range_end && !inside_transition(start) {
          boundaries.push(start)
        }
        if end_tick > range_start &&
          end_tick < range_end &&
          !inside_transition(end_tick) {
          boundaries.push(end_tick)
        }
      }
    }
  }
  for transition in value.transitions {
    if transition.kind != "cut" {
      boundaries.push(Int::max(range_start, transition.range.start_tick))
      boundaries.push(
        Int::min(
          range_end,
          transition.range.start_tick + transition.range.duration_ticks,
        ),
      )
    }
  }
  boundaries.sort()
  boundaries.dedup()
  let result : Array[SegmentProjection] = []
  for index in 0..<(boundaries.length() - 1) {
    let start = boundaries[index]
    let end_tick = boundaries[index + 1]
    if end_tick > start {
      let range : @plan.TickRange = {
        start_tick: start,
        duration_ticks: end_tick - start,
      }
      let tracks = value.tracks.map(track => {
        ..track,
        clips: track.clips.filter_map(clip => slice_clip(clip, start, end_tick)),
      })
      let transitions = value.transitions.filter(transition => {
        transition.range.start_tick >= start &&
        transition.range.start_tick + transition.range.duration_ticks <=
        end_tick
      })
      let sliced = @plan.rehash({ ..value, range, tracks, transitions })
      let projection = @plan.cache_projection(sliced, range)
      result.push({ key: projection.cache_key, range, plan: sliced })
    }
  }
  guard !result.is_empty() else {
    fail("preview timeline contains no segments")
  }
  result
}

///|
pub fn plan_dirty_ranges(
  index : CacheIndex,
  projections : Array[@plan.CacheKeyProjection],
) -> DirtyRangePlan {
  let requested : Array[@plan.TickRange] = []
  let reusable : Array[@plan.TickRange] = []
  let dirty : Array[@plan.TickRange] = []
  let invalidated : Array[String] = []
  for projection in projections {
    requested.push(projection.range)
    if index.segments.any(entry => entry.key == projection.cache_key) {
      reusable.push(projection.range)
    } else {
      dirty.push(projection.range)
      for entry in index.segments {
        if overlaps(entry.range, projection.range) &&
          entry.plan_digest != projection.plan_digest {
          invalidated.push(entry.key)
        }
      }
    }
  }
  {
    contract: "mooncast.editor-dirty-range-plan.v1",
    requested,
    reusable,
    dirty,
    invalidated_segment_keys: invalidated,
  }
}

///|
pub async fn PreviewCache::put_segment(
  self : PreviewCache,
  entry : SegmentEntry,
  bytes : Bytes,
) -> Unit {
  ignore(self.segment_store.put_blob("segment-" + entry.key + ".mp4", bytes))
  let index = self.load_index()
  let segments = index.segments.filter(value => value.key != entry.key)
  segments.push(entry)
  self.save_index({ ..index, segments, })
}

///|
pub async fn PreviewCache::get_segment(
  self : PreviewCache,
  key : String,
) -> Bytes? {
  match self.segment_store.get_blob("segment-" + key + ".mp4") {
    None => None
    Some(value) => Some(value.bytes)
  }
}

///|
pub async fn PreviewCache::invalidate(
  self : PreviewCache,
  keys : Array[String],
) -> Unit {
  let index = self.load_index()
  for key in keys {
    ignore(self.segment_store.remove("segment-" + key + ".mp4"))
  }
  self.save_index({
    ..index,
    segments: index.segments.filter(entry => !keys.contains(entry.key)),
  })
}

///|
pub fn eviction_keys(
  index : CacheIndex,
  preserved : Array[String],
  maximum_bytes : Int,
  maximum_segments : Int,
) -> Array[String] {
  let remaining = index.segments.copy()
  let evicted : Array[String] = []
  let mut bytes = remaining.fold(init=0, (total, item) => {
    total + item.size_bytes
  })
  let mut cursor = 0
  while (
          remaining.length() - evicted.length() > maximum_segments ||
          bytes > maximum_bytes
        ) &&
        cursor < remaining.length() {
    let candidate = remaining[cursor]
    if !preserved.contains(candidate.key) {
      evicted.push(candidate.key)
      bytes -= candidate.size_bytes
    }
    cursor += 1
  }
  evicted
}

///|
pub async fn PreviewCache::enforce_quota(
  self : PreviewCache,
  preserved : Array[String],
  maximum_bytes : Int,
  maximum_segments : Int,
) -> Array[String] {
  let index = self.load_index()
  let keys = eviction_keys(index, preserved, maximum_bytes, maximum_segments)
  self.invalidate(keys)
  keys
}

///|
fn report_digest(value : @plan.PreviewCacheReport) -> String {
  let body = { ..value, report_digest: "" }
  "sha256:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(body.to_json().stringify())),
  )
}

///|
pub fn cache_report(
  segment_keys : Array[String],
  hits : Array[@plan.TickRange],
  misses : Array[@plan.TickRange],
  proxies : Array[@plan.ProxyReadiness],
  evicted : Array[String],
  invalidated : Array[String],
  maximum_bytes : Int,
  maximum_segments : Int,
  current_bytes : Int,
  current_segments : Int,
) -> @plan.PreviewCacheReport {
  let provisional : @plan.PreviewCacheReport = {
    contract: "mooncast.editor-preview-cache-report.v1",
    profile: "mooncast-editor-compositor/bounded-low-resolution-v1",
    segment_count: segment_keys.length(),
    cache_hit_ranges: hits,
    cache_miss_ranges: misses,
    rebuilt_ranges: misses,
    proxy_readiness: proxies,
    evicted_segment_keys: evicted,
    invalidated_segment_keys: invalidated,
    segment_keys,
    quota: { maximum_bytes, maximum_segments, current_bytes, current_segments },
    report_digest: "",
  }
  { ..provisional, report_digest: report_digest(provisional) }
}
