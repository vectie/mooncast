///|
fn media_fixture_video(
  id : String,
  captions? : Bool = true,
) -> DeliveryVideoProjection {
  let base = "/api/v2/projects/caption-cut-project/delivery-builds/build-one/media/" +
    id
  {
    output_id: id,
    kind: "channel-cut",
    source_output_id: "vertical-1080p",
    orientation: Some("vertical"),
    in_seconds: Some(12.25),
    out_seconds: Some(18.5),
    width: 1080,
    height: 1920,
    name: "build-one-" + id + ".mp4",
    sha256: "sha256:" + id,
    preview_url: base + "/" + id,
    download_url: base + "/" + id + "/download",
    captions: if captions {
      Some({
        name: id + ".srt",
        sha256: "sha256:srt-" + id,
        preview_url: base + "/captions/srt-" + id + "/preview",
        download_url: base + "/captions/srt-" + id + "/download",
      })
    } else {
      None
    },
  }
}

///|
fn media_fixture_model() -> Model {
  let model = cut_fixture_model("1", "3")
  let build : DeliveryBuildProjection = {
    build_id: "build-one",
    build_digest: "build-digest",
    state: "completed",
    revision: 2,
    attempt_count: 1,
    recovery_count: 0,
    master_sha256: "sha256:master-file",
    delivery_digest: "delivery-digest",
    download_url: Some("/retained-package.zip"),
    last_error: None,
    record_digest: "record-digest",
    publication_authority: false,
    cover_frames: None,
    videos: Some([
      media_fixture_video("early"),
      media_fixture_video("later"),
      media_fixture_video("silent", captions=false),
    ]),
  }
  { ..model, delivery_builds: [build], }
}

///|
fn media_fixture_reply(
  model : Model,
  video : DeliveryVideoProjection,
  text : String,
) -> Msg {
  let captions = video.captions.unwrap()
  LoadedDeliveryMediaCaptions(
    model.delivery_media_generation,
    captions.preview_url,
    Ok({ name: captions.name, sha256: captions.sha256, content: text, }),
  )
}

///|
test "individual media selection renders exact player range source downloads captions and preserved package controls" {
  let initial = media_fixture_model()
  let before = rendered(
    render_delivery_build(
      _ => @rabbita.none,
      initial,
      initial.delivery_builds[0],
    ),
  )
  assert_false(before.contains("<video"))
  assert_true(before.contains("Download early.mp4"))
  assert_true(before.contains("href=\"/retained-package.zip\""))
  assert_true(before.contains("Accept exact build"))
  let selected = step(initial, SelectDeliveryMedia("build-one", "later"))
  assert_true(selected.delivery_caption_loading)
  assert_false(selected.busy)
  assert_false(selected.operator.human_confirmed)
  let video = selected_delivery_video(selected).unwrap()
  let ready = step(
    selected,
    media_fixture_reply(
      selected, video, "1\n00:00:00,000 --> 00:00:01,000\n<script>caption</script>",
    ),
  )
  let html = rendered(
    render_delivery_build(_ => @rabbita.none, ready, ready.delivery_builds[0]),
  )
  assert_true(html.contains("Playing: later"))
  assert_true(html.contains("source vertical-1080p"))
  assert_true(html.contains("source range 12.25–18.5 s"))
  assert_true(html.contains("src=\"" + video.preview_url + "\""))
  assert_true(html.contains("controls"))
  assert_false(
    html.contains("src=\"" + media_fixture_video("early").preview_url + "\""),
  )
  assert_true(html.contains("&lt;script&gt;caption&lt;/script&gt;"))
  assert_false(html.contains("<script>caption</script>"))
  assert_true(html.contains(video.captions.unwrap().download_url))
  assert_true(html.contains("Retry video and SRT"))
  assert_true(html.contains("sha256:later"))
  assert_true(html.contains("Original master: sha256:master-file"))
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
  let old_html = rendered(
    render_delivery_build(
      _ => @rabbita.none,
      historical,
      historical.delivery_builds[0],
    ),
  )
  assert_true(old_html.contains("Historical build:"))
  assert_true(old_html.contains(video.preview_url))
}

///|
test "rapid video switching rejects stale SRT replies and retry remounts exact selection" {
  let first = step(
    media_fixture_model(),
    SelectDeliveryMedia("build-one", "early"),
  )
  let old_reply = media_fixture_reply(
    first,
    selected_delivery_video(first).unwrap(),
    "old early captions",
  )
  let later = step(first, SelectDeliveryMedia("build-one", "later"))
  let ignored = step(later, old_reply)
  assert_eq(ignored.delivery_caption_preview, None)
  assert_true(ignored.delivery_caption_loading)
  assert_eq(selected_delivery_video(ignored).unwrap().output_id, "later")
  let failed = step(
    later,
    LoadedDeliveryMediaCaptions(
      later.delivery_media_generation,
      selected_delivery_video(later).unwrap().captions.unwrap().preview_url,
      Err(ProjectLoadTestError("offline")),
    ),
  )
  assert_true(failed.delivery_caption_error is Some(_))
  assert_false(failed.delivery_caption_loading)
  let retry = step(failed, RetryDeliveryMedia)
  assert_eq(
    retry.delivery_media_generation,
    failed.delivery_media_generation + 1,
  )
  assert_true(retry.delivery_caption_loading)
  assert_eq(retry.delivery_caption_error, None)
  assert_eq(retry.delivery_media_selection, failed.delivery_media_selection)
  let ready = step(
    retry,
    media_fixture_reply(
      retry,
      selected_delivery_video(retry).unwrap(),
      "correct later captions",
    ),
  )
  assert_eq(ready.delivery_caption_preview, Some("correct later captions"))
  let repeated = step(
    ready,
    media_fixture_reply(
      ready,
      selected_delivery_video(ready).unwrap(),
      "duplicate unexpected reply",
    ),
  )
  assert_eq(repeated.delivery_caption_preview, Some("correct later captions"))
  let silent = step(ready, SelectDeliveryMedia("build-one", "silent"))
  assert_false(silent.delivery_caption_loading)
  assert_eq(silent.delivery_caption_preview, None)
  assert_true(
    rendered(
      render_delivery_build(
        _ => @rabbita.none,
        silent,
        silent.delivery_builds[0],
      ),
    ).contains("No SRT sidecar was included"),
  )
}

///|
test "project switch A B A cannot regain old playback or caption result and same-project refresh preserves exact selection" {
  let first = step(
    media_fixture_model(),
    SelectDeliveryMedia("build-one", "early"),
  )
  let old_reply = media_fixture_reply(
    first,
    selected_delivery_video(first).unwrap(),
    "early captions",
  )
  let refreshed = step(first, RefreshProject)
  assert_eq(refreshed.delivery_media_selection, first.delivery_media_selection)
  let ready = step(refreshed, old_reply)
  assert_eq(ready.delivery_caption_preview, Some("early captions"))
  let other = step(first, SelectProject("other-project"))
  assert_eq(other.delivery_media_selection, None)
  assert_eq(other.delivery_caption_preview, None)
  assert_false(other.delivery_caption_loading)
  let returned = step(other, SelectProject(first.selected_project_id))
  assert_eq(step(returned, old_reply).delivery_caption_preview, None)
  let unavailable = reconcile_delivery_media({
    ..ready,
    delivery_builds: [{ ..ready.delivery_builds[0], state: "failed", }],
  })
  assert_eq(unavailable.delivery_media_selection, None)
  assert_false(
    rendered(
      render_delivery_build(
        _ => @rabbita.none,
        unavailable,
        unavailable.delivery_builds[0],
      ),
    ).contains("<video"),
  )
  let changed = reconcile_delivery_media({
    ..ready,
    delivery_builds: [
      {
        ..ready.delivery_builds[0],
        videos: Some([{ ..media_fixture_video("early"), sha256: "changed", }]),
      },
    ],
  })
  assert_eq(changed.delivery_media_selection, None)
}

///|
test "caption response identity mismatch cannot paint different sidecar and missing legacy metadata is safe" {
  let selected = step(
    media_fixture_model(),
    SelectDeliveryMedia("build-one", "early"),
  )
  let video = selected_delivery_video(selected).unwrap()
  let captions = video.captions.unwrap()
  let wrong = step(
    selected,
    LoadedDeliveryMediaCaptions(
      selected.delivery_media_generation,
      captions.preview_url,
      Ok({
        name: captions.name,
        sha256: "wrong-sha",
        content: "foreign captions",
      }),
    ),
  )
  assert_eq(wrong.delivery_caption_preview, None)
  assert_true(wrong.delivery_caption_error is Some(_))
  let legacy : DeliveryBuildProjection = @json.from_json({
    "build_id": "legacy",
    "build_digest": "digest",
    "state": "completed",
    "revision": 1,
    "attempt_count": 1,
    "recovery_count": 0,
    "master_sha256": "master",
    "delivery_digest": "delivery",
    "download_url": "/archive",
    "record_digest": "record",
    "publication_authority": false,
  })
  assert_true(legacy.videos is None)
  assert_false(
    rendered(render_delivery_media(_ => @rabbita.none, selected, legacy)).contains(
      "<video",
    ),
  )
}
