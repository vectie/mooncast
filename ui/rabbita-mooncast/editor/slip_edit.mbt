///|
fn selected_slip_plan(model : Model, offset_frames : Int) -> Result[Json, String] {
  guard !model.busy && !model.loading else { Err("Wait for the current edit to finish.") }
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
  @api.plan_slip_clip(value, model.selected_clip_ids, durations, offset_frames)
}

///|
fn slip_selection(dispatch : @rabbita.Emit[Msg], model : Model, frames : Int) -> (@rabbita.Cmd, Model) {
  match selected_slip_plan(model, frames) {
    Err(message) => (@rabbita.none, { ..model, error: message, })
    Ok(payload) => (
      @http.post("/api/editor/projects/" + model.project_id + "/commands")
        .with_json(make_command_body(model, "trim", payload))
        .expect_json(result => dispatch(CommandFinished("trim", payload, result))),
      { ..model, busy: true, request_sequence: model.request_sequence + 1,
        status: "Slipping source by \{frames} frame(s); timeline timing stays fixed…", error: "", },
    )
  }
}

///|
fn slip_edit_controls(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.div(class="tool-group slip-edit") <| [
    @html.button(type_="button", disabled=selected_slip_plan(model, -1) is Err(_),
      title="Use earlier source content without moving the clip", on_click=dispatch(SlipSelection(-1)), "Slip −1f"),
    @html.button(type_="button", disabled=selected_slip_plan(model, 1) is Err(_),
      title="Use later source content without moving the clip", on_click=dispatch(SlipSelection(1)), "Slip +1f"),
    @html.small(match selected_slip_plan(model, 1) {
      Ok(_) => "Signed one-frame source offset, rounded to timeline ticks. Undo restores the source window."
      Err(message) => match selected_slip_plan(model, -1) {
        Ok(_) => "Only earlier source handles are available."
        Err(_) => message
      }
    }),
  ]
}
