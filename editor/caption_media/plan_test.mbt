///|
fn probe() -> Json {
  {
    "format": {
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "start_time": "0.000000",
      "duration": "6.000000",
    },
    "chapters": [],
    "streams": [
      {
        "index": 0,
        "codec_type": "video",
        "codec_name": "h264",
        "disposition": { "attached_pic": 0, "default": 1 },
      },
      {
        "index": 2,
        "codec_type": "audio",
        "codec_name": "aac",
        "tags": { "language": "fra" },
        "disposition": { "default": 1 },
      },
      {
        "index": 5,
        "codec_type": "subtitle",
        "codec_name": "mov_text",
        "tags": { "language": "zho", "handler_name": "中文" },
        "disposition": { "default": 0 },
      },
    ],
  }
}

///|
fn draft() -> @captions.CaptionDraft {
  {
    contract: "mooncast.caption-draft.v1",
    source_file: "synthetic.srt",
    duration_ms: 6000,
    cues: [
      { start_ms: 250, end_ms: 1500, text: "Café & 🌱\nNext line", },
      { start_ms: 3000, end_ms: 5500, text: "Second cue.", },
    ],
  }
}

///|
test "inspect explicit sparse stream indices and language metadata" {
  let media = @caption_media.inspect_media(probe())
  assert_eq(media.duration_ms, 6000)
  assert_eq(media.tracks.map(t => t.index), [0, 2, 5])
  let track = @caption_media.select_track(media, 5)
  assert_eq(track.language, "zho")
  assert_eq(track.title, "中文")
  assert_true((try? @caption_media.select_track(media, 0)) is Err(_))
  assert_true((try? @caption_media.select_track(media, 1)) is Err(_))
}

///|
test "attach maps every existing track and only encodes the new subtitle" {
  let media = @caption_media.inspect_media(probe())
  @caption_media.validate_attachment(
    media,
    draft(),
    "eng",
    "English & captions",
  )
  let args = @caption_media.attach_arguments(
    media, "/clip.mp4", "/captions.srt", "eng", "English", "/out.mp4",
  )
  assert_eq(args, [
    "-hide_banner", "-v", "error", "-nostdin", "-n", "-protocol_whitelist", "file,pipe",
    "-i", "/clip.mp4", "-protocol_whitelist", "file,pipe", "-f", "srt", "-i", "/captions.srt",
    "-map", "0:0", "-map", "0:2", "-map", "0:5", "-map", "1:0", "-map_metadata",
    "0", "-map_chapters", "0", "-c", "copy", "-c:3", "mov_text", "-metadata:s:3",
    "language=eng", "-metadata:s:3", "title=English", "-metadata:s:3", "handler_name=English",
    "-disposition:3", "0", "/out.mp4",
  ])
  assert_true(@caption_media.extract_arguments("/clip.mp4", 5).contains("0:5"))
}

///|
test "refuse duration mismatch overlap and malformed labels" {
  let media = @caption_media.inspect_media(probe())
  assert_true(
    (try? @caption_media.validate_attachment(
      media,
      { ..draft(), duration_ms: 7000, },
      "eng",
      "English",
    ))
    is Err(_),
  )
  assert_true(
    (try? @caption_media.validate_attachment(media, draft(), "en", "English"))
    is Err(_),
  )
  assert_true(
    (try? @caption_media.validate_attachment(media, draft(), "ENG", "English"))
    is Err(_),
  )
  assert_true(
    (try? @caption_media.validate_attachment(
      media,
      draft(),
      "eng",
      "bad\ntitle",
    ))
    is Err(_),
  )
  let overlapping = {
    ..draft(),
    cues: [
      { start_ms: 100, end_ms: 2000, text: "First", },
      { start_ms: 1000, end_ms: 3000, text: "Second", },
    ],
  }
  assert_true(
    (try? @caption_media.validate_attachment(
      media, overlapping, "eng", "English",
    ))
    is Err(_),
  )
  @caption_media.validate_attachment(
    media,
    {
      ..draft(),
      cues: [
        { start_ms: 100, end_ms: 2000, text: "First", },
        { start_ms: 2000, end_ms: 3000, text: "Second", },
      ],
    },
    "und",
    "Unknown",
  )
}

///|
test "retained stream and appended caption verification" {
  let before = @caption_media.inspect_media(probe())
  let tracks = before.tracks.copy()
  tracks.push({
    index: 6,
    kind: "subtitle",
    codec: "mov_text",
    language: "eng",
    title: "English",
    is_default: false,
    forced: false,
  })
  let after = { ..before, tracks, }
  let selected = @caption_media.verify_attachment(
    before, after, "eng", "English",
  )
  assert_eq(selected.index, 6)
  assert_true(
    (try? @caption_media.verify_attachment(before, after, "fra", "English"))
    is Err(_),
  )
  assert_true(
    (try? @caption_media.verify_attachment(before, before, "eng", "English"))
    is Err(_),
  )
  let changed = tracks.copy()
  changed[1] = { ..changed[1], language: "eng", }
  assert_true(
    (try? @caption_media.verify_attachment(
      before,
      { ..after, tracks: changed, },
      "eng",
      "English",
    ))
    is Err(_),
  )
}

///|
test "matroska text extraction and image-subtitle refusal" {
  let base = @caption_media.inspect_media(probe())
  let tracks = base.tracks.copy()
  tracks[2] = { ..tracks[2], codec: "hdmv_pgs_subtitle", }
  assert_true(
    (try? @caption_media.select_track({ ..base, tracks, }, 5)) is Err(_),
  )
  tracks[2] = { ..tracks[2], codec: "subrip", }
  assert_eq(
    @caption_media.select_track({ ..base, suffix: ".mkv", tracks, }, 5).codec,
    "subrip",
  )
  assert_true(
    @caption_media.attach_arguments(
      { ..base, suffix: ".mkv", },
      "/a.mkv",
      "/a.srt",
      "eng",
      "English",
      "/b.mkv",
    ).contains("srt"),
  )
}

///|
test "media inspection rejects shifted missing and unsupported stream profiles" {
  let malformed : Json = {}
  assert_true((try? @caption_media.inspect_media(malformed)) is Err(_))
  let shifted = probe()
  guard shifted is Object(fields)
  fields["format"] = {
    "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
    "start_time": "1.0",
    "duration": "6.0",
  }
  assert_true((try? @caption_media.inspect_media(shifted)) is Err(_))
  let attachment = probe()
  guard attachment is { "streams": Array(streams), .. }
  streams.push({ "index": 6, "codec_type": "attachment", "codec_name": "ttf" })
  assert_true((try? @caption_media.inspect_media(attachment)) is Err(_))
}

///|
test "output verification rejects a changed chapter title or boundary" {
  let media = @caption_media.inspect_media(probe())
  let chapter : Json = {
    "start_time": "0.0",
    "end_time": "6.0",
    "tags": { "title": "Original" },
  }
  let before = { ..media, chapters: [chapter], }
  let tracks = before.tracks.copy()
  tracks.push({
    index: 6,
    kind: "subtitle",
    codec: "mov_text",
    language: "eng",
    title: "English",
    is_default: false,
    forced: false,
  })
  let good = { ..before, tracks, }
  ignore(@caption_media.verify_attachment(before, good, "eng", "English"))
  let wrong_title : Json = {
    "start_time": "0.0",
    "end_time": "6.0",
    "tags": { "title": "Other" },
  }
  assert_true(
    (try? @caption_media.verify_attachment(
      before,
      { ..good, chapters: [wrong_title], },
      "eng",
      "English",
    ))
    is Err(_),
  )
  let wrong_time : Json = {
    "start_time": "0.0",
    "end_time": "5.0",
    "tags": { "title": "Original" },
  }
  assert_true(
    (try? @caption_media.verify_attachment(
      before,
      { ..good, chapters: [wrong_time], },
      "eng",
      "English",
    ))
    is Err(_),
  )
}

///|
test "first MP4 caption default is explicit but never forced" {
  let media = @caption_media.inspect_media(probe())
  let bare = {
    ..media,
    tracks: media.tracks.filter(t => t.kind != "subtitle"),
  }
  assert_true(@caption_media.appended_track_is_default(bare))
  assert_false(@caption_media.appended_track_is_default(media))
  assert_false(
    @caption_media.appended_track_is_default({ ..bare, suffix: ".mkv", }),
  )
  assert_true(
    @caption_media.attach_arguments(
      bare, "/in.mp4", "/a.srt", "und", "Unknown", "/out.mp4",
    ).contains("default"),
  )
  let tracks = bare.tracks.copy()
  tracks.push({
    index: 3,
    kind: "subtitle",
    codec: "mov_text",
    language: "und",
    title: "Unknown",
    is_default: true,
    forced: false,
  })
  ignore(
    @caption_media.verify_attachment(
      bare,
      { ..bare, tracks, },
      "und",
      "Unknown",
    ),
  )
}
