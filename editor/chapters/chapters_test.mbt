///|
fn example() -> @chapters.Draft {
  {
    contract: "mooncast.chapter-draft.v1",
    project_id: "project.example",
    project_revision: 7,
    timeline_id: "timeline.example",
    timeline_revision: 3,
    ticks_per_second: 24,
    duration_ticks: 72,
    markers: [
      { marker_id: "opening", start_tick: 0, title: "Opening", },
      { marker_id: "answer", start_tick: 25, title: "Answer", },
    ],
  }
}

///|
test "chapter draft survives portable JSON" {
  let draft = example()
  let reopened = @chapters.read_draft(draft.to_json().stringify())
  assert_true(reopened == draft)
  assert_eq(reopened.project_revision, 7)
  assert_eq(reopened.timeline_revision, 3)
}

///|
test "edit rename move add and remove without modifying original" {
  let original = example()
  let renamed = original.put({
    marker_id: "answer",
    start_tick: 48,
    title: "结语",
  })
  assert_eq(original.markers[1].start_tick, 25)
  assert_eq(renamed.markers[1].title, "结语")
  let inserted = renamed.put({
    marker_id: "middle",
    start_tick: 24,
    title: "Middle",
  })
  assert_eq(inserted.markers[1].marker_id, "middle")
  let removed = inserted.remove("answer")
  assert_eq(removed.markers.length(), 2)
  assert_eq(inserted.markers.length(), 3)
  assert_true((try? original.remove("unknown")) is Err(_))
}

///|
test "exact tick metadata and shared millisecond VTT boundaries" {
  let draft = example()
  assert_true(draft.ffmetadata().contains("TIMEBASE=1/24\nSTART=0\nEND=25"))
  assert_true(draft.ffmetadata().contains("START=25\nEND=72"))
  let vtt = draft.webvtt()
  assert_true(vtt.contains("00:00:00.000 --> 00:00:01.041"))
  assert_true(vtt.contains("00:00:01.041 --> 00:00:03.000"))
}

///|
test "escaping preserves Unicode titles in both target formats" {
  let draft = example().put({
    marker_id: "opening",
    start_tick: 0,
    title: "A=B; #\\ <猫> & C",
  })
  assert_true(draft.ffmetadata().contains("title=A\\=B\\; \\#\\\\ <猫> & C"))
  assert_true(draft.webvtt().contains("A=B; #\\ &lt;猫&gt; &amp; C"))
  assert_true(
    (try? draft.put({ marker_id: "opening", start_tick: 0, title: "a\nb", }))
    is Err(_),
  )
}

///|
test "chapter starts reject duplicates negative and beyond end" {
  let draft = example()
  for tick in [-1, 25, 72, 100] {
    assert_true(
      (try? draft.put({ marker_id: "new", start_tick: tick, title: "New", }))
      is Err(_),
    )
  }
  assert_true(
    (try? draft.put({ marker_id: "new", start_tick: 50, title: " ", }))
    is Err(_),
  )
  assert_true(
    (try? draft.put({ marker_id: "", start_tick: 50, title: "New", })) is Err(_),
  )
}

///|
test "invalid imported drafts do not silently reorder or drop chapters" {
  let draft = example()
  let invalid = { ..draft, markers: [draft.markers[1], draft.markers[0]], }
  assert_true((try? invalid.validate()) is Err(_))
  let duplicate = {
    ..draft,
    markers: [draft.markers[0], { ..draft.markers[1], marker_id: "opening", }],
  }
  assert_true((try? duplicate.validate()) is Err(_))
  let empty = { ..draft, markers: [], }
  assert_true((try? empty.validate()) is Err(_))
  let wrong_clock = { ..draft, ticks_per_second: 0, }
  assert_true((try? wrong_clock.validate()) is Err(_))
}

///|
test "submillisecond chapters remain exact in metadata and fail VTT" {
  let draft = { ..example(), ticks_per_second: 100000, }
  assert_true(draft.ffmetadata().contains("TIMEBASE=1/100000"))
  assert_true((try? draft.webvtt()) is Err(_))
}

///|
test "leading gap and long duration use nonoverflowing timestamp arithmetic" {
  let draft = {
    ..example(),
    ticks_per_second: 1,
    duration_ticks: 2147483647,
    markers: [{ marker_id: "chapter", start_tick: 5, title: "Long", }],
  }
  assert_true(draft.webvtt().contains("00:00:05.000 --> 596523:14:07.000"))
  assert_true(draft.ffmetadata().contains("START=5\nEND=2147483647"))
  assert_true((try? draft.remove("chapter")) is Err(_))
}

///|
test "metadata trailing backslash refuses FFmpeg line continuation ambiguity" {
  let draft = example().put({
    marker_id: "opening",
    start_tick: 0,
    title: "Folder\\",
  })
  assert_true((try? draft.ffmetadata()) is Err(_))
  assert_true(draft.webvtt().contains("Folder\\"))
}
