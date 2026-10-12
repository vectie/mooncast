///|
async fn main {
  let help = "usage:\n  review_sheet preview MEDIA uniform COUNT CAPTIONS.json|- TITLE\n  review_sheet export MEDIA uniform COUNT CAPTIONS.json|- TITLE NEW_FOLDER\n  review_sheet preview MEDIA chapters CHAPTERS.json CAPTIONS.json|- TITLE\n  review_sheet export MEDIA chapters CHAPTERS.json CAPTIONS.json|- TITLE NEW_FOLDER\n\nCreate an offline printable contact sheet from actual local MP4/MKV frames.\nUse 1–120 samples or editable chapter drafts. Captions are optional.\nSee docs/visual-review-sheet.md."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 7 && args[1] == "preview") ||
    (args.length() == 8 && args[1] == "export") else {
    fail(help)
  }
  guard args[3] == "uniform" || args[3] == "chapters" else { fail(help) }
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
  let video = media.tracks.filter(t => t.kind == "video")[0]
  validate_video(probe_json, video.index)
  let caption_bytes = if args[5] == "-" {
    None
  } else {
    Some(read_draft(args[5]))
  }
  let captions = caption_bytes.map(b => @captions.read_draft(@utf8.decode(b)))
  let chapter_bytes = if args[3] == "chapters" {
    Some(read_draft(args[4]))
  } else {
    None
  }
  let sheet = if chapter_bytes is Some(bytes) {
    @sheet.by_chapters(
      media.duration_ms,
      @chapters.read_draft(@utf8.decode(bytes)),
      args[6],
      captions?,
    )
  } else {
    @sheet.uniform(
      media.duration_ms,
      @string.parse_int(args[4]),
      args[6],
      captions?,
    )
  }
  let source_name = source.split("/").last().unwrap().to_string()
  let identity : Json = {
    "source_name": source_name,
    "source_sha256": source_hash,
    "video_stream_index": video.index,
    "caption_sha256": optional_digest(caption_bytes),
    "chapter_sha256": optional_digest(chapter_bytes),
    "sidecar_binding": "operator-selected; matching duration is not proof of media identity",
  }
  let preview : Json = {
    "contract": "mooncast.review-sheet-preview.v1",
    "source": identity,
    "plan": sheet,
  }
  if args[1] == "preview" {
    println(preview.stringify(indent=2))
    return
  }
  let folder = new_folder(args[7])
  // Finish semantic checks and HTML construction before creating output.
  let html = sheet.html(source_name, source_hash)
  @fs.mkdir(folder, recursive=false)
  @fs.mkdir(folder + "/frames", recursive=false)
  write_new(folder + "/plan.json", preview.stringify(indent=2) + "\n")
  if caption_bytes is Some(bytes) {
    @fs.write_file(folder + "/captions.json", bytes, create_mode=CreateNew)
  }
  if chapter_bytes is Some(bytes) {
    @fs.write_file(folder + "/chapters.json", bytes, create_mode=CreateNew)
  }
  let frames : Array[Json] = []
  for card in sheet.cards {
    let command = @render.compile_review_frame(
      source,
      video.index,
      card.requested_ms,
      folder + "/" + card.image,
    )
    let result = @process.run_capture(command)
    write_new(
      folder + "/frame-" + card.number.to_string() + ".log",
      @utf8.decode(result.stderr),
    )
    guard result.exit_code == Some(0) &&
      !result.timed_out &&
      !result.output_truncated else {
      fail(
        "frame extraction failed; partial folder retained: " +
        @utf8.decode(result.stderr),
      )
    }
    guard @fs.exists(folder + "/" + card.image) else {
      fail(
        "no video frame at requested time " +
        @sheet.time(card.requested_ms) +
        "; the container may outlast its video; partial folder retained",
      )
    }
    let bytes = read_draft(folder + "/" + card.image)
    // PNG signature plus 640x360 IHDR; a successful encoder can still emit no frame.
    guard bytes.length() > 32 &&
      bytes[0:8] == b"\x89PNG\r\n\x1a\n" &&
      bytes[12:16] == b"IHDR" &&
      bytes[16:24] == b"\x00\x00\x02\x80\x00\x00\x01\x68" else {
      fail("encoder did not produce a 640x360 PNG; partial folder retained")
    }
    frames.push({
      "image": card.image,
      "requested_ms": card.requested_ms,
      "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
      "bytes": bytes.length(),
    })
  }
  guard hash_file(source) == source_hash else {
    fail("source changed during export; partial folder retained")
  }
  if caption_bytes is Some(bytes) {
    guard read_draft(args[5]) == bytes else {
      fail("caption draft changed during export; partial folder retained")
    }
  }
  if chapter_bytes is Some(bytes) {
    guard read_draft(args[4]) == bytes else {
      fail("chapter draft changed during export; partial folder retained")
    }
  }
  write_new(folder + "/index.html", html)
  let receipt : Json = {
    "contract": "mooncast.review-sheet-result.v1",
    "source": identity,
    "plan": sheet,
    "frames": frames,
    "index": "index.html",
    "index_sha256": @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(html)),
    ),
    "client_acceptance": false,
  }
  // Completion receipt is last. A partial folder has no successful result.
  write_new(folder + "/result.json", receipt.stringify(indent=2) + "\n")
  println(receipt.stringify(indent=2))
}

///|
fn validate_video(probe : Json, index : Int) -> Unit raise {
  guard probe is { "streams": Array(streams), .. } else {
    fail("missing streams")
  }
  for stream in streams {
    if stream is { "index": Number(i, ..), .. } && i == index.to_double() {
      guard stream is { "width": Number(w, ..), "height": Number(h, ..), .. } &&
        w >= 16.0 &&
        w <= 8192.0 &&
        h >= 16.0 &&
        h <= 8192.0 else {
        fail("video dimensions must be between 16 and 8192 pixels")
      }
      if stream is { "sample_aspect_ratio": String(sar), .. } {
        guard sar == "1:1" || sar == "N/A" else {
          fail("review sampling currently requires square pixels")
        }
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
      return
    }
  }
  fail("video stream missing from probe")
}

///|
fn optional_digest(bytes : Bytes?) -> Json {
  match bytes {
    Some(value) =>
      Json::string(@crypto.bytes_to_hex_string(@crypto.sha256(value)))
    None => Json::null()
  }
}
