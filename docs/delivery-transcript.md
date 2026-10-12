# Completed-output caption navigation

In Delivery, inspect a completed build's master, variant, or named cut. The
player has a searchable transcript and synchronized active captions alongside
it. Search matches caption text (case-insensitively) and displayed start times.
Clear search to restore every cue. Tab to a cue and use Enter or Space to seek;
native player controls continue to control play/pause. Cue navigation never
starts playback automatically.

Times belong to the selected output. A cut beginning at master second 12.25
still starts at output second zero. Sidecars are already clipped and rebased by
the delivery factory; the viewer does not add the source trim offset again.
Active intervals include the start and exclude the end. Overlapping cues can
all be active, while a gap shows no active caption. Search does not hide active
captions or seek the player.

The viewer keeps the exact raw SRT and MP4/SRT download links. Missing,
malformed, empty, or oversized SRT disables only caption navigation. The parser
accepts UTF-8-decoded text, an optional BOM, LF or CRLF, and multiline cues;
timestamps must be HH:MM:SS,mmm with positive cue duration. The entire file must
fit 1,048,576 UTF-16 code units and at most 5,000 cues. Text is escaped rather
than interpreted as HTML. Invalid or unavailable media metadata disables seeks
and active captions. A failed seek offers another cue attempt or the existing
Retry video and SRT action.

Selections and callbacks are bound to build, output, video digest, sidecar
identity, and a fresh generation. Retry, project/output/build switches, leaving
Delivery, or invalidated metadata clear navigation and stop obsolete callbacks.
A same-project refresh preserves an unchanged exact selection. Historical
outputs retain their original captions after promotion of a newer master.

This feature reads saved artifacts. It does not edit, translate, regenerate,
build, perform QC, accept, or publish. The separate promoted-master pre-build
range player and cut draft behavior are unchanged.
