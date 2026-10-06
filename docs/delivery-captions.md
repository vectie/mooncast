# Verified captions in local delivery

The Studio Delivery action requests a sidecar from the exact promoted editor
export. It never accepts a caller filesystem path or generates/transcribes text.
The selected SRT must match the export provenance SHA-256 and the frozen render
plan's subtitle cues. Its project, episode, export, source bindings, master and
plan versions are checked before a build is queued.

Use **Preview selected captions and download SRT** in Delivery to inspect the
actual text, timestamps and source/version evidence. The page explains how to
restore missing evidence or open Cut Editor and promote a corrected export.
The source format does not record a language tag. The selection therefore uses
`und` and explicitly records that language is unknown; it does not copy an
unrelated animatic language or infer a language from the text.

## Contiguous channel cuts

Delivery can optionally create one Studio-selected cut from the promoted master.
Enter start/end seconds with at most millisecond precision, then use **Preview
selected cut captions and download SRT**. The preview identifies the exact master
and selected range. Blank fields leave the full-master delivery unchanged.
The API also supports independent contiguous cuts from spatial-only variants.
It does not concatenate or reorder cuts, change speed, or support a cut as the
source of another cut. Export and promote such an edited timeline in Cut Editor
before creating its delivery build.

Each cut intersects the verified source cues with the half-open selected range,
clips cues crossing either boundary, omits zero-duration intersections and
subtracts the cut's start time. Text, Unicode, line breaks, source selection,
language evidence and rights references are retained. Endpoints must be finite,
nonnegative whole milliseconds, with positive duration, inside the master and no
longer than 180 seconds. A range containing no verified cues is rejected with a
repair action instead of silently omitting required captions.

Each trimmed output has a separate digest-bound SRT in the ZIP. Full-length
outputs share the unchanged master sidecar. The subtitle manifest maps every
captioned output to its exact filename, digest, source interval, cue mapping,
boundary policy and derivation version; the source selection retains language
and rights provenance. The cut preview/download uses the same derivation as the
build. Creating a cut never edits the source SRT, master or earlier archives.

Queueing freezes a content-bound copy. The build profile identity includes the
caption selection, so different caption/version evidence cannot silently reuse
an old build identity. The delivery service verifies the frozen copy's SHA-256,
project and master binding, and copies SRT bytes without FFmpeg reserialization.
The ZIP's subtitle manifest and provenance retain the exact selection metadata,
cue timing, parser version, and source/rights references. Master subtitles remain
embedded where the verified source master contains them; they are not described
as burned-in. Client acceptance continues to use a separate receipt and cannot
rewrite an archive.

Scope: this closes the local required-caption production-handler/package gap and
bounded contiguous-cut caption rebasing in MOONCAST-R02/N05, with B07/B09/N02
provenance. Synthetic fixtures exercise full-master delivery, a 12-second actual
FFmpeg master trimmed to 3 seconds directly and through a spatial-only variant,
exact ZIP sidecar bytes and immutable prior artifacts. The promoted 180-second
episode fixture also exercises the production cut preview and build handler.
This does not prove deployed recipient access, live browser playback/accessibility,
translation, transcription, arbitrary timeline retiming or reordering. Existing gate and
rights rules remain in force. No customer acceptance, payment or publication is
inferred from the synthetic test.
