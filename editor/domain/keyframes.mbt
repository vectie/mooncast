///|
fn ease(name : String, t : Double) -> Double {
  match name {
    "hold" => 0.0
    "ease-in" => t * t
    "ease-out" => 1.0 - (1.0 - t) * (1.0 - t)
    "ease-in-out" =>
      if t < 0.5 {
        2.0 * t * t
      } else {
        1.0 - (-2.0 * t + 2.0) * (-2.0 * t + 2.0) / 2.0
      }
    _ => t
  }
}

///|
/// Samples a curve without depending on playback or UI state.
pub fn sample_curve(
  points : Array[KeyframePoint],
  tick : Int,
  fallback : Double,
) -> Double {
  if points.length() == 0 {
    return fallback
  }
  if tick <= points[0].tick {
    return points[0].value
  }
  for index in 1..<points.length() {
    let right = points[index]
    if tick <= right.tick {
      let left = points[index - 1]
      if right.tick == left.tick {
        return right.value
      }
      let raw = (tick - left.tick).to_double() /
        (right.tick - left.tick).to_double()
      let amount = ease(left.interpolation, raw)
      return left.value + (right.value - left.value) * amount
    }
  }
  points[points.length() - 1].value
}

///|
pub(all) struct SampledClipState {
  opacity : Double
  scale : Double
  position_x : Double
  position_y : Double
  brightness : Double
  contrast : Double
  saturation : Double
  gamma : Double
  volume_db : Double
  pan : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn sample_clip(clip : Clip, relative_tick : Int) -> SampledClipState {
  {
    opacity: sample_curve(
      clip.keyframes.opacity,
      relative_tick,
      clip.settings.opacity,
    ),
    scale: sample_curve(
      clip.keyframes.scale,
      relative_tick,
      clip.settings.scale,
    ),
    position_x: sample_curve(
      clip.keyframes.position_x,
      relative_tick,
      clip.settings.position_x,
    ),
    position_y: sample_curve(
      clip.keyframes.position_y,
      relative_tick,
      clip.settings.position_y,
    ),
    brightness: sample_curve(
      clip.keyframes.brightness,
      relative_tick,
      clip.settings.brightness,
    ),
    contrast: sample_curve(
      clip.keyframes.contrast,
      relative_tick,
      clip.settings.contrast,
    ),
    saturation: sample_curve(
      clip.keyframes.saturation,
      relative_tick,
      clip.settings.saturation,
    ),
    gamma: sample_curve(
      clip.keyframes.gamma,
      relative_tick,
      clip.settings.gamma,
    ),
    volume_db: sample_curve(
      clip.keyframes.volume_db,
      relative_tick,
      clip.settings.volume_db,
    ),
    pan: sample_curve(clip.keyframes.pan, relative_tick, clip.settings.pan),
  }
}

///|
fn partition_curve(
  points : Array[KeyframePoint],
  offset : Int,
) -> (Array[KeyframePoint], Array[KeyframePoint]) {
  let left : Array[KeyframePoint] = []
  let right : Array[KeyframePoint] = []
  for point in points {
    if point.tick <= offset {
      left.push(point)
    }
    if point.tick >= offset {
      right.push({ ..point, tick: point.tick - offset })
    }
  }
  (left, right)
}

///|
pub fn split_keyframes(
  value : KeyframeSet,
  offset : Int,
) -> (KeyframeSet, KeyframeSet) {
  let (lo, ro) = partition_curve(value.opacity, offset)
  let (ls, rs) = partition_curve(value.scale, offset)
  let (lpx, rpx) = partition_curve(value.position_x, offset)
  let (lpy, rpy) = partition_curve(value.position_y, offset)
  let (lb, rb) = partition_curve(value.brightness, offset)
  let (lc, rc) = partition_curve(value.contrast, offset)
  let (lsa, rsa) = partition_curve(value.saturation, offset)
  let (lg, rg) = partition_curve(value.gamma, offset)
  let (lv, rv) = partition_curve(value.volume_db, offset)
  let (lp, rp) = partition_curve(value.pan, offset)
  (
    {
      opacity: lo,
      scale: ls,
      position_x: lpx,
      position_y: lpy,
      brightness: lb,
      contrast: lc,
      saturation: lsa,
      gamma: lg,
      volume_db: lv,
      pan: lp,
    },
    {
      opacity: ro,
      scale: rs,
      position_x: rpx,
      position_y: rpy,
      brightness: rb,
      contrast: rc,
      saturation: rsa,
      gamma: rg,
      volume_db: rv,
      pan: rp,
    },
  )
}
