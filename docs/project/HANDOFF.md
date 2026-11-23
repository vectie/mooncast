# Mooncast project handoff

## MoonBit formatting scope

With the current MoonBit toolchain, `moon fmt` can rewrite additional files in
the enclosing UI module even when explicit file paths are supplied. Capture the
working-tree status before formatting, review the complete diff afterward, and
restore only files that were clean before the command. Never discard existing
user changes while removing formatter-only churn.

## Studio production bundle baseline

The 2026-11-23 Studio UI build produces a 1,004.42 kB JavaScript chunk
(170.59 kB gzip) and a 24.03 kB stylesheet (5.70 kB gzip). Vite continues to
warn that the Studio chunk exceeds 500 kB. The shell rebuild added about
1.46 kB of raw JavaScript and 4.74 kB of raw CSS over the preceding baseline;
future feature work should split Studio workspaces by route or feature instead
of growing the initial bundle indefinitely.

## Local caption preview and playback controls

The editor now opens on its playback lens. Playback speed (0.5 to 4 times)
changes monitoring only; preview quality changes the canvas resolution; export
resolution sets the actual export dimensions to 720p, 1080p, or 4K.

Local caption preview uses whisper.cpp and the bundled FFmpeg. Configure
`MOONCAST_WHISPER_BIN` (default `/opt/homebrew/bin/whisper-cli`) and
`MOONCAST_WHISPER_MODEL` (default `.tools/whisper/ggml-base.bin`). The multilingual
base model was downloaded locally for verification and is ignored by Git.
Inference sends no audio to external services.

Live mode processes up to eight seconds from the first audible audio track.
Solo a dialogue or voice track when other audio tracks overlap. Source windows
respect clip in/out boundaries. Responses are associated with project, revision,
source, position, and translation mode; requests run one at a time. These are
chunk previews with processing latency, not synchronized word captions or a
saved/exported subtitle track. Whisper translation currently targets English.
Full-track caption creation, editable cue persistence, and other target
languages remain follow-up work.

The native regression can run real inference with
`MOONCAST_LOCAL_CAPTION_TEST_AUDIO` pointing to a local speech WAV. It imports
that file into an isolated editor project, places it on the timeline, and calls
the same HTTP route as the browser. `MOONCAST_LOCAL_CAPTION_TEST_ROOT` optionally
sets that isolated data directory. The running local review server uses
`/tmp/mooncast-player-ui` and contains synthetic test speech only.

## Standalone Player and installed Mac app

Player is a distinct lens after Review, with a Studio shortcut and the direct
route `/apps/mooncast/editor/player`. Local media uses object URLs and needs no
project or upload. The installed `/Applications/Mooncast.app` serves its bundled
UI and native service on port 4312; keep it independent of development on 4302.
The bundle includes FFmpeg, Whisper, its GGML backends, and the base model.

Lepusa's shell entry point originally launched a differently named window
process. Native automation could see the app but could not find its window.
The adjacent Lepusa checkout now supports argument-free bundled runtime launch
(`cmd/runtime/main.mbt` and its package imports). Mooncast's
`scripts/finalize_macos.mbtx` installs that runtime as the declared native entry
and ad-hoc signs the bundle. Build the updated Lepusa runtime before packaging;
the finalizer alone is insufficient with the old runtime. Build instructions
are in `docs/mooncast-lepusa-release.md`.

The preparation/finalization `.mbtx` scripts use async 0.19.4 and must run with
`--target native` on the current toolchain. GGML plugins need their dylib load
paths rewritten as well as the CLI; rewriting only the CLI leaves Homebrew
dependencies in an otherwise portable bundle. Packaged inference sets
`GGML_BACKEND_PATH` explicitly to the bundled plugin directory.

On 2026-11-23, the installed app was opened through LaunchServices, its Studio
Player link opened the distinct Player tab, the macOS file picker selected a
synthetic five-second H.264/AAC MP4, and the native WKWebView displayed video
with its Pause control active. The same bundled route also passed browser
playback verification. The build is local/ad-hoc signed, not notarized for
public distribution.

Do not merge a new Mach-O-entry bundle over a previous shell-entry installation
with `ditto`: obsolete `CodeDirectory`, `CodeRequirements`, and `CodeSignature`
files can survive in `Contents/_CodeSignature`, making strict verification fail.
Install into a fresh destination or preserve/remove those obsolete files, then
run `codesign --verify --deep --strict` on the installed app as well as the build.

## Caption and translation acceptance check — 2026-11-23

Tested the installed bundle's Whisper executable, GGML libraries and base model
through the actual local-caption service route, using generated Mandarin speech:
“你好，今天我们测试字幕。我们可以把中文翻译成英文。”
The WAV is 5.057 seconds; the registered timeline clip spans eight seconds.
An isolated service/project on port 4313 served the installed production UI;
no existing user project was changed. The native Player on 4312 was inspected
separately and has no caption or translation controls yet.

Results:

- Mandarin transcription returned “你好,今天我们测试字母,我们可以把中文翻译成英文。”
  It recognizes speech but confuses 字幕 with its homophone 字母.
- English translation returned “Hi, today we test字母, we can turn the Chinese翻译成英文”.
  This fails an English-only acceptance check; enabling translation is not proof
  that the model produces a complete usable translation.
- First measured service transcription took 11,287 ms; subsequent Mandarin
  transcription/translation took 578/414 ms. English speech took 439/412 ms.
  These are observations on this machine, not guaranteed latency bounds.
- With live mode enabled and timeline playback active, the browser displayed
  Mandarin text after 1,691 ms and translated text after 1,654 ms on warm runs.
  The whole chunk appears together below the monitor, without cue/word timing.
  At the end of the clip it disappears because there is no active source;
  seeking back restores the cached result. Live mode also runs while paused.
- The English fixture passed both inference modes. The Mandarin fixture passed
  transcription but failed the stronger translation check (one of two tests
  failed). This is an unresolved product-quality issue, not a passing release
  qualification. No larger model, target-language selector, streaming worker,
  exported caption track, or standalone Player integration was implemented as
  part of this testing request.

The opt-in real-model regression now runs both modes, prints elapsed time and
text, validates SRT output, and rejects retained CJK ideographs in an English
translation. Supply `MOONCAST_LOCAL_CAPTION_TEST_AUDIO`, optionally
`MOONCAST_LOCAL_CAPTION_TEST_EXPECT_SOURCE` and
`MOONCAST_LOCAL_CAPTION_TEST_EXPECT_TRANSLATION` (both default to `moon`). Use
`LEPUSA_APP_DIR=/Applications/Mooncast.app/Contents` to test the bundled runtime
and model. Run `moon test studio_service/local_captions_wbtest.mbt --target native
--strip -j 2`. Without an audio fixture, the real-inference test returns early;
ordinary test-suite success must not be presented as model acceptance.
