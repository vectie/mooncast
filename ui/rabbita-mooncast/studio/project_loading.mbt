///|
/// Every project load owns its subordinate replies, including same-project
/// refreshes. A navigation or retry invalidates the entire previous generation.
priv struct ProjectRequest {
  project_id : String
  generation : Int
  selection_generation : Int
  tab_generation : Int
}

///|
fn project_request(model : Model) -> ProjectRequest {
  {
    project_id: model.selected_project_id,
    generation: model.project_generation,
    selection_generation: model.project_selection_generation,
    tab_generation: model.tab_generation,
  }
}

///|
fn ProjectRequest::is_current(self : ProjectRequest, model : Model) -> Bool {
  self.project_id != "" &&
  self.project_id == model.selected_project_id &&
  self.generation == model.project_generation
}

///|
/// Mutations survive a same-selection read refresh, but cannot regain focus
/// after navigation, including an A -> B -> A return or explicit cancellation.
fn ProjectRequest::is_current_selection(
  self : ProjectRequest,
  model : Model,
) -> Bool {
  self.project_id == model.selected_project_id &&
  self.selection_generation == model.project_selection_generation
}

///|
fn project_sections() -> Array[String] {
  [
    "Routed execution", "Delivery factory", "Client portals", "Billing ledger", "Asset factory",
    "Storyboard / Animatic", "Postprocess jobs", "Automated QC",
  ]
}

///|
fn ProjectRequest::may_change_focus(
  self : ProjectRequest,
  model : Model,
) -> Bool {
  self.is_current_selection(model) &&
  self.tab_generation == model.tab_generation
}

///|
fn finish_creation_in_background(
  model : Model,
  request : ProjectRequest,
) -> Model {
  if request.is_current_selection(model) {
    { ..model, busy: false, }
  } else {
    model
  }
}

///|
fn begin_project_load(
  emit : @rabbita.Emit[Msg],
  model : Model,
  project_id : String,
) -> (@rabbita.Cmd, Model) {
  let changed = model.selected_project_id != project_id
  let next = {
    ..model,
    selected_project_id: project_id,
    project_generation: model.project_generation + 1,
    project_selection_generation: model.project_selection_generation +
    (if changed || project_id == "" { 1 } else { 0 }),
    project_pending: if project_id == "" {
      []
    } else {
      ["Project"]
    },
    project_load_errors: [],
    loading: project_id != "",
    busy: if changed || project_id == "" {
      false
    } else {
      model.busy
    },
    error: None,
    status: if project_id == "" {
      "No project selected."
    } else {
      "Loading project revision and related evidence… Local creative edits are retained."
    },
    project: if changed {
      None
    } else {
      model.project
    },
    routed: if changed {
      []
    } else {
      model.routed
    },
    delivery_builds: if changed {
      []
    } else {
      model.delivery_builds
    },
    delivery_cut_start: if changed || project_id == "" {
      ""
    } else {
      model.delivery_cut_start
    },
    delivery_cut_end: if changed || project_id == "" {
      ""
    } else {
      model.delivery_cut_end
    },
    client_portals: if changed {
      []
    } else {
      model.client_portals
    },
    billing_entries: if changed {
      []
    } else {
      model.billing_entries
    },
    asset_factory: if changed {
      None
    } else {
      model.asset_factory
    },
    animatic_workspace: if changed {
      None
    } else {
      model.animatic_workspace
    },
    postprocess_workspace: if changed {
      None
    } else {
      model.postprocess_workspace
    },
    analyzer_workspace: if changed {
      None
    } else {
      model.analyzer_workspace
    },
    latest_client_url: model.client_urls.get(project_id),
    artifact_draft: if changed {
      "{}"
    } else {
      model.artifact_draft
    },
    asset_plan_draft: if changed {
      ""
    } else {
      model.asset_plan_draft
    },
    animatic_plan_draft: if changed {
      ""
    } else {
      model.animatic_plan_draft
    },
    postprocess_task_draft: if changed {
      ""
    } else {
      model.postprocess_task_draft
    },
    analyzer_task_draft: if changed {
      ""
    } else {
      model.analyzer_task_draft
    },
    operator: if changed {
      { ..model.operator, human_confirmed: false, }
    } else {
      model.operator
    },
  }
  if project_id == "" {
    (@rabbita.none, next)
  } else {
    let request = project_request(next)
    let cmd = @http.get("/api/v2/projects/" + project_id).expect_json(
      emit.map(result => LoadedProject(request, result)),
    )
    (cmd, next)
  }
}

///|
fn[T] load_result(
  request : ProjectRequest,
  section : String,
  result : Result[T, Error],
) -> (ProjectRequest, String, String?)? {
  Some(
    (
      request,
      section,
      match result {
        Ok(_) => None
        Err(error) => Some("\{error}")
      },
    ),
  )
}

///|
fn project_response(msg : Msg) -> (ProjectRequest, String, String?)? {
  match msg {
    LoadedProject(request, Ok(project)) if project.id != request.project_id =>
      Some(
        (
          request,
          "Project",
          Some(
            "Response project identity does not match the requested project.",
          ),
        ),
      )
    LoadedProject(request, result) => load_result(request, "Project", result)
    LoadedRouted(request, result) =>
      load_result(request, "Routed execution", result)
    LoadedDeliveries(request, result) =>
      load_result(request, "Delivery factory", result)
    LoadedPortals(request, result) =>
      load_result(request, "Client portals", result)
    LoadedBilling(request, result) =>
      load_result(request, "Billing ledger", result)
    LoadedAssetFactory(request, result) =>
      load_result(request, "Asset factory", result)
    LoadedAnimaticWorkspace(request, result) =>
      load_result(request, "Storyboard / Animatic", result)
    LoadedPostprocessWorkspace(request, result) =>
      load_result(request, "Postprocess jobs", result)
    LoadedAnalyzerWorkspace(request, result) =>
      load_result(request, "Automated QC", result)
    _ => None
  }
}

///|
fn update(
  emit : @rabbita.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@rabbita.Cmd, Model) {
  match msg {
    ActionCompleted(request, label, result) if !request.is_current_selection(
        model,
      ) => {
      let outcome = match result {
        Ok(value) =>
          match api_error_message(value) {
            Some(message) => " rejected: " + message
            None =>
              " recorded. Open or refresh that workspace to inspect its latest state."
          }
        Err(error) =>
          " response failed: \{error}. Check the originating workspace before retrying."
      }
      return (@rabbita.none, command_notice(model, request, label + outcome))
    }
    CreatedProject(request, Ok(project)) if !request.may_change_focus(model) => {
      let index = @http.get("/api/v2/projects").expect_json(
        emit.map(result => LoadedProjects(result)),
      )
      return (
        index,
        command_notice(
          finish_creation_in_background(model, request),
          request,
          "Project " +
          project.id +
          " created. Select it from the project list when ready.",
        ),
      )
    }
    CreatedProject(request, Err(error)) if !request.may_change_focus(model) =>
      return (
        @rabbita.none,
        command_notice(
          finish_creation_in_background(model, request),
          request,
          "Create project response failed: \{error}. Check the project list before retrying.",
        ),
      )
    CreatedClientPortal(request, Ok(value)) if !request.is_current_selection(
        model,
      ) => {
      let next = if value.portal.project_id == request.project_id {
        remember_client_url(model, value)
      } else {
        model
      }
      return (
        @rabbita.none,
        command_notice(
          next,
          request,
          if value.portal.project_id == request.project_id {
            "Client review URL created. Select or refresh that project to retrieve its URL in this tab."
          } else {
            "Client portal response had an unexpected project identity; its URL was not accepted."
          },
        ),
      )
    }
    CreatedClientPortal(request, Err(error)) if !request.is_current_selection(
        model,
      ) =>
      return (
        @rabbita.none,
        command_notice(
          model,
          request,
          "Client portal response failed: \{error}. Check that project before retrying.",
        ),
      )
    _ => ()
  }
  match project_response(msg) {
    None => update_current(emit, msg, model)
    Some((request, section, failure)) => {
      if !request.is_current(model) || !model.project_pending.contains(section) {
        return (@rabbita.none, model)
      }
      let (cmd, next) = if failure is Some(_) {
        (@rabbita.none, model)
      } else {
        update_current(emit, msg, model)
      }
      let pending = next.project_pending.filter(item => item != section)
      let errors = next.project_load_errors.filter(item => item.0 != section)
      if failure is Some(message) {
        errors.push((section, message))
      }
      (
        cmd,
        {
          ..next,
          project_pending: pending,
          project_load_errors: errors,
          loading: !pending.is_empty(),
          status: if !pending.is_empty() {
            "Loading related project evidence…"
          } else if !errors.is_empty() {
            "Some project evidence could not be refreshed. Any retained values are from the last successful load. Use Retry to load again."
          } else {
            "Project revision and related evidence loaded."
          },
        },
      )
    }
  }
}

///|
fn command_notice(
  model : Model,
  request : ProjectRequest,
  message : String,
) -> Model {
  let context = if request.project_id == "" {
    "Previous workspace"
  } else {
    "Project " + request.project_id
  }
  let notices = model.command_notices.copy()
  notices.push(context + ": " + message)
  { ..model, command_notices: notices, }
}

///|
/// Keep one-time portal results only in their project's tab-local state. A
/// response for another selection must never display its URL in the active one.
fn remember_client_url(
  model : Model,
  value : ClientPortalCreatedProjection,
) -> Model {
  let urls = model.client_urls.copy()
  urls[value.portal.project_id] = value.client_url
  { ..model, client_urls: urls, }
}

///|
fn project_artifact_draft(
  model : Model,
  project : ProjectProjection,
  kind : String,
) -> String {
  model.artifact_drafts
  .get((project.id, kind))
  .unwrap_or_else(() => {
    artifact_for(project, kind)
    .map(item => item.content.stringify())
    .unwrap_or("{}")
  })
}

///|
fn artifact_draft_is_dirty(model : Model) -> Bool {
  match model.project {
    Some(project) =>
      model.artifact_draft !=
      artifact_for(project, model.selected_artifact_kind)
      .map(item => item.content.stringify())
      .unwrap_or("{}")
    None => false
  }
}

///|
fn edit_artifact_draft(model : Model, text : String) -> Model {
  match model.project {
    Some(project) if project.id == model.selected_project_id => {
      let drafts = model.artifact_drafts.copy()
      let key = (project.id, model.selected_artifact_kind)
      let canonical = artifact_for(project, model.selected_artifact_kind)
        .map(item => item.content.stringify())
        .unwrap_or("{}")
      if text == canonical {
        drafts.remove(key)
      } else {
        drafts[key] = text
      }
      { ..model, artifact_draft: text, artifact_drafts: drafts, }
    }
    _ => model
  }
}

///|
/// Retire only edits matching a refreshed canonical version. Newer local edits
/// made while a save was in flight remain intact.
fn reconcile_artifact_drafts(
  model : Model,
  project : ProjectProjection,
) -> Model {
  let drafts = model.artifact_drafts.copy()
  for key, text in model.artifact_drafts {
    if key.0 == project.id &&
      artifact_for(project, key.1).map(item => item.content.stringify()) ==
      Some(text) {
      drafts.remove(key)
    }
  }
  { ..model, artifact_drafts: drafts, }
}
