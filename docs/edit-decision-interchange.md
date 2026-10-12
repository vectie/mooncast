# Exchange a cuts-only edit with CMX3600 EDL

`cmd/edit_decisions` turns an external cut list into a new, editable native
`mooncast.editor-project.v1` snapshot. It can also export a compatible native
cut to EDL. This is an offline editing utility, not a render, live-studio import,
rights decision, reviewed master, delivery or publication action.

## Try the complete local workflow

From the repository root, use the three checked-in synthetic fixtures:

```sh
moon run cmd/edit_decisions -- preview fixtures/edit-decisions.project.json fixtures/edit-decisions.edl fixtures/edit-decisions.reels.json
moon run cmd/edit_decisions -- import fixtures/edit-decisions.project.json fixtures/edit-decisions.edl fixtures/edit-decisions.reels.json interview
moon run cmd/edit_decisions -- export interview.project.json fixtures/edit-decisions.reels.json interview.edl "Synthetic interview cut"
```

The preview resolves both reels to existing media and shows source ranges,
record positions relative to the chosen origin, and leading/inter-cut gaps.
The example has two cuts, 120 record frames, and 23 gap frames at 24 fps. Its
1000-tick source clock becomes an exact 3000-tick draft clock; frame 1 is 125
ticks, with no millisecond rounding.

Import writes `interview.project.json` and `interview.preview.json`. Export
writes `interview.edl`, which another editor can use as a cut-list handoff.
The native snapshot contains actual `Timeline`, `Track` and `Clip` values,
including existing media locators and production identities. It can be read
with `@domain.snapshot_from_json`, edited with `EditorSession::dispatch`, and
exported again. Native tests exercise a real trim, undo and export through that
reducer. There is no new browser import screen or automatic mutation of the
live studio's store. Keep this separate draft until deliberately integrating
it with your editing workflow.

Keep the original media base/pack root available; copying this JSON does not
copy or relocate the referenced media.

All output paths must be new. Existing source/output files are never replaced.
Both import outputs are checked before writing. A filesystem failure during
the second write can leave the first output; retain it and choose a new prefix
after correcting the problem. `preview` writes no files.

## Map reels to your existing media

Use a current, fully populated native project snapshot as the source library.
The fixtures are metadata-only examples; they do not include playable media.
Create a JSON map with this shape:

```json
{
  "contract": "mooncast.edl-reel-map.v1",
  "fps": 24,
  "record_start_timecode": "01:00:00:00",
  "draft_timeline_id": "timeline.edl-draft",
  "bindings": [
    {
      "reel": "CAM_A",
      "media_ref_id": "media.a",
      "template_clip_id": "template.a",
      "source_start_timecode": "10:00:00:00"
    }
  ]
}
```

- `fps` is mandatory because a CMX3600 NDF header does not identify the frame
  rate. Use an integer from 1 to 60, matching the intended media interpretation.
- `record_start_timecode` identifies timeline tick zero. Leading and internal
  gaps are retained. Set it earlier than the first cut when you want a lead-in.
- Each reel must map to exactly one existing video `MediaRef`, with a known
  duration, and one existing clip that uses it. The clip supplies its identity,
  intent and optional artifact link; it does not supply timing or effects.
- `source_start_timecode` is the timecode of the first frame of that media file,
  not the current clip's in point. An EDL source time of `10:00:00:01` above
  selects frame 1 of the mapped file. Set it to zero for zero-based sources.
- Reel names are 1–8 uppercase ASCII letters, digits or underscores. `BL` is
  reserved. Reel names and media IDs must each be unique in the mapping.
- The operator chooses `draft_timeline_id`. Use a new ID for a separate cut.
  Draft project/timeline revisions start at zero; the preview records the
  source project ID, source revision and source timeline ID.

The new draft is intentionally **video-only and cuts-only**. It starts a fresh
single track with default clip settings, no keyframes, effects, transitions or
audio routes/buses. Existing template transforms and audio are not copied.
Project identity/intent/artifact records and media references remain available.
Import makes no claim that these records are current rights approvals.

When necessary, import multiplies the timebase and every media duration by the
same integer factor (the least common multiple of the old timebase and fps).
Thus both media-relative and timeline-relative seconds remain unchanged. Other
registry evidence outside this standalone snapshot is not rewritten. Tick
values must fit a nonnegative 32-bit native integer; overflow fails explicitly.

## Supported EDL profile and export limits

- Optional `TITLE:` (1–120 characters), followed by `FCM: NON-DROP FRAME`.
- 1–999 events with unique three-digit event numbers, one `V` channel and `C`
  cut: event, reel, V, C, source-in, source-out, record-in, record-out.
- Timecodes are exactly `HH:MM:SS:FF`, within one 24-hour day. In points are
  inclusive, out points exclusive. Source and record durations must match.
- Events must already be in record order and may have gaps. Overlapping or
  out-of-order events fail. Gaps are empty record intervals, not `BL` events.
- LF/CRLF and spaces/tabs between fields work. Descriptive `* FROM CLIP NAME:`,
  `* SOURCE FILE:` and `* COMMENT:` lines are ignored; their contents never
  select media. All other directives are rejected.
- Dissolves, wipes, transitions, audio events, layered tracks, drop-frame,
  fractional frame rates, speed/retime directives and midnight rollover are
  unsupported. Unknown data is not silently treated as a cut.

Export requires exactly one video track, matching integer output fps, no
transitions, and plain clips without settings changes, keyframes, effects or
audio routing. Source ranges must fit mapped media; source/record boundaries
must be exact frames. It refuses to flatten layered or transformed work and
never rounds a native edit. Output geometry and media files are not contained
in EDL. Audio mix/delivery settings are outside this V-only handoff.

Exports are canonical: clips sorted by record position, event numbers replaced
with 001 onward, descriptive comments omitted, and explicit source/record
origins restored from the map. Timing, media choice and gaps round-trip;
nonsequential original event numbers and comments do not. Use the same map and
source library to reimport an exported cut. For a new import using the draft
itself as a source library, update template IDs to clips that exist in it.

EDL/map inputs are capped at 2 MiB and project snapshots at 16 MiB. This utility
does not probe media, verify playback, resolve missing files, retime media,
recover missing frames, acquire rights, or contact any provider.
