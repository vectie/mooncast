///|
/// Solo is a monitor-only audition. Persisted track mute and gain still apply.
fn active_solo_track(model : Model) -> @api.Track? {
  guard model.program_surface == InteractiveProxy &&
    model.workspace is Some(workspace) &&
    workspace_matches_project(workspace, model.project_id) else {
    return None
  }
  tracks(model)
  .iter()
  .find_first(track => {
    track.kind == "audio" && track.track_id == model.solo_track_id
  })
}

///|
fn program_track_muted(model : Model, track : @api.Track) -> Bool {
  model.muted ||
  track.kind == "video" ||
  track.mix.map(mix => mix.muted).unwrap_or(false) ||
  active_solo_track(model)
  .map(solo => track.track_id != solo.track_id)
  .unwrap_or(false)
}

///|
fn toggle_track_solo(model : Model, track_id : String) -> Model {
  guard !model.busy &&
    !model.loading &&
    model.program_surface == InteractiveProxy &&
    model.workspace is Some(workspace) &&
    workspace_matches_project(workspace, model.project_id) &&
    tracks(model).any(track => {
      track.kind == "audio" && track.track_id == track_id
    }) else {
    return {
      ..model,
      error: "Open an audio track in the interactive proxy before solo audition.",
    }
  }
  {
    ..model,
    solo_track_id: if model.solo_track_id == track_id {
      ""
    } else {
      track_id
    },
    error: "",
  }
}

///|
fn audio_audition_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let audio = tracks(model).filter(track => track.kind == "audio")
  let solo = active_solo_track(model)
  @html.div(class="audio-audition") <| [
    @html.strong("Audio audition"),
    @html.small(
      "Interactive proxy only. Solo preserves saved track mute and gain; exports keep the full mix.",
    ),
    if audio.is_empty() {
      @html.span("Add voice, music or SFX to audition the mix.")
    } else {
      @html.nothing
    },
    ..audio.map(track => {
      @html.button(
        type_="button",
        class=if solo
          .map(value => value.track_id == track.track_id)
          .unwrap_or(false) {
          "is-active"
        } else {
          ""
        },
        disabled=model.busy ||
          model.loading ||
          model.program_surface != InteractiveProxy,
        on_click=dispatch(ToggleTrackSolo(track.track_id)),
        "Solo " +
        track.label.unwrap_or(track.track_id) +
        (if track.mix.map(mix => mix.muted).unwrap_or(false) {
          " (track muted)"
        } else {
          ""
        }),
      )
    }),
    @html.button(
      type_="button",
      disabled=model.solo_track_id == "",
      on_click=dispatch(ClearTrackSolo),
      "Restore full mix",
    ),
    @html.span(
      match solo {
        Some(track) =>
          "Listening to " +
          track.label.unwrap_or(track.track_id) +
          (if model.muted { " · master muted" } else { "" })
        None => "Full mix"
      },
    ),
  ]
}
