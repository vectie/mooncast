///|
priv struct PlayerCaptionRequest {
  audio : String
  target_language : String
} derive(FromJson)

///|
fn player_translation_language(code : String) -> String? {
  match code {
    "off" => Some("")
    "en" => Some("英语")
    "zh" => Some("简体中文")
    "ja" => Some("日语")
    "ko" => Some("韩语")
    "fr" => Some("法语")
    "de" => Some("德语")
    "es" => Some("西班牙语")
    "ru" => Some("俄语")
    "ar" => Some("阿拉伯语")
    _ => None
  }
}

///|
fn player_asr_text(raw : String) -> String {
  let parts = raw.split("<asr_text>").to_array()
  let text = parts[parts.length() - 1].to_owned()
  text.split("<|endoftext|>").join("").trim().to_owned()
}

///|
fn validate_player_wav(audio : String) -> Bytes raise {
  guard audio.length() <= 350000 else { fail("Audio window is too large.") }
  let wav = @base64.decode(audio)
  guard wav.length() >= 48 && wav.length() <= 256044 &&
    wav[:4] == b"RIFF"[:] && wav[8:12] == b"WAVE"[:] &&
    wav[12:16] == b"fmt "[:] && wav[16:20] == b"\x10\x00\x00\x00"[:] &&
    wav[20:24] == b"\x01\x00\x01\x00"[:] &&
    wav[24:28] == b"\x80\x3e\x00\x00"[:] &&
    wav[28:32] == b"\x00\x7d\x00\x00"[:] &&
    wav[32:36] == b"\x02\x00\x10\x00"[:] &&
    wav[36:40] == b"data"[:] && wav.length() % 2 == 0 else {
    fail("Expected a short mono 16 kHz PCM16 WAV audio window.")
  }
  let riff_size = wav[4].to_int() + (wav[5].to_int() << 8) + (wav[6].to_int() << 16) + (wav[7].to_int() << 24)
  let data_size = wav[40].to_int() + (wav[41].to_int() << 8) + (wav[42].to_int() << 16) + (wav[43].to_int() << 24)
  guard riff_size == wav.length() - 8 && data_size == wav.length() - 44 else { fail("Audio window length does not match WAV headers.") }
  wav
}

///|
async fn player_model_call(arguments : Array[String], label : String) -> Json raise {
  let result = @process.run_capture({
    executable: "/usr/bin/curl",
    arguments: ["--silent", "--show-error", "--fail", "--connect-timeout", "3", "--max-time", "30", ..arguments],
    working_directory: None,
    timeout_ms: 35000,
    max_output_bytes: 65536,
  })
  guard result.exit_code == Some(0) && !result.timed_out && !result.output_truncated else {
    fail(label + " is unavailable. Start the local model service and retry captions.")
  }
  @json.parse(@utf8.decode(result.stdout))
}

///|
async fn StudioService::player_caption_response(self : StudioService, request : @host_http.Request) -> @host_http.Response {
  try {
    guard request.body.length() <= 360000 else { fail("Audio window is too large.") }
    let input : PlayerCaptionRequest = @json.from_json(@json.parse(@utf8.decode(request.body)))
    guard player_translation_language(input.target_language) is Some(language) else {
      fail("Choose a supported translation language.")
    }
    let wav = validate_player_wav(input.audio)
    guard local_caption_slots.try_acquire() else { fail("Local speech model is busy. Retry captions shortly.") }
    defer local_caption_slots.release()
    let key = "player-audio-" + @async.now().to_string() + ".wav"
    let path = self.editor_render_files.prepare_owned_path(key)
    defer ignore(self.editor_render_files.remove(key))
    ignore(self.editor_render_files.put_blob(key, wav))
    let asr = player_model_call([
      "http://127.0.0.1:18731/v1/audio/transcriptions",
      "-F", "file=@" + path + ";type=audio/wav",
      "-F", "model=qwen3-asr-1.7b",
      "-F", "response_format=json",
    ], "Qwen ASR on port 18731")
    guard asr is { "text": String(raw), .. } else { fail("Local ASR returned an invalid response.") }
    let text = player_asr_text(raw)
    let translation = if language == "" || text.is_blank() {
      ""
    } else {
      let body : Json = {
        "model": "index-translate-2b",
        "messages": [{ "role": "user", "content": "请将以下文本翻译为" + language + "，直接输出翻译结果，不要进行任何解释。\n\n" + text }],
        "temperature": 0,
        "max_tokens": 512,
        "stream": false,
        "chat_template_kwargs": { "enable_thinking": false },
      }
      let result = player_model_call([
        "http://127.0.0.1:18732/v1/chat/completions",
        "-H", "Content-Type: application/json",
        "--data-binary", body.stringify(),
      ], "Index translation on port 18732")
      match result {
        { "choices": [{ "message": { "content": String(content), .. }, .. }, ..], .. } => content.trim().to_owned()
        _ => fail("Local translation returned an invalid response.")
      }
    }
    let response : Json = { "text": text, "translation": translation }
    @host_http.json_response(200, "OK", response.stringify())
  } catch {
    error => @host_http.json_response(422, "Unprocessable Content", ({ "error": error.to_string() } : Json).stringify())
  }
}
