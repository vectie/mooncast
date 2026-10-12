///|
test "local transcript file types survive missing and generic browser MIME values" {
  assert_eq(local_media_mime("interview.JSON", ""), "application/json")
  assert_eq(
    local_media_mime("interview.tsv", "application/octet-stream"),
    "text/tab-separated-values",
  )
  assert_eq(local_media_mime("labels.txt", ""), "text/plain")
  assert_eq(local_media_mime("captions.srt", ""), "application/x-subrip")
  assert_eq(local_media_mime("voice.wav", "audio/wav"), "audio/wav")
  assert_eq(local_media_mime("unknown", ""), "application/octet-stream")
}

///|
test "transcript intake advertises formats and preserves rights metadata after source choice" {
  let model = initial_model()
  let (_, selected) = update(
    _ => @rabbita.none,
    IntakeChanged("role", "subtitle"),
    model,
  )
  assert_eq(selected.intake.role, "subtitle")
  assert_eq(selected.intake.owner, model.intake.owner)
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(media_intake_view(_ => @rabbita.none, selected)),
  )
  assert_true(html.contains(".json,.tsv"))
  assert_true(html.contains("Whisper JSON"))
  assert_true(html.contains("Audacity region-label"))
  assert_true(html.contains("Rights owner"))
}
