# Alternate soundtrack planning

The pure API joins an explicit audio selection to a bounded existing picture.
The command probes actual files, verifies the isolated rendition and checks
the final media before reporting success.

```mbt check
///|
test "preview a first soundtrack without assuming editorial alignment" {
  let picture : Json = {
    "format": {
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "duration": "2",
      "start_time": "0",
    },
    "streams": [
      {
        "index": 0,
        "codec_type": "video",
        "codec_name": "h264",
        "disposition": { "attached_pic": 0, "default": 1 },
      },
    ],
    "chapters": [],
  }
  let soundtrack : Json = {
    "format": { "format_name": "wav", "duration": "2" },
    "streams": [
      {
        "index": 0,
        "codec_type": "audio",
        "codec_name": "pcm_s16le",
        "channels": 1,
        "sample_rate": "44100",
      },
    ],
  }
  let plan = @audio_media.prepare(picture, soundtrack, 0, "und", "Commentary")
  assert_eq(plan.audio.channels, 1)
  assert_eq(plan.codec, "aac")
  assert_true(plan.is_default)
  assert_eq(plan.media.duration_ms, 2000)
}
```
