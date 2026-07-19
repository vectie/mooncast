# Editor render keyframes

Mooncast freezes clip animation into `mooncast.editor-render-plan.v1`. Every
frozen clip has a `keyframes` object; an empty object means the existing
constant clip or track settings remain authoritative.

Keyframe ticks are relative to the beginning of the clip. Curves are ordered
by their fixed channel order and then ascending tick. The render-plan digest
therefore binds the exact animation as well as media, timing, settings, and
lineage.

The production FFmpeg compositor supports these channels:

- Video: `opacity`, `scale`, `position_x`, `position_y`, `brightness`,
  `contrast`, `saturation`, and `gamma`.
- Audio: `volume_db` and `pan`.

The supported interpolation modes are `hold`, `linear`, `ease-in`, `ease-out`,
and `ease-in-out`. Each point's interpolation controls the segment from that
point to the next. Before the first point the first value is held; after the
last point the last value is held.

The editor inspector constrains its channel picker to the selected clip's track
kind. Add, update, and remove operate at the clip-relative playhead and emit one
`set_keyframes` command containing only the edited channel. The kernel merges
that channel into the canonical clip, preserving every other curve. The ordered
inspector list is the accessible source of truth; timeline diamonds are a visual
projection of the server snapshot.

Timeline selection is ephemeral: Shift extends a same-track range and
Command/Control toggles clips. Group nudges, compatible-block drags, ripple
reorders, grouped trims, and deletes each emit one atomic group command before
the editor reconciles the returned server snapshot.

Color curves compile to per-frame `eq` expressions. Scale and position curves
compile to a fixed-canvas scale/overlay graph. Opacity compiles to a per-frame
RGB expression. Volume compiles from dB to a per-frame linear gain, and pan
compiles to per-channel audio expressions. Expressions use the frozen integer
timebase rather than ambient wall time.

Render-plan construction rejects malformed values, duplicate or out-of-range
ticks, unsupported channels, wrong track kinds, and unknown interpolation
modes. The production compositor validates the frozen curves again before it
launches FFmpeg. A curve that cannot be represented by the supported filter
graph fails the export; it is never silently discarded or replaced by a
constant setting.
