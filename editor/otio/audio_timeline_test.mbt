///|
fn audio_project() -> @domain.EditorProject {
  let source = project()
  let audio = {
    ..source.media_refs[0],
    media_ref_id: "media.soundtrack",
    locator: { kind: "pack-relative", uri: "synthetic-soundtrack.wav", },
    metadata: {
      ..source.media_refs[0].metadata,
      mime_type: "audio/wav",
      duration_ticks: 12000,
    },
  }
  let template = {
    ..source.timeline.tracks[0].clips[0],
    clip_id: "template.soundtrack",
    media_ref_id: audio.media_ref_id,
    duration_ticks: 12000,
    source_out_tick: 12000,
  }
  {
    ..source,
    media_refs: source.media_refs + [audio],
    timeline: {
      ..source.timeline,
      tracks: source.timeline.tracks +
      [
        {
          track_id: "audio.original",
          kind: "audio",
          order: 1,
          mix: None,
          clips: [template],
        },
      ],
    },
  }
}

///|
fn audio_map() -> @otio.MediaMap {
  let source = mapping()
  {
    ..source,
    bindings: source.bindings +
    [
      {
        target_url: "https://unfetched.invalid/music.wav",
        media_ref_id: "media.soundtrack",
        template_clip_id: "template.soundtrack",
        source_start_frame: 480,
      },
    ],
  }
}

///|
fn audio_clip(start : Int, duration : Int) -> Json {
  modified(clip(start~, duration~), "media_reference", {
    "OTIO_SCHEMA": "ExternalReference.1",
    "target_url": "https://unfetched.invalid/music.wav",
    "available_range": span(480, 288),
  })
}

///|
fn audiovisual_input(audio_first? : Bool = false) -> String raise {
  let value = @json.parse(
    timeline([gap(3), clip(), gap(21), clip(start=2410, v2=true)]),
  )
  guard value is Object(root) &&
    root["tracks"] is Object(stack) &&
    stack["children"] is Array(tracks) else {
    fail("fixture structure")
  }
  let audio : Json = {
    "OTIO_SCHEMA": "Track.1",
    "kind": "Audio",
    "name": "Music cue",
    "source_range": null,
    "children": [gap(12), audio_clip(481, 72), gap(24), audio_clip(576, 72)],
  }
  modified(
    value,
    "tracks",
    modified(
      root["tracks"],
      "children",
      (if audio_first { [audio, tracks[0]] } else { [tracks[0], audio] }).to_json(),
    ),
  ).stringify()
}

///|
fn audio_command(
  id : String,
  revision : Int,
  operation : @domain.EditOperation,
) -> @domain.EditCommand {
  {
    contract: "mooncast.editor-edit-command.v1",
    command_id: id,
    expected_revision: revision,
    actor: { actor_id: "editor", provenance: "synthetic-audio-journey", },
    operation,
  }
}

///|
test "OTIO picture and audio keep independent cuts gaps and exact shared clock" {
  let source = audio_project()
  let before = source.to_json().stringify()
  let result = @otio.import_timeline(source, audiovisual_input(), audio_map())
  assert_eq(result.catalog.duration_frames, 180)
  assert_eq(result.catalog.video_duration_frames, 120)
  assert_eq(result.catalog.audio_duration_frames, Some(180))
  assert_eq(result.project.timeline.timebase.ticks_per_second, 3000)
  assert_eq(result.project.timeline.tracks.length(), 2)
  assert_eq(result.project.timeline.tracks[0].clips[0].start_tick, 375)
  let audio = result.project.timeline.tracks[1]
  assert_eq(audio.kind, "audio")
  assert_eq(audio.clips[0].start_tick, 1500)
  assert_eq(audio.clips[0].source_in_tick, 125)
  assert_eq(audio.clips[0].duration_ticks, 9000)
  assert_eq(audio.clips[1].start_tick, 13500)
  assert_eq(audio.clips[1].source_in_tick, 12000)
  assert_eq(result.project.media_refs[1].metadata.duration_ticks, 36000)
  assert_eq(result.audio_preview[1].gap_before_frames, 24)
  assert_eq(result.preview.duration_frames, 120)
  assert_eq(result.edl_mapping.bindings.length(), 1)
  assert_false(result.normalized_edl.contains("music.wav"))
  assert_true(result.normalized_edl.contains("picture-only"))
  let reversed = @otio.import_timeline(
    source,
    audiovisual_input(audio_first=true),
    audio_map(),
  )
  assert_eq(reversed.project, result.project)
  assert_eq(before, source.to_json().stringify())
  try
    @edl.export_edl(result.project, result.edl_mapping, "Must not lose audio")
  catch {
    _ => ()
  } noraise {
    _ => fail("EDL export silently dropped audio")
  }
}

///|
async test "OTIO imported soundtrack edits undo and disk reopen through ordinary native session" {
  let root = match @env.get_env_var("MOONCAST_OTIO_AUDIO_EVIDENCE_DIR") {
    Some(path) => path
    None =>
      @env.get_env_var("TMPDIR").unwrap_or("/tmp") +
      "/mooncast-otio-audio-" +
      @env.now().to_string()
  }
  if !@fs.exists(root) {
    @fs.mkdir(root)
  }
  let input = audiovisual_input()
  let source = audio_project()
  let mapping = audio_map()
  let imported = @otio.import_timeline(source, input, mapping)
  let video = imported.project.timeline.tracks[0]
  let initial = @domain.EditorSession::new(imported.project)
  let trimmed = initial.dispatch(
    audio_command(
      "audio.trim",
      0,
      @domain.Trim(
        clip_id="otio.audio.1",
        source_in_tick=250,
        source_out_tick=9125,
        start_tick=None,
      ),
    ),
  )
  let settings = {
    ..trimmed.snapshot.timeline.tracks[1].clips[0].settings,
    volume_db: -6.0,
  }
  let edited = trimmed.dispatch(
    audio_command(
      "audio.gain",
      1,
      @domain.ConfigureClip(clip_id="otio.audio.1", settings~),
    ),
  )
  assert_eq(edited.snapshot.timeline.tracks[0], video)
  assert_eq(edited.snapshot.timeline.tracks[1].clips[0].duration_ticks, 8875)
  assert_eq(
    edited.snapshot.timeline.tracks[1].clips[1],
    imported.project.timeline.tracks[1].clips[1],
  )
  for
    (name, text) in [
      ("source.project.json", source.to_json().stringify(indent=2)),
      ("picture-and-soundtrack.otio", input),
      ("media-map.json", mapping.to_json().stringify(indent=2)),
      ("imported.project.json", imported.project.to_json().stringify(indent=2)),
      ("edited.project.json", edited.snapshot.to_json().stringify(indent=2)),
      ("edited.session.json", @domain.session_to_json(edited)),
      (
        "audio-trim.command.json",
        @domain.command_to_json(
          audio_command(
            "audio.trim",
            0,
            @domain.Trim(
              clip_id="otio.audio.1",
              source_in_tick=250,
              source_out_tick=9125,
              start_tick=None,
            ),
          ),
        ),
      ),
    ] {
    @fs.write_file(root + "/" + name, text + "\n", create_mode=CreateNew)
  }
  let reopened = @domain.snapshot_from_json(
    @fs.read_file(root + "/edited.project.json").text(),
  )
  assert_eq(reopened, edited.snapshot)
  let resumed = @domain.session_from_json(
    @fs.read_file(root + "/edited.session.json").text(),
  )
  assert_eq(resumed.snapshot, reopened)
  let undo_gain = resumed.dispatch(
    audio_command(
      "undo.gain",
      2,
      @domain.Undo(target_command_id=Some("audio.gain")),
    ),
  )
  assert_eq(
    undo_gain.snapshot.timeline.tracks,
    trimmed.snapshot.timeline.tracks,
  )
  let undone = undo_gain.dispatch(
    audio_command(
      "undo.trim",
      3,
      @domain.Undo(target_command_id=Some("audio.trim")),
    ),
  )
  assert_eq(undone.snapshot.timeline.tracks, imported.project.timeline.tracks)
  @fs.write_file(
    root + "/undone.project.json",
    undone.snapshot.to_json().stringify(indent=2) + "\n",
    create_mode=CreateNew,
  )
  @fs.write_file(
    root + "/RESULT.json",
    (
      {
        "status": "passed",
        "synthetic": true,
        "workflow": "Import two synchronized tracks; trim audio; set gain; save snapshot/session; disk reopen; undo gain and trim; video unchanged",
        "timebase_ticks_per_second": 3000,
        "ticks_per_frame": 125,
        "video_end_frame": 120,
        "audio_end_frame": 180,
        "original_source_ticks_per_second": 1000,
        "edl_scope": "picture-only",
        "playback_or_rendering_exercised": false,
      } : Json).stringify(indent=2) +
    "\n",
    create_mode=CreateNew,
  )
}

///|
test "OTIO audio refuses wrong media missing bindings and out of range sources" {
  let input = audiovisual_input()
  for
    source in [
      { ..audio_project(), media_refs: project().media_refs, },
      {
        ..audio_project(),
        media_refs: [
          project().media_refs[0],
          {
            ..audio_project().media_refs[1],
            metadata: {
              ..audio_project().media_refs[1].metadata,
              mime_type: "video/mp4",
            },
          },
        ],
      },
      {
        ..audio_project(),
        media_refs: [
          project().media_refs[0],
          {
            ..audio_project().media_refs[1],
            metadata: {
              ..audio_project().media_refs[1].metadata,
              duration_ticks: 1000,
            },
          },
        ],
      },
    ] {
    try @otio.import_timeline(source, input, audio_map()) catch {
      _ => ()
    } noraise {
      _ => fail("invalid audio media accepted")
    }
  }
  try @otio.import_timeline(audio_project(), input, mapping()) catch {
    _ => ()
  } noraise {
    _ => fail("unmapped audio accepted")
  }
  let map = audio_map()
  for
    binding in [
      { ..map.bindings[1], template_clip_id: "missing", },
      { ..map.bindings[1], source_start_frame: 481, },
    ] {
    try
      @otio.import_timeline(audio_project(), input, {
        ..map,
        bindings: [map.bindings[0], binding],
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid audio binding accepted")
    }
  }
  for
    bad in [
      input.replace(old="\"kind\":\"Video\"", new="\"kind\":\"Audio\""),
      input.replace(old="\"kind\":\"Audio\"", new="\"kind\":\"Video\""),
      input.replace(old="\"value\":481", new="\"value\":481.00000000000000001"),
      input.replace(old="\"rate\":24", new="\"rate\":23.976"),
    ] {
    try @otio.catalog_timeline(bad, 24) catch {
      _ => ()
    } noraise {
      _ => fail("unsupported audio timing/topology accepted")
    }
  }
}
