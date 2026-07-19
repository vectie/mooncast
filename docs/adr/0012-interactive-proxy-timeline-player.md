# ADR 0012: Interactive proxy playback is ephemeral

Status: accepted

Mooncast needs responsive editorial playback without weakening the authority of its reproducible review render. The editor therefore composes ready, digest-addressed review proxies in the browser from the canonical timeline snapshot. The browser owns only its clock, play/pause, loop points, decoder state, audio graph, drift correction, and canvas pixels.

The server snapshot and frozen render plan remain canonical. Cached whole-timeline review renders remain the only approval artifacts. The interactive player is visibly labelled as a proxy and has no approval, provider, publication, or mutation authority.

Video and audio originals are never exposed as an implicit fallback. Until a registered proxy exists, the affected timeline range is shown as missing/loading and renders blank. Rights-attested local images and logos can use their immutable digest-addressed original bytes because the browser does not transcode them. Subtitle cues come from their validated local-media binding.

Playback is synchronized to an explicit `performance.now()` timeline clock. Media elements resync when absolute drift exceeds 120 ms, and manual resync, frame-step, scrub, and loop in/out are available. Audio starts only after a user gesture creates or resumes Web Audio; there is no muted-autoplay path.
