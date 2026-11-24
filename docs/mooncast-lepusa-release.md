# Mooncast Lepusa release baseline

Mooncast's checked-in `lepusa.json` is verified against Lepusa 0.1.6. It opens Mooncast
Studio at `http://127.0.0.1:4312/apps/mooncast/studio`, waits on `/health`, and
supervises the native `mooncast-studio` sidecar.

The manifest grants the `studio` window only the two host capabilities required
by the current workflow:

- `localhost` for service status, readiness, and lifecycle
- `file-dialog` for choosing media without exposing a broad filesystem scope

The native Studio binary, Rabbita release directory, and the approved
ffmpeg/ffprobe executables are Lepusa bundle resources. The packaged launcher
starts in Lepusa's shared resource directory, while Studio resolves executable
media tools from the macOS app directory and writes durable state under
`LEPUSA_APP_DATA_DIR/mooncast`. No absolute workspace path or local Lepusa
checkout is part of the application manifest.

The cfy reference tree does not provide a Lepusa application manifest. Mooncast
therefore borrows graph-workspace behavior from cfy, but keeps packaging on the
native Lepusa contract below instead of importing cfy's Python/server launch
model. Workspace graph, asset, scheduler, share and event routes all remain
behind the same supervised loopback Studio sidecar and require no additional
Lepusa capability grant.

## Local verification and UI handoff

Build Mooncast's native sidecar first:

```sh
moon build --target native --release cmd/studio
```

Use Lepusa 0.1.6 from an installed package or checkout. For a checkout, run its
MoonBit CLI while keeping Mooncast's release binary on `PATH`:

```sh
export PATH="$PWD/_build/native/release/build/cmd/studio:$PATH"
moon -C "$LEPUSA_WORKSPACE" run cmd/main --target native -- \
  verify macos --strict --project "$PWD/lepusa.json"
moon -C "$LEPUSA_WORKSPACE" run cmd/main --target native -- \
  run macos --launch --project "$PWD/lepusa.json"
```

`run --launch` is the handoff point: Lepusa owns the desktop window and
sidecar lifecycle, while Mooncast owns the Studio HTTP routes and production
behavior. Closing the Lepusa window must stop its supervised Studio process.

## Standalone Mac app and player

The installed app is `/Applications/Mooncast.app`. The Player tab follows Review
in the workspace header and is also reachable from Studio. Its direct route is
`/apps/mooncast/editor/player`. It opens local video/audio files as browser blob
URLs without uploading them, and can play the current completed project render.
The app uses port 4312 independently of the browser development server on 4302.

Player's **Live captions** toggle samples playback audio in bounded four-second
windows, without importing the media into a project. **Translate to** selects
English, Chinese, Japanese, Korean, French, German, Spanish, Russian or Arabic;
Off keeps source-language captions only. Play the media after enabling captions.
Both source and translated text appear above the video controls, with processing
delay. Stop captions does not stop playback. These previews are not saved or
exported; the HTML overlay is not shown in native video full-screen mode.

The Player backend calls local Qwen ASR at `127.0.0.1:18731` and Index Translate
at `127.0.0.1:18732`. Those services must run on the same Mac as Mooncast; no
cloud fallback or LAN model endpoint is used. The cluster Mac's models remain
on `/Volumes/Vectie/MoonSuite/models`. Missing services produce a retryable
Player error rather than silently using another provider. The Editor's earlier
Whisper controls remain independent.

For a macOS 15 build on a newer development Mac, set
`MACOSX_DEPLOYMENT_TARGET=15.0` and use a fresh Moon `--target-dir`. A cached
macOS 26 async C stub can retain unavailable symbols even when the executable
reports a 15.0 minimum. Verify the new service on the target before replacing
the app, then sign and strictly verify the installed bundle.

Prepare local speech dependencies with
`moon run --target native scripts/prepare_whisper_runtime.mbtx`. This stages
Whisper, GGML CPU/Metal backends, OpenMP, and licenses, rewrites their dynamic
library references, and signs the staged binaries. Place the multilingual base
model at `.tools/whisper/ggml-base.bin`. Both the runtime and model are bundled.

For the native entry point, the updated adjacent Lepusa runtime recognizes an argument-free launch
from `Contents/MacOS`, initializes its resource/data paths, and opens the bundled
manifest. Build that runtime from the adjacent Lepusa checkout and the production
UI, then build and finalize the bundle:

```sh
moon -C ../lepusa build --target native --release cmd/runtime
moon -C ../lepusa build --target native --release cmd/main
cd ui/rabbita-mooncast
npm run build
cd ../..
LEPUSA_RUNTIME_EXECUTABLE="$PWD/../lepusa/_build/native/release/build/cmd/runtime/runtime.exe" \
  ../lepusa/_build/native/release/build/cmd/main/main.exe build macos \
  "$PWD/_build/lepusa/desktop" --project "$PWD/lepusa.json"
moon run --target native scripts/finalize_macos.mbtx "$PWD/_build/lepusa/desktop/mooncast.app"
```

The finalizer installs the native runtime as the declared application executable
and applies an ad-hoc signature. This keeps the window process associated with
Mooncast in LaunchServices. The original shell launcher caused native window
discovery failures during this verification. The runtime changes live in
`../lepusa/cmd/runtime/main.mbt` and its `moon.pkg`; they must accompany the
Mooncast changes when reproducing this build.

The installed app was verified through its native window: Studio → Player,
macOS file picker → local H.264/AAC video, then active video playback. Its
packaged HTTP route also decoded and played the same file in the browser.

The checked-in signing identity is `-`, macOS ad-hoc signing, so local strict
release gates have concrete signing metadata. Replace it with the publisher's
Developer ID configuration (and notarization profile) before public
distribution.

## Release gate

Run the MoonBit contract tests and regenerate package interfaces:

```sh
moon test release/lepusa_contract --target native
moon check --target native --warn-list +73
moon info
moon fmt
```

The contract tests lock `lepusa.json` to `pack.json`, assert the fixed loopback
URL and health path, reject workspace-local dependency paths, and require the
file-dialog/localhost grants plus the Studio, Rabbita, ffmpeg, and ffprobe
bundle resources.

Lepusa's strict verifier is the authoritative parser and release-readiness
gate. If it fails before launch, keep the failure in the handoff log; do not
replace the portable `mooncast-studio` command with an absolute build path.
