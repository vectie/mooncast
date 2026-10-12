# Keep chapter titles through a recut

`cmd/chapter_conform` carries existing source chapter titles through a native
single-track video cut. It handles trims, reordered sources and repeated clips,
including chapter drafts with a different tick clock. It writes an ordinary
editable chapter draft, WebVTT, FFmetadata and a trace of where every resulting
chapter came from. Source media need not be online. No media is read or rendered.

This is a local editing/output workflow for MC-W04/MOONCAST-B08 and
MC-W07/MOONCAST-R02. Review the resulting chapter names against the actual cut
before using the sidecars. A source-map binding is the operator's choice;
matching duration does not prove that the chapter draft describes that media.
No Studio/project mutation, rights decision, approval, client delivery or
publication happens here.

## Try a complete recut

From the MoonCast checkout, with its dependency graph installed and an absolute
external build target selected:

```sh
moon --target-dir /absolute/external/mooncast-build build cmd/chapter_conform cmd/chapters --target native --frozen --strip -j 1
/absolute/external/mooncast-build/native/debug/build/cmd/chapter_conform/chapter_conform.exe preview fixtures/chapter-conform.project.json fixtures/chapter-conform.sources.json
/absolute/external/mooncast-build/native/debug/build/cmd/chapter_conform/chapter_conform.exe export fixtures/chapter-conform.project.json fixtures/chapter-conform.sources.json /tmp/new-episode
/absolute/external/mooncast-build/native/debug/build/cmd/chapters/chapters.exe set /tmp/new-episode.chapters.json conformed.3 2000 'Reviewed demonstration' /tmp/edited-episode.json
/absolute/external/mooncast-build/native/debug/build/cmd/chapters/chapters.exe export /tmp/edited-episode.json /tmp/reviewed-episode
```

Choose unused output filenames and an existing parent directory. This synthetic
six-second fixture cuts source A from 0.5–2.5 seconds, source B from 2–4 seconds,
then repeats A. A's chapters use 1000 ticks/second and B's use 24 ticks/second.
The resulting seven chapter starts are 0, 500, 2000, 2500, 3500, 4000 and 4500
on the destination's 1000-tick clock. A's `ending` chapter is dropped.

Preview reports the exact output ranges and source clip/media/marker IDs and
checks the export formats without writing files. Export creates:

- `new-episode.chapters.json`: edit with the existing `chapters` commands
- `new-episode.chapters.vtt`: chapter navigation for a supporting player
- `new-episode.ffmetadata`: exact ticks for a separately chosen container mux
- `new-episode.conform.json`: selected input paths and SHA-256 hashes, source
  draft revisions, output draft, every retained interval and source chapter use

The ordinary chapter editor can change titles, move/remove markers and export
again. The conform report describes the initial output only; later manual edits
are not automatically reflected in it. Preserve the report and original draft
when revising. New conform marker IDs are stable within that output, not stable
across later changes to the cut.

## Bind source chapters explicitly

The source map associates each media reference used by the cut with an existing
`mooncast.chapter-draft.v1` file:

```json
{
  "contract": "mooncast.chapter-source-map.v1",
  "bindings": [
    { "media_ref_id": "media.a", "file": "interview.chapters.json" },
    { "media_ref_id": "media.b", "file": "demo.chapters.json" }
  ]
}
```

Relative source-draft paths resolve from the canonical source-map directory,
independent of the process working directory. Absolute local paths work too.
Project/map command arguments and the output prefix resolve from the working
directory. The command never opens media locators in the native project.

Each source draft describes its bound media starting at media time zero. Its
whole duration must equal that media reference's known duration after exact clock
conversion. Do not use a chapter draft from an unrelated or already-recut
sequence merely because it has the same length. The source project/timeline
identities and revisions are retained in the report, but no source identity or
content attestation is inferred from them.

Use existing [chapter import](chapter-import.md) to bring FFmetadata into an
appropriate source draft, or [chapter authoring](timeline-chapters.md) to create
and edit it. Bind every used media reference exactly once. Missing, duplicate
and unused bindings fail. There is no implicit empty-chapters binding.

## What happens to chapters at cuts

A source chapter covers its marker start through the next marker, or through
the source duration for the final marker. Every intersection with a selected
clip becomes one output chapter:

- A clip beginning halfway through a chapter retains that chapter's title at
  the new clip start. `clipped_at_start` records the trim.
- A cut inside a chapter shortens its output interval and sets `clipped_at_end`.
  Text is retained exactly; names may need editorial revision after trimming.
- A removed chapter has an empty `source_uses[].output_marker_ids` list.
- A repeated or split chapter lists every new output marker. Each cut keeps its
  own marker even if the adjacent title is identical; use `chapters remove`
  deliberately if those should become one navigation chapter.
- Boundaries use half-open intervals: a chapter starting exactly at a clip's
  out point is not selected. The source title ending at an in point is omitted.

The trace records original start/end ticks and source clock, output start/end
ticks, clip/media/marker IDs and clipping flags. Repeated source ranges therefore
remain distinguishable. Input clip arrays and chapter drafts are never changed.

## Supported profile and limitations

Exactly one video track, normal-speed source ranges, no transitions, and
contiguous clips starting at zero. Visual transforms do not change time and
are allowed. Enabled speed-ramp effects or speed points are rejected. Gaps,
overlapping/layered tracks, audio-only edits and chapter timing driven by an
independent audio mix are unsupported.

Every selected interval must already be covered by source chapters. A source
may have an unchaptered lead-in only when the selected clip begins after it.
Marker-only chapter drafts cannot represent an internal unchaptered gap without
silently extending the preceding title, so such cuts are refused.

Source and destination clocks may differ. Retained boundaries must convert to
whole destination ticks exactly; there is no rounding or frame-rate guess.
Inexact boundaries belonging only to removed chapters do not matter. FFmetadata
retains exact destination ticks. The existing WebVTT exporter floors shared
boundaries to milliseconds; a chapter shorter than that precision fails export
and preview. Its FFmetadata restriction on titles ending in a backslash also
applies. Unicode/escaped titles otherwise retain their existing exporter rules.

Bounds: 1–999 clips, 1–64 source bindings, 1–1000 chapters per source and at most
1000 output chapter segments; source and cut durations at most two hours and
signed 32-bit ticks. Project input is at most 16 MiB, map/drafts at most 2 MiB
each, combined source drafts at most 16 MiB and each output at most 32 MiB. JSON
uses the repository's normal parser, including last-value duplicate-key
semantics and ignored unknown fields. Use unambiguous, ordinary documents.

All four output contents and destination names are checked before any write.
Existing files, directories and dangling symlinks are refused; writes also use
exclusive creation. A filesystem failure or a concurrent destination creation
can leave a partial new set. Nothing is deleted or overwritten; retain the
partial files and choose a fresh prefix after resolving the cause. The report
hashes the exact input bytes read, without locking input files against changes.
No live edit synchronization, media mux, browser playback or external-player
compatibility is implied by the focused local tests.
