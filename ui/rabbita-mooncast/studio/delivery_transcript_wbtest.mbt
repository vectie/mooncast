///|
fn transcript_fixture_text() -> String {
  "1\r\n00:00:00,000 --> 00:00:01,500\r\n你好 🌙 <script>&\r\nSecond LINE\r\n\r\n2\r\n00:00:01,000 --> 00:00:02,000\r\nOverlap\r\n\r\n3\r\n00:00:03,000 --> 00:00:04,000\r\nAfter gap\r\n"
}

///|
fn transcript_fixture_model() -> Model {
  let selected = step(
    media_fixture_model(),
    SelectDeliveryMedia("build-one", "early"),
  )
  step(
    selected,
    media_fixture_reply(
      selected,
      selected_delivery_video(selected).unwrap(),
      transcript_fixture_text(),
    ),
  )
}

///|
test "SRT bounded strict parsing preserves Unicode CRLF multiline and searches empty case text timestamps" {
  let cues = parse_delivery_transcript("\uFEFF" + transcript_fixture_text()).unwrap()
  assert_eq(cues.length(), 3)
  assert_eq(cues[0].text, "你好 🌙 <script>&\nSecond LINE")
  assert_eq(cues[0].start_ms, 0)
  let transcript = { ..empty_delivery_transcript(), cues, }
  assert_eq(delivery_matching_cues(transcript).length(), 3)
  assert_eq(delivery_matching_cues({ ..transcript, query: "  ", }).length(), 3)
  assert_eq(
    delivery_matching_cues({ ..transcript, query: "line", })[0].index,
    0,
  )
  assert_eq(
    delivery_matching_cues({ ..transcript, query: "🌙", })[0].index,
    0,
  )
  assert_eq(
    delivery_matching_cues({ ..transcript, query: "你好", })[0].index,
    0,
  )
  assert_eq(
    delivery_matching_cues({ ..transcript, query: "00:00:03", })[0].index,
    2,
  )
  assert_true(
    delivery_matching_cues({ ..transcript, query: "absent", }).is_empty(),
  )
  for
    bad in [
      "", "1\n00:00:00.000 --> 00:00:01,000\ntext", "1\n00:60:00,000 --> 01:00:01,000\ntext",
      "1\n00:00:01,000 --> 00:00:01,000\ntext", "1\n-0:00:00,000 --> 00:00:01,000\ntext",
      "1\n00:00:02,000 --> 00:00:01,000\ntext", "1\n00:00:00,000 --> 00:00:01,000\n",
      "x\n00:00:00,000 --> 00:00:01,000\ntext",
    ] {
    assert_true(parse_delivery_transcript(bad) is Err(_))
  }
  let many = Array::make(5000, "1\n00:00:00,000 --> 00:00:01,000\nx\n\n").join(
    "",
  )
  assert_eq(parse_delivery_transcript(many).unwrap().length(), 5000)
  assert_true(
    parse_delivery_transcript(many + "1\n00:00:00,000 --> 00:00:01,000\nx")
    is Err(_),
  )
  assert_true(
    parse_delivery_transcript(Array::make(1048577, "x").join("")) is Err(_),
  )
}

///|
test "active captions use exact output-local half-open boundaries overlaps gaps and metadata guards" {
  let model = transcript_fixture_model()
  let generation = model.delivery_media_generation
  assert_eq(delivery_cue_seek_target(model, generation, 0), None)
  for
    (seconds, count) in [
      (0.0, 1),
      (0.999, 1),
      (1.0, 2),
      (1.499, 2),
      (1.5, 1),
      (2.0, 0),
      (2.999, 0),
      (3.0, 1),
      (4.0, 0),
    ] {
    let ready = step(
      model,
      DeliveryPlayerEvent(generation, "metadata", seconds, 6.25),
    )
    assert_eq(
      ready.delivery_transcript.cues
      .filter(cue => delivery_cue_active(cue, ready.delivery_transcript))
      .length(),
      count,
    )
    assert_eq(delivery_cue_seek_target(ready, generation, 0), Some(0))
  }
  let unavailable = step(
    model,
    DeliveryPlayerEvent(generation, "unavailable", 0.0, 0.0),
  )
  assert_false(
    step(unavailable, DeliveryPlayerEvent(generation, "metadata", 1.0, 6.25)).delivery_transcript.ready,
  )
  let ready = step(
    model,
    DeliveryPlayerEvent(generation, "metadata", 1.0, 6.25),
  )
  let failed = step(
    ready,
    DeliveryPlayerEvent(generation, "seek-error", 3.0, 6.25),
  )
  assert_eq(failed.delivery_transcript.seconds, 1.0)
  assert_true(failed.delivery_transcript.media_error is Some(_))
  assert_eq(
    step(failed, DeliveryPlayerEvent(generation, "seeked", 0.0, 6.25)).delivery_transcript.media_error,
    None,
  )
  let html = rendered(render_delivery_transcript(_ => @rabbita.none, ready))
  assert_true(html.contains("&lt;script&gt;&amp;"))
  assert_false(html.contains("<script>"))
  assert_true(html.contains("Seek 00:00:00,000"))
  assert_true(html.contains("Enter or Space"))
  let search = step(ready, SearchDeliveryTranscript(generation, "after"))
  assert_eq(
    search.delivery_transcript.seconds,
    ready.delivery_transcript.seconds,
  )
  assert_true(
    rendered(render_delivery_transcript(_ => @rabbita.none, search)).contains(
      "Overlap",
    ),
  )
  assert_eq(search.command_sequence, model.command_sequence)
  assert_false(search.busy)
}

///|
test "malformed SRT keeps exact raw and video; output build project retry and stale media events are isolated" {
  let model = transcript_fixture_model()
  let g = model.delivery_media_generation
  let ready = step(model, DeliveryPlayerEvent(g, "metadata", 1.0, 6.25))
  let retry = step(ready, RetryDeliveryMedia)
  assert_true(retry.delivery_transcript.cues.is_empty())
  assert_false(
    step(retry, DeliveryPlayerEvent(g, "metadata", 1.0, 6.25)).delivery_transcript.ready,
  )
  assert_eq(
    step(retry, SearchDeliveryTranscript(g, "stale")).delivery_transcript.query,
    "",
  )
  let switched = step(ready, SelectDeliveryMedia("build-one", "later"))
  assert_false(
    step(switched, DeliveryPlayerEvent(g, "metadata", 1.0, 6.25)).delivery_transcript.ready,
  )
  let malformed = step(
    switched,
    media_fixture_reply(
      switched,
      selected_delivery_video(switched).unwrap(),
      "<bad>raw</bad>",
    ),
  )
  assert_true(malformed.delivery_transcript.parse_error is Some(_))
  let html = rendered(
    render_delivery_media(
      _ => @rabbita.none,
      malformed,
      malformed.delivery_builds[0],
    ),
  )
  assert_true(html.contains("<video"))
  assert_true(html.contains("&lt;bad&gt;raw&lt;/bad&gt;"))
  assert_true(html.contains("Download matching SRT"))
  let other = step(ready, SelectProject("other-project"))
  assert_true(other.delivery_transcript.cues.is_empty())
  assert_false(
    step(other, DeliveryPlayerEvent(g, "metadata", 1.0, 6.25)).delivery_transcript.ready,
  )
  let left = step(ready, SelectTab(ControlTower))
  assert_true(left.delivery_transcript.cues.is_empty())
  assert_eq(left.delivery_media_selection, None)
  let new_build = { ..ready.delivery_builds[0], build_id: "build-two", }
  let two = step(
    { ..ready, delivery_builds: ready.delivery_builds + [new_build], },
    SelectDeliveryMedia("build-two", "early"),
  )
  assert_true(two.delivery_transcript.cues.is_empty())
  assert_false(
    step(two, DeliveryPlayerEvent(g, "metadata", 1.0, 6.25)).delivery_transcript.ready,
  )
  let historical = {
    ..ready,
    project: Some({
      ..ready.project.unwrap(),
      master: Some({
        ..ready.project.unwrap().master.unwrap(),
        sha256: "new-master",
      }),
    }),
  }
  assert_eq(historical.delivery_transcript.cues, ready.delivery_transcript.cues)
  assert_eq(delivery_cue_seek_target(historical, g, 0), Some(0))
  let original_video = selected_delivery_video(ready).unwrap()
  let metadata_changed = reconcile_delivery_media({
    ..ready,
    delivery_builds: [
      {
        ..ready.delivery_builds[0],
        videos: Some([
          {
            ..original_video,
            captions: Some({
              ..original_video.captions.unwrap(),
              sha256: "changed-sidecar",
            }),
          },
        ]),
      },
    ],
  })
  assert_eq(metadata_changed.delivery_media_selection, None)
  assert_true(metadata_changed.delivery_transcript.cues.is_empty())
  let too_short = step(model, DeliveryPlayerEvent(g, "metadata", 0.0, 3.0))
  assert_eq(delivery_cue_seek_target(too_short, g, 2), None)
  assert_eq(delivery_cue_seek_target(too_short, g, -1), None)
  assert_eq(delivery_cue_seek_target(too_short, g, 99), None)
}
