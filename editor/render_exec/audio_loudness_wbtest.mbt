///|
test "loudness compiles explicit track two passes and literal paths" {
  let first = compile_audio_loudness(
    "/media/quiet & 中文.wav",
    2,
    -16,
    -2,
    [],
    None,
  )
  assert_eq(first.arguments[first.arguments.length() - 1], "-")
  assert_true(first.arguments.contains("0:2"))
  assert_true(first.arguments.contains("/media/quiet & 中文.wav"))
  assert_true(
    first.arguments.contains(
      "loudnorm=I=-16:TP=-2:LRA=11:dual_mono=false:print_format=json",
    ),
  )
  let second = compile_audio_loudness(
    "input.wav",
    1,
    -19,
    -1,
    [-30.0, -24.0, 0.0, -40.0, 0.01],
    Some("output.wav"),
  )
  assert_true(second.arguments.contains("pcm_s24le"))
  assert_eq(second.arguments[second.arguments.length() - 1], "output.wav")
  assert_true(second.arguments.any(s => s.contains(":linear=true")))
  assert_false(second.arguments.contains("-ac"))
  assert_true(
    (try? compile_audio_loudness("a", 0, -16, -2, [], Some("b"))) is Err(_),
  )
  assert_true(
    (try? compile_audio_loudness("a", -1, -16, -2, [], None)) is Err(_),
  )
}
