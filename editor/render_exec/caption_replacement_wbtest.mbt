///|
test "caption replacement maps sparse source streams metadata and every disposition" {
  let command = compile_caption_replacement(
    [0, 2, 5, 6],
    2,
    ".mp4",
    [["default"], ["default"], ["default", "forced", "hearing_impaired"], []],
    "/original.mp4",
    "/new.srt",
    "/revised.mp4",
  )
  let args = command.arguments
  assert_eq(command.executable, "ffmpeg")
  assert_eq(command.timeout_ms, 300000)
  assert_eq(args, [
    "-hide_banner", "-v", "error", "-nostdin", "-n", "-protocol_whitelist", "file,pipe",
    "-i", "/original.mp4", "-protocol_whitelist", "file,pipe", "-f", "srt", "-i",
    "/new.srt", "-map", "0:0", "-map", "0:2", "-map", "1:0", "-map", "0:6", "-map_metadata",
    "0", "-map_chapters", "0", "-c", "copy", "-c:2", "mov_text", "-map_metadata:s:0",
    "0:s:0", "-map_metadata:s:1", "0:s:2", "-map_metadata:s:2", "0:s:5", "-map_metadata:s:3",
    "0:s:6", "-disposition:0", "default", "-disposition:1", "default", "-disposition:2",
    "default+forced+hearing_impaired", "-disposition:3", "0", "/revised.mp4",
  ])
  let mkv = compile_caption_replacement(
    [2, 5],
    1,
    ".mkv",
    [[], []],
    "/in.mkv",
    "/new.srt",
    "/out.mkv",
  )
  assert_true(mkv.arguments.contains("srt"))
  assert_false(mkv.arguments.contains("0:5"))
}
