///|
fn inspector_field(
  dispatch : @rabbita.Emit[Msg],
  label_text : String,
  key : String,
  value : String,
) -> @rabbita.Html {
  @html.label <| [
    @html.span(label_text),
    @html.input(
      value~,
      on_input=dispatch.map(next => InspectorChanged(key, next)),
    ),
  ]
}

///|
fn clip_identity(model : Model) -> @rabbita.Html {
  match selected_clip(model) {
    None =>
      @html.p(
        class="empty-note",
        "Select a clip to inspect canonical identity, rights, QC, lineage, and settings.",
      )
    Some(clip) => {
      let take = takes(model)
        .iter()
        .find_first(value => value.media_ref_id == clip.media_ref_id)
      let track = track_for_clip(model, clip.clip_id)
      @html.dl(class="inspector-data") <| [
        @html.dt("Clip"),
        @html.dd(clip.clip_id),
        @html.dt("Track"),
        @html.dd(
          track
          .map(value => "\{value.track_id} · \{value.kind}")
          .unwrap_or("—"),
        ),
        @html.dt("Range"),
        @html.dd(
          "\{timecode(model, clip.start_tick)} + \{timecode(model, clip.duration_ticks)}",
        ),
        @html.dt("Source in/out"),
        @html.dd("\{clip.source_in_tick}t / \{clip.source_out_tick}t"),
        @html.dt("Project / episode"),
        @html.dd("\{clip.identity.project_id} / \{clip.identity.episode_id}"),
        @html.dt("Scene / shot"),
        @html.dd("\{clip.identity.scene_id} / \{clip.identity.shot_id}"),
        @html.dt("Asset / media"),
        @html.dd("\{clip.identity.asset_id} / \{clip.media_ref_id}"),
        @html.dt("Intent"),
        @html.dd(clip.intent.intent_ref),
        @html.dt("QC / rights"),
        @html.dd(
          take
          .map(value => "\{value.qc.status} / \{value.rights.status}")
          .unwrap_or("declared source"),
        ),
        @html.dt("Provenance"),
        @html.dd(
          take
          .map(value => {
            "\{value.provider_ref.unwrap_or("fixture")} / \{value.model_ref.unwrap_or("local")}"
          })
          .unwrap_or("declared media reference"),
        ),
      ]
    }
  }
}

///|
fn clip_settings_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let draft = model.inspector
  @html.details(class="inspector-section", open=true) <| [
    @html.summary("Clip effects, mask & overlay"),
    @html.div(class="inspector-grid") <| [
      inspector_field(dispatch, "Brightness", "brightness", draft.brightness),
      inspector_field(dispatch, "Contrast", "contrast", draft.contrast),
      inspector_field(dispatch, "Saturation", "saturation", draft.saturation),
      inspector_field(dispatch, "Gamma", "gamma", draft.gamma),
      inspector_field(dispatch, "Opacity / mask", "opacity", draft.opacity),
      inspector_field(dispatch, "Scale", "scale", draft.scale),
      inspector_field(dispatch, "Position X", "position_x", draft.position_x),
      inspector_field(dispatch, "Position Y", "position_y", draft.position_y),
      inspector_field(dispatch, "Rotation degrees", "rotation", draft.rotation),
      @html.label(class="wide") <| [
        @html.span("Overlay text"),
        @html.textarea(
          value=draft.overlay_text,
          rows=3,
          on_input=dispatch.map(value => InspectorChanged("overlay_text", value)),
          "",
        ),
      ],
      inspector_field(dispatch, "Font size", "overlay_size", draft.overlay_size),
      @html.label <| [
        @html.span("Position"),
        @html.select(
          on_change=dispatch.map(value => {
            InspectorChanged("overlay_position", value)
          }),
        ) <| [
          @html.option(
            value="top",
            selected=draft.overlay_position == "top",
            "Top",
          ),
          @html.option(
            value="center",
            selected=draft.overlay_position == "center",
            "Center",
          ),
          @html.option(
            value="bottom",
            selected=draft.overlay_position == "bottom",
            "Bottom",
          ),
        ],
      ],
      @html.label <| [
        @html.span("Text color"),
        @html.input(
          input_type=@html.Color,
          value=draft.overlay_color,
          on_input=dispatch.map(value => {
            InspectorChanged("overlay_color", value)
          }),
        ),
      ],
      @html.label <| [
        @html.span("Background"),
        @html.input(
          input_type=@html.Color,
          value=draft.overlay_background,
          on_input=dispatch.map(value => {
            InspectorChanged("overlay_background", value)
          }),
        ),
      ],
      @html.label <| [
        @html.span("Mask shape"),
        @html.select(
          on_change=dispatch.map(value => InspectorChanged("mask_shape", value)),
        ) <| [
          @html.option(
            value="rectangle",
            selected=draft.mask_shape == "rectangle",
            "Rectangle",
          ),
          @html.option(
            value="ellipse",
            selected=draft.mask_shape == "ellipse",
            "Ellipse",
          ),
        ],
      ],
      inspector_field(dispatch, "Mask X", "mask_x", draft.mask_x),
      inspector_field(dispatch, "Mask Y", "mask_y", draft.mask_y),
      inspector_field(dispatch, "Mask width", "mask_width", draft.mask_width),
      inspector_field(dispatch, "Mask height", "mask_height", draft.mask_height),
      inspector_field(
        dispatch,
        "Mask feather",
        "mask_feather",
        draft.mask_feather,
      ),
      @html.label(class="check") <| [
        @html.input(
          input_type=@html.Checkbox,
          checked=draft.mask_invert,
          on_change=dispatch.map(_ => ToggleMaskInvert),
        ),
        @html.span("Invert mask"),
      ],
      inspector_field(
        dispatch,
        "Speed midpoint source %",
        "speed_midpoint",
        draft.speed_midpoint,
      ),
    ],
    @html.div(class="button-grid") <| [
      @html.button(
        class="primary",
        type_="button",
        disabled=model.busy || selected_clip(model) is None,
        on_click=dispatch(ApplyClipSettings),
        "Apply clip settings",
      ),
      @html.button(
        class="primary",
        type_="button",
        disabled=model.busy || selected_clip(model) is None,
        on_click=dispatch(ApplyEffectStack),
        "Apply effect + speed stack",
      ),
      @html.button(
        type_="button",
        disabled=selected_clip(model) is None,
        on_click=dispatch(AddTextLayer("title")),
        "Add title",
      ),
      @html.button(
        type_="button",
        disabled=selected_clip(model) is None,
        on_click=dispatch(AddTextLayer("subtitle")),
        "Add subtitle",
      ),
      @html.button(
        type_="button",
        disabled=selected_clip(model) is None,
        on_click=dispatch(AddAudioLayer("voice")),
        "Add voice",
      ),
      @html.button(
        type_="button",
        disabled=selected_clip(model) is None,
        on_click=dispatch(AddAudioLayer("music")),
        "Add music",
      ),
      @html.button(
        type_="button",
        disabled=selected_clip(model) is None,
        on_click=dispatch(AddAudioLayer("sfx")),
        "Add SFX",
      ),
    ],
  ]
}

///|
fn transition_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.details(class="inspector-section") <| [
    @html.summary("Transitions"),
    @html.div(class="inspector-grid") <| [
      @html.label <| [
        @html.span("Kind"),
        @html.select(
          on_change=dispatch.map(value => InspectorChanged("transition", value)),
        ) <| [
          @html.option(
            value="cross-dissolve",
            selected=model.inspector.transition == "cross-dissolve",
            "Cross dissolve",
          ),
          @html.option(
            value="fade-through-color",
            selected=model.inspector.transition == "fade-through-color",
            "Fade through black",
          ),
          @html.option(
            value="wipe-left",
            selected=model.inspector.transition == "wipe-left",
            "Wipe left",
          ),
          @html.option(
            value="wipe-right",
            selected=model.inspector.transition == "wipe-right",
            "Wipe right",
          ),
        ],
      ],
      inspector_field(
        dispatch,
        "Duration seconds",
        "transition_seconds",
        model.inspector.transition_seconds,
      ),
    ],
    @html.div(class="button-grid") <| [
      @html.button(
        class="primary",
        type_="button",
        on_click=dispatch(ApplyTransition),
        "Apply between 2 clips",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_transition_id == "",
        on_click=dispatch(ResizeTransition(-frame_ticks(model))),
        "Contract 1f",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_transition_id == "",
        on_click=dispatch(ResizeTransition(frame_ticks(model))),
        "Expand 1f",
      ),
      @html.button(
        type_="button",
        disabled=model.selected_transition_id == "",
        on_click=dispatch(RemoveTransition),
        "Remove",
      ),
    ],
  ]
}

///|
fn keyframe_view(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let draft = model.inspector
  @html.details(class="inspector-section") <| [
    @html.summary("Keyframes & speed curves"),
    @html.div(class="inspector-grid") <| [
      @html.label <| [
        @html.span("Channel"),
        @html.select(
          on_change=dispatch.map(value => {
            InspectorChanged("keyframe_channel", value)
          }),
        ) <| [
          ("opacity", "Opacity"),
          ("scale", "Scale"),
          ("position_x", "Position X"),
          ("position_y", "Position Y"),
          ("brightness", "Brightness"),
          ("contrast", "Contrast"),
          ("saturation", "Saturation"),
          ("gamma", "Gamma"),
          ("volume_db", "Volume dB"),
          ("pan", "Pan"),
        ].map(pair => {
          @html.option(
            value=pair.0,
            selected=draft.keyframe_channel == pair.0,
            pair.1,
          )
        }),
      ],
      inspector_field(dispatch, "Value", "keyframe_value", draft.keyframe_value),
      @html.label <| [
        @html.span("Interpolation"),
        @html.select(
          on_change=dispatch.map(value => {
            InspectorChanged("keyframe_interpolation", value)
          }),
        ) <| [
          @html.option(
            value="linear",
            selected=draft.keyframe_interpolation == "linear",
            "Linear",
          ),
          @html.option(
            value="hold",
            selected=draft.keyframe_interpolation == "hold",
            "Hold",
          ),
          @html.option(
            value="ease-in-out",
            selected=draft.keyframe_interpolation == "ease-in-out",
            "Ease in/out",
          ),
        ],
      ],
      @html.div(
        class="keyframe-time",
        "At \{selected_clip(model).map(clip => timecode(model, Int::max(0, model.playhead_ticks - clip.start_tick))).unwrap_or("—")}",
      ),
    ],
    @html.div(class="button-grid") <| [
      @html.button(
        class="primary",
        type_="button",
        disabled=selected_clip(model) is None,
        on_click=dispatch(SetKeyframe),
        "Add / update keyframe",
      ),
      @html.button(
        type_="button",
        disabled=selected_clip(model) is None,
        on_click=dispatch(RemoveKeyframe),
        "Remove at playhead",
      ),
    ],
    @html.p(
      class="microcopy",
      "The midpoint source percentage shapes a bounded 0.25×–4× speed ramp in the ordered effect stack; the server validates endpoints and rates.",
    ),
  ]
}

///|
fn audio_mix_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let is_audio = selected_clip(model)
    .bind(clip => track_for_clip(model, clip.clip_id))
    .map(track => track.kind == "audio")
    .unwrap_or(false)
  @html.details(class="inspector-section", hidden=!is_audio) <| [
    @html.summary("Audio bus & meters"),
    @html.div(class="inspector-grid") <| [
      inspector_field(
        dispatch,
        "Volume dB",
        "track_volume_db",
        model.inspector.track_volume_db,
      ),
      inspector_field(dispatch, "Pan", "track_pan", model.inspector.track_pan),
      @html.label(class="check") <| [
        @html.input(
          input_type=@html.Checkbox,
          checked=model.inspector.track_muted,
          on_change=dispatch.map(_ => ToggleTrackMute),
        ),
        @html.span("Muted"),
      ],
      @html.div(class="channel-meter") <| [
        @html.span(
          style=[
            "width: \{Double::min(100.0, Double::max(2.0, 72.0 + parse_number(model.inspector.track_volume_db, 0.0)))}%",
          ],
          @html.nothing,
        ),
      ],
    ],
    @html.button(
      class="primary",
      type_="button",
      on_click=dispatch(ApplyTrackMix),
      "Apply bus mix",
    ),
  ]
}

///|
fn inspector_panel(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.aside(class="inspector-pane") <| [
    @html.div(class="pane-heading") <| [
      @html.h2("Inspector"),
      @html.span("\{model.selected_clip_ids.length()} selected"),
    ],
    clip_identity(model),
    clip_settings_view(dispatch, model),
    transition_view(dispatch, model),
    keyframe_view(dispatch, model),
    audio_mix_view(dispatch, model),
  ]
}
