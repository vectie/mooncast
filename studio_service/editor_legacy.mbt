///|
struct LegacyColorSettings {
  brightness : Double?
  contrast : Double?
  saturation : Double?
  gamma : Double?
} derive(FromJson)

///|
struct LegacyVisualSettings {
  opacity : Double?
  scale : Double?
  x : Double?
  y : Double?
  rotation_degrees : Double?
} derive(FromJson)

///|
struct LegacyNestedClipSettings {
  fit : String?
  opacity : Double?
  scale : Double?
  position_x : Double?
  position_y : Double?
  rotation_degrees : Double?
  brightness : Double?
  contrast : Double?
  saturation : Double?
  gamma : Double?
  volume_db : Double?
  pan : Double?
  color : LegacyColorSettings?
  effect : LegacyVisualSettings?
} derive(FromJson)

///|
struct LegacyNestedClipPayload {
  clip_id : String
  settings : LegacyNestedClipSettings
} derive(FromJson)

///|
struct CanonicalClipPayload {
  clip_id : String
  settings : @editor_domain.ClipSettings
} derive(ToJson)

///|
struct LegacyNestedOutput {
  preset : String
  orientation : String?
  width : Int?
  height : Int?
  fps : @editor_domain.FrameRate?
  background : String?
} derive(FromJson)

///|
struct LegacyNestedOutputPayload {
  output : LegacyNestedOutput
} derive(FromJson)

///|
struct CanonicalOutputPayload {
  output : @editor_domain.OutputSettings
} derive(ToJson)

///|
fn find_editor_clip(
  project : @editor_domain.EditorProject,
  clip_id : String,
) -> @editor_domain.Clip? {
  for track in project.timeline.tracks {
    for clip in track.clips {
      if clip.clip_id == clip_id {
        return Some(clip)
      }
    }
  }
  None
}

///|
fn choose_double(
  primary : Double?,
  secondary : Double?,
  fallback : Double,
) -> Double {
  match primary {
    Some(value) => value
    None => secondary.unwrap_or(fallback)
  }
}

///|
fn compatible_clip_payload(
  project : @editor_domain.EditorProject,
  payload : Json,
) -> Json raise {
  let input : LegacyNestedClipPayload = @json.from_json(payload)
  let previous = match find_editor_clip(project, input.clip_id) {
    Some(clip) => clip.settings
    None => @editor_domain.default_clip_settings()
  }
  let color = input.settings.color
  let effect = input.settings.effect
  let effect_opacity = match effect {
    Some(value) => value.opacity
    None => None
  }
  let effect_scale = match effect {
    Some(value) => value.scale
    None => None
  }
  let effect_x = match effect {
    Some(value) => value.x
    None => None
  }
  let effect_y = match effect {
    Some(value) => value.y
    None => None
  }
  let effect_rotation = match effect {
    Some(value) => value.rotation_degrees
    None => None
  }
  let color_brightness = match color {
    Some(value) => value.brightness
    None => None
  }
  let color_contrast = match color {
    Some(value) => value.contrast
    None => None
  }
  let color_saturation = match color {
    Some(value) => value.saturation
    None => None
  }
  let color_gamma = match color {
    Some(value) => value.gamma
    None => None
  }
  CanonicalClipPayload::{
    clip_id: input.clip_id,
    settings: {
      fit: input.settings.fit.unwrap_or(previous.fit),
      opacity: choose_double(
        input.settings.opacity,
        effect_opacity,
        previous.opacity,
      ),
      scale: choose_double(input.settings.scale, effect_scale, previous.scale),
      position_x: choose_double(
        input.settings.position_x,
        effect_x,
        previous.position_x,
      ),
      position_y: choose_double(
        input.settings.position_y,
        effect_y,
        previous.position_y,
      ),
      rotation_degrees: choose_double(
        input.settings.rotation_degrees,
        effect_rotation,
        previous.rotation_degrees,
      ),
      brightness: choose_double(
        input.settings.brightness,
        color_brightness,
        previous.brightness,
      ),
      contrast: choose_double(
        input.settings.contrast,
        color_contrast,
        previous.contrast,
      ),
      saturation: choose_double(
        input.settings.saturation,
        color_saturation,
        previous.saturation,
      ),
      gamma: choose_double(input.settings.gamma, color_gamma, previous.gamma),
      volume_db: input.settings.volume_db.unwrap_or(previous.volume_db),
      pan: input.settings.pan.unwrap_or(previous.pan),
    },
  }.to_json()
}

///|
fn compatible_output_payload(
  project : @editor_domain.EditorProject,
  payload : Json,
) -> Json raise {
  let input : LegacyNestedOutputPayload = @json.from_json(payload)
  let previous = project.timeline.output
  let (orientation, width, height) = match input.output.preset {
    "vertical-1080p" => ("vertical", 1080, 1920)
    "square-1080p" => ("square", 1080, 1080)
    "horizontal-720p" => ("horizontal", 1280, 720)
    "vertical-720p" => ("vertical", 720, 1280)
    _ => ("horizontal", 1920, 1080)
  }
  CanonicalOutputPayload::{
    output: {
      preset: input.output.preset,
      orientation: input.output.orientation.unwrap_or(orientation),
      width: input.output.width.unwrap_or(width),
      height: input.output.height.unwrap_or(height),
      fps: input.output.fps.unwrap_or(previous.fps),
      background: input.output.background.unwrap_or(previous.background),
    },
  }.to_json()
}

///|
async fn StudioService::legacy_editor_command(
  self : StudioService,
  project_id : String,
  envelope : LegacyEditorCommandEnvelope,
) -> @editor_domain.EditCommand {
  guard envelope.command is Json::Object(command) &&
    command.get("type") is Some(kind_json) &&
    command.get("payload") is Some(raw_payload) else {
    raise Invalid(
      code="editor_command_invalid",
      message="legacy editor command requires type and payload",
    )
  }
  let kind : String = @json.from_json(kind_json)
  let project = self.get_editor_project(project_id)
  let payload = match kind {
    "configure_clip" => compatible_clip_payload(project.snapshot, raw_payload)
    "configure_output" =>
      compatible_output_payload(project.snapshot, raw_payload)
    _ => raw_payload
  }
  let legacy = Json::object({
    "contract": "mooncast.editor-edit-command.v1",
    "command_id": "http:" + envelope.idempotency_key,
    "expected_revision": envelope.expected_revision,
    "actor": @editor_domain.CommandActor::{
      actor_id: "editor-http",
      provenance: "mooncast:native-studio",
    }.to_json(),
    "type": kind_json,
    "payload": payload,
  })
  @editor_domain.legacy_command_from_json(legacy)
}
