///|
async fn main {
  let help = "usage:\n  screening preview MEDIA.mp4 CAPTIONS.json|- CHAPTERS.json|- TITLE\n  screening export MEDIA.mp4 CAPTIONS.json|- CHAPTERS.json|- TITLE NEW_FOLDER\n\nCopy a local H.264/AAC MP4 into an offline player with searchable captions and chapter navigation.\nSee docs/offline-screening.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 6 && args[1] == "preview") ||
    (args.length() == 7 && args[1] == "export") else {
    fail(help)
  }
  let source = local_file(args[2])
  let source_hash = hash_file(source)
  let probe = @process.run_capture(@render.compile_review_probe(source))
  guard probe.exit_code == Some(0) &&
    !probe.timed_out &&
    !probe.output_truncated else {
    fail("local media probe failed: " + @utf8.decode(probe.stderr))
  }
  let probe_json = @json.parse(@utf8.decode(probe.stdout))
  let media = @media.inspect_media(probe_json)
  validate_screening_video(probe_json)
  let caption_bytes = if args[3] == "-" {
    None
  } else {
    Some(read_draft(args[3]))
  }
  let chapter_bytes = if args[4] == "-" {
    None
  } else {
    Some(read_draft(args[4]))
  }
  let captions = caption_bytes.map(b => @captions.read_draft(@utf8.decode(b)))
  let chapters = chapter_bytes.map(b => @chapters.read_draft(@utf8.decode(b)))
  let plan = @screen.plan(media, args[5], captions?, chapters?)
  let source_name = source.split("/").last().unwrap().to_owned()
  let identity : Json = {
    "source_name": source_name,
    "source_sha256": source_hash,
    "caption_sha256": optional_digest(caption_bytes),
    "chapter_sha256": optional_digest(chapter_bytes),
    "sidecar_binding": "operator-selected; matching duration is not proof of media identity",
  }
  let preview : Json = {
    "contract": "mooncast.screening-preview.v1",
    "source": identity,
    "plan": plan,
  }
  if args[1] == "preview" {
    println(preview.stringify(indent=2))
    return
  }
  let folder = new_folder(args[6])
  let html = plan.html(source_name, source_hash)
  // Construct and validate all derivatives before touching the output folder.
  let vtt = captions.map(d => d.vtt())
  let chapter_vtt = chapters.map(d => d.webvtt())
  @fs.mkdir(folder, recursive=false)
  write_new(folder + "/plan.json", preview.stringify(indent=2) + "\n")
  copy_media(source, folder + "/media.mp4", source_hash)
  let artifacts : Array[Json] = []
  artifacts.push({
    "path": "media.mp4",
    "sha256": hash_file(folder + "/media.mp4"),
  })
  if caption_bytes is Some(bytes) {
    @fs.write_file(folder + "/captions.json", bytes, create_mode=CreateNew)
    artifacts.push({
      "path": "captions.json",
      "sha256": optional_digest(caption_bytes),
    })
  }
  if chapter_bytes is Some(bytes) {
    @fs.write_file(folder + "/chapters.json", bytes, create_mode=CreateNew)
    artifacts.push({
      "path": "chapters.json",
      "sha256": optional_digest(chapter_bytes),
    })
  }
  if vtt is Some(text) {
    write_new(folder + "/captions.vtt", text)
    artifacts.push({ "path": "captions.vtt", "sha256": digest(text) })
  }
  if chapter_vtt is Some(text) {
    write_new(folder + "/chapters.vtt", text)
    artifacts.push({ "path": "chapters.vtt", "sha256": digest(text) })
  }
  guard hash_file(source) == source_hash &&
    hash_file(folder + "/media.mp4") == source_hash else {
    fail("source or copied media changed; partial folder retained")
  }
  if caption_bytes is Some(bytes) {
    guard read_draft(args[3]) == bytes else {
      fail("caption draft changed; partial folder retained")
    }
  }
  if chapter_bytes is Some(bytes) {
    guard read_draft(args[4]) == bytes else {
      fail("chapter draft changed; partial folder retained")
    }
  }
  write_new(folder + "/index.html", html)
  artifacts.push({ "path": "index.html", "sha256": digest(html) })
  artifacts.push({
    "path": "plan.json",
    "sha256": digest(preview.stringify(indent=2) + "\n"),
  })
  let result : Json = {
    "contract": "mooncast.screening-result.v1",
    "source": identity,
    "plan": plan,
    "artifacts": artifacts,
    "index": "index.html",
    "client_acceptance": false,
  }
  write_new(folder + "/result.json", result.stringify(indent=2) + "\n")
  println(result.stringify(indent=2))
}

///|
fn digest(text : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))
}

///|
fn optional_digest(bytes : Bytes?) -> Json {
  match bytes {
    Some(value) =>
      Json::string(@crypto.bytes_to_hex_string(@crypto.sha256(value)))
    None => Json::null()
  }
}

///|
fn validate_screening_video(probe : Json) -> Unit raise {
  guard probe is { "streams": Array(streams), .. } else {
    fail("missing streams")
  }
  for stream in streams {
    if stream is { "codec_type": String("video"), .. } {
      guard stream
        is {
          "pix_fmt": String("yuv420p"),
          "width": Number(w, ..),
          "height": Number(h, ..),
          ..
        } &&
        w >= 16.0 &&
        w <= 4096.0 &&
        h >= 16.0 &&
        h <= 4096.0 else {
        fail(
          "screening requires 8-bit yuv420p video between 16 and 4096 pixels",
        )
      }
      if stream is { "start_time": String(start), .. } {
        guard @string.parse_double(start).abs() <= 0.001 else {
          fail("video stream must start at zero")
        }
      }
      if stream is { "color_transfer": String(transfer), .. } {
        guard transfer != "smpte2084" && transfer != "arib-std-b67" else {
          fail("HDR requires a separate color-managed review workflow")
        }
      }
    }
  }
}
