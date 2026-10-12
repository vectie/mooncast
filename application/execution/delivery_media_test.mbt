///|
async test "exact video and caption reads cannot create or substitute a missing delivery" {
  let service = @execution.DeliveryFactoryService::new(
    "/tmp/mooncast-missing-exact-media/state", "/tmp/mooncast-missing-exact-media/outputs",
    "/usr/bin/ffmpeg",
  )
  assert_true(
    service.verified_delivery_video(
      "project", "absent-build", "master", "0000000000000000000000000000000000000000000000000000000000000000",
    )
    is None,
  )
  assert_true(
    service.verified_delivery_video_captions(
      "project", "absent-build", "named-cut", "0000000000000000000000000000000000000000000000000000000000000000",
    )
    is None,
  )
  assert_true(service.load("absent-build") is None)
}
