///|
fn imported_example() -> @chapters.Draft {
  {
    contract: "mooncast.chapter-draft.v1",
    project_id: "project.source",
    project_revision: 9,
    timeline_id: "timeline.source",
    timeline_revision: 4,
    ticks_per_second: 24,
    duration_ticks: 72,
    markers: [{ marker_id: "old", start_tick: 0, title: "Old", }],
  }
}

///|
fn metadata_sample() -> String {
  ";FFMETADATA1\nencoder=external editor\n[CHAPTER]\nTIMEBASE=1/24\nSTART=0\nEND=25\ntitle=猫 A\\=B\\; \\# C\\\\D\n[CHAPTER]\nTIMEBASE=1/24\nSTART=25\nEND=72\ntitle=Finale\n"
}

///|
test "import external chapter titles and exact frames then edit and export" {
  let source = imported_example()
  let imported = source.import_ffmetadata(metadata_sample())
  assert_eq(imported.project_id, source.project_id)
  assert_eq(imported.project_revision, 9)
  assert_eq(imported.timeline_revision, 4)
  assert_eq(imported.markers[1].start_tick, 25)
  assert_eq(imported.markers[0].title, "猫 A=B; # C\\D")
  assert_eq(source.markers[0].title, "Old")
  let reopened = @chapters.read_draft(imported.to_json().stringify())
  assert_true(reopened == imported)
  assert_true(imported.import_ffmetadata(imported.ffmetadata()) == imported)
  let edited = reopened.put({
    marker_id: "imported.2",
    start_tick: 48,
    title: "Edited",
  })
  assert_true(edited.webvtt().contains("00:00:02.000"))
  assert_true(edited.ffmetadata().contains("START=48"))
}

///|
test "nanosecond input rational clocks CRLF leading gap and comments" {
  let text = ";FFMETADATA1\r\n;comment\r\n[CHAPTER]\r\nTIMEBASE=1/1000000000\r\nSTART=1000000000\r\nEND=3000000000\r\ntitle=One\r\n"
  let imported = imported_example().import_ffmetadata(text)
  assert_eq(imported.markers[0].start_tick, 24)
  let rational = text.replace_all(old="1/1000000000", new="3/3000000000")
  assert_true(imported_example().import_ffmetadata(rational) == imported)
}

///|
test "unsupported structures refuse rather than silently retime" {
  let text = metadata_sample()
  for
    invalid in [
      text.replace_all(old="START=25", new="START=26"),
      text.replace_all(old="START=25", new="START=24"),
      text.replace_all(old="END=72", new="END=71"),
      text.replace_all(old="END=72", new="END=73"),
      text.replace_all(old="END=25", new="END=0"),
      text.replace_all(old="1/24", new="1/25"),
      text.replace_all(old="1/24", new="0/24"),
      text.replace_all(old="1/24", new="1/0"),
      text.replace_all(old="START=25", new="START=-1"),
      text.replace_all(old="START=25", new="START=9223372036854775808"),
      text.replace_all(old="START=25", new="START=9223372036854775807"),
      text.replace_all(old="title=Finale", new="title=Finale\ntitle=duplicate"),
      text.replace_all(old="title=Finale", new="unknown=Finale"),
      text.replace_all(old="title=Finale", new="title="),
      text.replace_all(old="title=Finale", new="title=a\\\nb"),
      text.replace_all(old="title=Finale", new="title=a#b"),
      text.replace_all(old="[CHAPTER]", new="[STREAM]"),
      "wrong header\n",
      ";FFMETADATA1\n",
    ] {
    assert_true((try? imported_example().import_ffmetadata(invalid)) is Err(_))
  }
}

///|
test "large exact clocks reduce before multiplying and input bounds hold" {
  let source = {
    ..imported_example(),
    ticks_per_second: 2147483647,
    duration_ticks: 2147483647,
  }
  let text = ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=2147483647/2147483647\nSTART=0\nEND=1\ntitle=All\n"
  assert_eq(source.import_ffmetadata(text).markers.length(), 1)
  assert_true((try? source.import_ffmetadata("x".repeat(2097153))) is Err(_))
  assert_true(
    (try? source.import_ffmetadata(
      ";FFMETADATA1\n" + "[CHAPTER]\n".repeat(1001),
    ))
    is Err(_),
  )
}
