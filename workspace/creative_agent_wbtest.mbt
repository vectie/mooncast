///|
test "creative agent proposes bounded parameter edits on the capable node" {
  let capsule = brief_to_delivery_capsule("project", "operator", "now")
  let catalog = complete_node_catalog([
    @pack.tool_declaration(
      "shots.generate",
      "mooncast",
      "generation-request",
      "shot-record",
      @pack.SandboxExecution,
      evidence_outputs=["workspace/artifacts"],
    ),
  ])
  let vertical = suggest_creative_graph_edit(
    capsule.graph,
    catalog,
    "brief",
    "Make the campaign vertical for mobile",
  ).unwrap()
  assert_eq(vertical.affected_node_ids, ["generate"])
  assert_eq(vertical.graph.revision, 2)
  assert_true(
    node_named(vertical.graph, "generate").unwrap().parameters.any(parameter => {
      parameter.key == "aspect_ratio" && parameter.value == "9:16".to_json()
    }),
  )
  let variants = suggest_creative_graph_edit(
    materialize_graph_parameters(vertical.graph, catalog),
    catalog,
    "review",
    "Give me more variants to compare",
  ).unwrap()
  assert_true(
    node_named(variants.graph, "generate").unwrap().parameters.any(parameter => {
      parameter.key == "variant_count" && parameter.value == (5).to_json()
    }),
  )
}

///|
test "creative agent leaves unsupported intent unchanged" {
  let capsule = combine_videos_capsule("project", "operator", "now")
  assert_eq(
    suggest_creative_graph_edit(
      capsule.graph,
      builtin_workspace_catalog(),
      "concat",
      "publish this everywhere",
    ),
    None,
  )
}
