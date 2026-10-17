///|
fn[T] rejects(body : () -> T raise) -> Unit raise {
  try body() catch {
    _ => ()
  } noraise {
    _ => fail("expected operation to reject the invalid media")
  }
}

///|
fn audio(
  index : Int,
  channels : Int,
  duration : String,
  start : String,
) -> Json {
  {
    "index": index,
    "codec_type": "audio",
    "codec_name": "aac",
    "channels": channels,
    "sample_rate": "48000",
    "start_time": start,
    "duration": duration,
    "tags": { "language": "eng", "title": "Original mix" },
    "disposition": { "default": 1, "forced": 0 },
  }
}

///|
fn video() -> Json {
  {
    "index": 0,
    "codec_type": "video",
    "codec_name": "h264",
    "tags": { "language": "und", "title": "Picture" },
    "disposition": { "default": 1, "attached_pic": 0, "forced": 0 },
  }
}

///|
fn probe(streams : Array[Json]) -> Json {
  {
    "format": {
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "duration": "5",
      "start_time": "0",
    },
    "streams": streams,
    "chapters": [
      { "start_time": "0", "end_time": "5", "tags": { "title": "Episode" } },
    ],
  }
}

///|
test "explicit audio selection retains original mix and names selectable output" {
  let plan = @audio_media.prepare(
    probe([video(), audio(2, 2, "5", "0")]),
    probe([audio(1, 1, "5", "0"), audio(3, 2, "5", "0")]),
    3,
    "fra",
    "Français",
  )
  assert_eq(plan.audio.index, 3)
  assert_eq(plan.audio.channels, 2)
  assert_eq(plan.language, "fra")
  assert_eq(plan.title, "Français")
  assert_eq(plan.codec, "aac")
  assert_eq(plan.rendition_suffix, ".m4a")
  assert_false(plan.is_default)
  assert_eq(plan.dispositions, [["default"], ["default"]])
  assert_eq(plan.media.tracks.map(t => t.index), [0, 2])
}

///|
test "silent media receives its first default soundtrack" {
  let plan = @audio_media.prepare(
    probe([video()]),
    probe([audio(0, 1, "5", "0")]),
    0,
    "und",
    "Commentary",
  )
  assert_true(plan.is_default)
}

///|
test "reject wrong stream timing surround and invalid labels before encoding" {
  let media = probe([video()])
  for
    source in [
      probe([audio(1, 6, "5", "0")]),
      probe([audio(1, 1, "4.9", "0")]),
      probe([audio(1, 1, "5", "0.020")]),
    ] {
    rejects(() => @audio_media.prepare(media, source, 1, "eng", "Commentary"))
  }
  let source = probe([audio(1, 2, "5", "0")])
  for index in [-1, 0, 99] {
    rejects(() => {
      @audio_media.prepare(media, source, index, "eng", "Commentary")
    })
  }
  for language in ["en", "ENg", "en-US", ""] {
    rejects(() => @audio_media.prepare(media, source, 1, language, "Commentary"))
  }
  for title in ["", "  ", "bad\nlabel"] {
    rejects(() => @audio_media.prepare(media, source, 1, "eng", title))
  }
}

///|
test "encoded selected duration cannot be hidden by container duration" {
  let plan = @audio_media.prepare(
    probe([video()]),
    probe([audio(0, 1, "5", "0")]),
    0,
    "eng",
    "Commentary",
  )
  @audio_media.verify_rendition(plan, probe([audio(0, 1, "5", "0")]))
  rejects(() => {
    @audio_media.verify_rendition(plan, probe([audio(0, 1, "2", "0")]))
  })
  rejects(() => {
    @audio_media.verify_rendition(plan, probe([audio(0, 2, "5", "0")]))
  })
  rejects(() => {
    @audio_media.verify_rendition(
      plan,
      probe([audio(0, 1, "5", "0"), audio(1, 1, "5", "0")]),
    )
  })
}

///|
test "verify exact original metadata and new track language channels and default" {
  let original = audio(1, 2, "5", "0")
  let plan = @audio_media.prepare(
    probe([video(), original]),
    probe([audio(0, 1, "5", "0")]),
    0,
    "fra",
    "French",
  )
  let added : Json = {
    "index": 2,
    "codec_type": "audio",
    "codec_name": "aac",
    "channels": 1,
    "sample_rate": "48000",
    "start_time": "0",
    "duration": "5",
    "tags": { "language": "fra", "title": "French" },
    "disposition": { "default": 0 },
  }
  let output = probe([video(), original, added])
  assert_eq(@audio_media.verify_output(plan, output).index, 2)
  guard added is Object(fields) else { fail("object") }
  fields["disposition"] = { "default": 1 }
  rejects(() => @audio_media.verify_output(plan, output))
  fields["disposition"] = { "default": 0 }
  fields["channels"] = 2
  rejects(() => @audio_media.verify_output(plan, output))
  fields["channels"] = 1
  guard original is Object(old) else { fail("object") }
  old["tags"] = { "language": "eng", "title": "Changed mix" }
  rejects(() => @audio_media.verify_output(plan, output))
}

///|
test "Matroska uses lossless FLAC and chapter changes fail verification" {
  let media = probe([video()])
  guard media is Object(fields) else { fail("object") }
  fields["format"] = {
    "format_name": "matroska,webm",
    "duration": "5",
    "start_time": "0",
  }
  let plan = @audio_media.prepare(
    media,
    probe([audio(0, 1, "5", "0")]),
    0,
    "eng",
    "Commentary",
  )
  assert_eq(plan.codec, "flac")
  assert_eq(plan.rendition_suffix, ".flac")
  let added = audio(1, 1, "5", "0")
  guard added is Object(track) else { fail("object") }
  track["codec_name"] = "flac"
  track["tags"] = { "language": "eng", "title": "Commentary" }
  fields["streams"] = [video(), added]
  ignore(@audio_media.verify_output(plan, media))
  fields["chapters"] = [
    { "start_time": "0.1", "end_time": "5", "tags": { "title": "Episode" } },
  ]
  rejects(() => @audio_media.verify_output(plan, media))
}
