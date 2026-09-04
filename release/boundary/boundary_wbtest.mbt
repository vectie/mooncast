///|
test "safe pack-relative paths reject traversal and absolute references" {
  assert_true(safe_relative_path("schemas/creative-brief.schema.json"))
  assert_false(safe_relative_path("../moonfish/pack.json"))
  assert_false(safe_relative_path("/tmp/external.json"))
  assert_false(safe_relative_path("schemas\\external.json"))
  assert_false(safe_relative_path("schemas//broken.json"))
}

///|
test "strict JSON key scanner detects decoded duplicate object keys" {
  debug_inspect(
    duplicate_json_keys("{\"id\":1,\"\\u0069d\":2}"),
    content="[\"id\"]",
  )
  debug_inspect(
    duplicate_json_keys("{\"a\":{\"id\":1},\"b\":{\"id\":2}}"),
    content="[]",
  )
}

///|
test "source boundary rejects generic imports and sibling workspaces" {
  assert_false(
    source_text_issues("kernel/main.mbt", "let value = moonflow", "mooncast").length() >
    0,
  )
  assert_true(
    source_text_issues("moon.pkg", "  \"vectie/moonfish/runtime\",", "mooncast").length() >
    0,
  )
  assert_true(
    source_text_issues(
      "adapter.js", "import Agent from 'moonflow/agent'", "mooncast",
    ).length() >
    0,
  )
  assert_true(
    source_text_issues(
      "main.mbt", "let p = \"/Users/a/Workspace/moonfish/x\"", "mooncast",
    ).length() >
    0,
  )
  assert_false(
    source_text_issues(
      "ui.mbt", "let endpoint = \"/api/workspace/projects/p1\"", "mooncast",
    ).length() >
    0,
  )
}

///|
async test "checked-in repository passes the MoonBit-native release boundary" {
  let issues = scan(".")
  debug_inspect(issues, content="[]")
}
