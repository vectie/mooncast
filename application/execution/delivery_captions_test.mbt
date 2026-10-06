///|
test "public caption derivation keeps source text and starts trim at zero" {
  let output : @execution_domain.DeliveryOutputSpec = {
    output_id: "intro",
    kind: "channel-cut",
    container: "mp4",
    codec: "libx264",
    width: 320,
    height: 240,
    subtitle_mode: "sidecar",
    metadata_digest: "fixture",
    source_output_id: Some("master"),
    orientation: None,
    framing_policy: None,
    in_seconds: Some(2.0),
    out_seconds: Some(4.0),
    timestamp_seconds: None,
  }
  let captions = @execution.delivery_output_captions(
    b"1\n00:00:01,000 --> 00:00:03,000\nExact source text\n", 5.0, output,
  )
  assert_eq(
    captions.content,
    "1\n00:00:00,000 --> 00:00:01,000\nExact source text\n",
  )
}
