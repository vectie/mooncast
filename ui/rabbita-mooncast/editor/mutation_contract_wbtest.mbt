///|
test "canonical add-clip template retains settings required by mutation API" {
  let source : Json = {
    "track_id": "track-ai-label",
    "clip": {
      "clip_id": "clip-logo",
      "media_ref_id": "media:logo",
      "identity": {
        "project_id": "project",
        "episode_id": "episode",
        "scene_id": "scene",
        "shot_id": "shot",
        "asset_id": "asset",
      },
      "intent": { "intent_ref": "mooncast:editor-role:logo" },
      "start_tick": 0,
      "duration_ticks": 5000,
      "source_in_tick": 0,
      "source_out_tick": 5000,
      "settings": {
        "fit": "contain",
        "opacity": 1.0,
        "scale": 1.0,
        "position_x": 0.0,
        "position_y": 0.0,
        "rotation_degrees": 0.0,
        "brightness": 0.0,
        "contrast": 1.0,
        "saturation": 1.0,
        "gamma": 1.0,
        "volume_db": 0.0,
        "pan": 0.0,
      },
    },
  }
  let template : @api.AddClipTemplate = @json.from_json(source)
  guard template.clip.to_json() is Json::Object(clip) &&
    clip.get("settings") is Some(Json::Object(settings)) else {
    fail("canonical clip settings were not serialized")
  }
  for
    key in [
      "fit", "opacity", "scale", "position_x", "position_y", "rotation_degrees",
      "brightness", "contrast", "saturation", "gamma", "volume_db", "pan",
    ] {
    assert_true(settings.contains(key))
  }
}
