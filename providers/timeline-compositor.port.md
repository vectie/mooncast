# Timeline-compositor provider port

The compositor consumes ordered selected shots and creates a content-addressed
3–8 minute master. It must preserve audio, embed subtitles, retain visible AI
labels, write complete shot lineage, probe the result, and reject duration or
stream failures before review.

The pack-local production adapter is
`mooncast-editor-production-compositor@1`. It consumes a frozen editor render
plan, resolves immutable media-registry objects, applies source trims and edit
order, applies audio-track volume/pan/mute, clip color/effect/transition settings,
title/subtitle overlays, and horizontal or vertical output presets, composites
MP4/H.264/AAC, embeds the subtitle stream, probes the result,
and emits a non-publishing receipt. A separate named-authority operation
promotes that receipt to the production master; compositor success alone has no
delivery or publication authority.
