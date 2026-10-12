///|
priv struct Binding {
  media_ref_id : String
  file : String
} derive(FromJson)

///|
priv struct ChapterMap {
  contract : String
  bindings : Array[Binding]
} derive(FromJson)

///|
async fn read_local(path : String, limit : Int) -> Bytes {
  guard !path.is_empty() &&
    !path.contains("://") &&
    @fs.exists(path) &&
    @fs.kind(path) is Regular else {
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
fn parent_path(path : String) -> String {
  let parts = path.split("/").map(p => p.to_string()).to_array()
  if parts.length() <= 1 {
    return "."
  }
  parts.pop() |> ignore
  let parent = parts.join("/")
  if parent.is_empty() {
    "/"
  } else {
    parent
  }
}

///|
async fn main {
  let help = "usage:\n  chapter_conform preview PROJECT.json CHAPTER_MAP.json\n  chapter_conform export PROJECT.json CHAPTER_MAP.json NEW_PREFIX\n\nCarry source chapter titles through contiguous, normal-speed video cuts.\nSource draft paths resolve from the map directory. No media is opened.\nWrites .chapters.json, .chapters.vtt, .ffmetadata and .conform.json.\nSee docs/chapter-conforming.md."
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
  let mapping : ChapterMap = @json.from_json(
    @json.parse(@utf8.decode(map_bytes)),
  )
  guard mapping.contract == "mooncast.chapter-source-map.v1" &&
    !mapping.bindings.is_empty() &&
    mapping.bindings.length() <= 64 else {
    fail("expected mooncast.chapter-source-map.v1 with 1–64 bindings")
  }
  let parent = parent_path(@fs.realpath(args[3]))
  let sources : Array[@conform.SourceChapters] = []
  let receipts : Array[Json] = []
  let mut total_bytes = 0
  for binding in mapping.bindings {
    guard !binding.file.is_empty() && !binding.file.contains("://") else {
      fail("source draft file must be a nonempty local path")
    }
    let path = if binding.file.has_prefix("/") {
      binding.file
    } else {
      parent + "/" + binding.file
    }
    let bytes = read_local(path, 2097152)
    total_bytes += bytes.length()
    guard total_bytes <= 16777216 else {
      fail("combined chapter drafts exceed 16 MiB")
    }
    let draft = @chapters.read_draft(@utf8.decode(bytes))
    sources.push({ media_ref_id: binding.media_ref_id, draft, })
    receipts.push({
      "media_ref_id": binding.media_ref_id,
      "file": @fs.realpath(path),
      "sha256": digest(bytes),
      "source_project_id": draft.project_id,
      "source_project_revision": draft.project_revision,
      "source_timeline_id": draft.timeline_id,
      "source_timeline_revision": draft.timeline_revision,
    })
  }
  let result = @conform.conform(project, sources)
  // Preview checks all export formats too, without writing anything.
  let vtt = result.draft.webvtt()
  let metadata = result.draft.ffmetadata()
  let report : Json = {
    "contract": "mooncast.chapter-conform-export.v1",
    "source_project": @fs.realpath(args[2]),
    "source_project_sha256": digest(project_bytes),
    "source_map": @fs.realpath(args[3]),
    "source_map_sha256": digest(map_bytes),
    "source_chapters": receipts,
    "result": result.to_json(),
    "media_validation": "metadata only; source binding is operator selected, media is not opened or verified",
  }
  let outputs = [
    (".chapters.json", result.draft.to_json().stringify(indent=2) + "\n"),
    (".chapters.vtt", vtt),
    (".ffmetadata", metadata),
    (".conform.json", report.stringify(indent=2) + "\n"),
  ]
  for (_, content) in outputs {
    guard @utf8.encode(content).length() <= 33554432 else {
      fail("chapter conform output exceeds 32 MiB")
    }
  }
  if args[1] == "export" {
    let prefix = args[4]
    guard !prefix.is_empty() &&
      !prefix.contains(":") &&
      !prefix.iter().any(c => c < ' ') else {
      fail("invalid local output prefix")
    }
    let output_parent = @fs.realpath(parent_path(prefix))
    let name = prefix.split("/").last().unwrap().to_string()
    guard !name.is_empty() && name != "." && name != ".." else {
      fail("invalid output filename")
    }
    // Directory entries catch existing files, directories and dangling symlinks.
    let names = @fs.readdir(output_parent, include_hidden=true)
    for (suffix, _) in outputs {
      guard !names.contains(name + suffix) else {
        fail("output exists; choose a fresh prefix")
      }
    }
    for (suffix, content) in outputs {
      @fs.write_file(
        output_parent + "/" + name + suffix,
        @utf8.encode(content),
        create_mode=CreateNew,
      )
    }
    println(
      "Created " +
      prefix +
      ".chapters.json, .chapters.vtt, .ffmetadata and .conform.json",
    )
  }
  for index, marker in result.draft.markers {
    let origin = result.origins[index]
    println(
      marker.marker_id +
      "\t" +
      marker.start_tick.to_string() +
      "–" +
      origin.output_end_tick.to_string() +
      " ticks\t" +
      origin.clip_id +
      " / " +
      origin.media_ref_id +
      " / " +
      origin.source_marker_id +
      "\t" +
      marker.title,
    )
  }
  println(
    result.draft.markers.length().to_string() +
    " chapter segments; " +
    result.source_uses
    .filter(u => u.output_marker_ids.is_empty())
    .length()
    .to_string() +
    " source chapters dropped; " +
    result.source_uses
    .filter(u => u.output_marker_ids.length() > 1)
    .length()
    .to_string() +
    " source chapters split/repeated; review titles against the cut",
  )
}
