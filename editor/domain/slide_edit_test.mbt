///|
fn slide_native_journey(command : @domain.EditCommand) -> Unit raise {
  let base = roll_source_project()
  let original_track = base.timeline.tracks[0]
  let after = { ..original_track.clips[0], clip_id: "after", start_tick: 6000, }
  let outside = {
    ..original_track,
    track_id: "other",
    clips: [{ ..after, clip_id: "other-clip", }],
  }
  let before = {
    ..base,
    timeline: {
      ..base.timeline,
      output: {
        ..base.timeline.output,
        fps: { numerator: 25, denominator: 1, },
      },
      tracks: [
        { ..original_track, clips: original_track.clips + [after], },
        outside,
      ],
    },
  }
  let session = @domain.EditorSession::new(before)
  let slid = session.dispatch(command)
  let track = slid.snapshot.timeline.tracks[0]
  assert_eq(track.clips[0], {
    ..original_track.clips[0],
    source_out_tick: 3040,
    duration_ticks: 2040,
  })
  assert_eq(track.clips[1], { ..original_track.clips[1], start_tick: 2040, })
  assert_eq(track.clips[2], {
    ..original_track.clips[2],
    source_in_tick: 1040,
    start_tick: 4040,
    duration_ticks: 1960,
  })
  assert_eq(track.clips[0].start_tick, 0)
  assert_eq(track.clips[2].start_tick + track.clips[2].duration_ticks, 6000)
  assert_eq(track.clips[3], after)
  assert_eq(slid.snapshot.timeline.tracks[1], outside)
  assert_eq(slid.snapshot.revision, 8)
  assert_eq(slid.command_log.length(), 1)
  assert_eq(slid.dispatch(command), slid)
  assert_true(
    (try? slid.dispatch({ ..command, command_id: "stale.slide", })) is Err(_),
  )
  let undo = {
    ..command,
    command_id: "undo.slide",
    expected_revision: 8,
    operation: @domain.Undo(target_command_id=Some(command.command_id)),
  }
  let undone = slid.dispatch(undo)
  assert_eq(undone.snapshot.timeline.tracks, before.timeline.tracks)
  let redo = {
    ..command,
    command_id: "redo.slide",
    expected_revision: 9,
    operation: @domain.Redo(target_command_id=Some(command.command_id)),
  }
  let redone = undone.dispatch(redo)
  assert_eq(redone.snapshot.timeline.tracks, slid.snapshot.timeline.tracks)
  assert_eq(@domain.replay(before, [command, undo, redo]), redone)
  let restore = {
    ..command,
    command_id: "reverse.slide",
    expected_revision: 10,
    operation: @domain.GroupTrim(
      original_track.clips.map(clip => {
        clip_id: clip.clip_id,
        source_in_tick: clip.source_in_tick,
        source_out_tick: clip.source_out_tick,
        start_tick: Some(clip.start_tick),
      }),
    ),
  }
  assert_eq(
    redone.dispatch(restore).snapshot.timeline.tracks,
    before.timeline.tracks,
  )
  guard command.operation is @domain.GroupTrim(trims) else {
    fail("Expected three canonical trims")
  }
  assert_eq(trims.length(), 3)
  let broken = {
    ..command,
    operation: @domain.GroupTrim([
      trims[0],
      trims[1],
      { ..trims[2], clip_id: "missing", },
    ]),
  }
  assert_true((try? session.dispatch(broken)) is Err(_))
  assert_eq(session.snapshot, before)
  assert_eq(session.command_log.length(), 0)
}

///|
test "slide canonical group trim keeps shot content outer timing and atomic history" {
  let command = @domain.command_from_json(
    (
      {
        "contract": "mooncast.editor-edit-command.v1",
        "command_id": "slide.1",
        "expected_revision": 7,
        "actor": { "actor_id": "editor", "provenance": "slide-test" },
        "type": "group_trim",
        "payload": {
          "trims": [
            {
              "clip_id": "template.a",
              "source_in_tick": 1000,
              "source_out_tick": 3040,
              "start_tick": 0,
            },
            {
              "clip_id": "template.b",
              "source_in_tick": 1000,
              "source_out_tick": 3000,
              "start_tick": 2040,
            },
            {
              "clip_id": "tail",
              "source_in_tick": 1040,
              "source_out_tick": 3000,
              "start_tick": 4040,
            },
          ],
        },
      } : Json).stringify(),
  )
  slide_native_journey(command)
}
