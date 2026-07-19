///|
async test "release surfaces name the native host boundary and Rabbita build" {
  let readme = @fs.read_file("README.mbt.md").text()
  let workflow = @fs.read_file(".github/workflows/pack-boundary.yml").text()
  assert_true(readme.contains("moon run cmd/studio"))
  assert_true(readme.contains("ui/rabbita-mooncast run build"))
  assert_true(workflow.contains("moon run cmd/pack_boundary"))
  assert_true(workflow.contains("npm run build"))
}
