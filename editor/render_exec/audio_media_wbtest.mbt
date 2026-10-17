///|
test "audio import encodes only the named track without trimming padding or mixing" {
  let command = compile_audio_rendition(
    "/audio file.mkv", 3, 2, "aac", "/soundtrack.m4a",
  )
  assert_eq(command.executable, "ffmpeg")
  assert_true(command.arguments.contains("0:3"))
  assert_true(command.arguments.contains("160k"))
  assert_false(command.arguments.contains("-shortest"))
  assert_false(command.arguments.contains("-t"))
  assert_false(command.arguments.contains("-af"))
  let flac = compile_audio_rendition(
    "/audio.flac", 0, 1, "flac", "/soundtrack.flac",
  )
  assert_false(flac.arguments.contains("160k"))
}

///|
test "audio attachment preserves sparse indices tags full dispositions and chapters" {
  let command = compile_audio_attachment(
    "/media.mkv",
    "/soundtrack.flac",
    [0, 2, 5],
    [["default"], ["default", "visual_impaired"], ["forced"]],
    "fra",
    "Français",
    false,
    "/output.mkv",
  )
  assert_eq(command.arguments, [
    "-hide_banner", "-v", "error", "-nostdin", "-n", "-threads", "1", "-protocol_whitelist",
    "file,pipe", "-i", "/media.mkv", "-protocol_whitelist", "file,pipe", "-i", "/soundtrack.flac",
    "-map", "0:0", "-map", "0:2", "-map", "0:5", "-map", "1:0", "-map_metadata",
    "0", "-map_chapters", "0", "-c", "copy", "-map_metadata:s:0", "0:s:0", "-disposition:0",
    "default", "-map_metadata:s:1", "0:s:2", "-disposition:1", "default+visual_impaired",
    "-map_metadata:s:2", "0:s:5", "-disposition:2", "forced", "-map_metadata:s:3",
    "-1", "-metadata:s:3", "language=fra", "-metadata:s:3", "title=Français", "-metadata:s:3",
    "handler_name=Français", "-disposition:3", "0", "/output.mkv",
  ])
}
