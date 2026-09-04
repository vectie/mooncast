///|
test "creative workspace is the primary lens" {
  let model = initial_model()
  assert_eq(model.workspace_lens, GraphLens)
  assert_eq(model.selected_workspace_recipe, CombineVideosRecipe)
  assert_eq(model.selected_workspace_node, "concat")
  assert_eq(workspace_nodes(CombineVideosRecipe).length(), 6)
  assert_eq(workspace_node_state(model, "intake"), "ready")
  assert_eq(workspace_node_state(model, "concat"), "blocked")
}

///|
test "concat activity projects onto inspectable node states" {
  let running = {
    ..initial_model(),
    utility_concat: { ..initial_model().utility_concat, phase: "running" },
  }
  assert_eq(workspace_node_state(running, "intake"), "ready")
  assert_eq(workspace_node_state(running, "probe"), "succeeded")
  assert_eq(workspace_node_state(running, "normalize"), "running")
  assert_eq(workspace_node_state(running, "concat"), "running")
  assert_eq(workspace_node_state(running, "verify"), "blocked")

  let succeeded = {
    ..running,
    utility_concat: { ..running.utility_concat, phase: "succeeded" },
  }
  assert_true(
    workspace_nodes(CombineVideosRecipe).all(node => {
      workspace_node_state(succeeded, node.node_id) ==
      (if node.node_id == "intake" { "ready" } else { "succeeded" })
    }),
  )
}

///|
test "recipe selection changes the visible graph and inspector focus" {
  let (_, model) = update(
    _ => @rabbita.none,
    SelectWorkspaceRecipe(BriefToDeliveryRecipe),
    initial_model(),
  )
  assert_eq(model.selected_workspace_recipe, BriefToDeliveryRecipe)
  assert_eq(model.selected_workspace_node, "generate")
  assert_eq(selected_workspace_node(model).owner, "MoonFlow")
  assert_eq(workspace_nodes(BriefToDeliveryRecipe).length(), 6)
}

///|
test "workspace lens and inspector selection update without mutation" {
  let model = initial_model()
  let (_, editor) = update(
    _ => @rabbita.none,
    SwitchWorkspaceLens(EditorLens),
    model,
  )
  assert_eq(editor.workspace_lens, EditorLens)
  let (_, selected) = update(
    _ => @rabbita.none,
    SelectWorkspaceNode("verify"),
    editor,
  )
  assert_eq(selected.selected_workspace_node, "verify")
  assert_eq(selected.workspace_lens, EditorLens)
}
