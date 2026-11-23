///|
extern "js" fn player_fullscreen() -> Unit =
  #|() => { const el = document.querySelector('.monitor-panel'); if (!el) return; if (document.fullscreenElement) { document.exitFullscreen?.().catch(() => {}); } else { el.requestFullscreen?.().catch(() => {}); } }

///|
extern "js" fn player_media_rate(rate : Double) -> Unit =
  #|rate => { for (const media of document.querySelectorAll?.('.monitor-panel video, .monitor-panel audio, .standalone-player video') || []) { media.playbackRate = rate; } }

///|
extern "js" fn player_render_play(playing : Bool) -> Unit =
  #|playing => { const media = document.getElementById('authoritative-preview'); if (!media) return; if (playing) media.play().catch(() => {}); else media.pause(); }

///|
fn playback_rate(model : Model) -> Double {
  Double::min(4.0, Double::max(0.25, parse_number(model.playback_speed, 1.0)))
}

///|
fn local_caption_target(model : Model) -> (String, Int32, Int32)? {
  guard model.workspace is Some(workspace) &&
    workspace_matches_project(workspace, model.project_id) &&
    model.program_surface == InteractiveProxy else {
    return None
  }
  // Speech follows the audible timeline source, rather than an unrelated bin selection.
  let clip = tracks(model)
    .iter()
    .filter(track => track.kind == "audio" && !program_track_muted(model, track))
    .flat_map(track => track.clips.iter())
    .find_first(clip => clip_is_active(clip, model.playhead_ticks))
  guard clip is Some(clip) && take_for_clip(model, clip) is Some(take) else {
    return None
  }
  let source_ms = (clip.source_in_tick + model.playhead_ticks - clip.start_tick).to_double() *
    1000.0 /
    ticks_per_second(model).to_double()
  let first = (clip.source_in_tick.to_double() *
  1000.0 /
  ticks_per_second(model).to_double()).to_int()
  let last = (clip.source_out_tick.to_double() *
  1000.0 /
  ticks_per_second(model).to_double()).to_int()
  let start = Int32::max(first, source_ms.to_int() / 8000 * 8000)
  let length = Int32::min(8000, last - start)
  if length <= 0 {
    None
  } else {
    Some((take.take_id, start, length))
  }
}

///|
fn local_caption_identity(model : Model) -> String {
  match local_caption_target(model) {
    Some((take, start, _)) =>
      model.project_id +
      ":" +
      selected_revision(model).to_string() +
      ":" +
      take +
      ":" +
      start.to_string() +
      ":" +
      model.local_caption_translate.to_string()
    None => ""
  }
}

///|
fn player_controls(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  fn select_control(
    label : String,
    value : String,
    values : Array[(String, String)],
    change : @rabbita.Emit[String],
  ) -> @rabbita.Html {
    @html.label(class="player-setting", [
      @html.span(label),
      @html.select(
        on_change=change,
        values.map(item => {
          @html.option(value=item.0, selected=item.0 == value, item.1)
        }),
      ),
    ])
  }
  @html.div(class="player-controls", [
    select_control(
      "Playback speed",
      model.playback_speed,
      [
        ("0.5", "0.5×"),
        ("0.75", "0.75×"),
        ("1", "1×"),
        ("1.25", "1.25×"),
        ("1.5", "1.5×"),
        ("2", "2×"),
        ("4", "4×"),
      ],
      dispatch.map(value => SetPlaybackSpeed(value)),
    ),
    select_control(
      "Preview quality",
      model.preview_height.to_string(),
      [("360", "360p"), ("540", "540p"), ("720", "720p"), ("1080", "1080p")],
      dispatch.map(value => SetPreviewHeight(value)),
    ),
    select_control(
      "Export resolution",
      model.output_height.to_string(),
      [("720", "720p"), ("1080", "1080p"), ("2160", "4K")],
      dispatch.map(value => SetOutputHeight(value)),
    ),
    @html.button(on_click=dispatch(PlayerFullscreen), "Full screen"),
  ])
}

///|
fn local_caption_controls(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.details(class="local-caption-panel", [
    @html.summary("Local captions and translation"),
    @html.div(class="local-caption-actions", [
      @html.button(
        class=if model.local_caption_live { "is-active" } else { "" },
        on_click=dispatch(ToggleLocalCaptions),
        if model.local_caption_live {
          "Stop live captions"
        } else {
          "Live captions"
        },
      ),
      @html.button(
        class=if model.local_caption_translate { "is-active" } else { "" },
        on_click=dispatch(ToggleCaptionTranslation),
        if model.local_caption_translate {
          "English translation on"
        } else {
          "Translate to English"
        },
      ),
      @html.button(
        disabled=model.local_caption_pending != "" ||
          local_caption_target(model) is None,
        on_click=dispatch(GenerateLocalCaptions),
        if model.local_caption_pending != "" {
          "Transcribing locally…"
        } else {
          "Caption current 8 seconds"
        },
      ),
    ]),
    @html.p(
      "Whisper runs on this computer. Live mode follows the first audible audio track in 8-second chunks with processing delay. Solo the voice track for best results. Preview captions do not change the exported caption track.",
    ),
    if model.local_caption_error != "" {
      @html.p(
        class="error-text",
        attrs=@html.Attrs::build().role("alert"),
        model.local_caption_error,
      )
    } else {
      @html.nothing
    },
  ])
}
