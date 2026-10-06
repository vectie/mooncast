///|
/// Tab-local drafts belong to an opened project, never to the next selection.
priv struct EditorProjectDraft {
  recipe : WorkspaceRecipe
  graph : WorkspaceGraphSummary?
  graph_dirty : Bool
  graph_undo : Array[WorkspaceGraphSummary]
  graph_redo : Array[WorkspaceGraphSummary]
  selected_node : String
  selected_nodes : Array[String]
  selected_take : String
  selected_clips : Array[String]
  playhead : Int
  inspector : InspectorDraft
  intake : IntakeDraft
  utility_concat : UtilityConcatState
  review_comment : String
  workspace_comment : String
  public_input : String
  agent_instruction : String
  export_state : ExportState
  production_project_id : String
}

///|
fn chosen_project(model : Model) -> String {
  model.selected_project_id.unwrap_or(model.project_id)
}

///|
fn workspace_matches_project(
  workspace : @api.WorkspaceSnapshot,
  project_id : String,
) -> Bool {
  workspace.project_id.map(id => id == project_id).unwrap_or(true) &&
  workspace.snapshot
  .map(value => value.project_id == project_id)
  .unwrap_or(true)
}

///|
fn retain_project_draft(model : Model) -> Map[String, EditorProjectDraft] {
  let drafts = model.project_drafts.copy()
  drafts[model.project_id] = {
    recipe: model.selected_workspace_recipe,
    graph: if model.workspace_graph_dirty {
      model.workspace_graph
    } else {
      None
    },
    graph_dirty: model.workspace_graph_dirty,
    graph_undo: model.workspace_graph_undo,
    graph_redo: model.workspace_graph_redo,
    selected_node: model.selected_workspace_node,
    selected_nodes: model.selected_workspace_node_ids,
    selected_take: model.selected_take_id,
    selected_clips: model.selected_clip_ids,
    playhead: model.playhead_ticks,
    inspector: model.inspector,
    intake: model.intake,
    utility_concat: model.utility_concat,
    review_comment: model.review_comment,
    workspace_comment: model.workspace_comment,
    public_input: model.workspace_public_input,
    agent_instruction: model.workspace_agent_instruction,
    export_state: { ..model.export_state, promoted: false, },
    production_project_id: model.production_project_id,
  }
  drafts
}

///|
fn activate_editor_project(model : Model, project_id : String) -> Model {
  let drafts = retain_project_draft(model)
  let fresh = {
    ..initial_model(),
    bootstrapped: model.bootstrapped,
    catalog_state: model.catalog_state,
    catalog_generation: model.catalog_generation,
    catalog_auto_open: false,
    projects: model.projects,
    project_id,
    selected_project_id: Some(project_id),
    project_drafts: drafts,
    workspace_catalog: model.workspace_catalog,
    workspace_actor_id: model.workspace_actor_id,
    workspace_actor_name: model.workspace_actor_name,
    workspace_lens: model.workspace_lens,
    open_generation: model.open_generation,
    preview_generation: model.preview_generation + 1,
    request_sequence: model.request_sequence,
  }
  match drafts.get(project_id) {
    None => fresh
    Some(draft) =>
      {
        ..fresh,
        selected_workspace_recipe: draft.recipe,
        workspace_graph: draft.graph,
        workspace_graph_dirty: draft.graph_dirty,
        workspace_graph_undo: draft.graph_undo,
        workspace_graph_redo: draft.graph_redo,
        selected_workspace_node: draft.selected_node,
        selected_workspace_node_ids: draft.selected_nodes,
        selected_take_id: draft.selected_take,
        selected_clip_ids: draft.selected_clips,
        playhead_ticks: draft.playhead,
        inspector: draft.inspector,
        intake: draft.intake,
        utility_concat: draft.utility_concat,
        review_comment: draft.review_comment,
        workspace_comment: draft.workspace_comment,
        workspace_public_input: draft.public_input,
        workspace_agent_instruction: draft.agent_instruction,
        export_state: draft.export_state,
        production_project_id: draft.production_project_id,
      }
  }
}

///|
/// Every asynchronous effect keeps the project/open identity that produced it.
/// Catalog reads are global and already use their own request generation.
fn project_dispatch(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  message : Msg,
) -> @rabbita.Emit[Msg] {
  let (project_id, generation) = match message {
    OpenProject if model.catalog_state == CatalogReady =>
      (chosen_project(model), model.open_generation + 1)
    ProductionImported(Ok(_)) =>
      (model.production_project_id, model.open_generation + 1)
    ProjectsLoaded(_, Ok(response)) if model.catalog_auto_open => {
      let projects = decode_project_response(response).unwrap_or([])
      if projects.is_empty() {
        (model.project_id, model.open_generation)
      } else {
        let selected = projects
          .iter()
          .find_first(item => item.project_id == model.project_id)
        (
          option_or(selected, projects.get(0)).unwrap().project_id,
          model.open_generation + 1,
        )
      }
    }
    _ => (model.project_id, model.open_generation)
  }
  let export_generation = model.export_generation + 1
  let export_id = if message is StartExport &&
    model.export_state.job_id.trim().is_blank() {
    "production-master-1"
  } else {
    model.export_state.job_id.trim().to_owned()
  }
  dispatch.map(reply => {
    match reply {
      ProjectsLoaded(_, _) => reply
      ExportStarted(_)
      | ExportPolled(_)
      | MasterPromoted(_)
      | HandoffRequestRecorded(_) =>
        ProjectReply(
          project_id,
          generation,
          ExportReply(export_id, export_generation, reply),
        )
      _ => ProjectReply(project_id, generation, reply)
    }
  })
}

///|
fn update(
  dispatch : @rabbita.Emit[Msg],
  message : Msg,
  model : Model,
) -> (@rabbita.Cmd, Model) {
  match message {
    ExportReply(job_id, generation, reply) =>
      if job_id == model.export_state.job_id.trim().to_owned() &&
        generation == model.export_generation {
        update(dispatch, reply, model)
      } else {
        (@rabbita.none, model)
      }
    ProjectReply(project_id, generation, reply) =>
      if project_id == model.project_id && generation == model.open_generation {
        update(dispatch, reply, model)
      } else {
        (@rabbita.none, model)
      }
    _ => update_project(dispatch, message, model)
  }
}
