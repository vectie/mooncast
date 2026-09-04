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
          if projects.is_empty() {
            return (
              @rabbita.none,
              {
                ..model,
                projects,
                loading: false,
                status: "No governed editor project. Quick combine is ready.",
                error: "",
              },
            )
          }
          let requested = projects
            .iter()
            .find_first(item => item.project_id == model.project_id)
          let project_id = option_or(requested, projects.get(0))
            .map(item => item.project_id)
            .unwrap_or(model.project_id)
          let opened = @http.get("/api/editor/projects/" + project_id).expect_json(value => {
              dispatch(WorkspaceOpened(model.open_generation + 1, value))
            },
          )
          let proposals = @http.get(
            "/api/workspace/projects/" + project_id + "/proposals",
          ).expect_json(value => dispatch(WorkspaceProposalsLoaded(value)))
          let catalog = @http.get("/api/workspace/catalog").expect_json(value => {
            dispatch(WorkspaceCatalogLoaded(value))
          })
          let graph = @http.post(
              "/api/workspace/projects/" +
              project_id +
              "/capsules/combine-videos/install",
            )
            .with_json({
              "graph_id": "combine-videos",
              "title": "Combine videos",
              "actor": model.workspace_actor_name,
            })
            .expect_json(value => dispatch(WorkspaceGraphLoaded(value)))
          let assets = @http.get(
            workspace_asset_library_url({ ..model, project_id, }),
          ).expect_json(value => dispatch(WorkspaceAssetsLoaded(value)))
          let features = @http.get(
            "/api/workspace/projects/" + project_id + "/features",
          ).expect_json(value => dispatch(WorkspaceFeaturesLoaded(value)))
          let runs = @http.get(
            "/api/workspace/projects/" + project_id + "/runs?limit=20",
          ).expect_json(value => dispatch(WorkspaceRunHistoryLoaded(value)))
          (
            @rabbita.batch([
              opened, proposals, catalog, graph, assets, features, runs,
            ]),
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
    WorkspaceCatalogLoaded(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            { ..model, error: "Could not load the governed node catalog." },
          )
        Ok(response) => {
          let decoded : WorkspaceCatalogPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            Some(value) =>
              (
                @rabbita.none,
                {
                  ..model,
                  workspace_catalog: value.definitions,
                  workspace_activity: model.workspace_activity +
                  [
                    "\{value.definitions.length()} governed node definitions loaded",
                  ],
                },
              )
            None =>
              (
                @rabbita.none,
                { ..model, error: "Node catalog response was invalid." },
              )
          }
        }
      }
    WorkspaceGraphLoaded(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              loading: false,
              error: "Could not install or load the workspace graph.",
            },
          )
        Ok(response) => {
          let decoded : WorkspaceGraphSummary? = Some(@json.from_json(response)) catch {
            _ => None
          }
          match decoded {
            Some(graph) =>
              (
                @rabbita.none,
                {
                  ..model,
                  workspace_graph: Some(graph),
                  workspace_graph_undo: [],
                  workspace_graph_redo: [],
                  workspace_graph_dirty: false,
                  workspace_graph_saving: false,
                  selected_workspace_node: graph.nodes
                  .get(0)
                  .map(node => node.node_id)
                  .unwrap_or(""),
                  selected_workspace_node_ids: graph.nodes
                  .get(0)
                  .map(node => [node.node_id])
                  .unwrap_or([]),
                  selected_workspace_edge: "",
                  loading: false,
                  status: "Loaded saved graph revision \{graph.revision}.",
                  error: "",
                },
              )
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  loading: false,
                  error: "Workspace graph response was invalid.",
                },
              )
          }
        }
      }
    WorkspaceAssetsLoaded(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              workspace_activity: model.workspace_activity +
              ["Asset library could not be refreshed"],
            },
          )
        Ok(response) => {
          let decoded : WorkspaceAssetLibraryPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            Some(library) =>
              (
                @rabbita.none,
                {
                  ..model,
                  workspace_assets: library.entries,
                  workspace_asset_total: library.total,
                  workspace_asset_offset: library.offset,
                  workspace_asset_limit: library.limit,
                  workspace_asset_has_more: library.has_more,
                  selected_workspace_asset_ids: model.selected_workspace_asset_ids.filter(id => {
                      library.entries.any(entry => {
                        entry.artifact.artifact_id == id
                      })
                    },
                  ),
                },
              )
            None => (@rabbita.none, model)
          }
        }
      }
    WorkspaceAssetQueryChanged(workspace_asset_query) => {
      let next = { ..model, workspace_asset_query, workspace_asset_offset: 0 }
      (
        @http.get(workspace_asset_library_url(next)).expect_json(result => {
          dispatch(WorkspaceAssetsLoaded(result))
        }),
        next,
      )
    }
    WorkspaceAssetKindChanged(workspace_asset_kind) => {
      let next = { ..model, workspace_asset_kind, workspace_asset_offset: 0 }
      (
        @http.get(workspace_asset_library_url(next)).expect_json(result => {
          dispatch(WorkspaceAssetsLoaded(result))
        }),
        next,
      )
    }
    WorkspaceAssetTagChanged(workspace_asset_tag) => {
      let next = { ..model, workspace_asset_tag, workspace_asset_offset: 0 }
      (
        @http.get(workspace_asset_library_url(next)).expect_json(result => {
          dispatch(WorkspaceAssetsLoaded(result))
        }),
        next,
      )
    }
    WorkspaceAssetPageChanged(direction) => {
      let next_offset = Int::max(
        0,
        model.workspace_asset_offset + direction * model.workspace_asset_limit,
      )
      let next = { ..model, workspace_asset_offset: next_offset }
      (
        @http.get(workspace_asset_library_url(next)).expect_json(result => {
          dispatch(WorkspaceAssetsLoaded(result))
        }),
        next,
      )
    }
    WorkspaceFeaturesLoaded(result) =>
      match result {
        Err(_) => (@rabbita.none, model)
        Ok(response) => {
          let decoded : WorkspaceFeaturesPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            Some(features) =>
              (
                @rabbita.none,
                {
                  ..model,
                  workspace_comments: features.comments,
                  workspace_presence: features.presence,
                },
              )
            None => (@rabbita.none, model)
          }
        }
      }
    WorkspaceProposalsLoaded(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              workspace_activity: model.workspace_activity +
              ["Agent proposals could not be refreshed"],
            },
          )
        Ok(response) => {
          let decoded : WorkspaceProposalPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            Some(value) =>
              (@rabbita.none, { ..model, workspace_proposals: value.proposals })
            None => (@rabbita.none, model)
          }
        }
      }
    SelectProject(project_id) => (@rabbita.none, { ..model, project_id, })
    SwitchWorkspaceLens(workspace_lens) =>
      (@rabbita.none, { ..model, workspace_lens, })
    SelectWorkspaceRecipe(selected_workspace_recipe) => {
      let selected_workspace_node = match selected_workspace_recipe {
        CombineVideosRecipe => "concat"
        BriefToDeliveryRecipe => "generate"
      }
      let capsule_id = workspace_recipe_id(selected_workspace_recipe)
      (
        @http.post(
          "/api/workspace/projects/" +
          model.project_id +
          "/capsules/" +
          capsule_id +
          "/install",
        )
        .with_json({
          "graph_id": capsule_id,
          "title": workspace_recipe_title(selected_workspace_recipe),
          "actor": model.workspace_actor_name,
        })
        .expect_json(result => dispatch(WorkspaceGraphLoaded(result))),
        {
          ..model,
          selected_workspace_recipe,
          selected_workspace_node,
          selected_workspace_node_ids: [selected_workspace_node],
          selected_workspace_edge: "",
          loading: true,
          status: "Loading saved recipe graph…",
          error: "",
        },
      )
    }
    WorkspaceNodePaletteChanged(workspace_node_palette_search) =>
      (@rabbita.none, { ..model, workspace_node_palette_search, })
    AddWorkspaceNode(definition_id) =>
      match workspace_definition(model, definition_id) {
        Some(definition) =>
          (@rabbita.none, workspace_graph_add_node(model, definition))
        None =>
          (
            @rabbita.none,
            { ..model, error: "That node definition is unavailable." },
          )
      }
    DeleteSelectedWorkspaceNode =>
      (@rabbita.none, workspace_graph_delete_selected(model))
    ToggleWorkspaceNodeSelection => {
      let id = model.selected_workspace_node
      let ids = if model.selected_workspace_node_ids.contains(id) {
        model.selected_workspace_node_ids.filter(value => value != id)
      } else {
        model.selected_workspace_node_ids + [id]
      }
      (@rabbita.none, { ..model, selected_workspace_node_ids: ids })
    }
    SelectWorkspaceEdge(selected_workspace_edge) =>
      (
        @rabbita.none,
        {
          ..model,
          selected_workspace_edge,
          status: "Connection selected. Pick a new output and input to reconnect, or delete it.",
          error: "",
        },
      )
    DeleteSelectedWorkspaceEdge =>
      (@rabbita.none, workspace_graph_delete_selected_edge(model))
    CopyWorkspaceNodes => (@rabbita.none, workspace_graph_copy_selection(model))
    PasteWorkspaceNodes =>
      (@rabbita.none, workspace_graph_paste_selection(model))
    GroupWorkspaceNodes =>
      (@rabbita.none, workspace_graph_group_selection(model))
    ToggleWorkspaceNodeMode(key) =>
      (@rabbita.none, workspace_graph_toggle_mode(model, key))
    AutoLayoutWorkspaceGraph =>
      (@rabbita.none, workspace_graph_auto_layout(model))
    DuplicateSelectedWorkspaceNode =>
      (@rabbita.none, workspace_graph_duplicate_selected(model))
    ToggleSelectedWorkspaceNodeCollapsed =>
      (@rabbita.none, workspace_graph_toggle_collapsed(model))
    WorkspaceParameterKeyChanged(workspace_parameter_key) =>
      (@rabbita.none, { ..model, workspace_parameter_key, })
    WorkspaceParameterValueChanged(workspace_parameter_value) =>
      (@rabbita.none, { ..model, workspace_parameter_value, })
    WorkspaceParameterTypeChanged(workspace_parameter_type) =>
      (@rabbita.none, { ..model, workspace_parameter_type, })
    SetWorkspaceNodeParameter =>
      (@rabbita.none, workspace_graph_set_parameter(model))
    DeleteWorkspaceNodeParameter(key) =>
      (@rabbita.none, workspace_graph_delete_parameter(model, key))
    WorkspaceGraphUndo =>
      match model.workspace_graph_undo.last() {
        None => (@rabbita.none, model)
        Some(previous) => {
          let undo = model.workspace_graph_undo.copy()
          ignore(undo.pop())
          (
            @rabbita.none,
            {
              ..model,
              workspace_graph: Some(previous),
              workspace_graph_undo: undo,
              workspace_graph_redo: model.workspace_graph
              .map(value => model.workspace_graph_redo + [value])
              .unwrap_or(model.workspace_graph_redo),
              workspace_graph_dirty: !undo.is_empty(),
              status: "Undid graph edit.",
              error: "",
            },
          )
        }
      }
    WorkspaceGraphRedo =>
      match model.workspace_graph_redo.last() {
        None => (@rabbita.none, model)
        Some(next) => {
          let redo = model.workspace_graph_redo.copy()
          ignore(redo.pop())
          (
            @rabbita.none,
            {
              ..model,
              workspace_graph: Some(next),
              workspace_graph_undo: model.workspace_graph
              .map(value => model.workspace_graph_undo + [value])
              .unwrap_or(model.workspace_graph_undo),
              workspace_graph_redo: redo,
              workspace_graph_dirty: true,
              status: "Redid graph edit.",
              error: "",
            },
          )
        }
      }
    SaveWorkspaceGraph(continuation) =>
      match model.workspace_graph {
        None => (@rabbita.none, { ..model, error: "No graph is loaded." })
        Some(graph) =>
          (
            @http.post(
              "/api/workspace/projects/" +
              graph.project_id +
              "/graphs/" +
              graph.graph_id +
              "/revisions",
            )
            .with_json(
              workspace_graph_revision_body(graph, model.workspace_actor_name),
            )
            .expect_json(result => {
              dispatch(WorkspaceGraphSaved(continuation, result))
            }),
            {
              ..model,
              workspace_graph_saving: true,
              status: "Validating and saving graph revision…",
              error: "",
            },
          )
      }
    WorkspaceGraphSaved(continuation, result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              workspace_graph_saving: false,
              error: "Graph save failed. Reload before retrying if another editor changed it.",
            },
          )
        Ok(response) => {
          let decoded : WorkspaceGraphSummary? = Some(@json.from_json(response)) catch {
            _ => None
          }
          guard decoded is Some(graph) else {
            return (
              @rabbita.none,
              {
                ..model,
                workspace_graph_saving: false,
                error: "Saved graph response was invalid.",
              },
            )
          }
          let saved = {
            ..model,
            workspace_graph: Some(graph),
            workspace_graph_undo: [],
            workspace_graph_redo: [],
            workspace_graph_dirty: false,
            workspace_graph_saving: false,
            status: "Saved graph revision \{graph.revision}.",
            error: "",
          }
          if continuation == "all" {
            (
              start_workspace_graph_http(dispatch, saved, false),
              { ..saved, busy: true },
            )
          } else if continuation == "selected" {
            (
              start_workspace_graph_http(dispatch, saved, true),
              { ..saved, busy: true },
            )
          } else {
            (@rabbita.none, saved)
          }
        }
      }
    SelectWorkspaceNode(selected_workspace_node) => {
      let body : Json = {
        "project_id": model.project_id,
        "actor_id": model.workspace_actor_id,
        "display_name": model.workspace_actor_name,
        "target_kind": "NodeTarget",
        "target_id": selected_workspace_node,
        "lifetime_seconds": 60,
      }
      (
        @http.post("/api/workspace/presence/leases")
        .with_json(body)
        .expect_json(result => dispatch(WorkspacePresenceRenewed(result))),
        {
          ..model,
          selected_workspace_node,
          selected_workspace_node_ids: if model.selected_workspace_node_ids.contains(
              selected_workspace_node,
            ) {
            model.selected_workspace_node_ids
          } else {
            [selected_workspace_node]
          },
          selected_workspace_edge: "",
        },
      )
    }
    RenewWorkspacePresence => {
      guard !model.selected_workspace_node.is_blank() else {
        return (@rabbita.none, model)
      }
      let body : Json = {
        "project_id": model.project_id,
        "actor_id": model.workspace_actor_id,
        "display_name": model.workspace_actor_name,
        "target_kind": "NodeTarget",
        "target_id": model.selected_workspace_node,
        "lifetime_seconds": 60,
      }
      (
        @http.post("/api/workspace/presence/leases")
        .with_json(body)
        .expect_json(result => dispatch(WorkspacePresenceRenewed(result))),
        model,
      )
    }
    WorkspaceActorChanged(workspace_actor_name) => {
      let normalized = workspace_actor_name
        .trim()
        .to_owned()
        .to_lower()
        .replace_all(old=" ", new="-")
      (
        @rabbita.none,
        {
          ..model,
          workspace_actor_name,
          workspace_actor_id: if normalized.is_blank() {
            "local-operator"
          } else {
            normalized
          },
        },
      )
    }
    WorkspacePresenceRenewed(result) =>
      match result {
        Ok(_) =>
          (
            @http.get(
              "/api/workspace/projects/" + model.project_id + "/features",
            ).expect_json(value => dispatch(WorkspaceFeaturesLoaded(value))),
            model,
          )
        Err(_) =>
          (@rabbita.none, { ..model, error: "Could not renew edit presence." })
      }
    WorkspaceCanvasPointerDown(node_id, mouse) => {
      let position = workspace_node_position(model, node_id)
      let prepared = begin_workspace_graph_edit(model)
      (
        @rabbita.none,
        {
          ..prepared,
          selected_workspace_node: node_id,
          workspace_canvas_drag: Some({
            node_id,
            origin_client_x: mouse.client_pos().x,
            origin_client_y: mouse.client_pos().y,
            origin_x: position.x,
            origin_y: position.y,
          }),
        },
      )
    }
    WorkspaceCanvasPointerMoved(mouse) =>
      match model.workspace_canvas_drag {
        None => (@rabbita.none, model)
        Some(drag) => {
          let x = Int::max(
            0,
            drag.origin_x + mouse.client_pos().x - drag.origin_client_x,
          )
          let y = Int::max(
            0,
            drag.origin_y + mouse.client_pos().y - drag.origin_client_y,
          )
          (@rabbita.none, workspace_graph_move_node(model, drag.node_id, x, y))
        }
      }
    WorkspaceCanvasPointerReleased => {
      let activity = match model.workspace_canvas_drag {
        Some(drag) =>
          model.workspace_activity + ["Moved " + drag.node_id + " on canvas"]
        None => model.workspace_activity
      }
      (
        @rabbita.none,
        { ..model, workspace_canvas_drag: None, workspace_activity: activity },
      )
    }
    WorkspaceNodeNudged(node_id, delta_x, delta_y) => {
      let position = workspace_node_position(model, node_id)
      let prepared = begin_workspace_graph_edit(model)
      (
        @rabbita.none,
        workspace_graph_move_node(
          prepared,
          node_id,
          position.x + delta_x,
          position.y + delta_y,
        ),
      )
    }
    WorkspaceZoomChanged(delta) =>
      (
        @rabbita.none,
        {
          ..model,
          workspace_canvas_zoom: Double::min(
            1.6,
            Double::max(0.55, model.workspace_canvas_zoom + delta),
          ),
        },
      )
    WorkspacePortActivated(node_id, port_id, is_output) => {
      if is_output {
        return (
          @rabbita.none,
          {
            ..model,
            workspace_connect_from: node_id,
            workspace_connect_port: port_id,
            status: "Choose a compatible input port.",
            error: "",
          },
        )
      }
      if model.workspace_connect_from.is_blank() {
        return (
          @rabbita.none,
          { ..model, error: "Choose an output port before choosing an input." },
        )
      }
      let source = model.workspace_connect_from
      let source_port_id = model.workspace_connect_port
      let source_kind = visible_workspace_nodes(model)
        .iter()
        .find_first(value => value.node_id == source)
        .bind(value => {
          value.outputs
          .iter()
          .find_first(port => port.port_id == source_port_id)
        })
        .map(port => port.artifact_kind)
      let target_kind = visible_workspace_nodes(model)
        .iter()
        .find_first(value => value.node_id == node_id)
        .bind(value => {
          value.inputs.iter().find_first(port => port.port_id == port_id)
        })
        .map(port => port.artifact_kind)
      if source_kind is None ||
        target_kind is None ||
        !workspace_port_accepts(target_kind.unwrap(), source_kind.unwrap()) {
        return (
          @rabbita.none,
          {
            ..model,
            workspace_connect_from: "",
            workspace_connect_port: "",
            error: "Typed ports are incompatible; the connection was not created.",
          },
        )
      }
      let connected = workspace_graph_connect(
        model, source, source_port_id, node_id, port_id,
      )
      (
        @rabbita.none,
        {
          ..connected,
          workspace_connect_from: "",
          workspace_connect_port: "",
          workspace_activity: connected.workspace_activity +
          ["Connected " + source + " → " + node_id + " (typed)"],
          status: if model.selected_workspace_edge.is_blank() {
            "Typed connection added."
          } else {
            "Typed connection reconnected."
          },
          error: "",
        },
      )
    }
    WorkspaceAssetDragStarted(workspace_dragged_asset) =>
      (@rabbita.none, { ..model, workspace_dragged_asset, })
    WorkspaceAssetAddRequested(workspace_dragged_asset) =>
      update(dispatch, WorkspaceAssetDropped, {
        ..model,
        workspace_dragged_asset,
      })
    WorkspaceAssetDropped => {
      guard !model.workspace_dragged_asset.is_blank() else {
        return (@rabbita.none, model)
      }
      guard model.workspace_assets
        .iter()
        .find_first(entry => {
          entry.artifact.artifact_id == model.workspace_dragged_asset
        })
        is Some(entry) else {
        return (
          @rabbita.none,
          { ..model, error: "The dragged asset version is no longer indexed." },
        )
      }
      (
        @rabbita.none,
        {
          ..workspace_graph_add_asset_node(model, entry),
          workspace_dragged_asset: "",
          workspace_activity: model.workspace_activity +
          [
            "Bound immutable asset " +
            entry.artifact.artifact_id +
            " v" +
            entry.artifact.version.to_string(),
          ],
        },
      )
    }
    ToggleWorkspaceAssetSelection(artifact_id) => {
      let selected = if model.selected_workspace_asset_ids.contains(artifact_id) {
        model.selected_workspace_asset_ids.filter(value => value != artifact_id)
      } else {
        model.selected_workspace_asset_ids + [artifact_id]
      }
      (@rabbita.none, { ..model, selected_workspace_asset_ids: selected })
    }
    TagSelectedWorkspaceAsset => {
      guard model.selected_workspace_asset_ids.last() is Some(artifact_id) &&
        model.workspace_assets
        .iter()
        .find_first(entry => entry.artifact.artifact_id == artifact_id)
        is Some(entry) else {
        return (@rabbita.none, { ..model, error: "Select an asset to tag." })
      }
      let tags = if entry.tags.contains("review") {
        entry.tags.filter(value => value != "review")
      } else {
        entry.tags + ["review"]
      }
      let body : Json = { "tags": tags, "actor": model.workspace_actor_name }
      (
        @http.post(
          "/api/workspace/assets/" +
          artifact_id +
          "/" +
          entry.artifact.version.to_string() +
          "/tags",
        )
        .with_json(body)
        .expect_json(result => {
          dispatch(WorkspaceAssetMutationFinished("tag", result))
        }),
        { ..model, busy: true, status: "Updating asset tags…", error: "" },
      )
    }
    DeleteSelectedWorkspaceAsset => {
      guard model.selected_workspace_asset_ids.last() is Some(artifact_id) &&
        model.workspace_assets
        .iter()
        .find_first(entry => entry.artifact.artifact_id == artifact_id)
        is Some(entry) else {
        return (@rabbita.none, { ..model, error: "Select an asset to hide." })
      }
      (
        @http.post(
          "/api/workspace/assets/" +
          artifact_id +
          "/" +
          entry.artifact.version.to_string() +
          "/delete",
        )
        .with_json({ "actor": model.workspace_actor_name })
        .expect_json(result => {
          dispatch(WorkspaceAssetMutationFinished("hide", result))
        }),
        {
          ..model,
          busy: true,
          status: "Checking references before hiding asset…",
          error: "",
        },
      )
    }
    WorkspaceAssetMutationFinished(action, result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Asset " + action + " failed; it may still be referenced.",
            },
          )
        Ok(_) =>
          (
            @http.get(workspace_asset_library_url(model)).expect_json(value => {
              dispatch(WorkspaceAssetsLoaded(value))
            }),
            {
              ..model,
              busy: false,
              status: "Asset " + action + " completed.",
              error: "",
            },
          )
      }
    ToggleWorkspaceAppView =>
      (
        @rabbita.none,
        { ..model, workspace_app_view: !model.workspace_app_view },
      )
    WorkspaceSearchChanged(workspace_search) => {
      guard workspace_search.trim().length() >= 2 else {
        return (
          @rabbita.none,
          { ..model, workspace_search, workspace_search_results: [] },
        )
      }
      let body : Json = { "project_id": "", "query": workspace_search }
      (
        @http.post("/api/workspace/search")
        .with_json(body)
        .expect_json(result => dispatch(WorkspaceSearchLoaded(result))),
        { ..model, workspace_search, },
      )
    }
    WorkspaceSearchLoaded(result) =>
      match result {
        Err(_) => (@rabbita.none, model)
        Ok(response) => {
          let decoded : WorkspaceSearchPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            Some(value) =>
              (
                @rabbita.none,
                { ..model, workspace_search_results: value.matches },
              )
            None => (@rabbita.none, model)
          }
        }
      }
    WorkspaceCommentChanged(workspace_comment) =>
      (@rabbita.none, { ..model, workspace_comment, })
    WorkspacePublicInputChanged(workspace_public_input) =>
      (@rabbita.none, { ..model, workspace_public_input, })
    PostWorkspaceNodeComment => {
      guard !model.workspace_comment.trim().is_blank() else {
        return (@rabbita.none, { ..model, error: "Write a comment first." })
      }
      let body : Json = {
        "project_id": model.project_id,
        "target_kind": "NodeTarget",
        "target_id": model.selected_workspace_node,
        "body": model.workspace_comment,
        "actor": model.workspace_actor_name,
      }
      (
        @http.post("/api/workspace/comments/drafts")
        .with_json(body)
        .expect_json(result => {
          dispatch(WorkspaceActionFinished("comment", result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Saving node comment…",
          error: "",
        },
      )
    }
    CompareWorkspaceAssets => {
      guard model.selected_workspace_asset_ids.length() >= 2 else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Select at least two distinct asset versions before comparing.",
          },
        )
      }
      let body : Json = {
        "project_id": model.project_id,
        "artifact_ids": model.selected_workspace_asset_ids,
        "baseline_artifact_id": model.selected_workspace_asset_ids[0],
      }
      (
        @http.post("/api/workspace/artifacts/compare")
        .with_json(body)
        .expect_json(result => dispatch(WorkspaceAssetComparisonLoaded(result))),
        {
          ..model,
          busy: true,
          status: "Comparing artifact provenance…",
          error: "",
        },
      )
    }
    WorkspaceAssetComparisonLoaded(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Artifact comparison could not be completed.",
            },
          )
        Ok(response) => {
          let decoded : WorkspaceArtifactComparisonPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  error: "Comparison response was invalid.",
                },
              )
            Some(value) =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  workspace_asset_comparison: if value.differences.is_empty() {
                    "No provenance differences from baseline " +
                    value.baseline_artifact_id +
                    "."
                  } else {
                    value.differences.join(" · ")
                  },
                  status: if value.comparable {
                    "Artifact comparison loaded."
                  } else {
                    "Artifacts are not directly comparable."
                  },
                  error: "",
                },
              )
          }
        }
      }
    PromoteWorkspaceAsset => {
      guard model.selected_workspace_asset_ids.last() is Some(artifact_id) &&
        model.workspace_assets
        .iter()
        .find_first(entry => entry.artifact.artifact_id == artifact_id)
        is Some(entry) else {
        return (
          @rabbita.none,
          { ..model, error: "Select a registered asset to promote." },
        )
      }
      let action_id = fresh_key(model, "promotion")
      let body : Json = {
        "project_id": model.project_id,
        "artifact_id": artifact_id,
        "artifact_version": entry.artifact.version,
        "channel": "master-candidate",
        "actor": model.workspace_actor_name,
        "note": "Promoted from workspace review",
        "promoted_at": action_id,
      }
      (
        @http.post("/api/workspace/artifacts/promote")
        .with_json(body)
        .expect_json(result => {
          dispatch(WorkspaceActionFinished("promotion", result))
        }),
        {
          ..model,
          busy: true,
          status: "Promoting reviewed artifact…",
          error: "",
        },
      )
    }
    BranchWorkspaceAsset => {
      guard model.selected_workspace_asset_ids.last() is Some(artifact_id) &&
        model.workspace_assets
        .iter()
        .find_first(entry => entry.artifact.artifact_id == artifact_id)
        is Some(entry) else {
        return (
          @rabbita.none,
          { ..model, error: "Select a registered asset before branching it." },
        )
      }
      let branch_id = fresh_key(model, "artifact-branch")
      let body : Json = {
        "project_id": model.project_id,
        "source_artifact_id": artifact_id,
        "source_version": entry.artifact.version,
        "artifact_id": branch_id,
        "actor": model.workspace_actor_name,
        "branched_at": branch_id,
      }
      (
        @http.post("/api/workspace/artifacts/branch")
        .with_json(body)
        .expect_json(result => {
          dispatch(WorkspaceActionFinished("branch", result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Branching immutable artifact lineage…",
          error: "",
        },
      )
    }
    PublishWorkspaceCapsule => {
      let capsule_id = match model.selected_workspace_recipe {
        CombineVideosRecipe => "combine-videos"
        BriefToDeliveryRecipe => "brief-to-generated-delivery"
      }
      let publication_id = fresh_key(model, "capsule-publication")
      let body : Json = {
        "publication_id": publication_id,
        "project_id": model.project_id,
        "visibility": "workspace",
        "actor": model.workspace_actor_name,
        "published_at": publication_id,
      }
      (
        @http.post("/api/workspace/capsules/" + capsule_id + "/publish")
        .with_json(body)
        .expect_json(result => {
          dispatch(WorkspaceActionFinished("publish", result))
        }),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Publishing immutable capsule version…",
          error: "",
        },
      )
    }
    ShareWorkspaceRun => {
      let has_workspace_run = !model.workspace_run_id.is_blank()
      let has_utility_run = !model.utility_concat.job_id.is_blank()
      let target_id = if has_workspace_run {
        model.workspace_run_id
      } else if has_utility_run {
        model.utility_concat.job_id
      } else {
        model.workspace_graph
        .map(graph => graph.graph_id)
        .unwrap_or("workspace-draft")
      }
      let body : Json = {
        "project_id": model.project_id,
        "target_kind": if has_workspace_run || has_utility_run {
          "RunTarget"
        } else {
          "GraphTarget"
        },
        "target_id": target_id,
        "mode": "client-review",
        "created_by": model.workspace_actor_name,
        "lifetime_seconds": 604800,
      }
      (
        @http.post("/api/workspace/shares/secure")
        .with_json(body)
        .expect_json(result => dispatch(WorkspaceSecureShareCreated(result))),
        {
          ..model,
          busy: true,
          request_sequence: model.request_sequence + 1,
          status: "Creating revocable client-review link…",
          error: "",
        },
      )
    }
    WorkspaceSecureShareCreated(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Secure review link could not be created.",
            },
          )
        Ok(response) => {
          let decoded : WorkspaceShareCreatedPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          guard decoded is Some(created) else {
            return (
              @rabbita.none,
              {
                ..model,
                busy: false,
                error: "Secure share response was invalid.",
              },
            )
          }
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              workspace_share_url: created.access_path,
              workspace_share_id: created.share.share_id,
              status: "Created a revocable review link. Its token is shown only in this response.",
              workspace_activity: model.workspace_activity +
              ["Secure client-review share created"],
              error: "",
            },
          )
        }
      }
    RevokeWorkspaceShare => {
      guard !model.workspace_share_id.is_blank() else {
        return (@rabbita.none, model)
      }
      (
        @http.post(
          "/api/workspace/shares/" + model.workspace_share_id + "/revoke",
        )
        .with_json({ "actor": model.workspace_actor_name })
        .expect_json(result => dispatch(WorkspaceShareRevoked(result))),
        { ..model, busy: true, status: "Revoking review link…", error: "" },
      )
    }
    WorkspaceShareRevoked(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            { ..model, busy: false, error: "Share revocation failed." },
          )
        Ok(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              workspace_share_url: "",
              workspace_share_id: "",
              status: "Review link revoked.",
              workspace_activity: model.workspace_activity +
              ["Review share revoked"],
              error: "",
            },
          )
      }
    ApplyWorkspaceProposal(proposal_id) =>
      (
        @http.post(
          "/api/workspace/projects/" +
          model.project_id +
          "/proposals/" +
          proposal_id +
          "/apply",
        )
        .with_json({ "actor": model.workspace_actor_name })
        .expect_json(result => dispatch(WorkspaceProposalApplied(result))),
        {
          ..model,
          busy: true,
          status: "Applying reviewed proposal to the exact base revision…",
          error: "",
        },
      )
    ReviewWorkspaceProposal(proposal_id) =>
      (
        @http.get(
          "/api/workspace/projects/" +
          model.project_id +
          "/proposals/" +
          proposal_id,
        ).expect_json(result => dispatch(WorkspaceProposalReviewLoaded(result))),
        { ..model, status: "Loading proposal diff…", error: "" },
      )
    WorkspaceProposalReviewLoaded(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            { ..model, error: "Proposal diff could not be loaded." },
          )
        Ok(response) => {
          let decoded : WorkspaceProposalReviewPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            Some(review) =>
              (
                @rabbita.none,
                {
                  ..model,
                  workspace_proposal_review: Some(review),
                  status: if review.stale {
                    "Proposal is stale against the current graph revision."
                  } else {
                    "Proposal diff loaded for review."
                  },
                },
              )
            None =>
              (@rabbita.none, { ..model, error: "Proposal diff was invalid." })
          }
        }
      }
    WorkspaceProposalApplied(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Proposal could not be applied. Refresh it if the graph revision changed.",
            },
          )
        Ok(response) => {
          let decoded : WorkspaceGraphSummary? = Some(@json.from_json(response)) catch {
            _ => None
          }
          guard decoded is Some(graph) else {
            return (
              @rabbita.none,
              {
                ..model,
                busy: false,
                error: "Applied proposal response was invalid.",
              },
            )
          }
          let proposals = @http.get(
            "/api/workspace/projects/" + model.project_id + "/proposals",
          ).expect_json(value => dispatch(WorkspaceProposalsLoaded(value)))
          (
            proposals,
            {
              ..model,
              busy: false,
              workspace_graph: Some(graph),
              workspace_graph_undo: [],
              workspace_graph_redo: [],
              workspace_graph_dirty: false,
              status: "Applied proposal as graph revision {graph.revision}.",
              workspace_activity: model.workspace_activity +
              ["Reviewed agent proposal applied"],
              error: "",
            },
          )
        }
      }
    WorkspaceAgentInstructionChanged(workspace_agent_instruction) =>
      (@rabbita.none, { ..model, workspace_agent_instruction, })
    AskWorkspaceAgent => {
      guard model.workspace_graph is Some(graph) &&
        !model.workspace_agent_instruction.trim().is_blank() else {
        return (
          @rabbita.none,
          { ..model, error: "Enter a workspace assistant instruction first." },
        )
      }
      (
        @http.post(
          "/api/workspace/projects/" + model.project_id + "/agent/assist",
        )
        .with_json({
          "graph_id": graph.graph_id,
          "target_node_id": model.selected_workspace_node,
          "instruction": model.workspace_agent_instruction,
          "actor": model.workspace_actor_name,
        })
        .expect_json(result => dispatch(WorkspaceAgentAssisted(result))),
        { ..model, busy: true, status: "Inspecting graph and run evidence…" },
      )
    }
    WorkspaceAgentAssisted(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Workspace assistant could not inspect this graph.",
            },
          )
        Ok(response) => {
          let decoded : WorkspaceAgentAssistPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          guard decoded is Some(value) else {
            return (@rabbita.none, { ..model, busy: false })
          }
          (
            @http.get(
              "/api/workspace/projects/" + model.project_id + "/proposals",
            ).expect_json(next => dispatch(WorkspaceProposalsLoaded(next))),
            {
              ..model,
              busy: false,
              workspace_agent_diagnosis: value.diagnosis,
              workspace_agent_instruction: "",
              status: "Workspace assistant diagnosis is ready for review.",
              error: "",
            },
          )
        }
      }
    StartWorkspaceSelectedOutput => {
      if model.selected_workspace_recipe == BriefToDeliveryRecipe &&
        model.workspace_public_input.trim().is_blank() {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Enter the public creative brief before starting this recipe.",
          },
        )
      }
      let prepared = workspace_graph_bind_public_input(model)
      if prepared.workspace_graph_dirty {
        update(dispatch, SaveWorkspaceGraph("selected"), prepared)
      } else {
        (
          start_workspace_graph_http(dispatch, prepared, true),
          {
            ..prepared,
            busy: true,
            status: "Freezing the saved graph through the selected output…",
            error: "",
          },
        )
      }
    }
    StartWorkspaceRecipe => {
      if model.selected_workspace_recipe == BriefToDeliveryRecipe &&
        model.workspace_public_input.trim().is_blank() {
        return (
          @rabbita.none,
          {
            ..model,
            error: "Enter the public creative brief before starting this recipe.",
          },
        )
      }
      let prepared = workspace_graph_bind_public_input(model)
      if prepared.workspace_graph_dirty {
        update(dispatch, SaveWorkspaceGraph("all"), prepared)
      } else {
        (
          start_workspace_graph_http(dispatch, prepared, false),
          {
            ..prepared,
            busy: true,
            status: "Validating and freezing the saved graph revision…",
            error: "",
          },
        )
      }
    }
    WorkspaceRecipeStarted(result) =>
      match result {
        Ok(response) => {
          let decoded : WorkspaceRunPayload? = Some(@json.from_json(response)) catch {
            _ => None
          }
          guard decoded is Some(run) else {
            return (
              @rabbita.none,
              {
                ..model,
                busy: false,
                error: "Workspace run response was invalid.",
              },
            )
          }
          let started = {
            ..model,
            busy: false,
            workspace_run_id: run.run_id,
            workspace_run_state: run.state.stringify(),
            workspace_run_nodes: run.nodes,
            workspace_run_blockers: [],
            workspace_run_last_event_id: "",
            status: "Run queued from the exact saved graph revision.",
            workspace_activity: model.workspace_activity +
            ["Saved graph revision validated, frozen, and queued"],
          }
          if model.selected_workspace_recipe == CombineVideosRecipe {
            update(dispatch, StartUtilityConcat, started)
          } else {
            update(dispatch, ClaimWorkspaceNode, started)
          }
        }
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Workspace recipe could not be started.",
            },
          )
      }
    PollWorkspaceRun => {
      guard !model.workspace_run_id.is_blank() else {
        return (@rabbita.none, model)
      }
      (
        @http.get(
          "/api/workspace/runs/" +
          model.workspace_run_id +
          "/events/replay?after=" +
          model.workspace_run_last_event_id,
        ).expect_json(result => dispatch(WorkspaceRunEventsLoaded(result))),
        model,
      )
    }
    WorkspaceRunEventsLoaded(result) =>
      match result {
        Err(_) =>
          (@rabbita.none, { ..model, error: "Run event replay failed." })
        Ok(response) => {
          let decoded : WorkspaceRunEventPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          guard decoded is Some(feed) else { return (@rabbita.none, model) }
          match feed.events.last() {
            None =>
              (
                @rabbita.none,
                { ..model, workspace_run_last_event_id: feed.last_event_id },
              )
            Some(event) => {
              let next_state = event.run.state.stringify()
              (
                @rabbita.none,
                {
                  ..model,
                  workspace_run_state: next_state,
                  workspace_run_nodes: event.run.nodes,
                  workspace_run_last_event_id: feed.last_event_id,
                  workspace_activity: model.workspace_activity +
                  feed.events.map(item => {
                    item.event_name + " · " + item.run.state.stringify()
                  }),
                  status: "Replayed \{feed.events.length()} run event(s).",
                  error: "",
                },
              )
            }
          }
        }
      }
    WorkspaceRunHistoryLoaded(result) =>
      match result {
        Err(_) => (@rabbita.none, model)
        Ok(response) => {
          let decoded : WorkspaceRunListPayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            Some(value) =>
              (@rabbita.none, { ..model, workspace_run_history: value.runs })
            None => (@rabbita.none, model)
          }
        }
      }
    OpenWorkspaceRun(run_id) => {
      guard model.workspace_run_history
        .iter()
        .find_first(run => run.run_id == run_id)
        is Some(run) else {
        return (@rabbita.none, model)
      }
      (
        @rabbita.none,
        {
          ..model,
          workspace_run_id: run.run_id,
          workspace_run_state: run.state.stringify(),
          workspace_run_nodes: run.nodes,
          workspace_run_blockers: [],
          workspace_run_last_event_id: "",
          status: "Reopened run " + run.run_id + " from history.",
          error: "",
        },
      )
    }
    ClaimWorkspaceNode => {
      guard !model.workspace_run_id.is_blank() else {
        return (
          @rabbita.none,
          { ..model, error: "Start a run before claiming work." },
        )
      }
      (
        @http.post("/api/workspace/runs/" + model.workspace_run_id + "/advance")
        .with_json({ "actor": model.workspace_actor_name })
        .expect_json(result => dispatch(WorkspaceRunAdvanced(result))),
        { ..model, busy: true, status: "Advancing supported native nodes…" },
      )
    }
    WorkspaceRunAdvanced(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Run coordinator could not advance this graph.",
            },
          )
        Ok(response) => {
          let decoded : WorkspaceRunAdvancePayload? = Some(
            @json.from_json(response),
          ) catch {
            _ => None
          }
          match decoded {
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  error: "Run coordinator response was invalid.",
                },
              )
            Some(value) =>
              (
                @http.get(
                  "/api/workspace/projects/" +
                  model.project_id +
                  "/runs?limit=20",
                ).expect_json(result => {
                  dispatch(WorkspaceRunHistoryLoaded(result))
                }),
                {
                  ..model,
                  busy: false,
                  workspace_run_state: value.run.state.stringify(),
                  workspace_run_nodes: value.run.nodes,
                  workspace_run_blockers: value.blockers,
                  workspace_activity: model.workspace_activity +
                  value.executed_node_ids.map(id => "Executed native node " + id),
                  status: if value.blockers.is_empty() {
                    "Run coordinator reached a terminal state."
                  } else {
                    "Run paused with \{value.blockers.length()} explicit blocker(s)."
                  },
                  error: "",
                },
              )
          }
        }
      }
    DecideWorkspaceHumanGate(decision) => {
      guard !model.workspace_run_id.is_blank() &&
        !model.selected_workspace_node.is_blank() else {
        return (@rabbita.none, model)
      }
      (
        @http.post(
          "/api/workspace/runs/" +
          model.workspace_run_id +
          "/nodes/" +
          model.selected_workspace_node +
          "/decision",
        )
        .with_json({
          "actor": model.workspace_actor_name,
          "decision": decision,
          "note": model.workspace_comment,
        })
        .expect_json(result => dispatch(WorkspaceHumanDecisionFinished(result))),
        { ..model, busy: true, status: "Recording named human decision…" },
      )
    }
    WorkspaceHumanDecisionFinished(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            { ..model, busy: false, error: "Human gate decision was rejected." },
          )
        Ok(response) => {
          let decoded : WorkspaceRunPayload? = Some(@json.from_json(response)) catch {
            _ => None
          }
          match decoded {
            None => (@rabbita.none, { ..model, busy: false })
            Some(run) => {
              let decided = {
                ..model,
                busy: false,
                workspace_run_state: run.state.stringify(),
                workspace_run_nodes: run.nodes,
                workspace_comment: "",
                status: "Human gate decision recorded with evidence.",
                error: "",
              }
              update(dispatch, ClaimWorkspaceNode, decided)
            }
          }
        }
      }
    CancelWorkspaceRun => {
      guard !model.workspace_run_id.is_blank() else {
        return (@rabbita.none, model)
      }
      (
        @http.post(
          "/api/workspace/runs/" + model.workspace_run_id + "/actions/cancel",
        )
        .with_json({ "node_id": "", "actor": model.workspace_actor_name })
        .expect_json(result => dispatch(WorkspaceRunPolled(result))),
        { ..model, busy: true, status: "Cancelling run…" },
      )
    }
    RetryWorkspaceNode => {
      guard !model.workspace_run_id.is_blank() &&
        !model.selected_workspace_node.is_blank() else {
        return (@rabbita.none, model)
      }
      (
        @http.post(
          "/api/workspace/runs/" + model.workspace_run_id + "/actions/retry",
        )
        .with_json({
          "node_id": model.selected_workspace_node,
          "actor": model.workspace_actor_name,
        })
        .expect_json(result => dispatch(WorkspaceRunPolled(result))),
        { ..model, busy: true, status: "Retrying failed node…" },
      )
    }
    WorkspaceRunPolled(result) =>
      match result {
        Err(_) =>
          (
            @rabbita.none,
            { ..model, busy: false, error: "Workspace run operation failed." },
          )
        Ok(response) => {
          let decoded : WorkspaceRunPayload? = Some(@json.from_json(response)) catch {
            _ => None
          }
          match decoded {
            None => (@rabbita.none, model)
            Some(run) => {
              let next_state = run.state.stringify()
              let activity = if next_state == model.workspace_run_state {
                model.workspace_activity
              } else {
                model.workspace_activity + ["Run state → " + next_state]
              }
              (
                @rabbita.none,
                {
                  ..model,
                  busy: false,
                  workspace_run_state: next_state,
                  workspace_run_nodes: run.nodes,
                  workspace_activity: activity,
                },
              )
            }
          }
        }
      }
    WorkspaceActionFinished(action, result) =>
      match result {
        Ok(_) => {
          let refresh = if action == "artifact registration" ||
            action == "branch" {
            @http.get(workspace_asset_library_url(model)).expect_json(value => {
              dispatch(WorkspaceAssetsLoaded(value))
            })
          } else if action == "comment" {
            @http.get(
              "/api/workspace/projects/" + model.project_id + "/features",
            ).expect_json(value => dispatch(WorkspaceFeaturesLoaded(value)))
          } else {
            @rabbita.none
          }
          (
            refresh,
            {
              ..model,
              busy: false,
              workspace_comment: if action == "comment" {
                ""
              } else {
                model.workspace_comment
              },
              workspace_activity: model.workspace_activity +
              [action + " recorded with evidence"],
              status: action + " completed.",
              error: "",
            },
          )
        }
        Err(_) =>
          (
            @rabbita.none,
            { ..model, busy: false, error: "Workspace " + action + " failed." },
          )
      }
    OpenProject => {
      let generation = model.open_generation + 1
      let opened = @http.get("/api/editor/projects/" + model.project_id).expect_json(result => {
          dispatch(WorkspaceOpened(generation, result))
        },
      )
      let proposals = @http.get(
        "/api/workspace/projects/" + model.project_id + "/proposals",
      ).expect_json(result => dispatch(WorkspaceProposalsLoaded(result)))
      let catalog = @http.get("/api/workspace/catalog").expect_json(result => {
        dispatch(WorkspaceCatalogLoaded(result))
      })
      let capsule_id = workspace_recipe_id(model.selected_workspace_recipe)
      let graph = @http.post(
          "/api/workspace/projects/" +
          model.project_id +
          "/capsules/" +
          capsule_id +
          "/install",
        )
        .with_json({
          "graph_id": capsule_id,
          "title": workspace_recipe_title(model.selected_workspace_recipe),
          "actor": model.workspace_actor_name,
        })
        .expect_json(result => dispatch(WorkspaceGraphLoaded(result)))
      let assets = @http.get(workspace_asset_library_url(model)).expect_json(result => {
        dispatch(WorkspaceAssetsLoaded(result))
      })
      let features = @http.get(
        "/api/workspace/projects/" + model.project_id + "/features",
      ).expect_json(result => dispatch(WorkspaceFeaturesLoaded(result)))
      let runs = @http.get(
        "/api/workspace/projects/" + model.project_id + "/runs?limit=20",
      ).expect_json(result => dispatch(WorkspaceRunHistoryLoaded(result)))
      (
        @rabbita.batch([
          opened, proposals, catalog, graph, assets, features, runs,
        ]),
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
    UtilityConcatFilesSelected(files) =>
      (
        @rabbita.none,
        {
          ..model,
          utility_concat: {
            files,
            job_id: "",
            phase: "selected",
            completed: 0,
            output_digest: "",
            output_size: 0,
            media_url: "",
            error: "",
          },
        },
      )
    StartUtilityConcat => {
      let state = model.utility_concat
      guard state.files.get(0) is Some(first) else {
        return (
          @rabbita.none,
          {
            ..model,
            utility_concat: {
              ..state,
              phase: "failed",
              error: "Select at least one MP4 video.",
            },
          },
        )
      }
      (
        hash_utility_concat_file(dispatch, 0, first),
        {
          ..model,
          utility_concat: {
            ..state,
            phase: "hashing",
            completed: 0,
            job_id: "",
            output_digest: "",
            output_size: 0,
            media_url: "",
            error: "",
          },
        },
      )
    }
    UtilityConcatFileHashed(index, result) =>
      match result {
        Err(error) =>
          (
            @rabbita.none,
            {
              ..model,
              utility_concat: {
                ..model.utility_concat,
                phase: "failed",
                error: "Could not hash selected video: \{error}",
              },
            },
          )
        Ok(digest) => {
          let state = model.utility_concat
          guard state.files.get(index) is Some(file) else {
            return (
              @rabbita.none,
              {
                ..model,
                utility_concat: {
                  ..state,
                  phase: "failed",
                  error: "Selected video order changed while hashing.",
                },
              },
            )
          }
          let files = state.files.copy()
          files[index] = { ..file, sha256: digest }
          let next_index = index + 1
          let next_state = {
            ..state,
            files,
            completed: next_index,
            phase: if next_index < files.length() {
              "hashing"
            } else {
              "creating"
            },
          }
          match files.get(next_index) {
            Some(next) =>
              (
                hash_utility_concat_file(dispatch, next_index, next),
                { ..model, utility_concat: next_state },
              )
            None =>
              (
                create_utility_concat(dispatch, files),
                { ..model, utility_concat: next_state },
              )
          }
        }
      }
    UtilityConcatCreated(result) =>
      match result {
        Err(error) =>
          (
            @rabbita.none,
            {
              ..model,
              utility_concat: {
                ..model.utility_concat,
                phase: "failed",
                error: "Could not create utility concat job: \{error}",
              },
            },
          )
        Ok(job) => {
          let state = model.utility_concat
          if job.contract != "mooncast.editor-utility-concat-job.v1" {
            return (
              @rabbita.none,
              {
                ..model,
                utility_concat: {
                  ..state,
                  phase: "failed",
                  error: "Utility concat used an unsupported response contract.",
                },
              },
            )
          }
          if job.state == "succeeded" {
            return (
              @rabbita.none,
              {
                ..model,
                utility_concat: {
                  ..state,
                  job_id: job.job_id,
                  phase: "succeeded",
                  completed: job.expected_count,
                  output_digest: job.output_digest,
                  output_size: job.output_size,
                  media_url: job.media_url,
                  error: "",
                },
              },
            )
          }
          if job.uploaded_count == job.expected_count &&
            job.expected_count == state.files.length() {
            return (
              run_utility_concat(dispatch, job.job_id),
              {
                ..model,
                utility_concat: {
                  ..state,
                  job_id: job.job_id,
                  phase: "running",
                  completed: job.uploaded_count,
                  error: "",
                },
              },
            )
          }
          guard job.next_pending_input() is Some(expected) &&
            state.files.get(expected.index) is Some(file) &&
            expected.matches_local(file) else {
            return (
              @rabbita.none,
              {
                ..model,
                utility_concat: {
                  ..state,
                  job_id: job.job_id,
                  phase: "failed",
                  error: "Utility concat resume metadata did not match the selected files.",
                },
              },
            )
          }
          (
            upload_utility_concat_input(
              dispatch,
              job.job_id,
              expected.index,
              file,
            ),
            {
              ..model,
              utility_concat: {
                ..state,
                job_id: job.job_id,
                phase: "uploading",
                completed: job.uploaded_count,
                error: "",
              },
            },
          )
        }
      }
    UtilityConcatInputUploaded(result) =>
      match result {
        Err(error) =>
          (
            @rabbita.none,
            {
              ..model,
              utility_concat: {
                ..model.utility_concat,
                phase: "failed",
                error: "Exact video upload failed: \{error}",
              },
            },
          )
        Ok(job) => {
          let state = model.utility_concat
          match job.next_pending_input() {
            Some(expected) => {
              guard state.files.get(expected.index) is Some(file) &&
                expected.matches_local(file) else {
                return (
                  @rabbita.none,
                  {
                    ..model,
                    utility_concat: {
                      ..state,
                      job_id: job.job_id,
                      phase: "failed",
                      error: "Utility concat resume metadata did not match the selected files.",
                    },
                  },
                )
              }
              (
                upload_utility_concat_input(
                  dispatch,
                  job.job_id,
                  expected.index,
                  file,
                ),
                {
                  ..model,
                  utility_concat: {
                    ..state,
                    job_id: job.job_id,
                    phase: "uploading",
                    completed: job.uploaded_count,
                  },
                },
              )
            }
            None =>
              (
                run_utility_concat(dispatch, job.job_id),
                {
                  ..model,
                  utility_concat: {
                    ..state,
                    job_id: job.job_id,
                    phase: "running",
                    completed: job.uploaded_count,
                  },
                },
              )
          }
        }
      }
    UtilityConcatFinished(result) =>
      match result {
        Err(error) =>
          (
            @rabbita.none,
            {
              ..model,
              utility_concat: {
                ..model.utility_concat,
                phase: "failed",
                error: "Utility concat failed: \{error}",
              },
            },
          )
        Ok(job) => {
          let next = {
            ..model,
            utility_concat: {
              ..model.utility_concat,
              job_id: job.job_id,
              phase: job.state,
              completed: job.uploaded_count,
              output_digest: job.output_digest,
              output_size: job.output_size,
              media_url: job.media_url,
              error: job.error,
            },
          }
          if job.state != "succeeded" {
            return (@rabbita.none, next)
          }
          let body : Json = {
            "actor": model.workspace_actor_name,
            "recorded_at": fresh_key(model, "artifact-register"),
          }
          (
            @http.post(
              "/api/workspace/projects/" +
              model.project_id +
              "/utility-concats/" +
              job.job_id +
              "/register",
            )
            .with_json(body)
            .expect_json(result => {
              dispatch(WorkspaceActionFinished("artifact registration", result))
            }),
            {
              ..next,
              busy: true,
              request_sequence: model.request_sequence + 1,
              status: "Registering immutable workspace artifact…",
            },
          )
        }
      }
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
        Ok(response) => {
          if decode_api_error(response) is Some(error) {
            return (
              @rabbita.none,
              {
                ..model,
                busy: false,
                error: error.message,
                status: "Production import rejected.",
              },
            )
          }
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
              (@rabbita.none, { ..model, analysis: Some(analysis), error: "" })
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  error: decode_api_error(response)
                  .map(error => error.message)
                  .unwrap_or(
                    "Media analysis used an unsupported response contract.",
                  ),
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
    SelectClip(clip_id, extend_selection) => {
      let selection = if extend_selection {
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
    SelectAdjacentClip(direction, extend_selection) => {
      guard selected_clip(model) is Some(clip) else {
        return (@rabbita.none, model)
      }
      guard track_for_clip(model, clip.clip_id) is Some(track) else {
        return (@rabbita.none, model)
      }
      let ordered = track.clips
      let index = clip_position(ordered, clip.clip_id)
      let next = Int::min(Int::max(0, index + direction), ordered.length() - 1)
      update(
        dispatch,
        SelectClip(ordered[next].clip_id, extend_selection),
        model,
      )
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
      guard !clips(model).any(clip => clip.media_ref_id == take.media_ref_id) else {
        return (
          @rabbita.none,
          {
            ..model,
            error: "This media is already placed on the authoritative timeline.",
          },
        )
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
                error: decode_api_error(response)
                .map(error => error.message)
                .unwrap_or(
                  "Editor mutation used an unsupported response contract.",
                ),
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
    IntakeFileSelected(blob) =>
      match blob {
        None =>
          (
            @rabbita.none,
            {
              ..model,
              intake: {
                ..model.intake,
                selected_blob: None,
                file_name: "",
                size_bytes: "0",
                sha256: "",
              },
              busy: false,
              error: "Choose one local media file.",
            },
          )
        Some(value) =>
          (
            prepare_local_media_blob(dispatch, value),
            {
              ..model,
              busy: true,
              status: "Hashing the selected local media in the browser…",
              error: "",
            },
          )
      }
    IntakeFilePrepared(result) =>
      match result {
        Err(error) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              error: "Could not read selected local media: \{error}",
            },
          )
        Ok(selection) =>
          (
            @rabbita.none,
            {
              ..model,
              busy: false,
              intake: {
                ..model.intake,
                selected_blob: Some(selection.blob),
                file_name: selection.file_name,
                mime_type: selection.mime_type,
                size_bytes: selection.size_bytes.to_string(),
                sha256: selection.sha256,
              },
              status: "Local media digest ready; confirm rights and source evidence.",
              error: "",
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
            Some(prepared) => {
              let upload = match model.intake.selected_blob {
                Some(blob) => @http.post(prepared.upload_url).with_blob(blob)
                None =>
                  @http.post(prepared.upload_url).with_text(
                    model.intake.pasted_content,
                  )
              }
              (
                upload.expect_json(value => {
                  dispatch(IntakeContentUploaded(value))
                }),
                {
                  ..model,
                  pending_intake_id: prepared.intake_id,
                  status: "Uploading immutable local media bytes…",
                },
              )
            }
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
              intake: { ..model.intake, selected_blob: None },
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
      if model.workspace_lens == GraphLens && command && key == "s" {
        update(dispatch, SaveWorkspaceGraph(""), model)
      } else if model.workspace_lens == GraphLens && command && key == "z" {
        update(
          dispatch,
          if keyboard.shift_key() {
            WorkspaceGraphRedo
          } else {
            WorkspaceGraphUndo
          },
          model,
        )
      } else if model.workspace_lens == GraphLens && command && key == "d" {
        update(dispatch, DuplicateSelectedWorkspaceNode, model)
      } else if model.workspace_lens == GraphLens &&
        (key == "delete" || key == "backspace") {
        update(dispatch, DeleteSelectedWorkspaceNode, model)
      } else if command && key == "z" {
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
