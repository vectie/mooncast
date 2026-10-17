///|
pub(all) struct Plan {
  track : @audio.AudioTrack
  duration_ms : Double
  target_lufs : Int
  ceiling_dbtp : Int
  omitted_stream_indices : Array[Int]
} derive(ToJson)

///|
pub extend Plan with ToJson::{to_json}

///|
/// Choose one existing zero-origin mono/stereo mix. No automatic downmix,
/// channel duplication, stream selection or rights decision is performed.
pub fn prepare(
  source : @audio.Source,
  index : Int,
  target_lufs : Int,
  ceiling_dbtp : Int,
) -> Plan raise {
  guard target_lufs >= -23 &&
    target_lufs <= -14 &&
    ceiling_dbtp >= -3 &&
    ceiling_dbtp <= -1 else {
    fail(
      "choose integrated loudness -23..-14 LUFS and true-peak ceiling -3..-1 dBTP (whole numbers)",
    )
  }
  guard source.duration_ms >= 3000.0 && source.duration_ms <= 7200000.0 else {
    fail("loudness edition requires 3 seconds to 2 hours")
  }
  let tracks = source.audio_tracks.filter(t => t.index == index)
  guard tracks.length() == 1 else {
    fail("choose an absolute audio stream index from inspect")
  }
  let track = tracks[0]
  guard track.channels == 1 || track.channels == 2 else {
    fail("choose a mono/stereo mix; surround downmix is not implicit")
  }
  guard track.start_ms >= -1.0 && track.start_ms <= 1.0 else {
    fail("selected track must start at zero; align it in an editor first")
  }
  if track.duration_ms is Some(duration) {
    guard duration >= source.duration_ms - 50.0 &&
      duration <= source.duration_ms + 50.0 else {
      fail("selected track and container durations differ by more than 50 ms")
    }
  }
  {
    track,
    duration_ms: source.duration_ms,
    target_lufs,
    ceiling_dbtp,
    omitted_stream_indices: source.stream_indices.filter(i => i != index),
  }
}

///|
pub(all) struct Measurement {
  integrated_lufs : Double
  true_peak_dbtp : Double
  range_lu : Double
  threshold_lufs : Double
  offset_db : Double
  normalization_type : String
} derive(ToJson)

///|
pub extend Measurement with ToJson::{to_json}

///|
fn number(
  value : Json,
  key : String,
  low : Double,
  high : Double,
) -> Double raise {
  guard value is Object(fields) && fields.get(key) is Some(String(text)) else {
    fail("loudness report is missing " + key)
  }
  let number = @string.parse_double(text)
  guard number >= low && number <= high else {
    fail(
      "non-finite or unsupported loudness: " +
      key +
      "; silence cannot be normalized",
    )
  }
  number
}

///|
/// Read FFmpeg's single loudnorm JSON report, retaining measured input values.
/// Silence, non-finite numbers and ambiguous multiple reports are rejected.
pub fn parse_measurement(log : String) -> Measurement raise {
  let text = StringBuilder()
  let mut inside = false
  let mut reports = 0
  for line in log.split("\n") {
    if line == "{" {
      guard !inside else { fail("nested loudness report") }
      inside = true
      reports += 1
    }
    if inside {
      text.write_string(line.to_owned() + "\n")
    }
    if line == "}" && inside {
      inside = false
    }
  }
  guard reports == 1 && !inside else {
    fail("expected exactly one complete loudnorm report")
  }
  let json = @json.parse(text.to_string())
  guard json is { "normalization_type": String(kind), .. } &&
    (kind == "linear" || kind == "dynamic") else {
    fail("unknown loudness normalization type")
  }
  {
    integrated_lufs: number(json, "input_i", -70.0, 0.0),
    true_peak_dbtp: number(json, "input_tp", -99.0, 20.0),
    range_lu: number(json, "input_lra", 0.0, 99.0),
    threshold_lufs: number(json, "input_thresh", -99.0, 0.0),
    offset_db: number(json, "target_offset", -99.0, 99.0),
    normalization_type: kind,
  }
}

///|
/// Verify a fresh measurement of the actual emitted audio, not the prediction
/// in an encoding log. This is a bounded numeric check, not editorial QC.
pub fn verify_loudness(plan : Plan, actual : Measurement) -> Unit raise {
  let target = plan.target_lufs.to_double()
  guard actual.integrated_lufs >= target - 0.5 &&
    actual.integrated_lufs <= target + 0.5 else {
    fail("actual WAV integrated loudness misses target by more than 0.5 LU")
  }
  guard actual.true_peak_dbtp <= plan.ceiling_dbtp.to_double() + 0.1 else {
    fail("actual WAV true peak exceeds ceiling by more than 0.1 dB")
  }
}

///|
pub fn verify_output(plan : Plan, probe : Json) -> Unit raise {
  let source = @audio.inspect_source(probe)
  guard source.format == "wav" &&
    source.stream_indices.length() == 1 &&
    source.audio_tracks.length() == 1 else {
    fail("expected a one-track WAV")
  }
  let track = source.audio_tracks[0]
  guard track.codec == "pcm_s24le" &&
    track.sample_rate == 48000 &&
    track.channels == plan.track.channels &&
    source.duration_ms >= plan.duration_ms - 50.0 &&
    source.duration_ms <= plan.duration_ms + 50.0 &&
    track.duration_ms is Some(duration) &&
    duration >= plan.duration_ms - 50.0 &&
    duration <= plan.duration_ms + 50.0 else {
    fail(
      "WAV codec, channel count, sample rate or actual duration differs from plan",
    )
  }
}
