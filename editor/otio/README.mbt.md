# Import an external cut for native editing

The public catalog/import types are owned by this package. Use the existing
native editor project and an explicit mapping; external URLs are recorded tokens,
not network or filesystem access. The CLI and complete supported profile are in
[OTIO timeline import](../../docs/otio-timeline-import.md).

```mbt check
///|
test {
  let map = @otio.read_media_map(
    (
      #|{"contract":"mooncast.otio-media-map.v1","fps":24,"draft_timeline_id":"cut.new","bindings":[{"target_url":"file:///recorded/take.mov","media_ref_id":"media.1","template_clip_id":"template.1","source_start_frame":0}]}
    ),
  )
  assert_eq(map.fps, 24)
  assert_eq(map.bindings[0].source_start_frame, 0)
}
```
