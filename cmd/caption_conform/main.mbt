///|
priv struct Binding {
  media_ref_id : String
  format : String
  file : String
} derive(FromJson)

///|
priv struct CaptionMap {
  contract : String
  bindings : Array[Binding]
} derive(FromJson)

///|
async fn read_local(path : String, limit : Int) -> Bytes {
  guard !path.contains("://") && @fs.exists(path) && @fs.kind(path) is Regular else {
    fail("expected an existing local file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= limit.to_int64() else {
    fail("input is empty or too large: " + path)
  }
  file.read_exactly_at(size.to_int(), position=0)
}

///|
fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
async fn main {
  let help = "usage:\n  caption_conform preview PROJECT.json CAPTIONS.json\n  caption_conform export PROJECT.json CAPTIONS.json NEW_OUTPUT_PREFIX\n\nRetimes source captions through a single normal-speed video cut.\nWrites .srt, .vtt, .draft.json and .conform.json; never overwrites files.\nSee docs/caption-conforming.md for source binding formats."
  let args = @env.args()
  if args.length() == 2 && (args[1] == "help" || args[1] == "--help") {
    println(help)
    return
  }
  guard (args.length() == 4 && args[1] == "preview") ||
    (args.length() == 5 && args[1] == "export") else {
    fail(help)
  }
  let project_bytes = read_local(args[2], 16777216)
  let project = @domain.snapshot_from_json(@utf8.decode(project_bytes))
  let map_bytes = read_local(args[3], 2097152)
  let mapping : CaptionMap = @json.from_json(
    @json.parse(@utf8.decode(map_bytes)),
  )
  guard mapping.contract == "mooncast.caption-source-map.v1" &&
    !mapping.bindings.is_empty() &&
    mapping.bindings.length() <= 64 else {
    fail("expected mooncast.caption-source-map.v1 with 1–64 bindings")
  }
  let sources : Array[@conform.SourceCaptions] = []
  let receipts : Array[Json] = []
  let mut total_bytes = 0
  for binding in mapping.bindings {
    let duration = @conform.media_duration_ms(project, binding.media_ref_id)
    if binding.format == "silent" {
      guard binding.file.is_empty() else {
        fail("silent bindings need an empty file")
      }
      sources.push({ media_ref_id: binding.media_ref_id, draft: None, })
      continue
    }
    let mime = match binding.format {
      "draft" | "whisper-json" => "application/json"
      "srt" => "application/x-subrip"
      "vtt" => "text/vtt"
      "whisper-tsv" => "text/tab-separated-values"
      "audacity" => "text/plain"
      _ => fail("unknown caption format: " + binding.format)
    }
    let bytes = read_local(binding.file, 2097152)
    total_bytes += bytes.length()
    guard total_bytes <= 16777216 else {
      fail("combined transcript inputs exceed 16 MiB")
    }
    let draft = if binding.format == "draft" {
      let draft = @captions.read_draft(@utf8.decode(bytes))
      { ..draft, source_file: binding.file, }
    } else {
      @captions.import_draft(bytes, mime, binding.file, duration)
    }
    sources.push({ media_ref_id: binding.media_ref_id, draft: Some(draft), })
    receipts.push({
      "media_ref_id": binding.media_ref_id,
      "file": binding.file,
      "format": binding.format,
      "sha256": digest(bytes),
    })
  }
  let result = @conform.conform(project, sources)
  // Validate complete deliverables before creating any output.
  let srt = result.draft.srt()
  let vtt = result.draft.vtt()
  if args[1] == "export" {
    let prefix = args[4]
    guard !prefix.is_empty() && !prefix.contains("://") else {
      fail("output prefix must be a nonempty local path")
    }
    let report : Json = {
      "contract": "mooncast.caption-conform-export.v1",
      "source_project": args[2],
      "source_project_sha256": digest(project_bytes),
      "source_map": args[3],
      "source_map_sha256": digest(map_bytes),
      "transcripts": receipts,
      "result": result.to_json(),
      "publication_authority": false,
    }
    let outputs = [
      (".srt", srt),
      (".vtt", vtt),
      (".draft.json", result.draft.to_json().stringify(indent=2) + "\n"),
      (".conform.json", report.stringify(indent=2) + "\n"),
    ]
    for (suffix, _) in outputs {
      guard !@fs.exists(prefix + suffix) else {
        fail("output exists; choose a new prefix: " + prefix + suffix)
      }
    }
    for (suffix, content) in outputs {
      @fs.write_file(
        prefix + suffix,
        @utf8.encode(content),
        create_mode=CreateNew,
      )
    }
    println("Created " + prefix + ".srt, .vtt, .draft.json and .conform.json")
  }
  for index, cue in result.draft.cues {
    let origin = result.origins[index]
    println(
      (index + 1).to_string() +
      "\t" +
      cue.start_ms.to_string() +
      "–" +
      cue.end_ms.to_string() +
      " ms\t" +
      origin.clip_id +
      " / " +
      origin.media_ref_id +
      " cue " +
      origin.source_cue.to_string() +
      (if origin.clipped_at_cut { " [clipped: review words]" } else { "" }) +
      "\t" +
      cue.text.replace_all(old="\n", new=" / "),
    )
  }
  println(
    result.draft.cues.length().to_string() +
    " captions, " +
    result.draft.duration_ms.to_string() +
    " ms timeline; " +
    result.origins.filter(o => o.clipped_at_cut).length().to_string() +
    " clipped cues need word review",
  )
}
