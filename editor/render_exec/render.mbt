///|
pub(all) struct ResolvedMedia {
  digest : String
  path : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RenderInvocation {
  contract : String
  executable : String
  arguments : Array[String]
  plan_digest : String
  output_path : String
  timeout_ms : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RenderReceipt {
  contract : String
  plan_digest : String
  output_path : String
  exit_code : Int
  stderr_tail : String
  timed_out : Bool
  output_truncated : Bool
  succeeded : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RenderEncoding {
  container : String
  video_codec : String
  audio_codec : String
  pixel_format : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn delivery_encoding(
  container : String,
  video_codec : String,
  audio_codec : String,
) -> RenderEncoding raise {
  let supported = (
      container == "mp4" && video_codec == "h264" && audio_codec == "aac"
    ) ||
    (container == "webm" && video_codec == "vp9" && audio_codec == "opus") ||
    (
      container == "mkv" &&
      (
        (video_codec == "h264" && audio_codec == "aac") ||
        (video_codec == "vp9" && audio_codec == "opus")
      )
    )
  guard supported else { fail("unsupported render encoding") }
  { container, video_codec, audio_codec, pixel_format: "yuv420p" }
}

///|
fn resolve_path(media : Array[ResolvedMedia], digest : String) -> String raise {
  for value in media {
    if value.digest == digest {
      return value.path
    }
  }
  fail("render media digest was not resolved")
}

///|
fn ff_filter_path(value : String) -> String {
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old=":", new="\\:")
  .replace_all(old="'", new="\\'")
}

///|
fn seconds(tick : Int, ticks_per_second : Int) -> String {
  (tick.to_double() / ticks_per_second.to_double()).to_string()
}

///|
fn speed_rate(clip : @plan.FrozenClip) -> Double {
  for effect in clip.effects {
    if effect.enabled &&
      effect.kind == "speed-ramp" &&
      effect.parameters.speed_points.length() >= 2 {
      let points = effect.parameters.speed_points
      let first = points[0]
      let last = points[points.length() - 1]
      return (last.source_tick - first.source_tick).to_double() /
        (last.timeline_tick - first.timeline_tick).to_double()
    }
  }
  1.0
}

///|
fn blend_mode(clip : @plan.FrozenClip) -> String {
  for effect in clip.effects {
    if effect.enabled &&
      effect.kind == "blend" &&
      effect.parameters.blend_mode is Some(mode) {
      return if mode == "add" { "addition" } else { mode }
    }
  }
  "normal"
}

///|
fn curve_expression(
  points : Array[@domain.KeyframePoint],
  clip_start : Int,
  ticks : Int,
  fallback : Double,
) -> String {
  if points.is_empty() {
    return fallback.to_string()
  }
  let mut expression = points[points.length() - 1].value.to_string()
  for offset in 0..<(points.length() - 1) {
    let index = points.length() - 2 - offset
    let left = points[index]
    let right = points[index + 1]
    let left_time = seconds(clip_start + left.tick, ticks)
    let right_time = seconds(clip_start + right.tick, ticks)
    let segment = if left.interpolation == "hold" {
      left.value.to_string()
    } else {
      left.value.to_string() +
      "+(" +
      (right.value - left.value).to_string() +
      ")*(t-" +
      left_time +
      ")/(" +
      right_time +
      "-" +
      left_time +
      ")"
    }
    expression = "if(lt(t," +
      right_time +
      ")," +
      segment +
      "," +
      expression +
      ")"
  }
  "if(lt(t," +
  seconds(clip_start + points[0].tick, ticks) +
  ")," +
  points[0].value.to_string() +
  "," +
  expression +
  ")"
}

///|
fn automation_expression(
  points : Array[@domain.AutomationPoint],
  ticks : Int,
  fallback : Double,
) -> String {
  let converted = points.map(point => @domain.KeyframePoint::{
    tick: point.tick,
    value: point.value,
    interpolation: point.interpolation,
  })
  curve_expression(converted, 0, ticks, fallback)
}

///|
fn bus_expression(
  bus_id : String?,
  buses : Array[@domain.AudioBus],
  ticks : Int,
) -> String {
  guard bus_id is Some(id) else { return "0" }
  let any_solo = buses.any(bus => bus.solo)
  for bus in buses {
    if bus.bus_id == id {
      if bus.muted || (any_solo && !bus.solo) {
        return "-60"
      }
      return automation_expression(bus.automation.gain_db, ticks, bus.gain_db)
    }
  }
  "0"
}

///|
fn visual_filter(
  index : Int,
  clip : @plan.FrozenClip,
  transitions : Array[@plan.FrozenTransition],
  ticks : Int,
  width : Int,
  height : Int,
) -> String raise {
  let start = seconds(clip.source_in_tick, ticks)
  let offset = seconds(clip.start_tick, ticks)
  let rate = speed_rate(clip)
  let filters : Array[String] = [
    "trim=start=" + start + ":end=" + seconds(clip.source_out_tick, ticks),
    "setpts=(PTS-STARTPTS)/" + rate.to_string() + "+" + offset + "/TB",
    "scale=" +
    width.to_string() +
    ":" +
    height.to_string() +
    ":force_original_aspect_ratio=decrease",
    "pad=" +
    width.to_string() +
    ":" +
    height.to_string() +
    ":(ow-iw)/2:(oh-ih)/2:color=black@0",
    "format=rgba",
    "eq=brightness=" +
    clip.settings.brightness.to_string() +
    ":contrast=" +
    clip.settings.contrast.to_string() +
    ":saturation=" +
    clip.settings.saturation.to_string() +
    ":gamma=" +
    clip.settings.gamma.to_string(),
  ]
  let mut opacity = clip.settings.opacity
  for effect in clip.effects {
    if effect.enabled {
      match effect.kind {
        "crop" =>
          if effect.parameters.crop is Some(crop) {
            filters.push(
              "crop=iw*(1-" +
              crop.left.to_string() +
              "-" +
              crop.right.to_string() +
              "):ih*(1-" +
              crop.top.to_string() +
              "-" +
              crop.bottom.to_string() +
              "):iw*" +
              crop.left.to_string() +
              ":ih*" +
              crop.top.to_string(),
            )
            filters.push(
              "scale=" + width.to_string() + ":" + height.to_string(),
            )
          }
        "transform" =>
          if effect.parameters.transform is Some(transform) {
            filters.push(
              "scale=iw*" +
              transform.scale.to_string() +
              ":ih*" +
              transform.scale.to_string(),
            )
            if transform.rotation_degrees != 0.0 {
              filters.push(
                "rotate=" +
                transform.rotation_degrees.to_string() +
                "*PI/180:ow=rotw(iw):oh=roth(ih):c=none",
              )
            }
            filters.push(
              "scale=" +
              width.to_string() +
              ":" +
              height.to_string() +
              ":force_original_aspect_ratio=decrease,pad=" +
              width.to_string() +
              ":" +
              height.to_string() +
              ":(ow-iw)/2:(oh-ih)/2:color=black@0",
            )
          }
        "opacity" =>
          if effect.parameters.opacity is Some(value) {
            opacity = value
          }
        "mask" =>
          if effect.parameters.mask is Some(mask) {
            let inside = if mask.shape == "ellipse" {
              "lte(pow((X/W-" +
              (mask.x + mask.width / 2.0).to_string() +
              ")/(" +
              (mask.width / 2.0).to_string() +
              "),2)+pow((Y/H-" +
              (mask.y + mask.height / 2.0).to_string() +
              ")/(" +
              (mask.height / 2.0).to_string() +
              "),2),1)"
            } else {
              "between(X,W*" +
              mask.x.to_string() +
              ",W*(" +
              mask.x.to_string() +
              "+" +
              mask.width.to_string() +
              "))*between(Y,H*" +
              mask.y.to_string() +
              ",H*(" +
              mask.y.to_string() +
              "+" +
              mask.height.to_string() +
              "))"
            }
            let alpha = if mask.invert {
              "if(" + inside + ",0,255)"
            } else {
              "if(" + inside + ",255,0)"
            }
            filters.push(
              "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='" + alpha + "'",
            )
          }
        _ => ()
      }
    }
  }
  let opacity_curve = curve_expression(
    clip.keyframes.opacity,
    clip.start_tick,
    ticks,
    opacity,
  )
  filters.push("colorchannelmixer=aa='" + opacity_curve + "'")
  for transition in transitions {
    if transition.kind != "cut" && transition.duration_ticks > 0 {
      let transition_start = seconds(transition.range.start_tick, ticks)
      let transition_duration = seconds(transition.range.duration_ticks, ticks)
      if transition.to_clip_id == clip.clip_id {
        if transition.kind == "wipe-left" || transition.kind == "wipe-right" {
          let progress = "max(0,min(1,(T-" +
            transition_start +
            ")/" +
            transition_duration +
            "))"
          let inside = if transition.kind == "wipe-left" {
            "lte(X/W," + progress + ")"
          } else {
            "gte(X/W,1-" + progress + ")"
          }
          filters.push(
            "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(" +
            inside +
            ",alpha(X,Y),0)'",
          )
        } else {
          guard transition.kind == "cross-dissolve" ||
            transition.kind == "fade-through-color" else {
            fail("unsupported render transition")
          }
          filters.push(
            "fade=t=in:st=" +
            transition_start +
            ":d=" +
            transition_duration +
            ":alpha=1",
          )
        }
      }
      if transition.from_clip_id == clip.clip_id {
        filters.push(
          "fade=t=out:st=" +
          transition_start +
          ":d=" +
          transition_duration +
          ":alpha=1",
        )
      }
    }
  }
  "[" +
  index.to_string() +
  ":v]" +
  filters.join(",") +
  "[v" +
  index.to_string() +
  "]"
}

///|
fn audio_filter(
  index : Int,
  clip : @plan.FrozenClip,
  mix : @domain.TrackMix?,
  buses : Array[@domain.AudioBus],
  ticks : Int,
) -> String {
  let start = seconds(clip.source_in_tick, ticks)
  let duration = seconds(clip.duration_ticks, ticks)
  let delay_ms = (clip.start_tick * 1000 / ticks).to_string()
  let rate = speed_rate(clip)
  let tempo = if rate < 0.5 {
    "atempo=0.5,atempo=" + (rate / 0.5).to_string()
  } else if rate > 2.0 {
    "atempo=2.0,atempo=" + (rate / 2.0).to_string()
  } else {
    "atempo=" + rate.to_string()
  }
  let volume = curve_expression(
    clip.keyframes.volume_db,
    clip.start_tick,
    ticks,
    clip.settings.volume_db,
  )
  let bus_gain = bus_expression(clip.audio_bus_id, buses, ticks)
  let track_gain = match mix {
    Some(value) => if value.muted { -60.0 } else { value.volume_db }
    None => 0.0
  }
  let track_pan = match mix {
    Some(value) => value.pan
    None => 0.0
  }
  let pan = "max(-1,min(1,(" +
    curve_expression(
      clip.keyframes.pan,
      clip.start_tick,
      ticks,
      clip.settings.pan,
    ) +
    ")+" +
    track_pan.to_string() +
    "))"
  "[" +
  index.to_string() +
  ":a]atrim=start=" +
  start +
  ":duration=" +
  duration +
  ",asetpts=PTS-STARTPTS,aresample=48000," +
  "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo," +
  tempo +
  ",volume='pow(10,((" +
  volume +
  ")+(" +
  bus_gain +
  ")+" +
  track_gain.to_string() +
  ")/20)':eval=frame" +
  ",aeval=exprs='val(0)*min(1,1-(" +
  pan +
  "))|val(1)*min(1,1+(" +
  pan +
  "))':c=stereo," +
  "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo," +
  "adelay=delays=" +
  delay_ms +
  ":all=1" +
  "[a" +
  index.to_string() +
  "]"
}

///|
/// Compiles argv only; it never invokes a shell and never grants publication authority.
pub fn compile_with_encoding(
  ffmpeg : String,
  render_plan : @plan.RenderPlan,
  media : Array[ResolvedMedia],
  output_path : String,
  encoding : RenderEncoding,
) -> RenderInvocation raise {
  guard render_plan.ready else { fail("render plan is not ready") }
  let arguments : Array[String] = ["-hide_banner", "-nostdin", "-y"]
  let clips : Array[@plan.FrozenClip] = []
  let track_kinds : Array[String] = []
  let track_mixes : Array[@domain.TrackMix?] = []
  for track in render_plan.tracks {
    for clip in track.clips {
      clips.push(clip)
      track_kinds.push(track.kind)
      track_mixes.push(track.mix)
    }
  }
  for clip in clips {
    if clip.local_media is Some(binding) &&
      (binding.role == "image" || binding.role == "logo") {
      arguments.append(["-loop", "1"])
    }
    arguments.push("-i")
    arguments.push(resolve_path(media, clip.selected_digest))
  }
  let filters : Array[String] = []
  let visual_labels : Array[String] = []
  let visual_modes : Array[String] = []
  let audio_labels : Array[String] = []
  let subtitle_paths : Array[String] = []
  let subtitle_inputs : Array[Int] = []
  for index, clip in clips {
    let subtitle = clip.local_media is Some(binding) &&
      binding.role == "subtitle"
    if subtitle {
      subtitle_paths.push(resolve_path(media, clip.selected_digest))
      subtitle_inputs.push(index)
    } else if track_kinds[index] != "audio" {
      filters.push(
        visual_filter(
          index,
          clip,
          render_plan.transitions,
          render_plan.timebase.ticks_per_second,
          render_plan.output.width,
          render_plan.output.height,
        ),
      )
      visual_labels.push("[v" + index.to_string() + "]")
      visual_modes.push(blend_mode(clip))
    }
    if track_kinds[index] == "audio" ||
      track_kinds[index] == "video" ||
      clip.audio_bus_id is Some(_) {
      filters.push(
        audio_filter(
          index,
          clip,
          track_mixes[index],
          render_plan.audio_buses,
          render_plan.timebase.ticks_per_second,
        ),
      )
      audio_labels.push("[a" + index.to_string() + "]")
    }
  }
  let duration = seconds(
    render_plan.range.duration_ticks,
    render_plan.timebase.ticks_per_second,
  )
  filters.push(
    "color=c=" +
    render_plan.output.background +
    ":s=" +
    render_plan.output.width.to_string() +
    "x" +
    render_plan.output.height.to_string() +
    ":d=" +
    duration +
    "[base]",
  )
  let mut current = "[base]"
  for index, label in visual_labels {
    let next = "[vo" + index.to_string() + "]"
    let mode = visual_modes[index]
    if mode == "normal" {
      filters.push(
        current + label + "overlay=eof_action=pass:shortest=0" + next,
      )
    } else {
      filters.push(
        current + label + "blend=all_mode=" + mode + ":shortest=0" + next,
      )
    }
    current = next
  }
  let labeled = "[vlabeled]"
  filters.push(
    current +
    "drawtext=text='AI GENERATED':fontcolor=white:fontsize=24:box=1:boxcolor=black@0.65:x=w-tw-24:y=h-th-20" +
    labeled,
  )
  current = labeled
  for index, path in subtitle_paths {
    let next = "[vs" + index.to_string() + "]"
    filters.push(
      current + "subtitles=filename='" + ff_filter_path(path) + "'" + next,
    )
    current = next
  }
  if !audio_labels.is_empty() {
    let policy = render_plan.delivery_audio
    let limiter = if policy.limiter_enabled {
      ",alimiter=limit=" +
      @math.pow(10.0, policy.true_peak_limit_dbtp / 20.0).to_string()
    } else {
      ""
    }
    filters.push(
      audio_labels.join("") +
      "amix=inputs=" +
      audio_labels.length().to_string() +
      ":duration=longest:normalize=0," +
      "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo," +
      "loudnorm=I=" +
      policy.target_lufs.to_string() +
      ":TP=" +
      policy.true_peak_limit_dbtp.to_string() +
      limiter +
      ",aresample=48000," +
      "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo" +
      "[aout]",
    )
  }
  arguments.push("-filter_complex")
  arguments.push(filters.join(";"))
  arguments.push("-map")
  arguments.push(current)
  if !audio_labels.is_empty() {
    arguments.push("-map")
    arguments.push("[aout]")
  }
  for input_index in subtitle_inputs {
    arguments.push("-map")
    arguments.push(input_index.to_string() + ":0")
  }
  let video_encoder = if encoding.video_codec == "h264" {
    "libx264"
  } else {
    "libvpx-vp9"
  }
  let audio_encoder = if encoding.audio_codec == "aac" {
    "aac"
  } else {
    "libopus"
  }
  arguments.append([
    "-r",
    render_plan.output.fps.numerator.to_string() +
    "/" +
    render_plan.output.fps.denominator.to_string(),
    "-c:v",
    video_encoder,
    "-pix_fmt",
    encoding.pixel_format,
    "-c:a",
    audio_encoder,
  ])
  if !subtitle_inputs.is_empty() {
    arguments.append([
      "-c:s",
      if encoding.container == "mp4" {
        "mov_text"
      } else if encoding.container == "webm" {
        "webvtt"
      } else {
        "srt"
      },
    ])
  }
  if encoding.container == "mp4" || encoding.container == "mkv" {
    arguments.append(["-movflags", "+faststart"])
  }
  if !audio_labels.is_empty() {
    arguments.append(["-ar", "48000", "-ac", "2"])
    if encoding.audio_codec == "aac" {
      arguments.append(["-sample_fmt", "fltp"])
    }
  }
  arguments.append(["-f", encoding.container, "-t", duration, output_path])
  {
    contract: "mooncast.editor-ffmpeg-invocation.v1",
    executable: ffmpeg,
    arguments,
    plan_digest: render_plan.plan_digest,
    output_path,
    timeout_ms: 1800000,
  }
}

///|
/// Default review/master encoding retained for callers that do not request a delivery codec.
pub fn compile(
  ffmpeg : String,
  render_plan : @plan.RenderPlan,
  media : Array[ResolvedMedia],
  output_path : String,
) -> RenderInvocation raise {
  compile_with_encoding(
    ffmpeg,
    render_plan,
    media,
    output_path,
    delivery_encoding("mp4", "h264", "aac"),
  )
}

///|
pub async fn execute(invocation : RenderInvocation) -> RenderReceipt {
  let result = @process.run_capture({
    executable: invocation.executable,
    arguments: invocation.arguments,
    working_directory: None,
    timeout_ms: invocation.timeout_ms,
    max_output_bytes: 4194304,
  })
  let stderr = @utf8.decode(result.stderr)
  let tail = if stderr.length() > 4000 {
    stderr[stderr.length() - 4000:].to_owned()
  } else {
    stderr
  }
  let exit_code = match result.exit_code {
    Some(value) => value
    None => -1
  }
  {
    contract: "mooncast.editor-render-receipt.v1",
    plan_digest: invocation.plan_digest,
    output_path: invocation.output_path,
    exit_code,
    stderr_tail: tail,
    timed_out: result.timed_out,
    output_truncated: result.output_truncated,
    succeeded: exit_code == 0 && !result.timed_out,
    publication_authority: false,
  }
}
