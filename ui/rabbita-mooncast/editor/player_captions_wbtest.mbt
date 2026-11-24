///|
test "standalone Player exposes captions translation languages and local model disclosure without a project" {
  let model = {
    ..initial_model(),
    workspace_lens: PlayerLens,
    player_file_url: "blob:test",
  }
  let markup = @rabbita.render_to_string(
    @rabbita.static_cell(standalone_player_view(_ => @rabbita.none, model)),
  )
  assert_true(markup.contains("Live captions"))
  assert_true(markup.contains("Translate to"))
  assert_true(markup.contains("日本語"))
  assert_true(markup.contains("Local model details"))
  assert_false(markup.contains("Whisper"))
  let live = {
    ..model,
    player_captions: {
      ..PlayerCaptions::new(),
      enabled: true,
      target: "ja",
      generation: 4,
    },
  }
  let switched = activate_editor_project(live, "different-project")
  assert_true(switched.player_captions.enabled)
  assert_eq(switched.player_captions.target, "ja")
  assert_eq(switched.player_captions.generation, 4)
}

///|
test "caption results are discarded after seeking switching file target or stopping but release the one request slot" {
  let active : PlayerCaptions = {
    ..PlayerCaptions::new(),
    enabled: true,
    generation: 2,
    pending: "chunk",
  }
  let result : Result[Json, Error] = Ok({
    "text": "字幕",
    "translation": "Captions",
  })
  let ready = player_caption_reply(active, 2, "chunk", result)
  assert_eq(ready.text, "字幕")
  assert_eq(ready.translation, "Captions")
  assert_eq(ready.pending, "")
  let seeked = active.invalidate()
  assert_eq(seeked.pending, "chunk")
  let stale = player_caption_reply(seeked, 2, "chunk", result)
  assert_eq(stale.text, "")
  assert_eq(stale.pending, "")
  let stopped = { ..active, enabled: false, }
  assert_eq(player_caption_reply(stopped, 2, "chunk", result).text, "")
  assert_eq(
    player_caption_reply(active, 2, "other-file", result).pending,
    "chunk",
  )
  let failed = player_caption_reply(
    active,
    2,
    "chunk",
    Ok({ "error": "Model not available" }),
  )
  assert_false(failed.enabled)
  assert_eq(failed.error, "Model not available")
}
