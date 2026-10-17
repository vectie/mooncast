///|
async fn main {
  let help = "usage:\n  audio_loudness inspect MEDIA\n  audio_loudness measure MEDIA AUDIO_STREAM_INDEX TARGET_LUFS CEILING_DBTP\n  audio_loudness export MEDIA AUDIO_STREAM_INDEX TARGET_LUFS CEILING_DBTP NEW_FOLDER\n\nTargets: whole-number -23..-14 LUFS and -3..-1 dBTP. Mono/stereo, 3 seconds–2 hours.\nTwo-pass 48 kHz/24-bit WAV, independently remeasured before success. See docs/audio-loudness.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "help") {
    println(help)
    return
  }
  guard (args.length() == 3 && args[1] == "inspect") ||
    (args.length() == 6 && args[1] == "measure") ||
    (args.length() == 7 && args[1] == "export") else {
    fail(help)
  }
  let output_folder = if args[1] == "export" {
    Some(new_folder(args[6]))
  } else {
    None
  }
  let path = local_file(args[2])
  let hash = hash_file(path)
  let source = @audio.inspect_source(probe(path))
  if args[1] == "inspect" {
    guard hash_file(path) == hash else {
      fail("source changed during inspection")
    }
    let result : Json = {
      "contract": "mooncast.audio-loudness-inspect.v1",
      "path": path,
      "sha256": hash,
      "source": source,
      "selection": "explicit absolute stream index required",
    }
    println(result.stringify(indent=2))
    return
  }
  let plan = @loudness.prepare(
    source,
    @string.parse_int(args[3]),
    @string.parse_int(args[4]),
    @string.parse_int(args[5]),
  )
  let analyze = @render.compile_audio_loudness(
    path,
    plan.track.index,
    plan.target_lufs,
    plan.ceiling_dbtp,
    [],
    None,
  )
  let before_log = run_media(analyze)
  let before = @loudness.parse_measurement(before_log)
  guard hash_file(path) == hash else {
    fail("source changed during measurement")
  }
  let preview : Json = {
    "contract": "mooncast.audio-loudness-measure.v1",
    "source": path,
    "source_sha256": hash,
    "plan": plan,
    "measured": before,
    "output": "48 kHz, 24-bit PCM WAV; source channel count",
    "normalization": "two-pass loudnorm requests linear gain; FFmpeg may use dynamic normalization to meet range/peak constraints",
    "mono": "mono remains mono, dual_mono=false; no stereo playback compensation",
    "tolerances": {
      "integrated_lu": 0.5,
      "true_peak_db": 0.1,
      "duration_ms": 50,
    },
    "boundary": "audio derivative only; no video/captions/chapters, mixing, rights grant, editorial approval, client acceptance or publishing",
  }
  guard output_folder is Some(folder) else {
    println(preview.stringify(indent=2))
    return
  }
  @fs.mkdir(folder, recursive=false)
  write_new(folder + "/before.json", preview.stringify(indent=2) + "\n")
  write_new(folder + "/measure-before.log", before_log)
  let output = folder + "/normalized.wav"
  let encode = @render.compile_audio_loudness(
    path,
    plan.track.index,
    plan.target_lufs,
    plan.ceiling_dbtp,
    [
      before.integrated_lufs,
      before.true_peak_dbtp,
      before.range_lu,
      before.threshold_lufs,
      before.offset_db,
    ],
    Some(output),
  )
  let encode_log = run_media(encode, log=folder + "/encode.log")
  let encoded = @loudness.parse_measurement(encode_log)
  let output_probe = probe(output)
  @loudness.verify_output(plan, output_probe)
  let remeasure = @render.compile_audio_loudness(
    output,
    0,
    plan.target_lufs,
    plan.ceiling_dbtp,
    [],
    None,
  )
  let after_log = run_media(remeasure, log=folder + "/measure-after.log")
  let actual = @loudness.parse_measurement(after_log)
  write_new(folder + "/after.json", actual.to_json().stringify(indent=2) + "\n")
  @loudness.verify_loudness(plan, actual)
  guard hash_file(path) == hash else {
    fail("source changed during export; partial folder retained")
  }
  let receipt : Json = {
    "contract": "mooncast.audio-loudness-result.v1",
    "source": preview,
    "audio": "normalized.wav",
    "sha256": hash_file(output),
    "actual": actual,
    "normalization_type": encoded.normalization_type,
    "probe": output_probe,
    "commands": [analyze.arguments, encode.arguments, remeasure.arguments],
    "rights_approval": false,
    "client_acceptance": false,
    "publication_authority": false,
  }
  write_new(folder + "/result.json", receipt.stringify(indent=2) + "\n")
  println(receipt.stringify(indent=2))
}

///|
async fn run_media(command : @process.CommandSpec, log? : String) -> String {
  let result = @process.run_capture(command)
  let diagnostics = @utf8.decode(result.stderr)
  if log is Some(path) {
    write_new(path, diagnostics)
  }
  guard result.exit_code == Some(0) &&
    !result.timed_out &&
    !result.output_truncated else {
    fail(
      "media command failed; partial folder retained if created: " + diagnostics,
    )
  }
  diagnostics
}
