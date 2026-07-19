///|
fn update(
  dispatch : @rabbita.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@rabbita.Cmd, Model) {
  match msg {
    Bootstrap => {
      guard !model.bootstrapped else { return (@rabbita.none, model) }
      (
        @http.get("/api/editor/projects").expect_json(result => {
          dispatch(ProjectsLoaded(result))
        }),
        {
          ..model,
          bootstrapped: true,
          loading: true,
          status: "Loading editor projects…",
        },
      )
    }
    ProjectsLoaded(result) =>
      match result {
        Ok(response) => {
          guard decode_project_response(response) is Some(projects) else {
            return (
              @rabbita.none,
              {
                ..model,
                loading: false,
                error: "Editor project catalog used an unsupported response contract.",
              },
            )
          }
          let requested = projects
            .iter()
            .find_first(item => item.project_id == model.project_id)
          let project_id = option_or(requested, projects.get(0))
            .map(item => item.project_id)
            .unwrap_or(model.project_id)
          (
            @http.get("/api/editor/projects/" + project_id).expect_json(value => {
              dispatch(WorkspaceOpened(model.open_generation + 1, value))
            }),
            {
              ..model,
              projects,
              project_id,
              open_generation: model.open_generation + 1,
              loading: true,
              status: "Opening \{project_id}…",
              error: "",
            },
          )
        }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              loading: false,
              error: "Could not load editor projects.",
              retry: Some(RetryOpen(model.project_id)),
            },
          )
      }
    SelectProject(project_id) => (@rabbita.none, { ..model, project_id, })
    OpenProject => {
      let generation = model.open_generation + 1
      (
        @http.get("/api/editor/projects/" + model.project_id).expect_json(result => {
          dispatch(WorkspaceOpened(generation, result))
        }),
        {
          ..model,
          workspace: None,
          selected_take_id: "",
          selected_clip_ids: [],
          selected_transition_id: "",
          playhead_ticks: 0,
          last_animation_ms: None,
          timeline_drag: None,
          timeline_scroll_x: 0,
          open_generation: generation,
          loading: true,
          status: "Opening \{model.project_id}…",
          error: "",
          conflict: "",
          retry: None,
        },
      )
    }
    ProductionProjectChanged(value) =>
      (@rabbita.none, { ..model, production_project_id: value })
    ImportProduction => {
      guard model.production_project_id.trim().length() > 0 else {
        return (
          @rabbita.none,
          { ..model, error: "Enter a G4 production project id." },
        )
      }
      (
        @http.post(
          "/api/editor/projects/" +
          model.production_project_id +
          "/production-import",
        )
        .with_json(Json::object({}))
        .expect_json(result => dispatch(ProductionImported(result))),
        {
          ..model,
          busy: true,
          status: "Importing G4 production breakdown…",
          error: "",
        },
      )
    }
    ProductionImported(result) =>
      match result {
        Ok(_) => {
          let project_id = model.production_project_id
          let generation = model.open_generation + 1
          (
            @http.get("/api/editor/projects/" + project_id).expect_json(value => {
              dispatch(WorkspaceOpened(generation, value))
            }),
            {
              ..model,
              project_id,
              open_generation: generation,
              busy: false,
              loading: true,
              status: "Opening imported production…",
            },
          )
        }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Production import failed. G4 approval may be missing.",
            },
          )
      }
    WorkspaceOpened(generation, result) => {
      guard generation == model.open_generation else {
        return (@rabbita.none, model)
      }
      match result {
        Ok(response) => {
          guard decode_workspace_response(response) is Some(workspace) else {
            return (
              @rabbita.none,
              {
                ..model,
                loading: false,
                error: "Editor workspace used an unsupported response contract.",
              },
            )
          }
          let next = normalized_after_snapshot(model, workspace)
          paint_program_canvas(next)
          (
            @http.get("/api/editor/projects/" + model.project_id + "/snapshot").expect_json(value => {
                dispatch(SnapshotLoaded(generation, value))
              },
            ),
            {
              ..next,
              loading: true,
              status: "Reconciling canonical timeline…",
            },
          )
        }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              loading: false,
              error: "Could not open the editor workspace.",
              retry: Some(RetryOpen(model.project_id)),
            },
          )
      }
    }
    SnapshotLoaded(generation, result) => {
      guard generation == model.open_generation else {
        return (@rabbita.none, model)
      }
      match result {
        Ok(response) => {
          guard decode_workspace_response(response) is Some(workspace) else {
            return (
              @rabbita.none,
              {
                ..model,
                loading: false,
                error: "Canonical snapshot used an unsupported response contract.",
              },
            )
          }
          let next = normalized_after_snapshot(model, workspace)
          let command = match selected_take(next) {
            Some(take) if take.source.analysis_url is Some(url) =>
              @http.get(url).expect_json(value => {
                dispatch(AnalysisLoaded(take.take_id, value))
              })
            _ => @rabbita.none
          }
          (command, next)
        }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              loading: false,
              error: "Canonical snapshot reconciliation failed.",
              retry: Some(RetryOpen(model.project_id)),
            },
          )
      }
    }
    SelectTake(take_id) => {
      let command = match
        takes(model).iter().find_first(take => take.take_id == take_id) {
        Some(take) if take.source.analysis_url is Some(url) =>
          @http.get(url).expect_json(value => {
            dispatch(AnalysisLoaded(take_id, value))
          })
        _ => @rabbita.none
      }
      (command, { ..model, selected_take_id: take_id, analysis: None })
    }
    SelectAdjacentTake(direction) => {
      let visible = filtered_takes(model)
      guard visible.length() > 0 else { return (@rabbita.none, model) }
      let index = take_position(visible, model.selected_take_id)
      let next = Int::min(Int::max(0, index + direction), visible.length() - 1)
      update(dispatch, SelectTake(visible[next].take_id), model)
    }
    AnalysisLoaded(take_id, result) =>
      match result {
        Ok(response) if take_id == model.selected_take_id =>
          match decode_analysis_response(response) {
            Some(analysis) =>
              (@rabbita.none, { ..model, analysis: Some(analysis) })
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  error: "Media analysis used an unsupported response contract.",
                },
              )
          }
        _ => (@rabbita.none, model)
      }
    FilterSearchChanged(value) =>
      (@rabbita.none, { ..model, filters: { ..model.filters, search: value } })
    FilterKindChanged(value) =>
      (@rabbita.none, { ..model, filters: { ..model.filters, kind: value } })
    FilterQcChanged(value) =>
      (@rabbita.none, { ..model, filters: { ..model.filters, qc: value } })
    FilterRightsChanged(value) =>
      (@rabbita.none, { ..model, filters: { ..model.filters, rights: value } })
    FilterPlacementChanged(value) =>
      (
        @rabbita.none,
        { ..model, filters: { ..model.filters, placement: value } },
      )
    SelectClip(clip_id, extend) => {
      let selection = if extend {
        if model.selected_clip_ids.contains(clip_id) {
          model.selected_clip_ids.filter(id => id != clip_id)
        } else {
          append_string(model.selected_clip_ids, clip_id)
        }
      } else {
        [clip_id]
      }
      let take_id = clips(model)
        .iter()
        .find_first(clip => clip.clip_id == clip_id)
        .bind(clip => {
          takes(model)
          .iter()
          .find_first(take => take.media_ref_id == clip.media_ref_id)
        })
        .map(take => take.take_id)
        .unwrap_or(model.selected_take_id)
      let next = {
        ..model,
        selected_clip_ids: selection,
        selected_transition_id: "",
        selected_take_id: take_id,
        inspector: inspector_for_clip(model, clip_id),
      }
      (@rabbita.none, next)
    }
    SelectAdjacentClip(direction, extend) => {
      guard selected_clip(model) is Some(clip) else {
        return (@rabbita.none, model)
      }
      guard track_for_clip(model, clip.clip_id) is Some(track) else {
        return (@rabbita.none, model)
      }
      let ordered = track.clips
      let index = clip_position(ordered, clip.clip_id)
      let next = Int::min(Int::max(0, index + direction), ordered.length() - 1)
      update(dispatch, SelectClip(ordered[next].clip_id, extend), model)
    }
    SelectTransition(id) =>
      (
        @rabbita.none,
        { ..model, selected_transition_id: id, selected_clip_ids: [] },
      )
    SeekTicks(value) => {
      let next = {
        ..model,
        playhead_ticks: bounded_tick(model, value),
        last_animation_ms: None,
      }
      sync_program_media(next, true)
      paint_program_canvas(next)
      sync_authoritative_media(next)
      (@rabbita.none, next)
    }
    ScrubChanged(value) => {
      let seconds = parse_number(value, 0.0)
      update(
        dispatch,
        SeekTicks(
          (seconds * Double::from_int(ticks_per_second(model))).to_int(),
        ),
        model,
      )
    }
    StepFrame(direction) =>
      update(
        dispatch,
        SeekTicks(model.playhead_ticks + direction * frame_ticks(model)),
        { ..model, playing: false, last_animation_ms: None },
      )
    TogglePlay => {
      let playing = duration_ticks(model) > 0 && !model.playing
      let next = {
        ..model,
        playing,
        playhead_ticks: if playing &&
          model.playhead_ticks >= duration_ticks(model) {
          0
        } else {
          model.playhead_ticks
        },
        last_animation_ms: None,
      }
      sync_program_media(next, true)
      paint_program_canvas(next)
      (@rabbita.none, next)
    }
    AnimationFrame(now) => {
      guard model.playing else { return (@rabbita.none, model) }
      let elapsed = model.last_animation_ms
        .map(previous => Double::max(0.0, Double::min(250.0, now - previous)))
        .unwrap_or(0.0)
      let advance = if elapsed <= 0.0 {
        0
      } else {
        Int::max(
          1,
          (elapsed * Double::from_int(ticks_per_second(model)) / 1000.0).to_int(),
        )
      }
      let proposed = model.playhead_ticks + advance
      let (playing, tick) = match (model.loop_enabled, model.loop_out) {
        (true, Some(out)) if proposed >= out => (true, model.loop_in)
        (_, _) if proposed >= duration_ticks(model) =>
          (false, duration_ticks(model))
        _ => (true, proposed)
      }
      let next = {
        ..model,
        playing,
        playhead_ticks: tick,
        last_animation_ms: if playing {
          Some(now)
        } else {
          None
        },
      }
      let previous_active = clips(model)
        .iter()
        .find_first(clip => clip_is_active(clip, model.playhead_ticks))
        .map(clip => clip.clip_id)
        .unwrap_or("")
      let next_active = clips(next)
        .iter()
        .find_first(clip => clip_is_active(clip, next.playhead_ticks))
        .map(clip => clip.clip_id)
        .unwrap_or("")
      if previous_active != next_active ||
        (tick == model.loop_in && proposed != tick) {
        sync_program_media(next, true)
      }
      paint_program_canvas(next)
      (@rabbita.none, next)
    }
    SwitchMonitor(mode) => {
      let next = {
        ..model,
        monitor_mode: mode,
        playing: false,
        last_animation_ms: None,
      }
      sync_program_media(next, false)
      (@rabbita.none, next)
    }
    SwitchProgramSurface(surface) => {
      let next = {
        ..model,
        program_surface: surface,
        playing: false,
        last_animation_ms: None,
      }
      sync_program_media(next, false)
      paint_program_canvas(next)
      (@rabbita.none, next)
    }
    VolumeChanged(value) => {
      let next = {
        ..model,
        volume: value,
        muted: parse_number(value, 0.0) <= 0.0,
      }
      sync_program_media(next, false)
      sync_authoritative_media(next)
      (@rabbita.none, next)
    }
    ToggleMute => {
      let next = { ..model, muted: !model.muted }
      sync_program_media(next, false)
      sync_authoritative_media(next)
      (@rabbita.none, next)
    }
    SetLoopIn =>
      (
        @rabbita.none,
        {
          ..model,
          loop_in: model.playhead_ticks,
          loop_out: match model.loop_out {
            Some(out) if out > model.playhead_ticks => Some(out)
            _ => None
          },
        },
      )
    SetLoopOut =>
      (
        @rabbita.none,
        {
          ..model,
          loop_out: Some(
            Int::max(model.playhead_ticks, model.loop_in + frame_ticks(model)),
          ),
        },
      )
    ToggleLoop =>
      (@rabbita.none, { ..model, loop_enabled: !model.loop_enabled })
    ResyncProxy => {
      sync_program_media(model, true)
      paint_program_canvas(model)
      (
        @rabbita.none,
        {
          ..model,
          status: "Interactive proxy resynchronized at \{timecode(model, model.playhead_ticks)}.",
        },
      )
    }
    RefreshProgramMedia => {
      sync_program_media(model, false)
      paint_program_canvas(model)
      (@rabbita.none, model)
    }
    ToggleRipple => (@rabbita.none, { ..model, ripple: !model.ripple })
    ToggleSnap => (@rabbita.none, { ..model, snap: !model.snap })
    ToggleBlade => (@rabbita.none, { ..model, blade: !model.blade })
    ToggleMultiSelect =>
      (@rabbita.none, { ..model, multi_select: !model.multi_select })
    TimelinePointerDown(clip_id, width, mouse) => {
      guard !model.busy else { return (@rabbita.none, model) }
      guard clips(model).iter().find_first(clip => clip.clip_id == clip_id)
        is Some(clip) else {
        return (@rabbita.none, model)
      }
      let pointer = mouse.offset_pos().x
      if model.blade {
        let local_tick = quantize_ticks(
          model,
          (Double::from_int(pointer) / timeline_scale(model)).to_int(),
        )
        let tick = Int::min(
          clip.start_tick + clip.duration_ticks - frame_ticks(model),
          Int::max(
            clip.start_tick + frame_ticks(model),
            clip.start_tick + local_tick,
          ),
        )
        return update(dispatch, SplitSelection, {
          ..model,
          selected_clip_ids: [clip_id],
          selected_transition_id: "",
          selected_take_id: take_for_clip(model, clip)
          .map(take => take.take_id)
          .unwrap_or(model.selected_take_id),
          inspector: inspector_for_clip(model, clip_id),
          playhead_ticks: tick,
        })
      }
      let selection = if model.multi_select {
        if model.selected_clip_ids.contains(clip_id) {
          model.selected_clip_ids
        } else {
          append_string(model.selected_clip_ids, clip_id)
        }
      } else if model.selected_clip_ids.contains(clip_id) {
        model.selected_clip_ids
      } else {
        [clip_id]
      }
      let edge = 11
      let mode = if pointer <= edge {
        DragTrimStart
      } else if pointer >= width - edge {
        DragTrimEnd
      } else {
        DragMove
      }
      (
        @rabbita.none,
        {
          ..model,
          selected_clip_ids: selection,
          selected_transition_id: "",
          selected_take_id: take_for_clip(model, clip)
          .map(take => take.take_id)
          .unwrap_or(model.selected_take_id),
          inspector: inspector_for_clip(model, clip_id),
          timeline_drag: Some({
            clip_id,
            mode,
            origin_client_x: mouse.client_pos().x,
            preview_delta_ticks: 0,
          }),
          playing: false,
          last_animation_ms: None,
        },
      )
    }
    TimelinePointerMoved(mouse) =>
      match model.timeline_drag {
        Some(drag) =>
          (
            @rabbita.none,
            {
              ..model,
              timeline_drag: Some({
                ..drag,
                preview_delta_ticks: drag_delta(
                  model,
                  drag,
                  mouse.client_pos().x,
                ),
              }),
            },
          )
        None => (@rabbita.none, model)
      }
    TimelinePointerReleased =>
      match model.timeline_drag {
        None => (@rabbita.none, model)
        Some(drag) => {
          let next = { ..model, timeline_drag: None }
          if drag.preview_delta_ticks == 0 {
            (@rabbita.none, next)
          } else {
            match drag.mode {
              DragMove =>
                update(dispatch, MoveSelection(drag.preview_delta_ticks), next)
              DragTrimStart =>
                update(
                  dispatch,
                  TrimSelection("start", drag.preview_delta_ticks),
                  next,
                )
              DragTrimEnd =>
                update(
                  dispatch,
                  TrimSelection("end", drag.preview_delta_ticks),
                  next,
                )
            }
          }
        }
      }
    TimelineScrolled(scroll) =>
      (@rabbita.none, { ..model, timeline_scroll_x: scroll.offset_pos().x })
    ZoomIn =>
      (@rabbita.none, { ..model, zoom: Double::min(8.0, model.zoom * 1.5) })
    ZoomOut =>
      (@rabbita.none, { ..model, zoom: Double::max(0.25, model.zoom / 1.5) })
    FitTimeline => {
      let seconds = Double::from_int(Int::max(1, duration_ticks(model))) /
        Double::from_int(ticks_per_second(model))
      let available = Double::from_int(
        Int::max(320, model.viewport_width - 420),
      )
      (
        @rabbita.none,
        {
          ..model,
          zoom: Double::min(
            8.0,
            Double::max(0.25, available / (96.0 * seconds)),
          ),
        },
      )
    }
    AddSelectedTake => {
      guard selected_take(model) is Some(take) else {
        return (
          @rabbita.none,
          { ..model, error: take_eligibility(selected_take(model)) },
        )
      }
      guard take_is_eligible(take) else {
        return (@rabbita.none, { ..model, error: take_eligibility(Some(take)) })
      }
      guard take.add_clip_template is Some(template) else {
        return (@rabbita.none, model)
      }
      let kind = if model.ripple { "ripple_insert" } else { "add" }
      let payload : Json = {
        "track_id": template.track_id,
        "clip": template.clip.to_json(),
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, kind, payload))
        .expect_json(result => dispatch(CommandFinished(kind, payload, result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving \{kind}…",
          error: "",
        },
      )
    }
    MoveSelection(delta) => {
      let chosen = clips(model).filter(clip => {
        model.selected_clip_ids.contains(clip.clip_id)
      })
      guard chosen.length() > 0 else { return (@rabbita.none, model) }
      let kind = if chosen.length() == 1 { "move" } else { "group_move" }
      let payload : Json = if chosen.length() == 1 {
        let clip = chosen[0]
        let track_id = track_for_clip(model, clip.clip_id)
          .map(track => track.track_id)
          .unwrap_or("")
        {
          "clip_id": clip.clip_id,
          "track_id": track_id,
          "start_tick": Int::max(0, clip.start_tick + delta),
        }
      } else {
        let moves = chosen.map(clip => {
          let track_id = track_for_clip(model, clip.clip_id)
            .map(track => track.track_id)
            .unwrap_or("")
          (
            {
              "clip_id": clip.clip_id,
              "track_id": track_id,
              "start_tick": Int::max(0, clip.start_tick + delta),
            } : Json)
        })
        { "moves": Json::array(moves) }
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, kind, payload))
        .expect_json(result => dispatch(CommandFinished(kind, payload, result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving \{kind}…",
          error: "",
        },
      )
    }
    TrimSelection(edge, delta) => {
      let chosen = clips(model).filter(clip => {
        model.selected_clip_ids.contains(clip.clip_id)
      })
      guard chosen.length() > 0 else { return (@rabbita.none, model) }
      let kind = if chosen.length() == 1 {
        if model.ripple {
          "ripple_trim"
        } else {
          "trim"
        }
      } else {
        "group_trim"
      }
      let payload : Json = if chosen.length() == 1 {
        let clip = chosen[0]
        let source_in = clip.source_in_tick +
          (if edge == "start" { delta } else { 0 })
        let source_out = clip.source_out_tick +
          (if edge == "end" { delta } else { 0 })
        if edge == "start" && !model.ripple {
          {
            "clip_id": clip.clip_id,
            "source_in_tick": source_in,
            "source_out_tick": source_out,
            "start_tick": clip.start_tick + delta,
          }
        } else {
          {
            "clip_id": clip.clip_id,
            "source_in_tick": source_in,
            "source_out_tick": source_out,
          }
        }
      } else {
        let trims = chosen.map(clip => {
          let source_in = clip.source_in_tick +
            (if edge == "start" { delta } else { 0 })
          let source_out = clip.source_out_tick +
            (if edge == "end" { delta } else { 0 })
          (
            {
              "clip_id": clip.clip_id,
              "source_in_tick": source_in,
              "source_out_tick": source_out,
              "start_tick": clip.start_tick +
              (if edge == "start" { delta } else { 0 }),
            } : Json)
        })
        { "trims": Json::array(trims) }
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, kind, payload))
        .expect_json(result => dispatch(CommandFinished(kind, payload, result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving \{kind}…",
          error: "",
        },
      )
    }
    SplitSelection => {
      guard selected_clip(model) is Some(clip) else {
        return (@rabbita.none, model)
      }
      guard model.selected_clip_ids.length() == 1 else {
        return (@rabbita.none, model)
      }
      guard model.playhead_ticks > clip.start_tick &&
        model.playhead_ticks < clip.start_tick + clip.duration_ticks else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Move the playhead inside one selected clip before splitting.",
          },
        )
      }
      let payload : Json = {
        "clip_id": clip.clip_id,
        "split_tick": model.playhead_ticks,
        "left_clip_id": fresh_key(model, "split-left"),
        "right_clip_id": fresh_key(model, "split-right"),
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "split", payload))
        .expect_json(result => {
          dispatch(CommandFinished("split", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving split…",
          error: "",
        },
      )
    }
    DeleteSelection => {
      guard model.selected_clip_ids.length() > 0 else {
        return (@rabbita.none, model)
      }
      let kind = if model.selected_clip_ids.length() > 1 {
        "group_delete"
      } else if model.ripple {
        "ripple_delete"
      } else {
        "delete"
      }
      let payload : Json = if model.selected_clip_ids.length() > 1 {
        {
          "clip_ids": Json::array(
            model.selected_clip_ids.map(id => id.to_json()),
          ),
        }
      } else {
        { "clip_id": model.selected_clip_ids[0] }
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, kind, payload))
        .expect_json(result => dispatch(CommandFinished(kind, payload, result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving \{kind}…",
          error: "",
        },
      )
    }
    Undo => {
      guard last_string(model.undo_stack) is Some(target) else {
        return (@rabbita.none, model)
      }
      let payload : Json = { "target_command_id": target }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "undo", payload))
        .expect_json(result => {
          dispatch(CommandFinished("undo", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Undoing exact command…",
        },
      )
    }
    Redo => {
      guard last_string(model.redo_stack) is Some(target) else {
        return (@rabbita.none, model)
      }
      let payload : Json = { "target_command_id": target }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "redo", payload))
        .expect_json(result => {
          dispatch(CommandFinished("redo", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Redoing exact command…",
        },
      )
    }
    CommandFinished(kind, payload, result) =>
      match result {
        Ok(response) => {
          let command_id = "http:" +
            fresh_key(
              { ..model, request_sequence: model.request_sequence - 1 },
              kind,
            )
          let stacks = if kind == "undo" {
            (
              drop_last_string(model.undo_stack),
              append_string(
                model.redo_stack,
                last_string(model.undo_stack).unwrap_or(""),
              ),
            )
          } else if kind == "redo" {
            (
              append_string(
                model.undo_stack,
                last_string(model.redo_stack).unwrap_or(""),
              ),
              drop_last_string(model.redo_stack),
            )
          } else {
            (append_string(model.undo_stack, command_id), [])
          }
          let undo_stack = stacks.0
          let redo_stack = stacks.1
          guard model.workspace is Some(current) else {
            return (
              @rabbita.none,
              {
                ..model,
                busy: false,
                error: "Mutation returned without an open workspace.",
              },
            )
          }
          guard decode_mutation_response(response, current) is Some(incoming) else {
            return (
              @rabbita.none,
              {
                ..model,
                busy: false,
                error: "Editor mutation used an unsupported response contract.",
              },
            )
          }
          let next = normalized_after_snapshot(
            { ..model, undo_stack, redo_stack },
            incoming,
          )
          (
            @http.get("/api/editor/projects/" + model.project_id + "/snapshot").expect_json(value => {
                dispatch(SnapshotLoaded(model.open_generation, value))
              },
            ),
            {
              ..next,
              loading: true,
              status: "Mutation accepted; reconciling server authority…",
            },
          )
        }
        Err(_) =>
          (
            @http.get("/api/editor/projects/" + model.project_id + "/snapshot").expect_json(value => {
                dispatch(SnapshotLoaded(model.open_generation, value))
              },
            ),
            {
              ..model,
              busy: false,
              loading: true,
              conflict: "Mutation was rejected; latest server revision is being loaded.",
              retry: Some(RetryCommand(kind, payload)),
            },
          )
      }
    InspectorChanged(field, value) => {
      let draft = model.inspector
      let inspector = match field {
        "transition" => { ..draft, transition: value }
        "transition_seconds" => { ..draft, transition_seconds: value }
        "brightness" => { ..draft, brightness: value }
        "contrast" => { ..draft, contrast: value }
        "saturation" => { ..draft, saturation: value }
        "gamma" => { ..draft, gamma: value }
        "opacity" => { ..draft, opacity: value }
        "scale" => { ..draft, scale: value }
        "position_x" => { ..draft, position_x: value }
        "position_y" => { ..draft, position_y: value }
        "rotation" => { ..draft, rotation: value }
        "mask_shape" => { ..draft, mask_shape: value }
        "mask_x" => { ..draft, mask_x: value }
        "mask_y" => { ..draft, mask_y: value }
        "mask_width" => { ..draft, mask_width: value }
        "mask_height" => { ..draft, mask_height: value }
        "mask_feather" => { ..draft, mask_feather: value }
        "speed_midpoint" => { ..draft, speed_midpoint: value }
        "overlay_text" => { ..draft, overlay_text: value }
        "overlay_position" => { ..draft, overlay_position: value }
        "overlay_size" => { ..draft, overlay_size: value }
        "overlay_color" => { ..draft, overlay_color: value }
        "overlay_background" => { ..draft, overlay_background: value }
        "track_volume_db" => { ..draft, track_volume_db: value }
        "track_pan" => { ..draft, track_pan: value }
        "keyframe_channel" => { ..draft, keyframe_channel: value }
        "keyframe_value" => { ..draft, keyframe_value: value }
        "keyframe_interpolation" => { ..draft, keyframe_interpolation: value }
        _ => draft
      }
      (@rabbita.none, { ..model, inspector, })
    }
    ToggleTrackMute =>
      (
        @rabbita.none,
        {
          ..model,
          inspector: {
            ..model.inspector,
            track_muted: !model.inspector.track_muted,
          },
        },
      )
    ToggleMaskInvert =>
      (
        @rabbita.none,
        {
          ..model,
          inspector: {
            ..model.inspector,
            mask_invert: !model.inspector.mask_invert,
          },
        },
      )
    ApplyClipSettings => {
      guard selected_clip(model) is Some(clip) else {
        return (@rabbita.none, model)
      }
      let draft = model.inspector
      let payload : Json = {
        "clip_id": clip.clip_id,
        "settings": {
          "transition": { "name": "cut", "duration_ticks": 0 },
          "color": {
            "brightness": parse_number(draft.brightness, 0.0),
            "contrast": parse_number(draft.contrast, 1.0),
            "saturation": parse_number(draft.saturation, 1.0),
            "gamma": parse_number(draft.gamma, 1.0),
          },
          "effect": {
            "opacity": parse_number(draft.opacity, 1.0),
            "scale": parse_number(draft.scale, 1.0),
            "x": parse_number(draft.position_x, 0.0),
            "y": parse_number(draft.position_y, 0.0),
          },
          "overlay": {
            "text": draft.overlay_text,
            "font_size": parse_whole(draft.overlay_size, 48),
            "color": draft.overlay_color,
            "background": draft.overlay_background + "99",
            "position": draft.overlay_position,
          },
        },
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "configure_clip", payload))
        .expect_json(result => {
          dispatch(CommandFinished("configure_clip", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving clip effects and overlay…",
        },
      )
    }
    ApplyEffectStack => {
      guard selected_clip_track(model) is Some((clip, track)) else {
        return (@rabbita.none, model)
      }
      let draft = model.inspector
      let midpoint_timeline = Int::max(1, clip.duration_ticks / 2)
      let source_span = clip.source_out_tick - clip.source_in_tick
      let midpoint_source = clip.source_in_tick +
        (Double::from_int(source_span) *
        parse_number(draft.speed_midpoint, 50.0) /
        100.0).to_int()
      let speed : Json = {
        "effect_id": fresh_key(model, "speed"),
        "type": "speed-ramp",
        "enabled": true,
        "parameters": {
          "points": [
            {
              "timeline_tick": 0,
              "source_tick": clip.source_in_tick,
              "interpolation": "linear",
            },
            {
              "timeline_tick": midpoint_timeline,
              "source_tick": midpoint_source,
              "interpolation": "linear",
            },
            {
              "timeline_tick": clip.duration_ticks,
              "source_tick": clip.source_out_tick,
              "interpolation": "linear",
            },
          ],
        },
      }
      let effects : Array[Json] = if track.kind == "audio" {
        [speed]
      } else {
        [
          (
            {
              "effect_id": fresh_key(model, "transform"),
              "type": "transform",
              "enabled": true,
              "parameters": {
                "scale": parse_number(draft.scale, 1.0),
                "x": parse_number(draft.position_x, 0.0),
                "y": parse_number(draft.position_y, 0.0),
                "rotation_degrees": parse_number(draft.rotation, 0.0),
              },
            } : Json),
          (
            {
              "effect_id": fresh_key(model, "opacity"),
              "type": "opacity",
              "enabled": true,
              "parameters": { "value": parse_number(draft.opacity, 1.0) },
            } : Json),
          (
            {
              "effect_id": fresh_key(model, "mask"),
              "type": "mask",
              "enabled": true,
              "parameters": {
                "shape": draft.mask_shape,
                "x": parse_number(draft.mask_x, 0.1),
                "y": parse_number(draft.mask_y, 0.1),
                "width": parse_number(draft.mask_width, 0.8),
                "height": parse_number(draft.mask_height, 0.8),
                "feather": parse_number(draft.mask_feather, 0.05),
                "invert": draft.mask_invert,
              },
            } : Json),
          speed,
        ]
      }
      let payload : Json = {
        "clip_id": clip.clip_id,
        "effects": Json::array(effects),
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "configure_effect_stack", payload))
        .expect_json(result => {
          dispatch(CommandFinished("configure_effect_stack", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving ordered transform, mask, opacity, and speed-ramp stack…",
        },
      )
    }
    ApplyTrackMix => {
      guard selected_clip_track(model) is Some((_, track)) else {
        return (@rabbita.none, model)
      }
      guard track.kind == "audio" else { return (@rabbita.none, model) }
      let payload : Json = {
        "track_id": track.track_id,
        "mix": {
          "volume_db": parse_number(model.inspector.track_volume_db, 0.0),
          "pan": parse_number(model.inspector.track_pan, 0.0),
          "muted": model.inspector.track_muted,
        },
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "configure_track", payload))
        .expect_json(result => {
          dispatch(CommandFinished("configure_track", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving audio bus mix…",
        },
      )
    }
    AddTextLayer(role) => {
      guard selected_clip(model) is Some(source) else {
        return (@rabbita.none, model)
      }
      guard tracks(model)
        .iter()
        .find_first(track => lower(track.track_id).contains(role))
        is Some(track) else {
        return (
          @rabbita.none,
          { ..model, error: "No canonical \{role} track exists." },
        )
      }
      let duration = Int::min(
        source.duration_ticks,
        ticks_per_second(model) * 3,
      )
      let payload : Json = {
        "track_id": track.track_id,
        "clip": {
          "clip_id": fresh_key(model, role),
          "media_ref_id": source.media_ref_id,
          "identity": source.identity.to_json(),
          "intent": source.intent.to_json(),
          "start_tick": model.playhead_ticks,
          "duration_ticks": duration,
          "source_in_tick": source.source_in_tick,
          "source_out_tick": source.source_in_tick + duration,
          "settings": {
            "transition": { "name": "cut", "duration_ticks": 0 },
            "color": {
              "brightness": 0.0,
              "contrast": 1.0,
              "saturation": 1.0,
              "gamma": 1.0,
            },
            "effect": { "opacity": 1.0, "scale": 1.0, "x": 0.0, "y": 0.0 },
            "overlay": {
              "text": if model.inspector.overlay_text == "" {
                if role == "title" {
                  "New title"
                } else {
                  "New subtitle"
                }
              } else {
                model.inspector.overlay_text
              },
              "font_size": parse_whole(model.inspector.overlay_size, 48),
              "color": model.inspector.overlay_color,
              "background": model.inspector.overlay_background + "99",
              "position": model.inspector.overlay_position,
            },
          },
        },
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "add", payload))
        .expect_json(result => dispatch(CommandFinished("add", payload, result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Adding \{role} layer…",
        },
      )
    }
    AddAudioLayer(role) => {
      guard selected_clip(model) is Some(source) else {
        return (@rabbita.none, model)
      }
      guard tracks(model)
        .iter()
        .find_first(track => {
          track.kind == "audio" && lower(track.track_id).contains(role)
        })
        is Some(track) else {
        return (
          @rabbita.none,
          { ..model, error: "No canonical \{role} audio bus exists." },
        )
      }
      let payload : Json = {
        "track_id": track.track_id,
        "clip": {
          "clip_id": fresh_key(model, role),
          "media_ref_id": source.media_ref_id,
          "identity": source.identity.to_json(),
          "intent": source.intent.to_json(),
          "start_tick": model.playhead_ticks,
          "duration_ticks": source.duration_ticks,
          "source_in_tick": source.source_in_tick,
          "source_out_tick": source.source_out_tick,
        },
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "add", payload))
        .expect_json(result => dispatch(CommandFinished("add", payload, result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Adding \{role} bus layer…",
        },
      )
    }
    ApplyTransition => {
      guard model.selected_clip_ids.length() == 2 else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Select exactly two adjacent clips for a transition.",
          },
        )
      }
      guard track_for_clip(model, model.selected_clip_ids[0]) is Some(track) else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Transition clips must be on the same canonical track.",
          },
        )
      }
      guard track.clips.any(clip => clip.clip_id == model.selected_clip_ids[1]) else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Transition clips must be on the same canonical track.",
          },
        )
      }
      let duration = (parse_number(model.inspector.transition_seconds, 0.5) *
      Double::from_int(ticks_per_second(model))).to_int()
      let outgoing = Int::max(1, duration / 2)
      let incoming = Int::max(1, duration - outgoing)
      let transition : Json = {
        "transition_id": if model.selected_transition_id == "" {
          fresh_key(model, "transition")
        } else {
          model.selected_transition_id
        },
        "track_id": track.track_id,
        "from_clip_id": model.selected_clip_ids[0],
        "to_clip_id": model.selected_clip_ids[1],
        "kind": model.inspector.transition,
        "duration_ticks": duration,
        "outgoing_handle_ticks": outgoing,
        "incoming_handle_ticks": incoming,
        "color": "#000000",
        "direction": if model.inspector.transition == "wipe-left" {
          "left"
        } else if model.inspector.transition == "wipe-right" {
          "right"
        } else {
          "none"
        },
      }
      let payload : Json = { "transition": transition }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "configure_transition", payload))
        .expect_json(result => {
          dispatch(CommandFinished("configure_transition", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving transition…",
        },
      )
    }
    ResizeTransition(delta) => {
      guard timeline(model) is Some(value) else {
        return (@rabbita.none, model)
      }
      guard value.transitions
        .iter()
        .find_first(item => item.transition_id == model.selected_transition_id)
        is Some(transition) else {
        return (@rabbita.none, model)
      }
      let payload : Json = {
        "transition": {
          "transition_id": transition.transition_id,
          "track_id": transition.track_id.unwrap_or(
            track_for_clip(model, transition.from_clip_id)
            .map(track => track.track_id)
            .unwrap_or(""),
          ),
          "from_clip_id": transition.from_clip_id,
          "to_clip_id": transition.to_clip_id,
          "kind": transition.kind,
          "duration_ticks": Int::max(
            frame_ticks(model),
            transition.duration_ticks + delta,
          ),
          "outgoing_handle_ticks": Int::max(
            1,
            transition.outgoing_handle_ticks.unwrap_or(
              transition.duration_ticks / 2,
            ) +
            delta / 2,
          ),
          "incoming_handle_ticks": Int::max(
            1,
            transition.incoming_handle_ticks.unwrap_or(
              transition.duration_ticks - transition.duration_ticks / 2,
            ) +
            delta -
            delta / 2,
          ),
          "color": transition.color.unwrap_or("#000000"),
          "direction": transition.direction.unwrap_or("none"),
        },
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "configure_transition", payload))
        .expect_json(result => {
          dispatch(CommandFinished("configure_transition", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Resizing transition…",
        },
      )
    }
    RemoveTransition => {
      guard model.selected_transition_id != "" else {
        return (@rabbita.none, model)
      }
      let payload : Json = { "transition_id": model.selected_transition_id }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "remove_transition", payload))
        .expect_json(result => {
          dispatch(CommandFinished("remove_transition", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Removing transition…",
        },
      )
    }
    SetKeyframe | RemoveKeyframe => {
      guard selected_clip(model) is Some(clip) else {
        return (@rabbita.none, model)
      }
      let relative = Int::min(
        Int::max(0, model.playhead_ticks - clip.start_tick),
        clip.duration_ticks,
      )
      let curve = match msg {
        SetKeyframe =>
          Json::array([
            (
              {
                "tick": relative,
                "value": parse_number(model.inspector.keyframe_value, 1.0),
                "interpolation": model.inspector.keyframe_interpolation,
              } : Json),
          ])
        _ => Json::array([])
      }
      let keyframes : Json = match model.inspector.keyframe_channel {
        "scale" => { "scale": curve }
        "position_x" => { "position_x": curve }
        "position_y" => { "position_y": curve }
        "brightness" => { "brightness": curve }
        "contrast" => { "contrast": curve }
        "saturation" => { "saturation": curve }
        "gamma" => { "gamma": curve }
        "volume_db" => { "volume_db": curve }
        "pan" => { "pan": curve }
        _ => { "opacity": curve }
      }
      let payload : Json = { "clip_id": clip.clip_id, "keyframes": keyframes }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "set_keyframes", payload))
        .expect_json(result => {
          dispatch(CommandFinished("set_keyframes", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving keyframe curve…",
        },
      )
    }
    IntakeChanged(field, value) => {
      let draft = model.intake
      let intake = match field {
        "role" => { ..draft, role: value }
        "file_name" => { ..draft, file_name: value }
        "mime_type" => { ..draft, mime_type: value }
        "size_bytes" => { ..draft, size_bytes: value }
        "sha256" => { ..draft, sha256: value }
        "duration_seconds" => { ..draft, duration_seconds: value }
        "owner" => { ..draft, owner: value }
        "basis" => { ..draft, basis: value }
        "territory" => { ..draft, territory: value }
        "channels" => { ..draft, channels: value }
        "rights_ref" => { ..draft, rights_ref: value }
        "source_kind" => { ..draft, source_kind: value }
        "source_ref" => { ..draft, source_ref: value }
        "pasted_content" => { ..draft, pasted_content: value }
        _ => draft
      }
      (@rabbita.none, { ..model, intake, })
    }
    CreateMediaIntake => {
      guard model.workspace is Some(workspace) else {
        return (@rabbita.none, model)
      }
      let identity = option_or(
        selected_clip(model).map(clip => clip.identity),
        workspace.navigator.bind(items => items.get(0)),
      )
      guard identity is Some(binding) else {
        return (
          @rabbita.none,
          { ..model, error: "Open a production shot before media intake." },
        )
      }
      let draft = model.intake
      let channels = draft.channels
        .split(",")
        .map(value => value.trim().to_owned().to_json())
        .collect()
      let body : Json = {
        "expected_editor_revision": selected_revision(model),
        "idempotency_key": fresh_key(model, "local-media"),
        "role": draft.role,
        "file_name": draft.file_name,
        "mime_type": draft.mime_type,
        "size_bytes": parse_whole(
          draft.size_bytes,
          draft.pasted_content.length(),
        ),
        "sha256": draft.sha256,
        "duration_ticks": Int::max(
          1,
          (parse_number(draft.duration_seconds, 5.0) *
          Double::from_int(ticks_per_second(model))).to_int(),
        ),
        "identity": binding.to_json(),
        "rights": {
          "confirmed": true,
          "owner": draft.owner,
          "basis": draft.basis,
          "territory": draft.territory,
          "channels": Json::array(channels),
          "rights_ref": draft.rights_ref,
        },
        "source": { "kind": draft.source_kind, "source_id": draft.source_ref },
        "created_by": "rabbita-editor-operator",
      }
      (
        @http.post(
          "/api/editor/projects/" + model.project_id + "/media-intakes",
        )
        .with_json(body)
        .expect_json(result => dispatch(IntakeCreated(result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Freezing rights and source metadata…",
        },
      )
    }
    IntakeCreated(result) =>
      match result {
        Ok(response) =>
          match decode_intake_prepared(response) {
            Some(prepared) =>
              (
                @http.post(prepared.upload_url)
                .with_text(model.intake.pasted_content)
                .expect_json(value => dispatch(IntakeContentUploaded(value))),
                {
                  ..model,
                  pending_intake_id: prepared.intake_id,
                  status: "Uploading immutable local media bytes…",
                },
              )
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  error: "Media intake used an unsupported response contract.",
                },
              )
          }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Rights intake was rejected; verify owner, basis, digest, and revision.",
            },
          )
      }
    IntakeContentUploaded(result) =>
      match result {
        Ok(_) =>
          (
            @http.get("/api/editor/projects/" + model.project_id).expect_json(value => {
              dispatch(WorkspaceOpened(model.open_generation, value))
            }),
            {
              ..model,
              busy: false,
              loading: true,
              selected_take_id: "take-" + model.pending_intake_id,
              pending_intake_id: "",
              status: "Media verified; refreshing asset registry…",
            },
          )
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Media bytes did not match the frozen intake digest or type.",
            },
          )
      }
    ReviewCommentChanged(value) =>
      (@rabbita.none, { ..model, review_comment: value })
    PostReviewComment => {
      let comment = model.review_comment.trim().to_owned()
      guard comment.length() > 0 && duration_ticks(model) > 0 else {
        return (@rabbita.none, model)
      }
      let start_tick = Int::min(
        Int::max(0, model.playhead_ticks),
        duration_ticks(model) - 1,
      )
      let body : Json = {
        "comment": {
          "comment_id": fresh_key(model, "comment"),
          "kind": "review",
          "start_tick": start_tick,
          "end_tick": Int::min(
            duration_ticks(model),
            start_tick + frame_ticks(model),
          ),
          "text": comment,
          "revision_round": 0,
        },
        "expected_revision": selected_revision(model),
        "idempotency_key": fresh_key(model, "review"),
      }
      (
        @http.post(
          "/api/editor/projects/" + model.project_id + "/review-comments",
        )
        .with_json(body)
        .expect_json(result => dispatch(CommentSaved(result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving frame-accurate review marker…",
        },
      )
    }
    CommentSaved(result) =>
      match result {
        Ok(_) =>
          (
            @http.get("/api/editor/projects/" + model.project_id).expect_json(value => {
              dispatch(WorkspaceOpened(model.open_generation, value))
            }),
            {
              ..model,
              busy: false,
              loading: true,
              review_comment: "",
              status: "Review marker saved; refreshing evidence…",
            },
          )
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Review marker was rejected.",
              retry: Some(RetryComment(model.review_comment)),
            },
          )
      }
    ExportChanged(field, value) => {
      let state = model.export_state
      let export_state = match field {
        "preset" => { ..state, output_preset: value }
        "job_id" => { ..state, job_id: value }
        "actor" => { ..state, actor: value }
        "authority_ref" => { ..state, authority_ref: value }
        _ => state
      }
      (@rabbita.none, { ..model, export_state, })
    }
    ApplyOutputPreset => {
      let payload : Json = {
        "output": {
          "preset": model.export_state.output_preset,
          "fps": { "numerator": 24, "denominator": 1 },
          "background": "#000000",
        },
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "configure_output", payload))
        .expect_json(result => {
          dispatch(CommandFinished("configure_output", payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving output contract…",
        },
      )
    }
    StartPreview => {
      guard timeline(model) is Some(value) else {
        return (@rabbita.none, model)
      }
      guard duration_ticks(model) > 0 else { return (@rabbita.none, model) }
      let generation = model.preview_generation + 1
      let session_id = fresh_key(model, "preview")
      let body : Json = {
        "session_id": session_id,
        "project_id": model.project_id,
        "timeline_id": value.timeline_id,
        "project_revision": selected_revision(model),
        "timeline_revision": value.revision,
        "timebase": value.timebase.to_json(),
        "range": { "start_tick": 0, "duration_ticks": duration_ticks(model) },
        "quality": "original",
        "created_at": "rabbita-editor",
      }
      (
        @http.post(
          "/api/editor/projects/" + model.project_id + "/preview-sessions",
        )
        .with_json(body)
        .expect_json(result => dispatch(PreviewStarted(generation, result))),
        {
          ..model,
          busy: true,
          preview_generation: generation,
          preview_job_id: session_id,
          preview_job: None,
          request_sequence: model.request_sequence + 1,
          status: "Creating deterministic proxy and cache report…",
        },
      )
    }
    PreviewStarted(generation, result) => {
      guard generation == model.preview_generation else {
        return (@rabbita.none, model)
      }
      match result {
        Ok(envelope) =>
          match
            accepted_editor_job_response(envelope, model.preview_job_id, false) {
            Some(job) => {
              let id = job_id(job)
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  preview_job: Some(job),
                  preview_job_id: id,
                  status: "Preview \{preview_state(job)} · \{id}",
                },
              )
            }
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  error: response_error_message(envelope.error).unwrap_or(
                    "Preview creation returned an invalid response.",
                  ),
                  retry: Some(RetryPreview),
                },
              )
          }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Preview creation failed.",
              retry: Some(RetryPreview),
            },
          )
      }
    }
    PollPreview(generation) => {
      guard generation == model.preview_generation && model.preview_job_id != "" else {
        return (@rabbita.none, model)
      }
      (
        @http.get(
          "/api/editor/projects/" +
          model.project_id +
          "/jobs/" +
          model.preview_job_id,
        ).expect_json(result => dispatch(PreviewPolled(generation, result))),
        model,
      )
    }
    PreviewPolled(generation, result) => {
      guard generation == model.preview_generation else {
        return (@rabbita.none, model)
      }
      match result {
        Ok(envelope) =>
          match
            accepted_editor_job_response(envelope, model.preview_job_id, false) {
            Some(job) => {
              let state = preview_state(job)
              let status = if state == "succeeded" {
                "Authoritative preview ready; proxy/cache artifacts are pinned."
              } else if state == "failed" {
                "Preview failed; bounded retry remains available."
              } else {
                "Preview \{state} · attempt \{job.attempts.unwrap_or(0)}/\{job.max_attempts.unwrap_or(0)}"
              }
              (
                @rabbita.none,
                {
                  ..model,
                  preview_job: Some(job),
                  status,
                  error: if state == "failed" {
                    "Preview provider failed."
                  } else {
                    ""
                  },
                },
              )
            }
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  error: response_error_message(envelope.error).unwrap_or(
                    "Preview polling returned an invalid response.",
                  ),
                  retry: Some(RetryPreview),
                },
              )
          }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              error: "Preview polling failed.",
              retry: Some(RetryPreview),
            },
          )
      }
    }
    RetryPreview => {
      guard model.preview_job_id != "" else {
        return update(dispatch, StartPreview, model)
      }
      let generation = model.preview_generation + 1
      (
        @http.post(
          "/api/editor/projects/" +
          model.project_id +
          "/jobs/" +
          model.preview_job_id +
          "/retry",
        )
        .with_json(Json::object({}))
        .expect_json(result => dispatch(PreviewStarted(generation, result))),
        {
          ..model,
          preview_generation: generation,
          busy: true,
          status: "Retrying preview within the recorded attempt budget…",
          error: "",
        },
      )
    }
    StartExport => {
      guard timeline(model) is Some(value) else {
        return (@rabbita.none, model)
      }
      let id = if model.export_state.job_id.trim().length() > 0 {
        model.export_state.job_id.trim().to_owned()
      } else {
        "production-master-1"
      }
      let body : Json = {
        "export": {
          "job_id": id,
          "request_id": id,
          "expected_editor_revision": selected_revision(model),
          "range": { "start_tick": 0, "duration_ticks": duration_ticks(model) },
          "quality": "original",
          "max_attempts": 2,
          "spec": {
            "width": if model.export_state.output_preset.contains("vertical") {
              1080
            } else {
              1920
            },
            "height": if model.export_state.output_preset.contains("vertical") {
              1920
            } else {
              1080
            },
            "fps": { "numerator": 24, "denominator": 1 },
            "container": "mp4",
            "video_codec": "h264",
            "audio_codec": "aac",
            "subtitle_mode": "embedded-and-sidecar",
            "ai_label_mode": "retain-visible",
            "retain_sources": true,
            "cost_ceiling": "5000",
          },
        },
        "idempotency_key": id,
      }
      (
        @http.post("/api/editor/projects/" + model.project_id + "/exports")
        .with_json(body)
        .expect_json(result => dispatch(ExportStarted(result))),
        {
          ..model,
          busy: true,
          export_state: {
            ..model.export_state,
            job_id: id,
            promoted: false,
            handed_off: false,
            receipt_state: "requested",
            canonical_revision: selected_revision(model),
            timeline_revision: value.revision,
            output_digest: "",
            render_plan_digest: "",
            handoff_record_id: "",
            handoff_record_digest: "",
            handoff_request_id: "",
            handoff_status: "not-prepared",
          },
          status: "Freezing and exporting canonical r\{selected_revision(model)} / timeline r\{value.revision}…",
        },
      )
    }
    ExportStarted(result) =>
      match result {
        Ok(envelope) =>
          match
            accepted_editor_job_response(
              envelope,
              model.export_state.job_id,
              true,
            ) {
            Some(job) => {
              let state = option_or(job.state, job.status).unwrap()
              let receipt = job.result.bind(value => value.export_receipt)
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  export_state: {
                    ..model.export_state,
                    receipt_state: state,
                    download_url: if state == "succeeded" {
                      option_or(
                        job.media_url,
                        receipt.bind(value => value.output_ref),
                      ).unwrap_or("")
                    } else {
                      ""
                    },
                    output_digest: if state == "succeeded" {
                      receipt.map(value => value.digest).unwrap_or("")
                    } else {
                      ""
                    },
                    render_plan_digest: if state == "succeeded" {
                      receipt.map(value => value.plan_digest).unwrap_or("")
                    } else {
                      ""
                    },
                  },
                  status: if state == "succeeded" {
                    "Verified production master, subtitle sidecar, and provenance are ready."
                  } else if state == "failed" {
                    "Production export failed; bounded retry is available."
                  } else {
                    "Production export \{state}; poll the exact job receipt."
                  },
                  error: if state == "failed" {
                    "Production export did not pass rendering or output verification."
                  } else {
                    ""
                  },
                },
              )
            }
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  export_state: {
                    ..model.export_state,
                    receipt_state: "rejected",
                    download_url: "",
                    output_digest: "",
                    render_plan_digest: "",
                  },
                  error: response_error_message(envelope.error).unwrap_or(
                    "Production export returned an invalid success envelope.",
                  ),
                },
              )
          }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              export_state: {
                ..model.export_state,
                receipt_state: "rejected",
                download_url: "",
                output_digest: "",
                render_plan_digest: "",
              },
              error: "Production export failed.",
            },
          )
      }
    PollExport => {
      guard model.export_state.job_id != "" else {
        return (@rabbita.none, model)
      }
      (
        @http.get(
          "/api/editor/projects/" +
          model.project_id +
          "/exports/" +
          model.export_state.job_id,
        ).expect_json(result => dispatch(ExportPolled(result))),
        { ..model, busy: true, status: "Reading exact export receipt…" },
      )
    }
    ExportPolled(result) =>
      match result {
        Ok(envelope) =>
          match
            accepted_editor_job_response(
              envelope,
              model.export_state.job_id,
              true,
            ) {
            Some(job) => {
              let state = option_or(job.state, job.status).unwrap()
              let receipt = job.result.bind(value => value.export_receipt)
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  export_state: {
                    ..model.export_state,
                    receipt_state: state,
                    download_url: if state == "succeeded" {
                      option_or(
                        job.media_url,
                        receipt.bind(value => value.output_ref),
                      ).unwrap_or("")
                    } else {
                      ""
                    },
                    output_digest: if state == "succeeded" {
                      receipt.map(value => value.digest).unwrap_or("")
                    } else {
                      ""
                    },
                    render_plan_digest: if state == "succeeded" {
                      receipt.map(value => value.plan_digest).unwrap_or("")
                    } else {
                      ""
                    },
                  },
                  status: "Exact production export state loaded: \{state}.",
                  error: if state == "failed" {
                    "Production export did not pass rendering or output verification."
                  } else {
                    ""
                  },
                },
              )
            }
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  error: response_error_message(envelope.error).unwrap_or(
                    "Export polling returned an invalid response.",
                  ),
                },
              )
          }
        Err(_) =>
          (
            @rabbita.none,
            { ..model, busy: false, error: "Could not read export receipt." },
          )
      }
    RetryExport => {
      guard model.export_state.job_id != "" else {
        return (@rabbita.none, model)
      }
      (
        @http.post(
          "/api/editor/projects/" +
          model.project_id +
          "/exports/" +
          model.export_state.job_id +
          "/retry",
        )
        .with_json(Json::object({}))
        .expect_json(result => dispatch(ExportStarted(result))),
        {
          ..model,
          busy: true,
          status: "Retrying the exact typed production export…",
          error: "",
        },
      )
    }
    PromoteMaster => {
      guard model.export_state.job_id != "" else {
        return (@rabbita.none, model)
      }
      guard exact_production_source(model) is Some(source) &&
        source.production_revision is Some(production_revision) &&
        source.binding_digest is Some(binding_digest) &&
        source.production_digest is Some(production_digest) &&
        source.g4_receipt_digest is Some(g4_receipt_digest) else {
        return (
          @rabbita.none,
          {
            ..model,
            export_state: { ..model.export_state, promoted: false },
            error: "Promotion is blocked: reopen or refresh the editor from an exact G4 production source.",
          },
        )
      }
      let body : Json = {
        "job_id": model.export_state.job_id,
        "expected_project_revision": production_revision,
        "production_binding_digest": binding_digest,
        "production_digest": production_digest,
        "g4_receipt_digest": g4_receipt_digest,
        "actor": model.export_state.actor,
        "authority_ref": model.export_state.authority_ref,
      }
      (
        @http.post(
          "/api/editor/projects/" +
          model.project_id +
          "/exports/" +
          model.export_state.job_id +
          "/promote-master",
        )
        .with_json(body)
        .expect_json(result => dispatch(MasterPromoted(result))),
        {
          ..model,
          busy: true,
          export_state: { ..model.export_state, promoted: false },
          status: "Promoting exact export under named authority…",
        },
      )
    }
    MasterPromoted(result) =>
      match result {
        Ok(receipt) => {
          let state = model.export_state
          let valid = receipt.error is None &&
            receipt.contract == Some("mooncast.editor-master-promotion.v1") &&
            receipt.project_id == Some(model.project_id) &&
            receipt.job_id == Some(state.job_id) &&
            receipt.digest == Some(state.output_digest) &&
            receipt.plan_digest == Some(state.render_plan_digest) &&
            receipt.actor == Some(state.actor) &&
            receipt.authority_ref == Some(state.authority_ref) &&
            receipt.size.map(value => value > 0).unwrap_or(false) &&
            receipt.video_ref.map(value => !value.is_blank()).unwrap_or(false) &&
            receipt.subtitle_ref
            .map(value => !value.is_blank())
            .unwrap_or(false) &&
            receipt.publication_authority == Some(false)
          if valid {
            (
              @rabbita.none,
              {
                ..model,
                busy: false,
                export_state: { ..state, promoted: true },
                status: "Exact verified export and subtitle sidecar promoted; G5–G7 remain required.",
              },
            )
          } else {
            (
              @rabbita.none,
              {
                ..model,
                busy: false,
                export_state: { ..state, promoted: false },
                error: response_error_message(receipt.error).unwrap_or(
                  "Master promotion returned incomplete or mismatched evidence.",
                ),
              },
            )
          }
        }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              export_state: { ..model.export_state, promoted: false },
              error: "Master promotion failed; verify authority and project revision.",
            },
          )
      }
    PrepareDeliverableHandoff => {
      let state = model.export_state
      let duration = duration_ticks(model) / ticks_per_second(model)
      guard state.promoted &&
        state.job_id != "" &&
        state.output_digest != "" &&
        state.render_plan_digest != "" else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Load the completed exact export receipt and promote the master before handoff.",
          },
        )
      }
      guard duration >= 180 && duration <= 480 && episode_id(model) != "" else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Final-deliverable handoff requires a canonical 3–8 minute episode identity.",
          },
        )
      }
      let record_id = deliverable_record_id(model)
      guard handoff_source_refs(model) is Some(refs) else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Final-deliverable handoff is blocked because the immutable production source binding is missing or invalid.",
          },
        )
      }
      let body : Json = {
        "candidate_id": record_id,
        "candidate_version": "1",
        "episode_id": episode_id(model),
        "workflow_ref": refs[0],
        "ability_ref": refs[1],
        "intake_authority_ref": refs[2],
        "submitted_at": "editor-canonical-r" +
        selected_revision(model).to_string(),
      }
      (
        @http.post(
          "/api/editor/projects/" +
          model.project_id +
          "/exports/" +
          state.job_id +
          "/handoff-request",
        )
        .with_json(body)
        .expect_json(result => dispatch(HandoffRequestRecorded(result))),
        {
          ..model,
          busy: true,
          export_state: {
            ..state,
            handoff_record_id: record_id,
            handoff_record_digest: state.output_digest,
            handoff_request_id: record_id + "-moonflow-handoff",
            handoff_status: "recording-request",
          },
          status: "Verifying G5, real client acceptance, and preparing the opaque MoonFlow request…",
        },
      )
    }
    HandoffRequestRecorded(result) =>
      match result {
        Ok(receipt) => {
          let expected_id = model.export_state.handoff_request_id
          match receipt.envelope {
            Some(envelope) if receipt.error is None &&
              receipt.created is Some(_) &&
              model.export_state.handoff_record_digest ==
              model.export_state.output_digest &&
              envelope.contract == "mooncast.immutable-record-envelope.v1" &&
              envelope.record_type == "external-handoff-request" &&
              envelope.record_id == expected_id &&
              valid_sha256(envelope.payload_digest) &&
              valid_sha256(envelope.envelope_digest) =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  export_state: {
                    ..model.export_state,
                    handed_off: true,
                    handoff_status: "prepared:" + envelope.envelope_digest,
                  },
                  status: "Opaque MoonFlow request prepared for MoonBook Bookkeeper; no external effect or publication was authorized.",
                },
              )
            _ =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  export_state: {
                    ..model.export_state,
                    handed_off: false,
                    handoff_status: "request-rejected",
                  },
                  error: response_error_message(receipt.error).unwrap_or(
                    "MoonFlow handoff returned incomplete or mismatched evidence.",
                  ),
                },
              )
          }
        }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              export_state: {
                ..model.export_state,
                handed_off: false,
                handoff_status: "request-rejected",
              },
              error: "Opaque MoonFlow handoff request was rejected; immutable Mooncast evidence remains recorded.",
            },
          )
      }
    RetryPending =>
      match model.retry {
        Some(RetryOpen(project_id)) =>
          update(dispatch, OpenProject, { ..model, project_id, retry: None })
        Some(RetryCommand(kind, payload)) =>
          (
            @http.post("/api/editor/projects/" + model.project_id + "/commands")
            .with_json(make_command_body(model, kind, payload))
            .expect_json(result => {
              dispatch(CommandFinished(kind, payload, result))
            }),
            {
              ..model,
              busy: true,
              request_sequence: model.request_sequence + 1,
              retry: None,
              status: "Retrying \{kind} against revision \{selected_revision(model)}…",
            },
          )
        Some(RetryComment(value)) =>
          update(dispatch, PostReviewComment, {
            ..model,
            review_comment: value,
            retry: None,
          })
        Some(RetryPreview) =>
          update(dispatch, RetryPreview, { ..model, retry: None })
        None => (@rabbita.none, model)
      }
    ClearError => (@rabbita.none, { ..model, error: "", conflict: "" })
    KeyPressed(keyboard) => {
      let key = lower(keyboard.key())
      let command = keyboard.meta_key() || keyboard.ctrl_key()
      if command && key == "z" {
        update(dispatch, if keyboard.shift_key() { Redo } else { Undo }, model)
      } else if key == " " || keyboard.code() == "Space" {
        update(dispatch, TogglePlay, model)
      } else if key == "arrowleft" {
        update(dispatch, StepFrame(-1), model)
      } else if key == "arrowright" {
        update(dispatch, StepFrame(1), model)
      } else if key == "delete" || key == "backspace" {
        update(
          dispatch,
          if model.selected_transition_id != "" {
            RemoveTransition
          } else {
            DeleteSelection
          },
          model,
        )
      } else if key == "s" && !command && !keyboard.alt_key() {
        update(dispatch, SplitSelection, model)
      } else {
        (@rabbita.none, model)
      }
    }
    Resized(viewport) =>
      (@rabbita.none, { ..model, viewport_width: viewport.width })
    UrlRequested(request) =>
      match request {
        Internal(url) => (@nav.push_url(url.to_string()), model)
        External(url) => (@nav.load(url), model)
      }
  }
}
