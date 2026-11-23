///|
test "preview sizing preserves orientation and playback rate is bounded" {
  let base = initial_model()
  assert_eq(program_width(base), 960.0)
  assert_eq(program_height(base), 540.0)
  let hd = { ..base, preview_height: 720, playback_speed: "2", }
  assert_eq(program_width(hd), 1280.0)
  assert_eq(program_height(hd), 720.0)
  assert_eq(playback_rate(hd), 2.0)
  assert_eq(playback_rate({ ..base, playback_speed: "100", }), 4.0)
  assert_eq(playback_rate({ ..base, playback_speed: "invalid", }), 1.0)
}

///|
test "old caption replies cannot overwrite current request or another project" {
  let base = {
    ..initial_model(),
    local_caption_pending: "current",
    local_caption_text: "keep",
  }
  let ignored = update(
      _ => @rabbita.none,
      LocalCaptionsLoaded("old", Ok(Json::object({ "text": Json("stale") }))),
      base,
    ).1
  assert_eq(ignored.local_caption_pending, "current")
  assert_eq(ignored.local_caption_text, "keep")
  let other = activate_editor_project(base, "other")
  assert_eq(other.local_caption_pending, "")
  assert_eq(other.local_caption_text, "")
  assert_eq(local_caption_identity(other), "")
}
