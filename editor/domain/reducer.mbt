///|
fn locate_track(
  project : EditorProject,
  track_id : String,
) -> Int raise EditorError {
  for index, track in project.timeline.tracks {
    if track.track_id == track_id {
      return index
    }
  }
  raise UnknownTrack(track_id)
}

///|
fn locate_clip(
  project : EditorProject,
  clip_id : String,
) -> (Int, Int) raise EditorError {
  for track_index, track in project.timeline.tracks {
    for clip_index, clip in track.clips {
      if clip.clip_id == clip_id {
        return (track_index, clip_index)
      }
    }
  }
  raise UnknownClip(clip_id)
}

///|
fn has_clip(project : EditorProject, clip_id : String) -> Bool {
  project.timeline.tracks.any(track => {
    track.clips.any(clip => clip.clip_id == clip_id)
  })
}

///|
fn ordered_clips(clips : Array[Clip]) -> Array[Clip] {
  let result : Array[Clip] = []
  for clip in clips {
    let mut inserted = false
    let next : Array[Clip] = []
    for current in result {
      if !inserted &&
        (
          clip.start_tick < current.start_tick ||
          (
            clip.start_tick == current.start_tick &&
            clip.clip_id < current.clip_id
          )
        ) {
        next.push(clip)
        inserted = true
      }
      next.push(current)
    }
    if !inserted {
      next.push(clip)
    }
    result.clear()
    result.append(next)
  }
  result
}

///|
fn with_tracks(project : EditorProject, tracks : Array[Track]) -> EditorProject {
  { ..project, timeline: { ..project.timeline, tracks, } }
}

///|
fn put_track(
  project : EditorProject,
  index : Int,
  track : Track,
) -> EditorProject {
  let tracks = project.timeline.tracks.copy()
  tracks[index] = { ..track, clips: ordered_clips(track.clips) }
  with_tracks(project, tracks)
}

///|
fn put_clip(
  project : EditorProject,
  track_index : Int,
  clip_index : Int,
  clip : Clip,
) -> EditorProject {
  let track = project.timeline.tracks[track_index]
  let clips = track.clips.copy()
  clips[clip_index] = clip
  put_track(project, track_index, { ..track, clips, })
}

///|
fn remove_clip(
  project : EditorProject,
  track_index : Int,
  clip_id : String,
) -> EditorProject {
  let track = project.timeline.tracks[track_index]
  put_track(project, track_index, {
    ..track,
    clips: track.clips.filter(clip => clip.clip_id != clip_id),
  })
}

///|
fn add_clip(
  project : EditorProject,
  track_index : Int,
  clip : Clip,
) -> EditorProject raise EditorError {
  guard !has_clip(project, clip.clip_id) else {
    raise DuplicateId(clip.clip_id)
  }
  let track = project.timeline.tracks[track_index]
  let clips = track.clips.copy()
  clips.push(clip)
  put_track(project, track_index, { ..track, clips, })
}

///|
fn shift_suffix(
  track : Track,
  from_tick : Int,
  delta : Int,
  excluded : String?,
) -> Track {
  {
    ..track,
    clips: track.clips.map(clip => {
      if clip.start_tick >= from_tick && Some(clip.clip_id) != excluded {
        { ..clip, start_tick: clip.start_tick + delta }
      } else {
        clip
      }
    }),
  }
}

///|
fn insert_tick(
  track : Track,
  before_clip_id : String?,
) -> Int raise EditorError {
  match before_clip_id {
    Some(id) => {
      for clip in track.clips {
        if clip.clip_id == id {
          return clip.start_tick
        }
      }
      raise UnknownClip(id)
    }
    None =>
      track.clips.fold(init=0, (end_tick, clip) => {
        Int::max(end_tick, clip.start_tick + clip.duration_ticks)
      })
  }
}

///|
fn ripple_insert(
  project : EditorProject,
  track_index : Int,
  clip : Clip,
  before_clip_id : String?,
) -> EditorProject raise EditorError {
  guard !has_clip(project, clip.clip_id) else {
    raise DuplicateId(clip.clip_id)
  }
  let track = project.timeline.tracks[track_index]
  let start = insert_tick(track, before_clip_id)
  let shifted = shift_suffix(track, start, clip.duration_ticks, None)
  let clips = shifted.clips.copy()
  clips.push({ ..clip, start_tick: start })
  put_track(project, track_index, { ..shifted, clips, })
}

///|
fn set_project_revision(
  project : EditorProject,
  revision : Int,
) -> EditorProject {
  { ..project, revision, timeline: { ..project.timeline, revision, } }
}

///|
fn split_one(
  project : EditorProject,
  clip_id : String,
  split_tick : Int,
  left_id : String,
  right_id : String,
) -> EditorProject raise EditorError {
  let (track_index, clip_index) = locate_clip(project, clip_id)
  let clip = project.timeline.tracks[track_index].clips[clip_index]
  let offset = split_tick - clip.start_tick
  guard offset > 0 && offset < clip.duration_ticks else {
    raise InvalidCommand("split_tick must be inside the clip")
  }
  guard left_id != right_id else { raise DuplicateId(left_id) }
  guard left_id == clip_id || !has_clip(project, left_id) else {
    raise DuplicateId(left_id)
  }
  guard right_id == clip_id || !has_clip(project, right_id) else {
    raise DuplicateId(right_id)
  }
  let (left_keyframes, right_keyframes) = split_keyframes(
    clip.keyframes,
    offset,
  )
  let left = {
    ..clip,
    clip_id: left_id,
    duration_ticks: offset,
    source_out_tick: clip.source_in_tick + offset,
    keyframes: left_keyframes,
  }
  let right = {
    ..clip,
    clip_id: right_id,
    start_tick: split_tick,
    duration_ticks: clip.duration_ticks - offset,
    source_in_tick: clip.source_in_tick + offset,
    keyframes: right_keyframes,
  }
  let track = project.timeline.tracks[track_index]
  let clips = track.clips.filter(value => value.clip_id != clip_id)
  clips.push(left)
  clips.push(right)
  put_track(project, track_index, { ..track, clips, })
}

///|
fn apply_edit(
  snapshot : EditorProject,
  operation : EditOperation,
) -> EditorProject raise EditorError {
  match operation {
    Add(track_id~, clip~) =>
      add_clip(snapshot, locate_track(snapshot, track_id), clip)
    RippleInsert(track_id~, clip~, before_clip_id~) =>
      ripple_insert(
        snapshot,
        locate_track(snapshot, track_id),
        clip,
        before_clip_id,
      )
    Move(clip_id~, track_id~, start_tick~) => {
      let (source_index, clip_index) = locate_clip(snapshot, clip_id)
      let target_index = locate_track(snapshot, track_id)
      let source = snapshot.timeline.tracks[source_index]
      let target = snapshot.timeline.tracks[target_index]
      guard source.kind == target.kind else { raise IncompatibleTrack(clip_id) }
      let clip = { ..source.clips[clip_index], start_tick, }
      let removed = remove_clip(snapshot, source_index, clip_id)
      let adjusted_target = locate_track(removed, track_id)
      let target_track = removed.timeline.tracks[adjusted_target]
      let clips = target_track.clips.copy()
      clips.push(clip)
      put_track(removed, adjusted_target, { ..target_track, clips, })
    }
    RippleMove(clip_id~, track_id~, before_clip_id~) => {
      let (source_index, clip_index) = locate_clip(snapshot, clip_id)
      let source = snapshot.timeline.tracks[source_index]
      let target_index = locate_track(snapshot, track_id)
      guard source.kind == snapshot.timeline.tracks[target_index].kind else {
        raise IncompatibleTrack(clip_id)
      }
      guard before_clip_id != Some(clip_id) else {
        raise InvalidCommand("clip cannot be inserted before itself")
      }
      let clip = source.clips[clip_index]
      let old_end = clip.start_tick + clip.duration_ticks
      let removed = remove_clip(snapshot, source_index, clip_id)
      let closed_source = shift_suffix(
        removed.timeline.tracks[source_index],
        old_end,
        -clip.duration_ticks,
        None,
      )
      let closed = put_track(removed, source_index, closed_source)
      ripple_insert(
        closed,
        locate_track(closed, track_id),
        clip,
        before_clip_id,
      )
    }
    Trim(clip_id~, source_in_tick~, source_out_tick~, start_tick~) => {
      guard source_out_tick > source_in_tick else {
        raise InvalidCommand("trim range must be nonempty")
      }
      let (track_index, clip_index) = locate_clip(snapshot, clip_id)
      let old = snapshot.timeline.tracks[track_index].clips[clip_index]
      let start = match start_tick {
        Some(value) => value
        None => old.start_tick
      }
      put_clip(snapshot, track_index, clip_index, {
        ..old,
        start_tick: start,
        source_in_tick,
        source_out_tick,
        duration_ticks: source_out_tick - source_in_tick,
      })
    }
    RippleTrim(clip_id~, source_in_tick~, source_out_tick~) => {
      guard source_out_tick > source_in_tick else {
        raise InvalidCommand("trim range must be nonempty")
      }
      let (track_index, clip_index) = locate_clip(snapshot, clip_id)
      let track = snapshot.timeline.tracks[track_index]
      let old = track.clips[clip_index]
      let old_end = old.start_tick + old.duration_ticks
      let new_duration = source_out_tick - source_in_tick
      let clips = track.clips.map(clip => {
        if clip.clip_id == clip_id {
          {
            ..clip,
            source_in_tick,
            source_out_tick,
            duration_ticks: new_duration,
          }
        } else if clip.start_tick >= old_end {
          {
            ..clip,
            start_tick: clip.start_tick + new_duration - old.duration_ticks,
          }
        } else {
          clip
        }
      })
      put_track(snapshot, track_index, { ..track, clips, })
    }
    Split(clip_id~, split_tick~, left_clip_id~, right_clip_id~) =>
      split_one(snapshot, clip_id, split_tick, left_clip_id, right_clip_id)
    Delete(clip_id~) => {
      let (track_index, _) = locate_clip(snapshot, clip_id)
      remove_clip(snapshot, track_index, clip_id)
    }
    RippleDelete(clip_id~) => {
      let (track_index, clip_index) = locate_clip(snapshot, clip_id)
      let track = snapshot.timeline.tracks[track_index]
      let clip = track.clips[clip_index]
      let end_tick = clip.start_tick + clip.duration_ticks
      let kept = track.clips.filter(value => value.clip_id != clip_id)
      put_track(
        snapshot,
        track_index,
        shift_suffix(
          { ..track, clips: kept },
          end_tick,
          -clip.duration_ticks,
          None,
        ),
      )
    }
    GroupMove(moves) => {
      let mut state = snapshot
      for edit_move in moves {
        state = apply_edit(
          state,
          Move(
            clip_id=edit_move.clip_id,
            track_id=edit_move.track_id,
            start_tick=edit_move.start_tick,
          ),
        )
      }
      state
    }
    GroupRippleMove(clip_ids~, track_id~, before_clip_id~) => {
      guard !clip_ids.is_empty() else {
        raise InvalidCommand("group must not be empty")
      }
      let mut state = snapshot
      let mut anchor = before_clip_id
      for clip_id in clip_ids.rev() {
        state = apply_edit(
          state,
          RippleMove(clip_id~, track_id~, before_clip_id=anchor),
        )
        anchor = Some(clip_id)
      }
      state
    }
    GroupDelete(ids) => {
      let mut state = snapshot
      for id in ids {
        state = apply_edit(state, Delete(clip_id=id))
      }
      state
    }
    GroupTrim(trims) => {
      let mut state = snapshot
      for trim in trims {
        state = apply_edit(
          state,
          Trim(
            clip_id=trim.clip_id,
            source_in_tick=trim.source_in_tick,
            source_out_tick=trim.source_out_tick,
            start_tick=trim.start_tick,
          ),
        )
      }
      state
    }
    ConfigureClip(clip_id~, settings~) => {
      let (ti, ci) = locate_clip(snapshot, clip_id)
      put_clip(snapshot, ti, ci, {
        ..snapshot.timeline.tracks[ti].clips[ci],
        settings,
      })
    }
    ConfigureTrack(track_id~, mix~) => {
      let ti = locate_track(snapshot, track_id)
      let track = snapshot.timeline.tracks[ti]
      put_track(snapshot, ti, { ..track, mix: Some(mix) })
    }
    ConfigureOutput(output) =>
      { ..snapshot, timeline: { ..snapshot.timeline, output, } }
    SetKeyframes(clip_id~, keyframes~) => {
      let (ti, ci) = locate_clip(snapshot, clip_id)
      put_clip(snapshot, ti, ci, {
        ..snapshot.timeline.tracks[ti].clips[ci],
        keyframes,
      })
    }
    ConfigureTransition(value) => {
      let transitions = snapshot.timeline.transitions.filter(item => {
        item.transition_id != value.transition_id
      })
      transitions.push(value)
      { ..snapshot, timeline: { ..snapshot.timeline, transitions, } }
    }
    RemoveTransition(id) => {
      guard snapshot.timeline.transitions.any(value => value.transition_id == id) else {
        raise UnknownTransition(id)
      }
      {
        ..snapshot,
        timeline: {
          ..snapshot.timeline,
          transitions: snapshot.timeline.transitions.filter(value => {
            value.transition_id != id
          }),
        },
      }
    }
    ConfigureEffectStack(clip_id~, effects~, effect_stack_digest~) => {
      let (ti, ci) = locate_clip(snapshot, clip_id)
      put_clip(snapshot, ti, ci, {
        ..snapshot.timeline.tracks[ti].clips[ci],
        effects,
        effect_stack_digest,
      })
    }
    ConfigureAudioRoute(clip_id~, bus_id~) => {
      let (ti, ci) = locate_clip(snapshot, clip_id)
      put_clip(snapshot, ti, ci, {
        ..snapshot.timeline.tracks[ti].clips[ci],
        audio_bus_id: Some(bus_id),
      })
    }
    ConfigureAudioBus(bus) => {
      guard snapshot.timeline.audio_buses.any(value => {
        value.bus_id == bus.bus_id
      }) else {
        raise InvalidCommand("unknown audio bus")
      }
      {
        ..snapshot,
        timeline: {
          ..snapshot.timeline,
          audio_buses: snapshot.timeline.audio_buses.map(value => {
            if value.bus_id == bus.bus_id {
              bus
            } else {
              value
            }
          }),
        },
      }
    }
    ConfigureDeliveryAudio(value) =>
      { ..snapshot, timeline: { ..snapshot.timeline, delivery_audio: value } }
    Undo(..) | Redo(..) =>
      raise InvalidCommand("undo and redo are history operations")
  }
}

///|
fn find_record(
  log : Array[CommandLogRecord],
  command_id : String,
) -> CommandLogRecord? {
  let mut result : CommandLogRecord? = None
  for record in log {
    if record.command.command_id == command_id {
      result = Some(record)
    }
  }
  result
}

///|
fn commit(
  session : EditorSession,
  command : EditCommand,
  before : EditorProject,
  candidate : EditorProject,
  active : Array[String],
  redo : Array[String],
) -> EditorSession {
  let after = set_project_revision(candidate, command.expected_revision + 1)
  let log = session.command_log.copy()
  log.push({
    contract: "mooncast.editor-command-log-record.v1",
    command,
    before,
    after,
  })
  {
    ..session,
    snapshot: after,
    command_log: log,
    active_command_ids: active,
    redo_command_ids: redo,
  }
}

///|
/// Deterministic command reducer with optimistic revisions and immutable history.
pub fn EditorSession::dispatch(
  self : EditorSession,
  command : EditCommand,
) -> EditorSession raise EditorError {
  guard command.contract == "mooncast.editor-edit-command.v1" else {
    raise InvalidCommand("unsupported command contract")
  }
  for record in self.command_log {
    if record.command.command_id == command.command_id {
      guard record.command == command else {
        raise InvalidCommand("command_id reused with a different body")
      }
      return self
    }
  }
  guard command.expected_revision == self.snapshot.revision else {
    raise RevisionConflict(
      expected=command.expected_revision,
      actual=self.snapshot.revision,
    )
  }
  let before = self.snapshot
  match command.operation {
    Undo(target_command_id~) => {
      guard self.active_command_ids.last() is Some(latest) else {
        raise NothingToUndo
      }
      guard target_command_id is None || target_command_id == Some(latest) else {
        raise InvalidCommand("undo target must be latest active command")
      }
      guard find_record(self.command_log, latest) is Some(record) else {
        raise NothingToUndo
      }
      let active = self.active_command_ids.copy()
      active.truncate(active.length() - 1)
      let redo = self.redo_command_ids.copy()
      redo.push(latest)
      commit(self, command, before, record.before, active, redo)
    }
    Redo(target_command_id~) => {
      guard self.redo_command_ids.last() is Some(latest) else {
        raise NothingToRedo
      }
      guard target_command_id is None || target_command_id == Some(latest) else {
        raise InvalidCommand("redo target must be latest undone command")
      }
      guard find_record(self.command_log, latest) is Some(record) else {
        raise NothingToRedo
      }
      let redo = self.redo_command_ids.copy()
      redo.truncate(redo.length() - 1)
      let active = self.active_command_ids.copy()
      active.push(latest)
      commit(self, command, before, record.after, active, redo)
    }
    operation => {
      let candidate = apply_edit(before, operation)
      let active = self.active_command_ids.copy()
      active.push(command.command_id)
      commit(self, command, before, candidate, active, [])
    }
  }
}

///|
/// Replays commands from the original snapshot, including explicit undo/redo records.
pub fn replay(
  initial : EditorProject,
  commands : Array[EditCommand],
) -> EditorSession raise EditorError {
  let mut session = EditorSession::new(initial)
  for command in commands {
    session = session.dispatch(command)
  }
  session
}
