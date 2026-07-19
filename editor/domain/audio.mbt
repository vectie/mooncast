///|
pub(all) struct SampledBusState {
  bus_id : String
  gain_db : Double
  pan : Double
  muted : Bool
  solo : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn sample_automation(
  points : Array[AutomationPoint],
  tick : Int,
  fallback : Double,
) -> Double {
  let curve = points.map(point => KeyframePoint::{
    tick: point.tick,
    value: point.value,
    interpolation: point.interpolation,
  })
  sample_curve(curve, tick, fallback)
}

///|
pub fn AudioBus::sample(self : AudioBus, tick : Int) -> SampledBusState {
  {
    bus_id: self.bus_id,
    gain_db: sample_automation(self.automation.gain_db, tick, self.gain_db),
    pan: sample_automation(self.automation.pan, tick, self.pan),
    muted: self.muted,
    solo: self.solo,
  }
}

///|
/// Maps a clip-local timeline tick to its source tick using the enabled speed ramp.
pub fn Clip::source_tick_at(self : Clip, relative_tick : Int) -> Int {
  let mut points : Array[SpeedPoint] = []
  for effect in self.effects {
    if effect.enabled && effect.kind == "speed-ramp" {
      points = effect.parameters.speed_points
    }
  }
  if points.length() < 2 {
    return self.source_in_tick + relative_tick
  }
  if relative_tick <= points[0].timeline_tick {
    return points[0].source_tick
  }
  for index in 1..<points.length() {
    let right = points[index]
    if relative_tick <= right.timeline_tick {
      let left = points[index - 1]
      if left.interpolation == "hold" {
        return left.source_tick
      }
      let numerator = (relative_tick - left.timeline_tick).to_double()
      let denominator = (right.timeline_tick - left.timeline_tick).to_double()
      return left.source_tick +
        ((right.source_tick - left.source_tick).to_double() *
        numerator /
        denominator).to_int()
    }
  }
  points[points.length() - 1].source_tick
}
