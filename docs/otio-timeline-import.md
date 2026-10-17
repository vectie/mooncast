# Bring an OpenTimelineIO cut into an editable MoonCast draft

Use `otio_import` when an editor has a local `.otio` JSON cut and wants to continue
editing with media already registered in a native MoonCast project. Catalog the
source, explicitly map its external-reference tokens to known media, inspect the
preview, and import a separate ordinary `mooncast.editor-project.v1` draft.
The supported assembly is one Video track plus one optional Audio track. The
native project keeps both tracks synchronized on the same exact clock, including
independent leading/internal gaps and an audio tail longer than the picture.
The CMX3600 sidecar is explicitly a picture-only projection.

## Keep an assembled soundtrack

Use `fixtures/otio-audio.project.json`, `fixtures/otio-audio.otio` and
`fixtures/otio-audio-map.json` with the same `catalog`, `preview` and `import`
commands below. The synthetic source is metadata-only; it does not contain media.
At 24 fps the picture ends at frame 120 and the soundtrack at frame 180. Picture
clips start at frames 3 and 72; audio clips start at frames 12 and 108, with a
24-frame internal audio gap. The 1000-tick source clock becomes 3000 ticks/second,
so one frame is exactly 125 ticks. No frame/sample rounding is performed.

The imported ordinary `otio.audio` track has independently editable clips
`otio.audio.1`, `otio.audio.2`, and neutral gain/pan/mute. Load the native project
through the existing snapshot API and use ordinary `Trim`, `ConfigureClip`,
`ConfigureTrack`, `Undo` and `Redo`. For example, set the first audio clip's source
in/out to 250/9125 ticks, then set its `volume_db` to -6. Save the snapshot for the
revised cut, or the `EditorSession` for resumable undo history. Reopening a snapshot
does not manufacture an undo log. The executable native test
`editor/otio/audio_timeline_test.mbt` performs this complete disk save/reopen and
two-step undo journey while proving picture and the later audio clip unchanged.

The video may itself contain audio. Import does not infer intended mixing,
automatically mute embedded sound, analyze synchronization, listen to media or
verify the supplied soundtrack. Inspect both tracks and adjust the normal mix.
Source rates must already use the common whole-frame clock; sample-rate audio
coordinates, fractional frame rates and resampling are not supported.

## Try the complete local journey

Use the pinned MoonBit toolchain and existing module dependencies. All Moon
commands need a private HOME/XDG and an absolute external target directory. With
`MOON_HOME`, `PATH`, `HOME`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
`XDG_STATE_HOME`, `XDG_RUNTIME_DIR` and `TMPDIR` set to private, precreated paths:

```sh
flock /absolute/external/native-build.lock moon --target-dir /absolute/external/build build --frozen --target native --strip -j 1 cmd/otio_import cmd/edit_decisions
/absolute/external/build/native/debug/build/cmd/otio_import/otio_import.exe catalog fixtures/otio-timeline.otio 24
/absolute/external/build/native/debug/build/cmd/otio_import/otio_import.exe preview fixtures/edit-decisions.project.json fixtures/otio-timeline.otio fixtures/otio-media-map.json
/absolute/external/build/native/debug/build/cmd/otio_import/otio_import.exe import fixtures/edit-decisions.project.json fixtures/otio-timeline.otio fixtures/otio-media-map.json /absolute/fresh/cut
/absolute/external/build/native/debug/build/cmd/edit_decisions/edit_decisions.exe export /absolute/fresh/cut.project.json /absolute/fresh/cut.edl-map.json /absolute/fresh/reexport.edl "OTIO assembly"
```

The synthetic example includes Clip.1 and Clip.2, Unicode names, two media sources,
a 3-frame leading gap and a 21-frame internal gap. At 24 fps the resulting cut is
120 frames. Its 1000-tick source clock becomes 3000 ticks/second, so each frame is
exactly 125 ticks. An HTTPS reference deliberately uses an unreachable `.invalid`
host: it is only a mapping key, and no media path or URL is opened.

`catalog` and `preview` only print JSON. Import writes four new files:

- `.project.json`: the editable native snapshot, retaining the selected source
  project's media locators, production identities, intent and artifact lineage
- `.import.json`: original OTIO text, input paths and SHA-256 hashes, catalog,
  resolved picture preview and separate `audio_preview`; names and arbitrary
  source metadata stay inspectable here. `edl_scope` states the picture-only loss.
- `.edl-map.json`: generated reel bindings for the existing EDL exporter
- `.edl`: normalized picture-only cut list using source-relative and timeline-zero
  frame coordinates; the title labels this projection and audio is never encoded

Keep `.project.json` to retain the soundtrack. `.edl` and `.edl-map.json` cannot
round-trip an audiovisual project. Existing `edit_decisions export` deliberately
refuses multitrack input instead of dropping its audio. The v2 catalog tags every
item with `track_kind`, reports each track duration, and uses their maximum as
`duration_frames`; the inherited `preview` still describes picture only.

All destinations are checked before writing and then created exclusively.
Existing files, directories and symlinks are refused. A later filesystem failure
can leave a partial new bundle; retain it and retry with a fresh prefix. Inputs
are never overwritten. The report retains local paths and original metadata, so
inspect it before sharing. Generating this bundle is not permission to share it.

## Make an explicit media map

Copy `fixtures/otio-media-map.json`. `fps` is an integer 1–60 that must match every
time value. Choose a new `draft_timeline_id`. Each binding has:

- `target_url`: exact OTIO string, with no case folding, path normalization,
  percent decoding, basename guessing or network access
- `media_ref_id`: one existing video or audio media reference with known positive
  duration and a matching MIME family for its track
- `template_clip_id`: one existing clip using that media and a valid production
  identity/intent; it supplies lineage, not effects or timing
- `source_start_frame`: the OTIO source coordinate of frame zero in the mapped
  media file. This is often a timecode-frame offset, not the clip's in point.

URL tokens and mapped media IDs must each be unique. Every imported clip must
resolve, and every binding must be used by at least one clip. A declared external `available_range` must contain the clip and have the
same starting coordinate as the explicit binding. Selected ranges must also fit
the mapped native media duration; neither duration nor matching metadata proves
the files actually contain the expected footage. Inspect the mapping yourself.

One URL token cannot bind simultaneously to an audio and a video media reference;
the bounded profile requires distinct explicit bindings. Audio templates retain
the same project identity, intent and optional artifact checks as picture.

Native timeline time begins at zero. An OTIO `global_start_time` is recorded in
the catalog, not added to clip positions or reintroduced into the generated EDL.
No OTIO name, color, metadata or reference URL changes an existing media locator.

## Continue editing

Read `.project.json` with `@domain.snapshot_from_json`, create an
`EditorSession::new`, and dispatch ordinary `Trim`, `Move`, `Split`, `Undo` or
other existing native editor commands. Save the resulting snapshot under a fresh
name. A video-only draft can pass with `.edl-map.json` to `edit_decisions export`.
The focused video-only test performs a real trim, EDL reimport and undo; the
two-track test performs audio trim/gain, disk save/reopen and undo. No new browser import screen or
automatic live-Studio mutation is included. Keep original media accessible at
the locators already present in the source project; this utility copies no media.

## Supported OTIO profile and deliberate refusals

The static JSON profile is grounded in the official
[serialized data model](https://github.com/AcademySoftwareFoundation/OpenTimelineIO/blob/main/docs/tutorials/otio-serialized-schema.md)
and [file-format specification](https://opentimelineio.readthedocs.io/en/v0.15/tutorials/otio-file-format-specification.html).
It does not install or run OTIO plugins/adapters.

- Timeline.1 → one Stack.1 → exactly one Track.1 with `kind: "Video"`, and
  optionally one Track.1 with `kind: "Audio"`. Either source track order is
  accepted; native output order is video then audio. Both tracks must contain at
  least one clip; duplicate kinds, audio-only and additional tracks reject.
- Clip.1 with `media_reference`, or Clip.2 with exactly one `media_references`
  member and its explicit `active_media_reference_key`.
- ExternalReference.1 only; an explicit TimeRange.1 source range on every clip.
  Available ranges can be null/absent or explicit. Reference image bounds must
  be null/absent. All RationalTime.1 values are nonnegative whole frames with
  the same explicit integer rate; there is no rounding or inferred frame rate.
- Gap.1 with a positive duration and zero source start. Leading and interior
  gaps are preserved. A trailing gap is rejected because the native timeline
  derives its end from clips and would otherwise lose the explicit tail.
- Optional name and object metadata are retained in original text/report rather
  than applied to the native cut. Container source ranges must be null/absent;
  effects/markers must be empty/absent; enabled must be true/absent; colors must
  be null/absent. Unknown fields and unknown schemas are rejected.

Additional layers, nested sequences, transitions, image sequences, generated/missing
references, alternate media representations, markers, effects, disabled clips,
retiming, mixed/fractional rates, negative times and trimmed containers are all
unsupported and refused. The new draft starts with default clip settings, no
effects, keyframes, transitions, audio routing or buses.
Source template visual/audio settings are deliberately not copied.

Bounds: 4 MiB OTIO, 2 MiB mapping, 16 MiB project CLI inputs; 1–999 clips and
1–1999 total clips/gaps across both tracks. Timelines and source-relative clip ends must stay strictly
below 24 hours for the established EDL interchange. Frame coordinates and the
rescaled native tick clock must fit nonnegative signed 32-bit integers. JSON uses
the repository's standard parser, including its duplicate-key handling; provide
unambiguous JSON. The importer is a bounded reader, not a general OTIO validator.

## Qualification and limits

Run focused native tests with `moon --target-dir /absolute/external/build test
--frozen --target native --strip -j 1 -p editor/otio` under the same private
environment and shared build lock. The checked-in `scripts/verify_otio_import.mbtx`
accepts `SOURCE_DIR OTIO_BINARY EDL_BINARY FRESH_EVIDENCE_DIR` and verifies actual
catalog/preview/import/export/reimport files, refusal cases and unchanged inputs.
Build this runner with the same isolated native policy before invoking it.

Evidence is synthetic, spec-grounded native development coverage. No real editor
export corpus, playback, browser UI, installed lifecycle, real provider, rights
approval, reviewed master, recipient access, client acceptance, broadcast or
publication qualification is claimed. Model-provider runtime remains outside
this workflow. Broader release gates remain independently blocking.
## Exact inputs and output preflight

Whole-frame values, rates, media-map fps and source origins are validated against
their exact JSON decimal tokens before numeric conversion. Integral decimal and
exponent spellings such as `24.0` and `240e-1` are supported. Fractional tails,
including tails that binary64 would round away, are refused. Duplicate decoded
object keys are refused rather than allowing a later value to replace an earlier
one. This applies to the complete input, including retained metadata.

All four output filenames are checked without following symlinks before writing.
A dangling symlink at any sibling destination blocks the operation before any
new output is created. Exclusive file creation remains in use; unforeseen later
filesystem failures may still leave a partial set, so inspect all outputs after
an OS error.
