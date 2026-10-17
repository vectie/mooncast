///|
fn selected_slide_plan(model : Model) -> Result[@api.SlideClipPlan, String] {
  guard !model.busy && !model.loading else {
    Err("Wait for the current edit to finish.")
  }
  let frames = @string.parse_int(model.slide_offset_frames.trim().to_owned()) catch {
    _ =>
      return Err(
        "Enter a signed whole number of frames, for example 12 or -12.",
      )
  }
  guard model.workspace is Some(workspace) &&
    workspace.project_id == Some(model.project_id) &&
    timeline(model) is Some(value) else {
    Err("Open and reconcile this project's timeline first.")
  }
  let durations : Map[String, Int] = {}
  for take in takes(model) {
    durations[take.media_ref_id] = match durations.get(take.media_ref_id) {
      Some(previous) => Int::min(previous, take.duration_ticks)
      None => take.duration_ticks
    }
  }
  @api.plan_slide_clip(value, model.selected_clip_ids, durations, frames)
}

///|
fn slide_selection(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> (@rabbita.Cmd, Model) {
  match selected_slide_plan(model) {
    Err(message) => (@rabbita.none, { ..model, error: message, })
    Ok(plan) =>
      (
        @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "group_trim", plan.payload))
        .expect_json(result => {
          dispatch(CommandFinished("group_trim", plan.payload, result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Sliding the shot and trimming both neighbors as one edit…",
          error: "",
        },
      )
  }
}

///|
fn slide_edit_controls(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let plan = selected_slide_plan(model)
  @html.div(class="tool-group slide-edit") <| [
    @html.label <| [
      @html.span("Slide frames "),
      @html.input(
        value=model.slide_offset_frames,
        on_input=dispatch.map(value => SetSlideOffset(value)),
        title="Signed whole frames: positive moves the shot later, negative earlier",
      ),
    ],
    @html.button(
      type_="button",
      disabled=plan is Err(_),
      on_click=dispatch(SlideSelection),
      "Slide shot",
    ),
    @html.small(
      match plan {
        Ok(value) =>
          "\{value.clip_id}: \{value.start_tick}–\{value.end_tick} ticks; trim \{value.left_clip_id} and \{value.right_clip_id}. Source content and episode duration stay fixed. Same track only; no linked audio/video sync. Frames round to ticks. Undo restores all three."
        Err(message) => message
      },
    ),
  ]
}
