# Reopen a project after moving its media

`cmd/media_relink` inventories a native editor snapshot, creates an editable
media-ID/path map, checks the relocated files against the snapshot's exact
SHA-256 and byte sizes, and saves a separate native snapshot with repaired
locators. Use it when moving a project folder or reorganizing source files.
There is no filename guessing, substitute take, transcoding, media copy or
rights decision.

## Inventory, map, verify, apply

From the repository root, using the native MoonBit toolchain (qualified here:
moon 0.1.20260920, moonc 0.10.14), with the module's declared dependencies
available: `moonbitlang/async@0.19.4`, `moonbitlang/x@0.4.50`, and
`vectie/moonlib@0.1.19`. A fresh checkout needs its ordinary dependency setup
first (`moon install --target-dir ../mooncast-relink-build`; this compiler
still supports dependency installation without arguments, although deprecated).
Then build with a frozen graph and an external target:

```sh
moon build --frozen --target native --strip -j 1 --target-dir ../mooncast-relink-build cmd/media_relink
../mooncast-relink-build/native/debug/build/cmd/media_relink/media_relink.exe inventory project.json
../mooncast-relink-build/native/debug/build/cmd/media_relink/media_relink.exe seed project.json moved-media.json
# Edit only new_uri values in moved-media.json.
../mooncast-relink-build/native/debug/build/cmd/media_relink/media_relink.exe preview project.json '/local/media root' moved-media.json
../mooncast-relink-build/native/debug/build/cmd/media_relink/media_relink.exe apply project.json '/local/media root' moved-media.json relocated
```

Inventory reads only the project JSON. It lists each media ID, declared locator,
SHA-256, byte size and the timeline clips that use it; it does not open those
locators or decide that the files exist. `seed` similarly does not read media.
The project must already have real lowercase SHA-256 values and known sizes.
The repository's older `edit-decisions.project.json` is metadata-only and has
synthetic digests, so it cannot be relinked without real input metadata.

The generated map looks like this:

```json
{
  "contract": "mooncast.media-relink-map.v1",
  "source_binding": "sha256:<generated binding; keep unchanged>",
  "replacements": [
    {"media_ref_id": "media.a", "new_uri": "relocated/camera-a.mp4"},
    {"media_ref_id": "media.b", "new_uri": "relocated/camera-b.mp4"}
  ]
}
```

Keep media IDs and source binding unchanged. You can remove unchanged rows for
a partial map, but at least one row is required. Omitted references keep their
existing locator. Reordering rows does not reorder the media library or cut.
Two media IDs may point to one file only when that file satisfies both declared
hashes and sizes; neither ID is merged or deleted.

`MEDIA_ROOT` is an explicit existing local directory. Every resulting locator,
including an omitted/unchanged one, is resolved under this root. Therefore a
successful preview shows the whole snapshot's media can be found there. Missing
files or an incorrect candidate fail the command. Preview writes no files.
Apply rereads and hashes every candidate; an earlier preview is never used as
proof that its bytes are still correct.

## Outputs and opening the draft

Apply writes `relocated.project.json` and `relocated.relink.json` only after all
resulting media pass. The first is the existing `mooncast.editor-project.v1`
format, accepted by `@domain.snapshot_from_json`, `EditorSession::dispatch`,
render-plan freezing, EDL export and chapter authoring. It is not a new project
schema. Project revision increases once if any URI changed; timeline revision,
timing, effects, audio settings, production identities, artifacts, media IDs,
metadata and intent references are unchanged. A no-op map keeps the revision.
Input bytes and media bytes are never modified.

The receipt records the canonical media root, source/output content bindings,
changed locators and each verified file. Open the draft with that root wherever
your snapshot consumer resolves pack-relative locators. The root is deliberately
not embedded as an absolute URI in the project. This CLI does not install the
draft in a running Studio, rewrite its separate media registry, copy rights
records outside the snapshot, render a cut, or promote a master. Those are
separate host/application workflows. A hash match proves byte identity, not
permission to use the file or that its recorded metadata is accurate.

The original snapshot remains the manual undo. After any other project edit,
seed a fresh map: the content binding detects stale maps even when someone
changed content without incrementing a revision. Formatting-only JSON changes
do not invalidate the typed semantic binding. Bindings and receipts are local
integrity evidence, not signatures, client acceptance or authorization.

## Paths, bounds and recovery

- Media URIs follow the existing portable native schema: relative ASCII letters,
  digits, `_`, `-`, `.`, and `/`, with no `..`, empty segments or `.` segments.
  Absolute paths, URLs, backslashes and traversal are rejected. This workflow
  does not silently rename nonportable files. Unicode/spaces work in the
  explicit root and project/map/output filenames, not within media URIs.
- Symlinks below the selected root are refused, including intermediate folders.
  The explicitly supplied root itself is resolved to a canonical directory.
  Use a trusted, quiescent local folder: path checks and file reads are not an
  operating-system sandbox against concurrent hostile filesystem changes.
- Up to 1000 media references, 16 MiB project JSON, 2 MiB map JSON, 256 MiB per
  media file and 4 GiB aggregate declared media size. Hashing uses 1 MiB chunks;
  larger sources need a separate workflow rather than an implicit partial hash.
  Each media ID is verified independently, including shared paths.
- All output paths must be new and their parent directory must exist. Both
  output names are checked without following symlinks, so dangling symlinks,
  directories and other existing entries reject the whole pair before writing.
  Exclusive creation also prevents
  overwrite. A later filesystem failure can leave a partial new pair; retain
  it, resolve the failure and choose a new prefix. No files are removed.
- Typed native snapshots are supported, not unknown extension fields or a
  session/event-log file. No media decoding, source search, codec conversion,
  online downloads, network calls or live-store mutation is performed.

The accompanying synthetic workflow creates and decodes real local media,
relinks two IDs to the same verified relocated file, reopens the native snapshot
through chapter authoring, and checks refusal cases. It is local interoperability
evidence, not real-provider production or a qualified client delivery.

The separate legacy `schemas/editor-project.schema.json` predates native
keyframes/effects/transitions/audio buses and rejects the pre-existing native
fixture as well as this output. Compatibility here is qualified against the
current typed native codec and actual consumers, not that older JSON schema.

## Try the delivered synthetic example

The accompanying kit contains actual inputs and outputs under
`workflow-preflight/`. After building the CLI above, set `KIT` to its extracted
absolute location. These preview commands work without the original cloud
paths; receipts retain their original run paths as evidence.

```sh
KIT=/absolute/path/to/kit
../mooncast-relink-build/native/debug/build/cmd/media_relink/media_relink.exe inventory "$KIT/workflow-preflight/source café.json"
../mooncast-relink-build/native/debug/build/cmd/media_relink/media_relink.exe preview "$KIT/workflow-preflight/source café.json" "$KIT/workflow-preflight/media café space" "$KIT/workflow-preflight/map café.json"
../mooncast-relink-build/native/debug/build/cmd/media_relink/media_relink.exe apply "$KIT/workflow-preflight/source café.json" "$KIT/workflow-preflight/media café space" "$KIT/workflow-preflight/map café.json" relocated-demo
```

Choose a new output prefix for each apply. `original-media.mp4` and
`media café space/relocated/shot-a.mp4` are the same generated ten-second video;
the two existing clip/media identities intentionally share that content.
The additional `chunks.bin` scenario is a byte-hashing test, not decodable
media. Production use needs genuine snapshot hashes and media you may edit.

Dependency retrieval from a registry was not exercised: qualification used the
accepted base's unchanged private dependency sources. The current native
consumer checks and the known legacy-schema failure are retained in the kit's
run evidence and handoff.
