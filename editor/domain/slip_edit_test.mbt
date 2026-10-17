///|
test "slip canonical Trim preserves timing lineage neighbors undo redo and revision guard" {
  let command = @domain.command_from_json(({
    "contract": "mooncast.editor-edit-command.v1", "command_id": "slip.1", "expected_revision": 7,
    "actor": { "actor_id": "editor", "provenance": "slip-test" }, "type": "trim",
    "payload": { "clip_id": "template.a", "source_in_tick": 1040, "source_out_tick": 3040, "start_tick": 0 },
  } : Json).stringify())
  slip_native_journey(command)
}

///|
fn slip_native_journey(command : @domain.EditCommand) -> Unit raise {
  let before = roll_source_project()
  let session = @domain.EditorSession::new(before)
  let slipped = session.dispatch(command)
  let original = before.timeline.tracks[0].clips[0]
  assert_eq(slipped.snapshot.timeline.tracks[0].clips[0], {
    ..original, source_in_tick: 1040, source_out_tick: 3040,
  })
  assert_eq(slipped.snapshot.timeline.tracks[0].clips[1], before.timeline.tracks[0].clips[1])
  assert_eq(slipped.snapshot.timeline.tracks[0].clips[2], before.timeline.tracks[0].clips[2])
  assert_eq(slipped.snapshot.revision, 8)
  assert_eq(slipped.command_log.length(), 1)
  assert_eq(slipped.dispatch(command), slipped)
  assert_true((try? slipped.dispatch({ ..command, command_id: "stale", })) is Err(_))
  assert_eq(session.snapshot, before)
  let undo = { ..command, command_id: "undo.slip", expected_revision: 8,
    operation: @domain.Undo(target_command_id=Some("slip.1")), }
  let undone = slipped.dispatch(undo)
  assert_eq(undone.snapshot.timeline.tracks, before.timeline.tracks)
  let redo = { ..command, command_id: "redo.slip", expected_revision: 9,
    operation: @domain.Redo(target_command_id=Some("slip.1")), }
  let redone = undone.dispatch(redo)
  assert_eq(redone.snapshot.timeline.tracks, slipped.snapshot.timeline.tracks)
  assert_eq(@domain.replay(before, [command, undo, redo]), redone)
  let earlier = redone.dispatch({ ..command, command_id: "slip.earlier", expected_revision: 10,
    operation: @domain.Trim(clip_id="template.a", source_in_tick=1000, source_out_tick=3000, start_tick=Some(0)), })
  assert_eq(earlier.snapshot.timeline.tracks, before.timeline.tracks)
}
