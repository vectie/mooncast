///|
fn plan_node_named(plan : ExecutionPlan, node_id : String) -> PlannedNode? {
  for node in plan.nodes {
    if node.node_id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn dependencies_complete(record : RunRecord, node_id : String) -> Bool {
  guard plan_node_named(record.plan, node_id) is Some(plan_node) else {
    return false
  }
  plan_node.input_node_ids.all(input_id => {
    record.nodes.any(node => {
      node.node_id == input_id &&
      (node.state == Succeeded || node.state == Cached)
    })
  })
}

///|
fn recompute_run(record : RunRecord, now : String) -> RunRecord {
  let nodes = record.nodes.copy()
  for index, node in nodes {
    if node.state == Blocked &&
      dependencies_complete({ ..record, nodes, }, node.node_id) {
      nodes[index] = { ..node, state: Ready }
    }
  }
  let state = if nodes.any(node => node.state == Failed) {
    FailedRun
  } else if nodes.all(node => {
      node.state == Succeeded || node.state == Cached || node.state == Cancelled
    }) {
    if nodes.any(node => node.state == Cancelled) {
      CancelledRun
    } else {
      SucceededRun
    }
  } else if nodes.any(node => node.state == Running) {
    RunningRun
  } else {
    Queued
  }
  { ..record, nodes, state, updated_at: now }
}

///|
pub fn new_run(
  plan : ExecutionPlan,
  run_id : String,
  created_by : String,
  created_at : String,
  maximum_retries? : Int = 2,
) -> RunRecord {
  let nodes = plan.nodes.map(node => {
    let state = if node.cache_hit {
      Cached
    } else if node.input_node_ids.is_empty() {
      Ready
    } else {
      Blocked
    }
    {
      node_id: node.node_id,
      state,
      progress_numerator: if state == Cached {
        1
      } else {
        0
      },
      progress_denominator: 1,
      retry_count: 0,
      maximum_retries,
      attempts: [],
    }
  })
  recompute_run(
    {
      contract: "mooncast.workspace-run.v1",
      run_id,
      plan,
      state: Queued,
      nodes,
      created_by,
      created_at,
      updated_at: created_at,
      publication_authority: false,
    },
    created_at,
  )
}

///|
fn node_run_index(
  record : RunRecord,
  node_id : String,
) -> Int raise WorkspaceError {
  for index, node in record.nodes {
    if node.node_id == node_id {
      return index
    }
  }
  raise UnknownNode(node_id)
}

///|
pub fn RunRecord::start_node(
  self : RunRecord,
  node_id : String,
  now : String,
) -> RunRecord raise WorkspaceError {
  let index = node_run_index(self, node_id)
  let node = self.nodes[index]
  guard node.state == Ready else {
    raise InvalidTransition("only a ready node can start")
  }
  let attempts = node.attempts.copy()
  attempts.push({
    attempt: attempts.length() + 1,
    state: Running,
    started_at: now,
    finished_at: "",
    output_digest: "",
    output_ref: "",
    error_code: "",
    error_message: "",
  })
  let nodes = self.nodes.copy()
  nodes[index] = {
    ..node,
    state: Running,
    progress_numerator: 0,
    progress_denominator: 1,
    attempts,
  }
  recompute_run({ ..self, nodes, }, now)
}

///|
pub fn RunRecord::progress_node(
  self : RunRecord,
  node_id : String,
  numerator : Int,
  denominator : Int,
  now : String,
) -> RunRecord raise WorkspaceError {
  let index = node_run_index(self, node_id)
  let node = self.nodes[index]
  guard node.state == Running &&
    denominator > 0 &&
    numerator >= 0 &&
    numerator <= denominator else {
    raise InvalidTransition("invalid node progress")
  }
  let nodes = self.nodes.copy()
  nodes[index] = {
    ..node,
    progress_numerator: numerator,
    progress_denominator: denominator,
  }
  recompute_run({ ..self, nodes, }, now)
}

///|
pub fn RunRecord::succeed_node(
  self : RunRecord,
  node_id : String,
  output_digest : String,
  output_ref : String,
  now : String,
) -> RunRecord raise WorkspaceError {
  let index = node_run_index(self, node_id)
  let node = self.nodes[index]
  guard node.state == Running &&
    output_digest.has_prefix("sha256:") &&
    !output_ref.is_blank() else {
    raise InvalidTransition("running node requires a content-addressed output")
  }
  let attempts = node.attempts.copy()
  let attempt_index = attempts.length() - 1
  attempts[attempt_index] = {
    ..attempts[attempt_index],
    state: Succeeded,
    finished_at: now,
    output_digest,
    output_ref,
  }
  let nodes = self.nodes.copy()
  nodes[index] = {
    ..node,
    state: Succeeded,
    progress_numerator: node.progress_denominator,
    attempts,
  }
  recompute_run({ ..self, nodes, }, now)
}

///|
pub fn RunRecord::fail_node(
  self : RunRecord,
  node_id : String,
  error_code : String,
  error_message : String,
  now : String,
) -> RunRecord raise WorkspaceError {
  let index = node_run_index(self, node_id)
  let node = self.nodes[index]
  guard node.state == Running else {
    raise InvalidTransition("only a running node can fail")
  }
  let attempts = node.attempts.copy()
  let attempt_index = attempts.length() - 1
  attempts[attempt_index] = {
    ..attempts[attempt_index],
    state: Failed,
    finished_at: now,
    error_code,
    error_message,
  }
  let nodes = self.nodes.copy()
  nodes[index] = { ..node, state: Failed, attempts }
  recompute_run({ ..self, nodes, }, now)
}

///|
pub fn RunRecord::retry_node(
  self : RunRecord,
  node_id : String,
  now : String,
) -> RunRecord raise WorkspaceError {
  let index = node_run_index(self, node_id)
  let node = self.nodes[index]
  guard node.state == Failed && node.retry_count < node.maximum_retries else {
    raise InvalidTransition("node is not retryable")
  }
  let nodes = self.nodes.copy()
  nodes[index] = {
    ..node,
    state: if dependencies_complete(self, node_id) {
      Ready
    } else {
      Blocked
    },
    progress_numerator: 0,
    retry_count: node.retry_count + 1,
  }
  recompute_run({ ..self, nodes, }, now)
}

///|
pub fn RunRecord::cancel(self : RunRecord, now : String) -> RunRecord {
  let nodes = self.nodes.map(node => {
    if node.state == Blocked || node.state == Ready || node.state == Running {
      { ..node, state: Cancelled }
    } else {
      node
    }
  })
  recompute_run({ ..self, nodes, }, now)
}

///|
/// Running nodes never silently survive process restart. Retryable work is
/// made ready again; exhausted work records a terminal interruption.
pub fn recover_run_after_restart(record : RunRecord, now : String) -> RunRecord {
  let nodes = record.nodes.map(node => {
    if node.state != Running {
      return node
    }
    let attempts = node.attempts.copy()
    if !attempts.is_empty() {
      let index = attempts.length() - 1
      attempts[index] = {
        ..attempts[index],
        state: Failed,
        finished_at: now,
        error_code: "process-restarted",
        error_message: "workspace worker restarted before a terminal receipt",
      }
    }
    if node.retry_count < node.maximum_retries {
      {
        ..node,
        state: Ready,
        progress_numerator: 0,
        retry_count: node.retry_count + 1,
        attempts,
      }
    } else {
      { ..node, state: Failed, attempts }
    }
  })
  recompute_run({ ..record, nodes, }, now)
}
