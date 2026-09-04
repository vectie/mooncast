///|
fn workspace_native_output_key(run_id : String, node_id : String) -> String {
  "workspace-native-output-" +
  sha256_text(run_id + "\u{0000}" + node_id) +
  ".json"
}

///|
fn workspace_graph_node(
  run : @workspace.RunRecord,
  node_id : String,
) -> @workspace.WorkflowNode? {
  run.plan.frozen_graph.nodes.iter().find_first(node => node.node_id == node_id)
}

///|
fn workspace_node_definition(
  service : StudioService,
  definition_id : String,
) -> @workspace.NodeDefinition? {
  service.workspace_catalog().definitions
  .iter()
  .find_first(definition => definition.definition_id == definition_id)
}

///|
fn workspace_terminal_ref(
  run : @workspace.RunRecord,
  node_id : String,
) -> String? {
  guard run.nodes.iter().find_first(node => node.node_id == node_id)
    is Some(node) else {
    return None
  }
  if node.state == @workspace.Cached {
    return run.plan.nodes
      .iter()
      .find_first(plan => plan.node_id == node_id)
      .map(plan => plan.cached_output_ref)
  }
  guard node.state == @workspace.Succeeded &&
    node.attempts.last() is Some(attempt) else {
    return None
  }
  Some(attempt.output_ref)
}

///|
fn workspace_input_refs(
  run : @workspace.RunRecord,
  node_id : String,
) -> Array[String]? {
  guard run.plan.nodes.iter().find_first(node => node.node_id == node_id)
    is Some(planned) else {
    return None
  }
  let refs : Array[String] = []
  for input_id in planned.input_node_ids {
    guard workspace_terminal_ref(run, input_id) is Some(value) else {
      return None
    }
    refs.push(value)
  }
  Some(refs)
}

///|
fn workspace_parameter_bool(
  node : @workspace.WorkflowNode,
  key : String,
) -> Bool? {
  guard node.parameters.iter().find_first(value => value.key == key)
    is Some(parameter) else {
    return None
  }
  match parameter.value {
    Json::True => Some(true)
    Json::False => Some(false)
    _ => None
  }
}

///|
fn workspace_parameter_string(
  node : @workspace.WorkflowNode,
  key : String,
) -> String? {
  guard node.parameters.iter().find_first(value => value.key == key)
    is Some(parameter) else {
    return None
  }
  match parameter.value {
    Json::String(value) => Some(value)
    _ => None
  }
}

///|
fn workspace_native_semantics(
  definition : @workspace.NodeDefinition,
  node : @workspace.WorkflowNode,
) -> Result[String, WorkspaceRunBlocker] {
  if workspace_parameter_bool(node, "workspace:muted") == Some(true) {
    return Ok("muted-node")
  }
  if workspace_parameter_bool(node, "workspace:bypassed") == Some(true) {
    return Ok("bypassed-node")
  }
  match definition.node_kind {
    @workspace.InputNode =>
      if definition.definition_id == "workspace.asset-input" {
        guard workspace_parameter_string(node, "artifact-id") is Some(_) &&
          workspace_parameter_string(node, "artifact-version") is Some(_) &&
          workspace_parameter_string(node, "artifact-digest") is Some(digest) &&
          digest.has_prefix("sha256:") &&
          workspace_parameter_string(node, "artifact-uri") is Some(_) else {
          return Err({
            node_id: node.node_id,
            execution_owner: "mooncast",
            reason: "asset input is not bound to an immutable artifact version",
            required_action: "bind artifact-id, artifact-version, artifact-digest, and artifact-uri",
          })
        }
        Ok("immutable-asset-reference")
      } else if node.parameters.is_empty() {
        Err({
          node_id: node.node_id,
          execution_owner: "mooncast",
          reason: "input node has no bound value",
          required_action: "bind at least one public input or node parameter",
        })
      } else {
        Ok("content-addressed-input")
      }
    @workspace.ControlNode =>
      match definition.definition_id {
        "workspace.control.generate-variants" => Ok("bounded-variant-set")
        "workspace.control.map" => Ok("ordered-map-reference-set")
        "workspace.control.select" => Ok("deterministic-ranked-selection")
        "workspace.control.merge" => Ok("ordered-reference-merge")
        "workspace.control.policy-gate" =>
          if workspace_parameter_bool(node, "approved") == Some(true) {
            Ok("approved-policy-gate")
          } else {
            Err({
              node_id: node.node_id,
              execution_owner: "mooncast",
              reason: "policy gate has not been approved",
              required_action: "set the approved parameter to true after policy review",
            })
          }
        _ =>
          Err({
            node_id: node.node_id,
            execution_owner: "mooncast",
            reason: "control executor is not registered",
            required_action: "install a native executor for " +
            definition.definition_id,
          })
      }
    @workspace.OutputNode =>
      if definition.definition_id == "workspace.artifact-register" {
        Ok("immutable-artifact-registration")
      } else {
        Err({
          node_id: node.node_id,
          execution_owner: "mooncast",
          reason: "output executor is not registered",
          required_action: "install a native executor for " +
          definition.definition_id,
        })
      }
    @workspace.OperationNode =>
      match definition.tool_id {
        "brief.validate" => Ok("creative-brief-validation")
        "project.create" => Ok("production-project-envelope")
        "delivery.package" => Ok("reviewed-delivery-envelope")
        _ =>
          Err({
            node_id: node.node_id,
            execution_owner: definition.execution_owner,
            reason: "declared capability has no generic native executor",
            required_action: "dispatch " +
            definition.tool_id +
            " through its owning application adapter",
          })
      }
    @workspace.CapsuleNode =>
      Err({
        node_id: node.node_id,
        execution_owner: "mooncast",
        reason: "subgraph node is not bound to an installed capsule revision",
        required_action: "bind capsule-id and capsule-version before expansion",
      })
    @workspace.HumanGateNode =>
      Err({
        node_id: node.node_id,
        execution_owner: "human",
        reason: "named human decision required",
        required_action: "approve or reject this node from the run inspector",
      })
  }
}

///|
async fn StudioService::execute_workspace_native_node(
  self : StudioService,
  run : @workspace.RunRecord,
  node : @workspace.WorkflowNode,
  definition : @workspace.NodeDefinition,
  semantics : String,
  input_refs : Array[String],
  actor : String,
) -> Unit {
  let recorded_at = now_string()
  let digest = "sha256:" +
    sha256_text(
      run.plan.graph_digest +
      "\u{0000}" +
      node.node_id +
      "\u{0000}" +
      semantics +
      "\u{0000}" +
      node.parameters.to_json().stringify() +
      "\u{0000}" +
      input_refs.to_json().stringify(),
    )
  let output_ref = "/api/workspace/runs/" +
    run.run_id +
    "/outputs/" +
    node.node_id
  let output : WorkspaceNativeOutput = {
    contract: "mooncast.workspace-native-output.v1",
    run_id: run.run_id,
    node_id: node.node_id,
    definition_id: definition.definition_id,
    semantics,
    input_refs: input_refs.copy(),
    parameters: node.parameters.copy(),
    actor,
    created_at: run.created_at,
    digest,
  }
  save_value(
    self.store,
    workspace_native_output_key(run.run_id, node.node_id),
    output,
  )
  let dispatch = self.prepare_workspace_dispatch(run.run_id, node.node_id, {
    input_refs,
    created_at: recorded_at,
  })
  ignore(
    self.apply_workspace_dispatch_receipt(dispatch.dispatch_id, {
      contract: "mooncast.workspace-dispatch-receipt.v1",
      dispatch_id: dispatch.dispatch_id,
      idempotency_key: dispatch.idempotency_key,
      state: @workspace.SucceededDispatch,
      output_digest: digest,
      output_ref,
      provider_receipt: {
        "executor": "mooncast-native".to_json(),
        "semantics": semantics.to_json(),
        "actor": actor.to_json(),
      },
      error_code: "",
      error_message: "",
      recorded_at,
    }),
  )
  if !definition.outputs.is_empty() {
    let artifact = @workspace.new_workspace_artifact(
      "artifact-" +
      sha256_text(run.run_id + "\u{0000}" + node.node_id)[:24].to_owned(),
      1,
      run.plan.frozen_graph.project_id,
      definition.outputs[0].artifact_kind,
      digest,
      output_ref,
      output_ref,
      input_refs.map(value => "sha256:" + sha256_text(value)),
      run.plan.graph_id,
      run.run_id,
      node.node_id,
      "",
      "mooncast-native",
      run.plan.model,
      output.to_json(),
      "inherited",
      "not-required",
      [semantics],
      0.0,
      0.0,
      run.created_at,
    ) catch {
      _ => return
    }
    ignore(self.save_workspace_artifact(artifact))
  }
}

///|
pub async fn StudioService::advance_workspace_run(
  self : StudioService,
  run_id : String,
  request : WorkspaceRunAdvanceRequest,
) -> WorkspaceRunAdvanceProjection {
  guard !request.actor.trim().is_blank() else {
    raise Invalid(
      code="workspace_run_actor_invalid",
      message="run advancement requires a named actor",
    )
  }
  let executed_node_ids : Array[String] = []
  let mut made_progress = true
  for ; made_progress; {
    made_progress = false
    let snapshot = self.get_workspace_run(run_id)
    for state in snapshot.nodes {
      if state.state != @workspace.Ready {
        continue
      }
      guard snapshot.plan.nodes
        .iter()
        .find_first(item => item.node_id == state.node_id)
        is Some(planned) &&
        workspace_graph_node(snapshot, state.node_id) is Some(node) &&
        workspace_node_definition(self, planned.definition_id)
        is Some(definition) else {
        continue
      }
      let locally_overridden = workspace_parameter_bool(node, "workspace:muted") ==
        Some(true) ||
        workspace_parameter_bool(node, "workspace:bypassed") == Some(true)
      if planned.execution_owner != "mooncast" && !locally_overridden {
        continue
      }
      guard workspace_input_refs(snapshot, node.node_id) is Some(input_refs) else {
        continue
      }
      match workspace_native_semantics(definition, node) {
        Ok(semantics) => {
          self.execute_workspace_native_node(
            snapshot,
            node,
            definition,
            semantics,
            input_refs,
            request.actor,
          )
          executed_node_ids.push(node.node_id)
          made_progress = true
        }
        Err(_) => ()
      }
    }
  }
  let run = self.get_workspace_run(run_id)
  let blockers : Array[WorkspaceRunBlocker] = []
  for state in run.nodes {
    if state.state != @workspace.Ready {
      continue
    }
    guard run.plan.nodes
      .iter()
      .find_first(item => item.node_id == state.node_id)
      is Some(planned) &&
      workspace_graph_node(run, state.node_id) is Some(node) &&
      workspace_node_definition(self, planned.definition_id) is Some(definition) else {
      continue
    }
    let locally_overridden = workspace_parameter_bool(node, "workspace:muted") ==
      Some(true) ||
      workspace_parameter_bool(node, "workspace:bypassed") == Some(true)
    if planned.execution_owner == "moonflow" && !locally_overridden {
      blockers.push({
        node_id: node.node_id,
        execution_owner: planned.execution_owner,
        reason: "external or physical effect requires a MoonFlow worker",
        required_action: "claim and execute this node with a configured provider adapter",
      })
    } else if planned.execution_owner == "human" {
      blockers.push({
        node_id: node.node_id,
        execution_owner: planned.execution_owner,
        reason: "named human decision required",
        required_action: "approve or reject this node from the run inspector",
      })
    } else {
      match workspace_native_semantics(definition, node) {
        Err(blocker) => blockers.push(blocker)
        Ok(_) => ()
      }
    }
  }
  {
    contract: "mooncast.workspace-run-advance.v1",
    run,
    executed_node_ids,
    blockers,
    publication_authority: false,
  }
}

///|
pub async fn StudioService::get_workspace_native_output(
  self : StudioService,
  run_id : String,
  node_id : String,
) -> WorkspaceNativeOutput {
  ignore(self.get_workspace_run(run_id))
  let value : WorkspaceNativeOutput? = load_value(
    self.store,
    workspace_native_output_key(run_id, node_id),
  )
  match value {
    Some(output) => output
    None => raise NotFound(entity="workspace_native_output", id=node_id)
  }
}

///|
pub async fn StudioService::decide_workspace_human_gate(
  self : StudioService,
  run_id : String,
  node_id : String,
  request : WorkspaceHumanDecisionRequest,
) -> @workspace.RunRecord {
  guard !request.actor.trim().is_blank() &&
    (request.decision == "approve" || request.decision == "reject") else {
    raise Invalid(
      code="workspace_human_decision_invalid",
      message="a named actor and approve or reject decision are required",
    )
  }
  let run = self.get_workspace_run(run_id)
  guard run.nodes.iter().find_first(node => node.node_id == node_id)
    is Some(state) &&
    state.state == @workspace.Ready &&
    run.plan.nodes.iter().find_first(node => node.node_id == node_id)
    is Some(planned) &&
    planned.execution_owner == "human" else {
    raise Conflict(
      code="workspace_human_gate_not_ready",
      message="only a ready human-owned node can receive a decision",
    )
  }
  let recorded_at = now_string()
  let running = self.apply_workspace_run_command(run_id, {
    command: "start",
    node_id,
    numerator: 0,
    denominator: 1,
    output_digest: "",
    output_ref: "",
    error_code: "",
    error_message: "",
    recorded_at,
  })
  ignore(running)
  if request.decision == "reject" {
    return self.apply_workspace_run_command(run_id, {
      command: "fail",
      node_id,
      numerator: 0,
      denominator: 1,
      output_digest: "",
      output_ref: "",
      error_code: "human-rejected",
      error_message: request.note,
      recorded_at,
    })
  }
  let digest = "sha256:" +
    sha256_text(
      run_id +
      "\u{0000}" +
      node_id +
      "\u{0000}" +
      request.actor +
      "\u{0000}" +
      request.note,
    )
  self.apply_workspace_run_command(run_id, {
    command: "succeed",
    node_id,
    numerator: 1,
    denominator: 1,
    output_digest: digest,
    output_ref: "/api/workspace/runs/" + run_id + "/decisions/" + node_id,
    error_code: "",
    error_message: "",
    recorded_at,
  })
}
