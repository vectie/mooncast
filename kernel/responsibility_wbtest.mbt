///|
test "production gates require named human responsibility" {
  assert_true(
    gate_reviewer_issues("creative-lead", "creative-director").is_empty(),
  )
  assert_true(gate_reviewer_issues("client-a", "client").is_empty())
  assert_false(gate_reviewer_issues("", "creative-director").is_empty())
  for
    role in [
      "automation", "agent", "moonclaw", "moonflow", "provider-execution-host", "workflow-orchestrator",
    ] {
    assert_false(gate_reviewer_issues("runtime", role).is_empty())
  }
}
