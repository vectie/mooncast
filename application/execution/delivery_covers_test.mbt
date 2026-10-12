///|
async test "public cover preview read returns no bytes before an exact completed build exists" {
  let root = "/tmp/mooncast-cover-public-" + @runtime.new_id(prefix="fixture")
  let service = @execution.DeliveryFactoryService::new(
    root + "/state",
    root + "/outputs",
    "/usr/bin/ffmpeg",
  )
  assert_eq(
    service.verified_cover_frame(
      "project", "missing-build", "cover", "not-a-digest",
    ),
    None,
  )
  assert_true(service.list("project").is_empty())
  assert_eq(service.acceptance("missing-build"), None)
}
