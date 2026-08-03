///|
test "studio journey maps every gate to one clear workspace" {
  assert_eq(studio_journey_for(None, false, false).action, "Start episode")
  assert_eq(studio_journey_for(Some("G1"), false, true).tab == Creative, true)
  assert_eq(
    studio_journey_for(Some("G3"), false, true).tab == StoryboardAnimatic,
    true,
  )
  assert_eq(studio_journey_for(Some("G4"), false, true).tab == ShotBoard, true)
  assert_eq(studio_journey_for(Some("G7"), false, true).tab == Commercial, true)
  assert_eq(studio_journey_for(None, false, true).position, 8)
}

///|
test "ready governed gates expose the receipt action" {
  assert_eq(studio_journey_for(Some("G0"), true, true).action, "Record G0")
  assert_eq(studio_journey_for(Some("G2"), true, true).action, "Record G2")
  assert_eq(studio_journey_for(Some("G3"), true, true).action, "Record G3")
}
