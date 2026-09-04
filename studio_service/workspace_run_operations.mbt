///|
fn workspace_run_event_key(run_id : String, event_id : String) -> String {
  "workspace-event-run-" +
  sha256_text(run_id) +
  "-" +
  sha256_text(event_id) +
  ".json"
}

///|
async fn StudioService::record_workspace_run_event(
  self : StudioService,
  run : @workspace.RunRecord,
) -> @workspace.WorkspaceRunEvent {
  let base = @workspace.workspace_run_event(run, now_string())
  let event = {
    ..base,
    event_id: @runtime.new_id(prefix="workspace-run-event"),
  }
  save_value(
    self.store,
    workspace_run_event_key(run.run_id, event.event_id),
    event,
  )
  event
}

///|
pub async fn StudioService::workspace_run_events(
  self : StudioService,
  run_id : String,
  after : String,
) -> WorkspaceRunEventProjection {
  ignore(self.get_workspace_run(run_id))
  let all : Array[@workspace.WorkspaceRunEvent] = []
  for key in self.store.list_keys(prefix="workspace-event-run-", suffix=".json") {
    let value : @workspace.WorkspaceRunEvent? = load_value(self.store, key)
    if value is Some(event) && event.run_id == run_id {
      all.push(event)
    }
  }
  all.sort_by((left, right) => {
    let time = left.recorded_at.compare(right.recorded_at)
    if time == 0 {
      left.event_id.compare(right.event_id)
    } else {
      time
    }
  })
  let events : Array[@workspace.WorkspaceRunEvent] = []
  let mut accepting = after.is_blank()
  for event in all {
    if accepting {
      events.push(event)
    } else if event.event_id == after {
      accepting = true
    }
  }
  {
    contract: "mooncast.workspace-run-events.v1",
    run_id,
    events,
    last_event_id: all.last().map(event => event.event_id).unwrap_or(after),
    publication_authority: false,
  }
}

///|
pub async fn StudioService::workspace_run_events_sse(
  self : StudioService,
  run_id : String,
  after : String,
) -> String {
  let feed = self.workspace_run_events(run_id, after)
  if feed.events.is_empty() {
    ": reconnect-safe heartbeat\n\n"
  } else {
    feed.events.map(event => @workspace.workspace_sse(event)).join("")
  }
}

///|
pub async fn StudioService::list_workspace_runs(
  self : StudioService,
  project_id : String,
  state : String,
  offset : Int,
  limit : Int,
) -> WorkspaceRunListProjection {
  guard valid_id(project_id) && offset >= 0 && limit >= 1 && limit <= 200 else {
    raise Invalid(
      code="workspace_run_query_invalid",
      message="run query requires a valid project and a limit from 1 to 200",
    )
  }
  let matching : Array[@workspace.RunRecord] = []
  for key in self.store.list_keys(prefix="workspace-run-", suffix=".json") {
    let value : @workspace.RunRecord? = load_value(self.store, key)
    if value is Some(run) &&
      run.plan.frozen_graph.project_id == project_id &&
      (
        state.is_blank() ||
        run.state.to_json().stringify() == "\"" + state + "\""
      ) {
      matching.push(run)
    }
  }
  matching.sort_by((left, right) => right.updated_at.compare(left.updated_at))
  let runs : Array[@workspace.RunRecord] = []
  for index, run in matching {
    if index >= offset && index < offset + limit {
      runs.push(run)
    }
  }
  {
    contract: "mooncast.workspace-runs.v1",
    project_id,
    runs,
    total: matching.length(),
    offset,
    limit,
    has_more: offset + runs.length() < matching.length(),
    publication_authority: false,
  }
}

///|
pub async fn StudioService::claim_workspace_run_node(
  self : StudioService,
  run_id : String,
  request : WorkspaceRunClaimRequest,
) -> @workspace.WorkspaceDispatch {
  guard !request.worker_id.trim().is_blank() else {
    raise Invalid(
      code="workspace_worker_invalid",
      message="a scheduler claim requires a worker identity",
    )
  }
  let run = self.get_workspace_run(run_id)
  for node in run.nodes {
    if node.state == @workspace.Ready &&
      run.plan.nodes.iter().find_first(plan => plan.node_id == node.node_id)
      is Some(plan) &&
      (
        request.execution_owner.is_blank() ||
        plan.execution_owner == request.execution_owner
      ) {
      return self.prepare_workspace_dispatch(run_id, node.node_id, {
        input_refs: request.input_refs,
        created_at: now_string(),
      })
    }
  }
  raise Conflict(
    code="workspace_run_no_claimable_node",
    message="no ready node matches this worker's execution owner",
  )
}

///|
pub async fn StudioService::apply_workspace_run_action(
  self : StudioService,
  run_id : String,
  action : String,
  request : WorkspaceRunActionRequest,
) -> @workspace.RunRecord {
  guard !request.actor.trim().is_blank() else {
    raise Invalid(
      code="workspace_run_actor_invalid",
      message="run action requires an actor",
    )
  }
  guard action == "cancel" || action == "retry" else {
    raise Invalid(
      code="workspace_run_action_unknown",
      message="supported run actions are cancel and retry",
    )
  }
  self.apply_workspace_run_command(run_id, {
    command: action,
    node_id: request.node_id,
    numerator: 0,
    denominator: 1,
    output_digest: "",
    output_ref: "",
    error_code: "",
    error_message: "",
    recorded_at: now_string(),
  })
}
