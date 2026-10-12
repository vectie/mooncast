# Collect an editable project with its media

`cmd/project_collect` makes a portable local editing folder from a native
`mooncast.editor-project.v1` snapshot and its media root. It copies actual bytes,
rewrites the snapshot's media locators, and keeps the complete editable cut.
Use it to move work to another disk or prepare a folder for a later authorized
handoff. No running Studio, media registry or external service is changed.

This fills the gap between exporting a snapshot and
[relinking already-moved media](media-relinking.md). It supports the editor's
retained creative state in PRD MC-W04 / MOONCAST-B08.

## Preview, collect, reopen

With the repository's pinned native graph available, build to an external path:

```sh
moon --target-dir /absolute/external/mooncast-build build cmd/project_collect --target native --frozen --strip -j 1
COLLECT=/absolute/external/mooncast-build/native/debug/build/cmd/project_collect/project_collect.exe
"$COLLECT" preview project.json '/local/media root'
"$COLLECT" collect project.json '/local/media root' '/local/handoffs/episode edit'
"$COLLECT" verify '/local/handoffs/episode edit'
```

Preview reads and hashes every source locator, including unused library assets
and repeated-content aliases. It prints media IDs, original and collected paths,
unique file count and required media-copy bytes without creating output. A
collect performs its own fresh preflight; a previous preview is not reused.

The destination parent must already exist and the final folder must be new.
Collection writes:

- `project.json`: the existing native editor snapshot, with portable locators
- `media/`: real byte-for-byte file copies, named by SHA-256 plus source suffix
- `collection.json`: source and output content bindings, exact project-byte
  digest, original-to-collected media mapping and copied-file inventory

Point a native snapshot consumer at `project.json` and use the collected folder
as its media root. The entire folder can be renamed or moved. `verify FOLDER`
checks the project bytes, semantic binding, complete media inventory and every
collected file using only that folder. It never consults the original source
root. For example, chapter authoring can reopen the collected snapshot:

```sh
chapters seed '/local/handoffs/episode edit/project.json' video new.chapters.json
```

Use the correct track ID from your own snapshot. The collection is an editable
local snapshot, not automatic installation in a running Studio.

## What is preserved

All native media references are included, even unused library assets. No clip,
media ID, production identity, intent or artifact record is removed or merged.
Two references with the same exact bytes and same filename suffix share a single
collected file; their IDs and metadata remain distinct. Different suffixes are
retained separately because existing consumers may select a parser by suffix.
Different-content files with the same original filename cannot collide.

Only media locator URIs and, when any locator changes, the project revision
change. Timeline revision, cut timing, settings, keyframes, effects, audio
routing and buses remain intact. Media are never decoded, trimmed, transcoded
or recompressed by the collector. The source snapshot and files are untouched.
Retain the original snapshot for manual undo. Hashes establish byte identity,
not rights, author authenticity or accurate media metadata.

This is not a complete archive of a Studio data root. Only the native snapshot's
`media_refs` are copied. Separate rights records, provider jobs, font files,
external resource/service state, event logs, render caches and companion
caption/chapter drafts outside those references are not gathered. A successful
collection is not a rendered/approved master, client delivery, verified client
access, acceptance or publication. Sharing the folder remains a separate action.

## Limits and interrupted work

- The input is a typed native snapshot with 1–1000 media references, valid
  lowercase SHA-256 digests and known sizes. Project JSON is capped at 16 MiB.
  Old metadata-only fixtures with `synthetic` digests need real media metadata.
- Every locator must be `pack-relative`, using the existing portable ASCII
  path profile (letters, digits, `.`, `_`, `-`, `/`; no empty, `.` or `..`
  segments, URLs, absolute paths or backslashes). Unicode and spaces work in
  the explicit source root and destination folder.
- Symlinks beneath the selected source or collected root are refused. The
  explicitly selected root itself may resolve to a canonical directory. Use
  trusted, quiescent local folders; these checks are not an OS sandbox against
  hostile concurrent filesystem changes.
- Each media file is at most 256 MiB. Aggregate declared source bytes (counting
  every media reference) are at most 4 GiB. Unique copied content includes
  separate suffix variants. JSON byte totals are decimal strings (64-bit values). The preview's byte count excludes small
  metadata files and filesystem overhead. Ensure adequate free disk space.
  Hashing/copying uses 1 MiB chunks, including sources larger than one chunk.
- Collection verifies every source before creating a destination. It hashes
  exact copied bytes, checks source size/mtime across copying, rereads copied
  files, and checks that source project bytes did not change before success.
  It cannot detect a concurrent change-and-restore race.
- Existing destination entries, including dangling symlinks, are refused.
  Exclusive file creation prevents overwrites. A late I/O or concurrent-source
  failure can leave a new partial folder. Nothing is removed or retried into
  it. Retain it for diagnosis, fix the cause and choose another new folder.
- `collection.json` is written last. An absent or malformed manifest is an
  incomplete collection; `verify` refuses it. Verification is content/inventory
  checking, not a guarantee of playable media or acceptance by every editor.
  Source bindings are local lineage claims, not signatures.

## Focused reproducible acceptance

`scripts/verify_project_collection.py` accepts `--source`, `--target`, and a
fresh `--output` path. Build `cmd/project_collect` and `cmd/chapters` first. The
script generates a tiny synthetic H.264 video and a multi-chunk WAV, collects two
video IDs plus unused audio/captions into three actual files, relocates the
folder and removes the old root from its original path by renaming it. It then
verifies the moved collection, reopens it in chapter authoring, inspects copied
media with FFprobe and checks no-overwrite, missing/changed media, symlinks,
manifest omissions and incomplete output. Every input, output and failure log
is retained. It uses Python's standard library and existing FFmpeg/FFprobe.

Native package tests cover deduplication without ID merging, suffix retention,
unused media, basename collisions, snapshot/manifest round trip, transform and
keyframe preservation, limits and missing/unsafe references. This is focused
local interoperability evidence only; cumulative qualification remains R50.
