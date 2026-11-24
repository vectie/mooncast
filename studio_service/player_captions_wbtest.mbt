///|
test "Qwen metadata is not caption text and target language is allowlisted" {
  assert_eq(
    player_asr_text("language Chinese<asr_text>你好<|endoftext|>"),
    "你好",
  )
  assert_eq(player_asr_text("Hello"), "Hello")
  assert_eq(player_translation_language("ja"), Some("日语"))
  assert_eq(player_translation_language("off"), Some(""))
  assert_eq(player_translation_language("file:///tmp/secret"), None)
}

///|
test "Player WAV validator accepts only bounded PCM16 frames with consistent sizes" {
  let wav = b"RIFF\x28\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80\x3e\x00\x00\x00\x7d\x00\x00\x02\x00\x10\x00data\x04\x00\x00\x00\x00\x00\x00\x00"
  assert_eq(validate_player_wav(@base64.encode(wav)), wav)
  try validate_player_wav(@base64.encode(b"not audio")) catch {
    _ => ()
  } noraise {
    _ => fail("Expected invalid WAV rejection")
  }
  try validate_player_wav("A".repeat(350001)) catch {
    _ => ()
  } noraise {
    _ => fail("Expected size rejection")
  }
}

///|
async test "opt-in Player model acceptance transcribes and translates a real Mandarin WAV through the public route" {
  guard @env.get_env_var("MOONCAST_PLAYER_CAPTION_TEST_AUDIO") is Some(path) else {
    return
  }
  let service = StudioService::new(
    "/tmp/mooncast-player-acceptance-" + @async.now().to_string(),
  )
  let audio = @base64.encode(@fs.read_file(path).binary())
  for target in ["en", "ja", "fr"] {
    let body : Json = { "audio": audio, "target_language": target }
    let response = service.dispatch_http({
      request_method: Post,
      path: "/api/player/captions",
      query: None,
      headers: Map([]),
      body: @utf8.encode(body.stringify()),
    })
    assert_eq(response.status, 200)
    guard @json.parse(@utf8.decode(response.body))
      is { "text": String(text), "translation": String(translation), .. } else {
      fail("Invalid model response")
    }
    assert_true(text.contains("字幕"))
    assert_false(text.contains("<asr_text>"))
    assert_true(!translation.is_blank())
    assert_false(translation.contains("请将以下文本"))
    assert_false(translation.contains("Translate the following"))
    if target == "en" {
      for ch in translation {
        assert_false(ch >= '\u4e00' && ch <= '\u9fff')
      }
    }
  }
}

///|
async test "Player caption route rejects malformed audio and unsupported languages before model calls" {
  let service = StudioService::new(
    "/tmp/mooncast-player-invalid-" + @async.now().to_string(),
  )
  for
    body in [
      "{\"audio\":\"AAAA\",\"target_language\":\"en\"}", "{\"audio\":\"AAAA\",\"target_language\":\"unknown\"}",
    ] {
    let response = service.dispatch_http({
      request_method: Post,
      path: "/api/player/captions",
      query: None,
      headers: Map([]),
      body: @utf8.encode(body),
    })
    assert_eq(response.status, 422)
  }
}
