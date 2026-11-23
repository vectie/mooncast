///|
extern "js" fn standalone_player_route() -> Bool =
  #|() => location.pathname.endsWith('/player')

///|
extern "js" fn standalone_player_location(player : Bool) -> Unit =
  #|player => { if (!globalThis.location || !globalThis.history) return; const prefix = location.pathname.startsWith('/apps/mooncast/') ? '/apps/mooncast' : ''; history.replaceState(null, '', prefix + (player ? '/editor/player' : '/editor')); }

///|
extern "js" fn standalone_player_file(previous : String) -> String =
  #|previous => { const file = document.getElementById('standalone-player-file')?.files?.[0]; if (!file) return ''; if (previous.startsWith('blob:')) URL.revokeObjectURL(previous); return JSON.stringify({url: URL.createObjectURL(file), name: file.name}); }

///|
extern "js" fn standalone_player_release(url : String) -> Unit =
  #|url => { if (url.startsWith('blob:')) URL.revokeObjectURL(url); }

///|
fn standalone_player_render_url(model : Model) -> String {
  if model.export_state.download_url != "" {
    model.export_state.download_url
  } else if model.preview_job.map(preview_state).unwrap_or("") == "succeeded" {
    authoritative_media_url(model)
  } else {
    ""
  }
}

///|
fn standalone_player_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let render_url = standalone_player_render_url(model)
  let url = if model.player_file_url != "" {
    model.player_file_url
  } else {
    render_url
  }
  @html.section(
    class="standalone-player",
    attrs=@html.Attrs::build().aria_label("Player"),
    [
      @html.div(class="player-toolbar", [
        @html.h1("Player"),
        @html.label(class="player-open-file", [
          @html.span("Open video or audio"),
          @html.input(
            id="standalone-player-file",
            input_type=@html.File,
            accept="video/*,audio/*",
            on_change=dispatch.map(_ => OpenPlayerFile),
          ),
        ]),
        if model.player_file_url != "" && render_url != "" {
          @html.button(
            on_click=dispatch(ClosePlayerFile),
            "Latest project render",
          )
        } else {
          @html.nothing
        },
        @html.label(class="player-setting", [
          @html.span("Playback speed"),
          @html.select(
            on_change=dispatch.map(value => SetPlaybackSpeed(value)),
            ["0.5", "0.75", "1", "1.25", "1.5", "2", "4"].map(value => {
              @html.option(
                value~,
                selected=value == model.playback_speed,
                value + "×",
              )
            }),
          ),
        ]),
        @html.button(
          on_click=dispatch(SwitchWorkspaceLens(EditorLens)),
          "Back to editing",
        ),
      ]),
      if url == "" {
        @html.div(class="standalone-player-empty", [
          @html.h2("Open something to watch"),
          @html.p(
            "Choose a video or audio file above, or render your edit and return here.",
          ),
        ])
      } else {
        @html.div(
          class="standalone-player-screen",
          Map::from_array([
            (
              url,
              @html.video(
                id="standalone-video",
                src=url,
                controls=true,
                preload="metadata",
                attrs=@html.Attrs::build().aria_label(
                  if model.player_file_name == "" {
                    "Latest project render"
                  } else {
                    model.player_file_name
                  },
                ),
                "This media format could not be played.",
              ),
            ),
          ]),
        )
      },
      @html.p(
        class="standalone-player-name",
        if model.player_file_name != "" {
          model.player_file_name
        } else if url != "" {
          "Latest project render"
        } else {
          "Local files stay on this computer."
        },
      ),
    ],
  )
}
