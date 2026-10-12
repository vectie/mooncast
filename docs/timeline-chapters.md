# Author chapters for an edited episode

Use `cmd/chapters` to turn a native timeline into named navigation chapters.
Seed suggestions from one chosen track's clip starts, then rename, add, move or
remove them without touching the source project. Export chapter WebVTT for a
player's `track kind="chapters"`, FFmetadata for a later media-container mux,
and the editable JSON draft. This is an offline sidecar workflow, not a render,
master approval, client acceptance or publishing action.

## Seed, edit and export

From the repository root:

```sh
moon run cmd/chapters -- seed fixtures/edit-decisions.project.json video first.chapters.json
moon run cmd/chapters -- preview first.chapters.json
moon run cmd/chapters -- set first.chapters.json template.a 0 "Opening" named.chapters.json
moon run cmd/chapters -- set named.chapters.json demonstration 6000 "Demonstration" expanded.chapters.json
moon run cmd/chapters -- remove expanded.chapters.json template.b reviewed.chapters.json
moon run cmd/chapters -- export reviewed.chapters.json episode
```

The synthetic source is a 20-second timeline at 1000 ticks/second. The reviewed
output has `Opening` from 0–6 seconds and `Demonstration` from 6–20 seconds.
The fixture references metadata-only media; actual source playback is not
needed to author chapters. The outputs are `episode.chapters.vtt`,
`episode.ffmetadata` and `episode.chapters.json`. The last file is a draft that
can be previewed and edited again using the same commands.

`set` replaces the chapter with the given ID, or adds it if the ID is new.
Its start is always in the draft's timeline ticks, not milliseconds or source
media time. Chapters are sorted after editing. Move a chapter by keeping its ID
and changing its start; keep its existing title unless intentionally renaming
it. `remove` needs an existing ID and cannot remove the last chapter. Every
edit writes a new file, leaving earlier drafts available as manual undo.

For a hand-authored draft, start with `fixtures/chapters-24fps.json`. It shows
an exact 24-tick clock with a chapter at frame 25, not a rounded millisecond.
The draft must retain its source project/timeline IDs and revisions. Changing
those fields does not conform the markers to another cut.

## Timing and scope

- Choose one track ID explicitly. Its clip starts become marker suggestions,
  initially titled with clip IDs. Other tracks extend the timeline duration
  when they end later, but do not create extra markers. Review the suggestions:
  clip boundaries do not necessarily coincide with editorial chapters.
- A chapter ends at the next marker, or at the maximum end of all timeline
  clips. Leading time before the first marker has no chapter. Gaps between
  clips remain within the preceding chapter; they are not cut out.
- FFmetadata retains exact ticks using `TIMEBASE=1/ticks_per_second`.
  WebVTT floors shared boundaries to milliseconds, so adjacent chapters remain
  adjacent; an interval that collapses to zero milliseconds prevents export.
- Titles are plain Unicode text, escaped separately for FFmetadata and WebVTT.
  IDs and titles must be nonblank single lines up to 200 UTF-16 code units.
  This FFmetadata profile rejects titles ending in a backslash because tested
  FFmpeg readers can interpret it as line continuation, even when escaped.
- Drafts contain 1–1000 distinct IDs and strictly increasing starts within a
  positive duration. Tick values fit a nonnegative signed 32-bit integer;
  timestamp conversion uses wider arithmetic. Coincident clip starts on the
  selected seed track require choosing a less ambiguous track or authoring a
  draft. Chapters need not begin at zero.
- The standalone draft records source identities and revisions but does not
  watch subsequent timeline edits. After recutting, seed from the new snapshot
  or [conform existing source chapters](chapter-conforming.md), then review the
  chapter placement again. There is no live Studio mutation,
  automatic ripple edit, chapter import screen or automatic media mux.
  For local FFmetadata intake, see [chapter import](chapter-import.md).

Use a chapter-aware player or a deliberate later FFmpeg mux with the exported
metadata. The command itself produces sidecars only and never opens or changes
media. Player chapter support varies; this workflow is not a promise of a
specific platform's upload or publication requirements.

## Files and recovery

All output paths must be new local paths; the parent directories must exist.
Export computes and validates every sidecar before writing, then checks all
three names. Existing files are not replaced. A later filesystem failure can
leave partial new outputs; retain them and retry with a new prefix after fixing
the problem. Project input is capped at 16 MiB and draft input at 2 MiB. No
network, provider, rights decision, commercial ledger, or live-store mutation
is involved.

Focused tests live in `editor/chapters`. The synthetic executable workflow also
round-trips escaped Unicode titles and chapter boundaries through a real
FFmpeg/FFprobe media-container inspection; that is local format interoperability,
not inspection of a delivered client episode.
