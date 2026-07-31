///|
fn waveform_view(model : Model) -> @rabbita.Html {
  let peaks = model.analysis
    .bind(value => value.waveform)
    .map(value => value.peaks)
    .unwrap_or([])
  @html.div(class="waveform", hidden=peaks.length() == 0) <| peaks.map(value => {
    @html.span(
      style=["--peak: \{Double::min(1.0, Double::max(0.04, value / 10.0))}"],
      @html.nothing,
    )
  })
}

///|
fn source_monitor(model : Model) -> @rabbita.Html {
  match selected_take(model) {
    None =>
      @html.div(
        class="monitor-empty",
        "Select a take to inspect its immutable source.",
      )
    Some(take) => {
      let mime = take.source.mime.unwrap_or("")
      let url = take.source.media_url.unwrap_or("")
      @html.div(class="source-monitor") <| [
        if mime.has_prefix("video/") && url != "" {
          @html.video(
            src=url,
            controls=true,
            preload="metadata",
            poster=take.source.thumbnail_url.unwrap_or(""),
            "",
          )
        } else if mime.has_prefix("audio/") && url != "" {
          @html.div(class="audio-source") <| [
            match take.source.thumbnail_url {
              Some(image) => @html.img(src=image, alt="Audio source thumbnail")
              None => @html.span(class="audio-icon", "AUDIO")
            },
            @html.audio(src=url, controls=true, preload="metadata", ""),
            waveform_view(model),
          ]
        } else if mime.has_prefix("image/") && url != "" {
          @html.img(class="source-image", src=url, alt="Selected source asset")
        } else {
          @html.div(
            class="monitor-empty",
            "Source \{take.source.state}. \{take_eligibility(Some(take))}",
          )
        },
        @html.div(class="source-meta") <| [
          @html.strong("\{take.take_id} · \{take.variant}"),
          @html.span(
            "\{take.role} · \{timecode(model, take.duration_ticks)} · read-only source",
          ),
          match model.analysis {
            Some(analysis) =>
              @html.small(
                "Analysis \{analysis.state} · \{analysis.duration_seconds.map(value => "\{value}s").unwrap_or("duration pending")} · \{analysis.analysis_digest.unwrap_or("digest pending")}",
              )
            None =>
              @html.small("Analysis loads from the source evidence endpoint.")
          },
        ],
      ]
    }
  }
}

///|
fn authoritative_media_url(model : Model) -> String {
  if model.export_state.download_url != "" {
    model.export_state.download_url
  } else if model.preview_job_id != "" {
    "/api/editor/projects/" +
    model.project_id +
    "/jobs/" +
    model.preview_job_id +
    "/media"
  } else {
    ""
  }
}

///|
fn program_media_node(
  model : Model,
  track : @api.Track,
  clip : @api.Clip,
) -> @rabbita.Html {
  match take_for_clip(model, clip) {
    None => @html.nothing
    Some(take) => {
      let source = program_media_url(take)
      let mime = take.source.mime.unwrap_or("")
      let active = clip_is_active(clip, model.playhead_ticks)
      let track_muted = track.mix.map(value => value.muted).unwrap_or(false)
      let settings = clip.settings
      let visible = active &&
        !track_muted &&
        (mime.has_prefix("video/") || mime.has_prefix("image/"))
      let visual_class = "program-proxy-media" +
        (if visible { " is-program-visible" } else { "" })
      let visual_style = [
        "--program-opacity: \{settings.bind(value => value.opacity).unwrap_or(1.0)}",
        "--program-scale: \{settings.bind(value => value.scale).unwrap_or(1.0)}",
        "--program-x: \{settings.bind(value => value.position_x).unwrap_or(0.0)}",
        "--program-y: \{settings.bind(value => value.position_y).unwrap_or(0.0)}",
        "--program-rotation: \{settings.bind(value => value.rotation_degrees).unwrap_or(0.0)}",
      ]
      if source == "" {
        @html.nothing
      } else if mime.has_prefix("video/") {
        @html.video(
          id=program_media_id(clip),
          class=visual_class,
          src=source,
          autoplay=model.playing && active,
          muted=true,
          preload="auto",
          style=visual_style,
          "",
        )
      } else if mime.has_prefix("audio/") {
        @html.audio(
          id=program_media_id(clip),
          class="program-proxy-media",
          src=source,
          autoplay=model.playing && active,
          muted=model.muted || track_muted,
          preload="auto",
          "",
        )
      } else if mime.has_prefix("image/") {
        @html.img(
          id=program_media_id(clip),
          class=visual_class,
          src=source,
          alt="",
          loading="eager",
          decoding="async",
          style=visual_style,
        )
      } else {
        @html.nothing
      }
    }
  }
}

///|
fn program_media_bank(model : Model) -> @rabbita.Html {
  let nodes : Array[@rabbita.Html] = []
  for track in tracks(model) {
    for clip in track.clips {
      nodes.push(program_media_node(model, track, clip))
    }
  }
  @html.div(class="program-media-bank") <| nodes
}

///|
fn program_monitor(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let ready = takes(model)
    .filter(take => take.source.media_url is Some(_))
    .length()
  @html.div(class="program-monitor") <| [
    @html.div(class="surface-tabs") <| [
      @html.button(
        class=if model.program_surface == InteractiveProxy {
          "is-active"
        } else {
          ""
        },
        type_="button",
        on_click=dispatch(SwitchProgramSurface(InteractiveProxy)),
        "Interactive proxy",
      ),
      @html.button(
        class=if model.program_surface == AuthoritativePreview {
          "is-active"
        } else {
          ""
        },
        type_="button",
        disabled=authoritative_media_url(model) == "",
        on_click=dispatch(SwitchProgramSurface(AuthoritativePreview)),
        "Authoritative render",
      ),
    ],
    if model.program_surface == InteractiveProxy {
      @html.div(class="program-canvas-stack") <| [
        @html.canvas(
          id="program-canvas",
          class="program-canvas",
          title="Interactive timeline proxy",
          style=[
            "aspect-ratio: \{program_width(model)} / \{program_height(model)}",
          ],
          attrs=@html.Attrs::build()
            .width(program_width(model).to_int())
            .height(program_height(model).to_int()),
          "",
        ),
        program_media_bank(model),
      ]
    } else {
      @html.video(
        id="authoritative-preview",
        src=authoritative_media_url(model),
        controls=true,
        muted=model.muted,
        preload="metadata",
        "",
      )
    },
    @html.div(class="proxy-status") <| [
      status_tag("neutral", "Canvas + media compositor"),
      status_tag(
        if model.preview_job.map(preview_state).unwrap_or("idle") == "succeeded" {
          "pass"
        } else {
          "hold"
        },
        "Render \{model.preview_job.map(preview_state).unwrap_or("idle")}",
      ),
      status_tag(
        if ready > 0 {
          "pass"
        } else {
          "hold"
        },
        "\{ready}/\{takes(model).length()} sources bound",
      ),
    ],
  ]
}

///|
fn transport(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let seconds = Double::from_int(model.playhead_ticks) /
    Double::from_int(ticks_per_second(model))
  let total = Double::from_int(duration_ticks(model)) /
    Double::from_int(ticks_per_second(model))
  @html.div(class="transport") <| [
    @html.button(
      type_="button",
      on_click=dispatch(StepFrame(-1)),
      title="Previous frame",
      "◀│",
    ),
    @html.button(
      class="play",
      type_="button",
      on_click=dispatch(TogglePlay),
      if model.playing {
        "Pause"
      } else {
        "Play"
      },
    ),
    @html.button(
      type_="button",
      on_click=dispatch(StepFrame(1)),
      title="Next frame",
      "│▶",
    ),
    @html.code(class="timecode", timecode(model, model.playhead_ticks)),
    @html.input(
      class="scrubber",
      input_type=@html.Range,
      min=0,
      max=Int::max(1, total.to_int()),
      step=1,
      value="\{seconds}",
      on_input=dispatch.map(value => ScrubChanged(value)),
    ),
    @html.button(
      type_="button",
      on_click=dispatch(ToggleMute),
      if model.muted {
        "Unmute"
      } else {
        "Mute"
      },
    ),
    @html.input(
      class="volume",
      input_type=@html.Range,
      min=0,
      max=100,
      step=1,
      value="\{(parse_number(model.volume, 1.0) * 100.0).to_int()}",
      on_input=dispatch.map(value => {
        VolumeChanged("\{parse_number(value, 100.0) / 100.0}")
      }),
    ),
    @html.button(type_="button", on_click=dispatch(SetLoopIn), "Loop in"),
    @html.button(type_="button", on_click=dispatch(SetLoopOut), "Loop out"),
    @html.button(
      class=if model.loop_enabled { "is-active" } else { "" },
      type_="button",
      on_click=dispatch(ToggleLoop),
      "Loop",
    ),
    @html.button(type_="button", on_click=dispatch(ResyncProxy), "Resync"),
  ]
}

///|
fn monitor_panel(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.section(class="monitor-panel") <| [
    @html.div(class="monitor-heading") <| [
      @html.div(class="surface-tabs") <| [
        @html.button(
          class=if model.monitor_mode == SourceMonitor {
            "is-active"
          } else {
            ""
          },
          type_="button",
          on_click=dispatch(SwitchMonitor(SourceMonitor)),
          "Source",
        ),
        @html.button(
          class=if model.monitor_mode == ProgramMonitor {
            "is-active"
          } else {
            ""
          },
          type_="button",
          on_click=dispatch(SwitchMonitor(ProgramMonitor)),
          "Program",
        ),
      ],
      @html.div(class="monitor-actions") <| [
        @html.button(
          type_="button",
          disabled=model.busy,
          on_click=dispatch(StartPreview),
          "Create preview",
        ),
        @html.button(
          type_="button",
          disabled=model.preview_job
            .map(job => preview_state(job) != "failed")
            .unwrap_or(true),
          on_click=dispatch(RetryPreview),
          "Retry",
        ),
      ],
    ],
    if model.monitor_mode == SourceMonitor {
      source_monitor(model)
    } else {
      program_monitor(dispatch, model)
    },
    transport(dispatch, model),
  ]
}
