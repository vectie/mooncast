# ADR 0013: Transitions belong to edit points

Status: accepted

A transition is a relationship between two adjacent clips. Mooncast stores it in `timeline.transitions` with stable clip and track references, bounded source handles, a type-specific direction/color, and a canonical digest. Clip settings no longer create rendered fades or wipes; their legacy transition field is normalized to cut while old snapshots remain readable.

The edit kernel verifies adjacency, a common cut, compatible track kind, a maximum three-second duration, immutable source-handle availability, non-overlapping transition regions, and digest integrity. Commands are revisioned and replayable. Any ordinary clip edit that would leave a dangling or under-handled transition fails, requiring the editor to resize or remove the transition first.

Render plans freeze the same transition parameters plus the calculated cut/range. Cache segmentation isolates those ranges. FFmpeg produces the approval pixels with `xfade` and equal-power `acrossfade`; the browser uses WebGL2 shaders for responsive playback and exposes Canvas fallback explicitly. This keeps one durable editorial decision while allowing two renderers with different authority.
