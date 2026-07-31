# Mooncast Lepusa release baseline

Mooncast's checked-in `lepusa.json` targets Lepusa 0.1.4. It opens Mooncast
Studio at `http://127.0.0.1:4302/apps/mooncast/studio`, waits on `/health`, and
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

## Local verification and UI handoff

Build Mooncast's native sidecar first:

```sh
moon build --target native --release cmd/studio
```

Use Lepusa 0.1.4 from an installed package or checkout. For a checkout, run its
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
