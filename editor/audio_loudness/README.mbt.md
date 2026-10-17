# Measure and make a local loudness edition

Select one existing mono/stereo mix and export a measured WAV derivative.
The CLI journey is in [audio-loudness.md](../../docs/audio-loudness.md).
The output is a listening/editing asset, not a rights or delivery decision.

```mbt check
///|
test "read a finite loudnorm report" {
  let report =
    #|{
    #|  "input_i": "-28.0",
    #|  "input_tp": "-22.0",
    #|  "input_lra": "0.0",
    #|  "input_thresh": "-38.0",
    #|  "target_offset": "0.0",
    #|  "normalization_type": "linear"
    #|}
  assert_eq(@audio_loudness.parse_measurement(report).integrated_lufs, -28.0)
}
```
