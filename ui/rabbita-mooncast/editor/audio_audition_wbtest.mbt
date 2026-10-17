///|
fn audition_model() -> Model raise {
  let base = roll_ui_model()
  let timeline = timeline(base).unwrap()
  let source = timeline.tracks[0]
  let audio = ["voice", "music", "sfx"].mapi((i, id) => {
    ..source,
    track_id: id,
    kind: "audio",
    label: Some(id),
    mix: Some({
      volume_db: -12.0 * i.to_double(),
      pan: 0.0,
      muted: id == "sfx",
    }),
    clips: [{ ..source.clips[0], clip_id: id, }],
  })
  {
    ..base,
    playing: true,
    workspace: Some({
      ..base.workspace.unwrap(),
      timeline: Some({ ..timeline, tracks: [source, ..audio], }),
    }),
  }
}

///|
extern "js" fn install_audition_dom() -> Unit =
  #| () => {
  #| globalThis.__auditionOld = Object.fromEntries(['document','HTMLMediaElement'].map(k=>[k,Object.getOwnPropertyDescriptor(globalThis,k)]));
  #| class Media { constructor(){this.muted=false;this.volume=1;this.currentTime=0;this.loads=0;this.pauses=0;} load(){this.loads++;} pause(){this.pauses++;} }
  #| globalThis.__auditionMedia = Object.fromEntries(['a','b','c','voice','music','sfx'].map(k=>['program-media-'+k,new Media()]));
  #| Object.defineProperty(globalThis,'HTMLMediaElement',{configurable:true,value:Media});
  #| Object.defineProperty(globalThis,'document',{configurable:true,value:{getElementById:id=>globalThis.__auditionMedia[id]||null}});
  #| }

///|
extern "js" fn audition_media_state(id : String) -> String =
  #| id => JSON.stringify(globalThis.__auditionMedia['program-media-'+id])

///|
extern "js" fn restore_audition_dom() -> Unit =
  #| () => {for(const [k,v] of Object.entries(globalThis.__auditionOld)){if(v)Object.defineProperty(globalThis,k,v);else delete globalThis[k];}delete globalThis.__auditionMedia;delete globalThis.__auditionOld;}

///|
test "solo switches actual program media audibility live and restores saved gain mute and timing" {
  install_audition_dom()
  defer restore_audition_dom()
  let original = audition_model()
  let voice = update(_ => @rabbita.none, ToggleTrackSolo("voice"), original).1
  assert_eq(voice.solo_track_id, "voice")
  assert_true(
    @json.parse(audition_media_state("voice"))
    is {
      "muted": False,
      "volume": Number(1, ..),
      "loads": Number(0, ..),
      "currentTime": Number(0, ..),
      ..
    },
  )
  assert_true(
    @json.parse(audition_media_state("music"))
    is { "muted": True, "volume": Number(0.8, ..), .. },
  )
  let music = update(_ => @rabbita.none, ToggleTrackSolo("music"), voice).1
  assert_true(
    @json.parse(audition_media_state("voice")) is { "muted": True, .. },
  )
  assert_true(
    @json.parse(audition_media_state("music"))
    is { "muted": False, "volume": Number(0.8, ..), .. },
  )
  let full = update(_ => @rabbita.none, ClearTrackSolo, music).1
  assert_eq(full.solo_track_id, "")
  assert_true(
    @json.parse(audition_media_state("voice")) is { "muted": False, .. },
  )
  assert_true(
    @json.parse(audition_media_state("sfx"))
    is { "muted": True, "volume": Number(0.6, ..), .. },
  )
  assert_eq(
    clips(full).map(clip => clip.to_json()),
    clips(original).map(clip => clip.to_json()),
  )
  assert_eq(
    tracks(full).map(track => track.mix.map(mix => mix.to_json())),
    tracks(original).map(track => track.mix.map(mix => mix.to_json())),
  )
  assert_eq(full.request_sequence, original.request_sequence)
  assert_eq(full.undo_stack.length(), 0)
  assert_true(full.playing)
  assert_eq(full.playhead_ticks, original.playhead_ticks)
}

///|
test "repeat solo cancels and master or persisted track mute remains authoritative" {
  let original = audition_model()
  let voice = toggle_track_solo(original, "voice")
  assert_eq(toggle_track_solo(voice, "voice").solo_track_id, "")
  assert_true(program_track_muted({ ..voice, muted: true, }, tracks(voice)[1]))
  let muted = toggle_track_solo(original, "sfx")
  assert_true(program_track_muted(muted, tracks(muted)[3]))
  assert_true(program_track_muted(voice, tracks(voice)[0]))
}

///|
test "solo rejects invalid stale busy loading and authoritative selections without mutating commands" {
  let original = audition_model()
  for
    model in [
      { ..original, loading: true, },
      { ..original, busy: true, },
      { ..original, project_id: "other", },
      { ..original, program_surface: AuthoritativePreview, },
    ] {
    let next = toggle_track_solo(model, "voice")
    assert_eq(next.solo_track_id, "")
    assert_true(next.error != "")
    assert_eq(next.request_sequence, original.request_sequence)
  }
  assert_true(toggle_track_solo(original, "v1").error != "")
  assert_true(toggle_track_solo(original, "missing").error != "")
}

///|
test "removed solo track and project change restore the full mix and do not retain audition in drafts" {
  let solo = toggle_track_solo(audition_model(), "voice")
  let workspace = solo.workspace.unwrap()
  let value = timeline(solo).unwrap()
  let changed = {
    ..workspace,
    timeline: Some({
      ..value,
      tracks: value.tracks.filter(track => track.track_id != "voice"),
    }),
  }
  let normalized = normalized_after_snapshot(solo, changed)
  assert_eq(normalized.solo_track_id, "")
  let other = activate_editor_project(solo, "other")
  assert_eq(other.solo_track_id, "")
  assert_eq(activate_editor_project(other, "p").solo_track_id, "")
}

///|
test "audition controls appear in program monitor and identify muted track and rendered preview boundary" {
  let model = toggle_track_solo(audition_model(), "voice")
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(program_monitor(_ => @rabbita.none, model)),
  )
  assert_true(html.contains("Audio audition"))
  assert_true(html.contains("Solo music"))
  assert_true(html.contains("Solo sfx (track muted)"))
  assert_true(html.contains("Listening to voice"))
  assert_true(html.contains("Restore full mix"))
  let render = @rabbita.render_to_string(
    @rabbita.static_cell(
      audio_audition_view(_ => @rabbita.none, {
        ..model,
        program_surface: AuthoritativePreview,
      }),
    ),
  )
  assert_true(render.contains("disabled"))
  assert_true(render.contains("Full mix"))
}

///|
test "switching to authoritative preview cancels solo and restores DOM mix with master volume" {
  install_audition_dom()
  defer restore_audition_dom()
  let original = { ..audition_model(), volume: "0.5", }
  let solo = update(_ => @rabbita.none, ToggleTrackSolo("voice"), original).1
  let rendered = update(
      _ => @rabbita.none,
      SwitchProgramSurface(AuthoritativePreview),
      solo,
    ).1
  assert_eq(rendered.solo_track_id, "")
  assert_false(rendered.playing)
  assert_true(
    @json.parse(audition_media_state("music"))
    is { "muted": False, "volume": Number(0.4, ..), .. },
  )
  assert_true(@json.parse(audition_media_state("sfx")) is { "muted": True, .. })
  let returned = update(
      _ => @rabbita.none,
      SwitchProgramSurface(InteractiveProxy),
      rendered,
    ).1
  assert_eq(returned.solo_track_id, "")
  assert_eq(returned.request_sequence, original.request_sequence)
}
