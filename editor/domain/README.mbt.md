# Mooncast editor domain

This package is the canonical, pure MoonBit model for the OpenCut-class editor.
It has no filesystem, HTTP, FFmpeg, provider, publication, or UI dependency.

The aggregate is `EditorProject -> Timeline -> Track -> Clip`. A clip owns typed
settings, keyframes, an ordered effect stack, optional AIGC provenance, and an
audio-bus route. The timeline owns transitions, canonical audio buses, delivery
loudness policy, and output geometry.

All mutations are explicit `EditCommand` values reduced through
`EditorSession::dispatch`. Group commands contain stable clip IDs and never read
ephemeral UI selection. Each accepted command creates an immutable before/after
log record. Undo and redo append control records instead of rewriting history;
`replay` reconstructs state from the initial snapshot and command sequence.

`LocalMediaBinding` deliberately stores references and evidence only. Resolving
paths, probing files, checking rights services, rendering frames, and publishing
belong to later host adapters. `editor/render_plan` freezes one editor revision
and derives deterministic cache-key projections before those effects occur.

Wire contract constants retain the existing `mooncast.editor-*.v1` names. The
typed codecs are domain-owned, including the exact legacy `type/payload` wire
envelope. Decoding produces an `EditOperation` before reducer execution, so wire
compatibility does not introduce transport branching into the reducer.
