///|
fn source() -> @audio.Source {
  {
    format: "wav",
    duration_ms: 8000.0,
    stream_indices: [0, 1, 2],
    audio_tracks: [
      {
        index: 1,
        codec: "pcm_s24le",
        language: "eng",
        title: "Quiet mix",
        channels: 1,
        sample_rate: 44100,
        start_ms: 0.0,
        duration_ms: Some(8000.0),
      },
      {
        index: 2,
        codec: "flac",
        language: "fra",
        title: "Stereo mix",
        channels: 2,
        sample_rate: 48000,
        start_ms: 0.0,
        duration_ms: Some(8000.0),
      },
    ],
  }
}

///|
fn report(i : String, peak : String, kind : String) -> String {
  "diagnostic before\n{\n\"input_i\": \"" +
  i +
  "\",\n\"input_tp\": \"" +
  peak +
  "\",\n\"input_lra\": \"0.10\",\n\"input_thresh\": \"-36.0\",\n\"target_offset\": \"0.01\",\n\"normalization_type\": \"" +
  kind +
  "\"\n}\ndiagnostic after\n"
}

///|
test "explicit selection retains mono stereo and omitted stream list" {
  let mono = @audio_loudness.prepare(source(), 1, -19, -2)
  assert_eq(mono.track.channels, 1)
  assert_eq(mono.omitted_stream_indices, [0, 2])
  let stereo = @audio_loudness.prepare(source(), 2, -16, -1)
  assert_eq(stereo.track.language, "fra")
  assert_eq(stereo.track.channels, 2)
  for i in [-1, 0, 3] {
    assert_true((try? @audio_loudness.prepare(source(), i, -16, -2)) is Err(_))
  }
}

///|
test "bounded targets timing and surround do not silently transform" {
  for target in [-24, -13] {
    assert_true(
      (try? @audio_loudness.prepare(source(), 1, target, -2)) is Err(_),
    )
  }
  for peak in [-4, 0] {
    assert_true(
      (try? @audio_loudness.prepare(source(), 1, -16, peak)) is Err(_),
    )
  }
  for duration in [2999.0, 7200001.0] {
    assert_true(
      (try? @audio_loudness.prepare(
        { ..source(), duration_ms: duration, },
        1,
        -16,
        -2,
      ))
      is Err(_),
    )
  }
  let track = source().audio_tracks[0]
  for
    changed in [
      { ..track, channels: 6, },
      { ..track, start_ms: 250.0, },
      { ..track, duration_ms: Some(2000.0), },
    ] {
    assert_true(
      (try? @audio_loudness.prepare(
        { ..source(), audio_tracks: [changed], },
        1,
        -16,
        -2,
      ))
      is Err(_),
    )
  }
}

///|
test "parse measured input values and actual linear or dynamic mode" {
  let measured = @audio_loudness.parse_measurement(
    report("-29.22", "-24.03", "linear"),
  )
  assert_eq(measured.integrated_lufs, -29.22)
  assert_eq(measured.true_peak_dbtp, -24.03)
  assert_eq(measured.offset_db, 0.01)
  assert_eq(measured.normalization_type, "linear")
  assert_eq(
    @audio_loudness.parse_measurement(report("-19", "-15", "dynamic")).normalization_type,
    "dynamic",
  )
}

///|
test "silence NaN missing and ambiguous measurements fail" {
  for i in ["-inf", "NaN", "inf", "-71", "1"] {
    assert_true(
      (try? @audio_loudness.parse_measurement(report(i, "-12", "linear")))
      is Err(_),
    )
  }
  for
    bad in [
      "",
      "{\n}",
      "{\n",
      report("-20", "NaN", "linear"),
      report("-20", "-12", "unknown"),
      report("-20", "-12", "linear") + report("-20", "-12", "linear"),
    ] {
    assert_true((try? @audio_loudness.parse_measurement(bad)) is Err(_))
  }
}

///|
test "actual waveform loudness tolerance and peak ceiling" {
  let plan = @audio_loudness.prepare(source(), 1, -19, -2)
  for i in ["-19.50", "-18.50", "-19.0"] {
    @audio_loudness.verify_loudness(
      plan,
      @audio_loudness.parse_measurement(report(i, "-1.90", "dynamic")),
    )
  }
  for pair in [("-19.51", "-2"), ("-18.49", "-2"), ("-19", "-1.89")] {
    assert_true(
      (try? @audio_loudness.verify_loudness(
        plan,
        @audio_loudness.parse_measurement(report(pair.0, pair.1, "linear")),
      ))
      is Err(_),
    )
  }
}

///|
test "actual output requires one complete correctly encoded WAV" {
  let plan = @audio_loudness.prepare(source(), 2, -16, -2)
  let audio : Json = {
    "index": 0,
    "codec_type": "audio",
    "codec_name": "pcm_s24le",
    "sample_rate": "48000",
    "channels": 2,
    "duration": "8.0",
  }
  let valid : Json = {
    "format": { "format_name": "wav", "duration": "8.0" },
    "streams": [audio],
  }
  @audio_loudness.verify_output(plan, valid)
  let invalid : Array[Json] = [
    {
      "format": { "format_name": "wav", "duration": "9.0" },
      "streams": [audio],
    },
    {
      "format": { "format_name": "wav", "duration": "8.0" },
      "streams": [audio, { "index": 1, "codec_type": "video" }],
    },
    {
      "format": { "format_name": "wav", "duration": "8.0" },
      "streams": [
        {
          "index": 0,
          "codec_type": "audio",
          "codec_name": "pcm_s16le",
          "sample_rate": "44100",
          "channels": 1,
          "duration": "8.0",
        },
      ],
    },
  ]
  for bad in invalid {
    assert_true((try? @audio_loudness.verify_output(plan, bad)) is Err(_))
  }
}
