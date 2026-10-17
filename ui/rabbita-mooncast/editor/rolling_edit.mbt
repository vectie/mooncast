///|
fn selected_roll_plan(
  model : Model,
  direction : Int,
) -> Result[@api.RollCutPlan, String] {
  guard !model.busy && !model.loading else {
    Err("Wait for the current edit to finish.")
  }
  guard direction == -1 || direction == 1 else {
    Err("Choose an earlier or later cut.")
  }
  guard model.workspace is Some(workspace) &&
    workspace.project_id == Some(model.project_id) &&
    timeline(model) is Some(value) else {
    Err("Open and reconcile this project's timeline first.")
  }
  let step = match @api.roll_frame_ticks(value) {
    Ok(ticks) => ticks
    Err(message) => return Err(message)
  }
  let durations : Map[String, Int] = {}
  for take in takes(model) {
    // Conflicting metadata never expands a source's available handles.
    durations[take.media_ref_id] = match durations.get(take.media_ref_id) {
      Some(previous) => Int::min(previous, take.duration_ticks)
      None => take.duration_ticks
    }
  }
  @api.plan_roll_cut(
    value,
    model.selected_clip_ids,
    durations,
    step * direction,
  )
}

///|
fn roll_selection(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  direction : Int,
) -> (@rabbita.Cmd, Model) {
  match selected_roll_plan(model, direction) {
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
          status: "Rolling cut by one frame; preserving episode timing…",
          error: "",
        },
      )
  }
}

///|
fn rolling_edit_controls(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(class="tool-group rolling-edit") <| [
    @html.button(
      type_="button",
      disabled=selected_roll_plan(model, -1) is Err(_),
      title="Move the shared cut earlier without shifting later clips",
      on_click=dispatch(RollSelection(-1)),
      "Roll −1f",
    ),
    @html.button(
      type_="button",
      disabled=selected_roll_plan(model, 1) is Err(_),
      title="Move the shared cut later without shifting later clips",
      on_click=dispatch(RollSelection(1)),
      "Roll +1f",
    ),
    @html.small(
      match selected_roll_plan(model, 1) {
        Ok(_) =>
          "One output-frame step, rounded to timeline ticks. Total timing stays fixed. Undo restores both."
        Err(message) =>
          match selected_roll_plan(model, -1) {
            Ok(_) => "Only earlier roll has available source handles."
            Err(_) => message
          }
      },
    ),
  ]
}
