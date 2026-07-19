///|
fn drag_mode_label(mode : TimelineDragMode) -> String {
  match mode {
    DragMove => "Move"
    DragTrimStart => "Trim in"
    DragTrimEnd => "Trim out"
  }
}

///|
fn clip_lane_item(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  track : @api.Track,
  clip : @api.Clip,
) -> @rabbita.Html {
  let selected = model.selected_clip_ids.contains(clip.clip_id)
  let scale = timeline_scale(model)
  let (preview_start, preview_duration) = preview_geometry(model, clip)
  let left = Double::from_int(preview_start) * scale
  let width = Double::max(28.0, Double::from_int(preview_duration) * scale)
  let take = takes(model)
    .iter()
    .find_first(item => item.media_ref_id == clip.media_ref_id)
  let dragging = model.timeline_drag
    .map(value => value.clip_id == clip.clip_id || selected)
    .unwrap_or(false)
  @html.div(
    class="timeline-clip kind-" +
      track.kind +
      (if selected { " is-selected" } else { "" }) +
      (if dragging { " is-dragging" } else { "" }),
    style=["left: \{left}px", "width: \{width}px"],
    title="\{clip.clip_id} · \{timecode(model, preview_start)} · \{timecode(model, preview_duration)} · drag body to move, edges to trim",
    on_mousedown=mouse => {
      dispatch(TimelinePointerDown(clip.clip_id, width.to_int(), mouse))
    },
  ) <| [
    @html.span(class="trim-handle trim-start", @html.nothing),
    @html.strong(take.map(value => value.variant).unwrap_or(clip.clip_id)),
    @html.small(
      "\{timecode(model, preview_duration)} · \{take.map(value => value.role).unwrap_or(track.kind)}",
    ),
    if track.kind == "audio" {
      @html.span(class="clip-waveform", "▂▅▃▇▄▆▂▅▃▆▁▅")
    } else {
      @html.span(class="clip-frames", "▦ ▦ ▦ ▦")
    },
    @html.span(class="trim-handle trim-end", @html.nothing),
  ]
}

///|
fn track_lane(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  track : @api.Track,
) -> @rabbita.Html {
  let duration = Int::max(duration_ticks(model), ticks_per_second(model) * 10)
  let width = Double::from_int(duration) *
    96.0 *
    model.zoom /
    Double::from_int(ticks_per_second(model))
  let mix = track.mix
  @html.div(class="track-row") <| [
    @html.div(class="track-header") <| [
      @html.strong(track.label.unwrap_or(track.track_id)),
      @html.span(track.kind),
      if track.kind == "audio" {
        @html.div(class="meter") <| [
          @html.span(
            style=[
              "width: \{Double::min(100.0, Double::max(2.0, 72.0 + mix.map(value => value.volume_db).unwrap_or(0.0)))}%",
            ],
            @html.nothing,
          ),
        ]
      } else {
        @html.nothing
      },
    ],
    @html.div(class="track-lane", style=["width: \{width}px"]) <| [
      @html.span(
        class="playhead",
        style=[
          "left: \{Double::from_int(model.playhead_ticks) * 96.0 * model.zoom / Double::from_int(ticks_per_second(model))}px",
        ],
        @html.nothing,
      ),
      ..track.clips.map(clip => clip_lane_item(dispatch, model, track, clip)),
    ],
  ]
}

///|
fn transition_rail(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let transitions = timeline(model)
    .map(value => value.transitions)
    .unwrap_or([])
  @html.div(class="transition-rail") <| [
    @html.span(class="rail-label", "Transitions"),
    if transitions.length() == 0 {
      @html.span(class="empty-inline", "Select two adjacent clips to add one")
    } else {
      @html.div(class="transition-list") <| transitions.map(item => {
        @html.button(
          type_="button",
          class=if item.transition_id == model.selected_transition_id {
            "is-selected"
          } else {
            ""
          },
          on_click=dispatch(SelectTransition(item.transition_id)),
          "\{item.kind} · \{timecode(model, item.duration_ticks)} · \{item.from_clip_id} → \{item.to_clip_id}",
        )
      })
    },
  ]
}

///|
fn timeline_toolbar(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(class="timeline-toolbar") <| [
    @html.div(class="tool-group") <| [
      @html.button(
        type_="button",
        disabled=model.busy || model.undo_stack.length() == 0,
        on_click=dispatch(Undo),
        "Undo",
      ),
      @html.button(
        type_="button",
        disabled=model.busy || model.redo_stack.length() == 0,
        on_click=dispatch(Redo),
        "Redo",
      ),
      @html.button(
        type_="button",
        disabled=model.busy || model.selected_clip_ids.length() != 1,
        on_click=dispatch(SplitSelection),
        "Split",
      ),
      @html.button(
        class=if model.blade { "is-active" } else { "" },
        type_="button",
        on_click=dispatch(ToggleBlade),
        "Blade",
      ),
      @html.button(
        class=if model.multi_select { "is-active" } else { "" },
        type_="button",
        on_click=dispatch(ToggleMultiSelect),
        "Multi-select",
      ),
      @html.button(
        type_="button",
        disabled=model.busy || model.selected_clip_ids.length() == 0,
        on_click=dispatch(DeleteSelection),
        "Delete",
      ),
    ],
    @html.div(class="tool-group") <| [
      @html.button(
        class=if model.ripple { "is-active" } else { "" },
        type_="button",
        on_click=dispatch(ToggleRipple),
        "Ripple",
      ),
      @html.button(
        class=if model.snap { "is-active" } else { "" },
        type_="button",
        on_click=dispatch(ToggleSnap),
        "Snap",
      ),
      @html.button(type_="button", on_click=dispatch(ZoomOut), "−"),
      @html.span("\{(model.zoom * 100.0).to_int()}%"),
      @html.button(type_="button", on_click=dispatch(ZoomIn), "+"),
      @html.button(type_="button", on_click=dispatch(FitTimeline), "Fit"),
    ],
    @html.div(class="tool-group frame-edits") <| [
      @html.button(
        type_="button",
        disabled=model.selected_clip_ids.length() == 0,
        on_click=dispatch(SelectAdjacentClip(-1, true)),
        "Extend ←",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_clip_ids.length() == 0,
        on_click=dispatch(SelectAdjacentClip(1, true)),
        "Extend →",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_clip_ids.length() == 0,
        on_click=dispatch(MoveSelection(-frame_ticks(model))),
        "Move −1f",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_clip_ids.length() == 0,
        on_click=dispatch(MoveSelection(frame_ticks(model))),
        "Move +1f",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_clip_ids.length() == 0,
        on_click=dispatch(TrimSelection("start", frame_ticks(model))),
        "Trim in +1f",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_clip_ids.length() == 0,
        on_click=dispatch(TrimSelection("end", -frame_ticks(model))),
        "Trim out −1f",
      ),
    ],
  ]
}

///|
fn timeline_view(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let seconds = Int::max(1, duration_ticks(model) / ticks_per_second(model))
  @html.section(class="timeline-panel") <| [
    timeline_toolbar(dispatch, model),
    @html.div(class="ruler-row") <| [
      @html.span(class="ruler-spacer", "Time"),
      @html.input(
        class="timeline-seek",
        input_type=@html.Range,
        min=0,
        max=Int::max(1, duration_ticks(model)),
        step=frame_ticks(model),
        value=model.playhead_ticks.to_string(),
        on_input=dispatch.map(value => SeekTicks(parse_whole(value, 0))),
      ),
      @html.span(class="duration-label", "\{seconds}s"),
    ],
    @html.div(
      class="timeline-scroll",
      on_scroll=scroll => dispatch(TimelineScrolled(scroll)),
    ) <| [
      @html.div(class="scroll-state") <| [
        @html.span(
          "\{timecode(model, (Double::from_int(model.timeline_scroll_x) / timeline_scale(model)).to_int())}",
        ),
        match model.timeline_drag {
          Some(drag) =>
            @html.strong(
              "\{drag_mode_label(drag.mode)} \{if drag.preview_delta_ticks >= 0 { "+" } else { "" }}\{timecode(model, drag.preview_delta_ticks.abs())}",
            )
          None =>
            @html.span(
              if model.blade {
                "Click a clip to split at pointer"
              } else {
                "Drag clip body · trim from edges"
              },
            )
        },
      ],
      ..tracks(model).map(track => track_lane(dispatch, model, track)),
    ],
    transition_rail(dispatch, model),
  ]
}
