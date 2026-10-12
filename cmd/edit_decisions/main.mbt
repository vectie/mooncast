///|
async fn read_local(path : String, limit : Int) -> String {
  guard !path.contains("://") && @fs.exists(path) && @fs.kind(path) is Regular else {
    fail("expected an existing local file: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size > 0L && size <= limit.to_int64() else {
    fail("input is empty or too large: " + path)
  }
  @utf8.decode(file.read_exactly_at(size.to_int(), position=0))
}

///|
async fn unused(path : String) -> Unit {
  guard !path.is_empty() && !path.contains("://") && !@fs.exists(path) else {
    fail("output must be a new local file: " + path)
  }
}

///|
fn preview(value : @edl.DraftPreview) -> Unit {
  println(
    value.title +
    " | " +
    value.fps.to_string() +
    " fps NON-DROP FRAME | record origin " +
    value.record_start_timecode,
  )
  println(
    "event\treel\tmedia\tsource frames\trecord frames (relative)\tgap before",
  )
  for cut in value.cuts {
    println(
      cut.event_number.to_string() +
      "\t" +
      cut.reel +
      "\t" +
      cut.media_ref_id +
      "\t" +
      cut.source_in_frame.to_string() +
      "–" +
      cut.source_out_frame.to_string() +
      "\t" +
      cut.start_frame.to_string() +
      "–" +
      cut.end_frame.to_string() +
      "\t" +
      cut.gap_before_frames.to_string(),
    )
  }
  println(
    value.cuts.length().to_string() +
    " cuts; " +
    value.duration_frames.to_string() +
    " frames including " +
    value.gap_frames.to_string() +
    " gap frames; exact timebase " +
    value.ticks_per_second.to_string() +
    " ticks/s",
  )
}

///|
async fn main {
  let args = @env.args()
  let help = "usage:\n  edit_decisions preview PROJECT.json CUT.edl REELS.json\n  edit_decisions import PROJECT.json CUT.edl REELS.json OUTPUT_PREFIX\n  edit_decisions export PROJECT.json REELS.json OUTPUT.edl [TITLE]\n\nCreates a new video-only native draft. Source project is never overwritten.\nCMX3600: one V track, cuts only, explicit integer 1–60 fps, NDF.\nSee docs/edit-decision-interchange.md for reel mapping and supported limits."
  if args.length() == 2 && (args[1] == "--help" || args[1] == "help") {
    println(help)
    return
  }
  guard args.length() >= 5 else { fail(help) }
  let project = @domain.snapshot_from_json(read_local(args[2], 16777216))
  match args[1] {
    "preview" | "import" => {
      guard (args[1] == "preview" && args.length() == 5) ||
        (args[1] == "import" && args.length() == 6) else {
        fail(help)
      }
      let mapping = @edl.read_reel_map(read_local(args[4], 2097152))
      let result = @edl.import_edl(
        project,
        read_local(args[3], 2097152),
        mapping,
      )
      if args[1] == "import" {
        let output = args[5] + ".project.json"
        let report = args[5] + ".preview.json"
        unused(output)
        unused(report)
        @fs.write_file(
          output,
          @utf8.encode(result.project.to_json().stringify(indent=2) + "\n"),
          create_mode=CreateNew,
        )
        @fs.write_file(
          report,
          @utf8.encode(result.preview.to_json().stringify(indent=2) + "\n"),
          create_mode=CreateNew,
        )
        println("Created " + output + " and " + report)
      }
      preview(result.preview)
    }
    "export" => {
      guard args.length() == 5 || args.length() == 6 else { fail(help) }
      let mapping = @edl.read_reel_map(read_local(args[3], 2097152))
      let title = if args.length() == 6 { args[5] } else { "MoonCast cut" }
      let output = @edl.export_edl(project, mapping, title)
      unused(args[4])
      @fs.write_file(args[4], @utf8.encode(output), create_mode=CreateNew)
      println("Created " + args[4])
    }
    _ => fail(help)
  }
}
