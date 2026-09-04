///|
test "declarative workspace parameters materialize stable defaults" {
  let definition = definition_named(
    builtin_workspace_catalog(),
    "workspace.media-concat",
  ).unwrap()
  let parameters = materialize_node_parameters(definition, [
    { key: "container", value: "mov".to_json() },
    { key: "legacy-note", value: "preserved".to_json() },
  ])
  assert_eq(parameters.map(parameter => parameter.key), [
    "container", "fast_start", "legacy-note",
  ])
  assert_eq(parameters[0].value, "mov".to_json())
  assert_eq(parameters[1].value, true.to_json())
}

///|
test "parameter validation reports types bounds and compatible legacy keys" {
  let definition = definition_named(
    bounded_control_catalog(),
    "workspace.control.generate-variants",
  ).unwrap()
  let invalid = validate_node_parameters(definition, [
    { key: "variant_count", value: (12).to_json() },
    { key: "legacy", value: "kept".to_json() },
    { key: "workspace:muted", value: true.to_json() },
  ])
  assert_false(invalid.valid)
  assert_true(invalid.errors.any(error => error.contains("outside its bounds")))
  assert_eq(invalid.warnings, ["undeclared parameter preserved: legacy"])
  let wrong_type = validate_node_parameters(definition, [
    { key: "variant_count", value: "four".to_json() },
  ])
  assert_true(wrong_type.errors.any(error => error.contains("wrong type")))
}

///|
test "manifest generation contracts project rich creative controls" {
  let definition = catalog_from_tools([
      @pack.tool_declaration(
        "shots.generate",
        "mooncast",
        "generation-request",
        "shot-record",
        @pack.SandboxExecution,
        evidence_outputs=["workspace/artifacts"],
      ),
    ])[0]
  assert_true(
    definition.parameters.any(parameter => {
      parameter.parameter_id == "prompt" && parameter.control == TextAreaControl
    }),
  )
  assert_true(
    definition.parameters.any(parameter => {
      parameter.parameter_id == "variant_count" &&
      parameter.control == SliderControl
    }),
  )
  assert_true(
    definition.parameters.any(parameter => {
      parameter.parameter_id == "provider" && parameter.advanced
    }),
  )
}

///|
test "execution plans freeze explicit parameter defaults" {
  let graph = combine_videos_capsule("project", "operator", "now").graph
  let plan = freeze_plan(
    graph,
    builtin_workspace_catalog(),
    [],
    {
      provider: "local",
      model: "ffmpeg",
      policy_digest: "policy",
      cached_outputs: [],
    },
    "later",
  )
  let concat = node_named(plan.frozen_graph, "concat").unwrap()
  assert_true(
    concat.parameters.any(parameter => {
      parameter.key == "container" && parameter.value == "mp4".to_json()
    }),
  )
  assert_true(
    concat.parameters.any(parameter => {
      parameter.key == "fast_start" && parameter.value == true.to_json()
    }),
  )
  assert_eq(plan.graph_digest, graph_digest(plan.frozen_graph))
}
