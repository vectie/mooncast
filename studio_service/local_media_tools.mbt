///|
fn bundled_media_tool(name : String) -> String {
  match @env.get_env_var("LEPUSA_APP_DIR") {
    Some(app_dir) => app_dir + "/MacOS/.tools/ffmpeg/darwin_arm64/" + name
    None => ".tools/ffmpeg/darwin_arm64/" + name
  }
}

///|
let bundled_ffmpeg : String = bundled_media_tool("ffmpeg")

///|
let bundled_ffprobe : String = bundled_media_tool("ffprobe")
