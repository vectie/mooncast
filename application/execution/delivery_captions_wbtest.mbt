///|
fn caption_fixture_output(
  kind : String,
  start? : Double,
  finish? : Double,
) -> @execution_domain.DeliveryOutputSpec {
  {
    output_id: if kind == "channel-cut" {
      "selected-cut"
    } else {
      "master"
    },
    kind,
    container: "mp4",
    codec: "libx264",
    width: 320,
    height: 240,
    subtitle_mode: "sidecar",
    metadata_digest: "sha256:synthetic-caption-output",
    source_output_id: if kind == "channel-cut" {
      Some("master")
    } else {
      None
    },
    orientation: None,
    framing_policy: None,
    in_seconds: start,
    out_seconds: finish,
    timestamp_seconds: None,
  }
}

///|
fn caption_fixture_srt() -> Bytes {
  @utf8.encode(
    "1\n00:00:00,000 --> 00:00:02,000\nBefore cut\n\n2\n00:00:02,000 --> 00:00:04,000\n跨越开始\nSecond line unchanged\n\n3\n00:00:04,500 --> 00:00:05,250\nInside\n\n4\n00:00:05,750 --> 00:00:08,000\nCrossing end\n\n5\n00:00:08,000 --> 00:00:10,000\nAfter cut\n",
  )
}

///|
test "contiguous caption mapping clips both edges without changing cue text" {
  let source = caption_fixture_srt()
  let derived = delivery_output_captions(
    source,
    12.0,
    caption_fixture_output("channel-cut", start=3.0, finish=6.0),
  )
  assert_eq(
    derived.content,
    "1\n00:00:00,000 --> 00:00:01,000\n跨越开始\nSecond line unchanged\n\n2\n00:00:01,500 --> 00:00:02,250\nInside\n\n3\n00:00:02,750 --> 00:00:03,000\nCrossing end\n",
  )
  assert_eq(
    delivery_output_captions(
      source,
      12.0,
      caption_fixture_output("source-master"),
    ).content,
    @utf8.decode(source),
  )
  let exact = delivery_output_captions(
    source,
    12.0,
    caption_fixture_output("channel-cut", start=4.0, finish=5.75),
  )
  assert_eq(exact.content, "1\n00:00:00,500 --> 00:00:01,250\nInside\n")
  let long_source = @utf8.encode("1\n01:00:00,000 --> 01:00:01,000\nHour cue\n")
  assert_eq(
    delivery_output_captions(
      long_source,
      3602.0,
      caption_fixture_output("channel-cut", start=3600.0, finish=3602.0),
    ).content,
    "1\n00:00:00,000 --> 00:00:01,000\nHour cue\n",
  )
}

///|
test "unsupported empty fractional and out of range caption mappings reject" {
  for
    bounds in [
      (3.0, 3.0),
      (-1.0, 3.0),
      (3.0, 13.0),
      (10.0, 12.0),
      (3.0005, 6.0),
      (0.0 / 0.0, 6.0),
    ] {
    try
      delivery_output_captions(
        caption_fixture_srt(),
        12.0,
        caption_fixture_output("channel-cut", start=bounds.0, finish=bounds.1),
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("Unsupported range must not reuse the master SRT")
    }
  }
  let retimed = {
    ..caption_fixture_output("source-master"),
    in_seconds: Some(1.0),
  }
  try delivery_output_captions(caption_fixture_srt(), 12.0, retimed) catch {
    _ => ()
  } noraise {
    _ => fail("Undeclared mapping must not be treated as identity")
  }
  let chained = caption_fixture_output("channel-cut", start=3.0, finish=6.0)
  assert_false(
    delivery_profile_valid(
      {
        contract: "mooncast.delivery-build-profile.v1",
        profile_version: 1,
        profile_digest: "test",
        outputs: [{ ..chained, source_output_id: Some("another-cut"), }],
        include_provenance_manifest: true,
        include_rights_ledger: true,
        include_acceptance_receipt: true,
      },
      12.0,
    ),
  )
}
