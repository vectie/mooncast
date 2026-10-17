///|
async fn read(path : String, limit : Int) -> Bytes {
  if path.contains("://") || !@fs.exists(path) || @fs.kind(path) != Regular {
    fail("Expected an existing regular local file: " + path)
  }
  let f = @fs.open(path, mode=ReadOnly)
  defer f.close()
  let size = f.size()
  if size <= 0L || size > limit.to_int64() {
    fail("Input is empty or too large: " + path)
  }
  f.read_exactly_at(size.to_int(), position=0)
}

///|
fn digest(bytes : Bytes) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
async fn unused(path : String) -> Unit {
  if path.is_empty() || path.contains("://") {
    fail("Output must be a new local file: " + path)
  }
  let exists = try @fs.kind(path, follow_symlink=false) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => false
    error => raise error
  } noraise {
    _ => true
  }
  if exists {
    fail("Output must be a new local file: " + path)
  }
}

///|
async fn run() -> Unit {
  let help = "Usage:\n  otio_import catalog CUT.otio FPS\n  otio_import preview PROJECT.json CUT.otio MAP.json\n  otio_import import PROJECT.json CUT.otio MAP.json OUTPUT_PREFIX\n\nCreates a separate editable native picture cut with an optional synchronized audio track.\nEDL sidecars contain picture only; keep the native project for audio.\nNo reference URL is opened. See docs/otio-timeline-import.md."
  match @env.args()[1:] {
    ["--help"] | ["help"] => println(help)
    ["catalog", path, fps] =>
      println(
        @otio.catalog_timeline(
          @utf8.decode(read(path, 4194304)),
          @string.parse_int(fps),
        )
        .to_json()
        .stringify(indent=2),
      )
    [mode, project_path, timeline_path, map_path, .. rest] => {
      if (mode != "preview" && mode != "import") ||
        (mode == "preview" && rest.length() != 0) ||
        (mode == "import" && rest.length() != 1) {
        fail(help)
      }
      let project_bytes = read(project_path, 16777216)
      let timeline_bytes = read(timeline_path, 4194304)
      let map_bytes = read(map_path, 2097152)
      let input = @utf8.decode(timeline_bytes)
      let imported = @otio.import_timeline(
        @domain.snapshot_from_json(@utf8.decode(project_bytes)),
        input,
        @otio.read_media_map(@utf8.decode(map_bytes)),
      )
      let report = Json::object({
          "contract": "mooncast.otio-import-report.v2".to_json(),
          "source_project_path": project_path.to_json(),
          "source_project_digest": digest(project_bytes).to_json(),
          "source_otio_path": timeline_path.to_json(),
          "source_otio_digest": digest(timeline_bytes).to_json(),
          "source_map_path": map_path.to_json(),
          "source_map_digest": digest(map_bytes).to_json(),
          "original_otio_text": input.to_json(),
          "catalog": imported.catalog.to_json(),
          "preview": imported.preview.to_json(),
          "audio_preview": imported.audio_preview.to_json(),
          "edl_scope": "Picture-only projection; soundtrack is retained only in the native project and audio_preview. Existing EDL export refuses multitrack projects.".to_json(),
          "notice": "Separate local picture and optional soundtrack draft. Names and metadata remain in this report; global origin is recorded while native time starts at zero. No media was fetched or verified, and no rights, approval, acceptance or publication is inferred.".to_json(),
        }).stringify(indent=2) +
        "\n"
      if mode == "preview" {
        println(report)
        return
      }
      let paths = [
        rest[0] + ".project.json",
        rest[0] + ".import.json",
        rest[0] + ".edl-map.json",
        rest[0] + ".edl",
      ]
      for path in paths {
        unused(path)
      }
      let contents = [
        imported.project.to_json().stringify(indent=2) + "\n",
        report,
        imported.edl_mapping.to_json().stringify(indent=2) + "\n",
        imported.normalized_edl,
      ]
      for i, path in paths {
        @fs.write_file(path, @utf8.encode(contents[i]), create_mode=CreateNew)
      }
      println("Created " + paths.join(", "))
    }
    _ => fail(help)
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("otio_import: \{error}\n")
      exit(1)
    }
  }
}
