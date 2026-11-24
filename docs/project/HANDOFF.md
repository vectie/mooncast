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

## Cluster Mac installation and Vectie models — 2026-11-24

Installed MoonDesk `7fd15d83`, Mooncast `7ebe514`, and MoonGate `ebf4e1a` in
`/Applications` on the M4/16 GB cluster Mac `192.168.2.195`, reached through the
cluster SSH management host. All installed bundles passed strict deep signature
verification, launched through LaunchServices, and returned healthy service
responses (Desk 4201, Mooncast 4312, Gate 15721). These are local/ad-hoc builds,
not notarized releases. Existing data was preserved. Previous Desk/Gate bundles
and the installation receipt are under
`/Users/jiaanguo/moonsuite-install-20261124/` on that Mac.

The Mac runs macOS 15.7.3. Local native builds and Homebrew Whisper targeted
macOS 26 and could not be used unchanged. Rebuild the app services and Lepusa
runtime with `MACOSX_DEPLOYMENT_TARGET=15.0`, verify Mach-O minimum versions,
and build static Whisper with embedded Metal kernels and system frameworks.
MoonGate was built from isolated clean HEAD to exclude unrelated worktree edits;
MoonDesk's MoonFlow dependency and Lepusa runtime used the existing workspace.
MoonGate's registry dependency required the existing cache plus `--frozen` with
this toolchain; do not silently change dependency versions to unblock packaging.

All model weights are on `/Volumes/Vectie/MoonSuite/models` (about 3.9 GB):

- `Qwen3-ASR-1.7B-Q8_0.gguf` and its required
  `mmproj-Qwen3-ASR-1.7B-Q8_0.gguf`, from ModelScope
  `ggml-org/Qwen3-ASR-1.7B-GGUF`.
- `Index-Translate-2B.Q5_K_M.gguf`, from ModelScope
  `IndexTeam/Index-Translate-2B-GGUF`.
- `ggml-base.bin`, retained for Mooncast's existing Whisper path. The remote
  bundle's `LSEnvironment.MOONCAST_WHISPER_MODEL` points to this external file;
  its bundled model directory was omitted. Keep Vectie mounted to use models.

The three downloaded GGUF files were SHA-256 verified against ModelScope
metadata. A receipt with sources and hashes is beside them. Official
llama.cpp `b12669` is installed in the user's MoonSuite Application Support
directory; two user LaunchAgents serve ASR on loopback port 18731 and text
translation on 18732. Both use Metal, one slot, and 4096-token contexts. CORS
is restricted to the installed apps' three loopback origins. They are not
public/LAN endpoints. Initial model loading/Metal compilation took minutes;
wait for `/health` to report `ok`, not merely an open port. When replacing a
LaunchAgent, `bootout` may return before registration removal: wait for removal
before deciding whether to `bootstrap` the replacement.

On the synthetic 5.057-second Mandarin fixture used above, warm Qwen ASR
returned the correct 字幕 text in 0.402 s. Index translated it into complete
English in 0.336 s: “Hello, today we're testing the subtitles. We can translate
Chinese into English.” These warm synthetic observations are not live-caption
latency guarantees. After restarting with restricted CORS, both services again
reported healthy; the same ASR test took 0.662 s without a prompt-cache hit.
Chinese-to-French and Chinese-to-Japanese smoke checks returned complete
target-language sentences in 0.564 s and 0.403 s. Other speech languages and
long-form quality were not tested. Qwen's transcription response contains
`language Chinese<asr_text>` before the text; a future adapter must parse this
metadata rather than display it as caption content. Static Whisper ran with
the external base model, but still confused 字幕 with 字母.

**Installation is not product integration.** Mooncast still uses its existing
Whisper chunk-preview backend; the standalone Player still has no caption or
translation controls. No Qwen/Index adapter, target-language UI, timed caption
track, or live end-to-end acceptance has been implemented by this deployment.
Desk and Player screens were verified over SSH-forwarded browser connections.
Gate serves its UI successfully at its native origin; the alternate forwarded
port is correctly rejected by its authority checks. Do not weaken that check
just to permit a verification tunnel. Remote native window interaction was
not verified from this machine.

## Four-product UI and transparent icon pass — 2026-11-24

Mooncast now consumes the canonical MoonSuite website mark (copied from
`../vectie.github.io/logos/mooncast.svg`) in both Studio and Editor. Its Lepusa
manifest declares `assets/mooncast.icns`, generated from the padded macOS SVG.
All four apps now use their own recognizable mark in the same visual family,
not one indistinguishable icon copied onto every product.

Quick Look's thumbnail renderer flattened outer icon padding to opaque white.
Checking `hasAlpha` did not detect this. The MoonBit generator
`scripts/generate_macos_icon.mbtx` uses `rsvg-convert` without a background,
resizes all ten icon representations, and rejects nonzero corner alpha. It
requires rsvg-convert, ffmpeg, sips and iconutil on PATH. All four corner pixels
at every icon size passed for Desk, Mooncast, Gate and Proj; the installed ICNS
hashes match these independently regenerated outputs. No white padding remains.

Player no longer shows project selectors, revision/draft status or editing-only
publication warnings. Empty Editor shows one explicit Create creative workspace
action rather than empty filters and inactive clip controls. The existing
OpenProject effect still owns creation; no second workflow was introduced.
Error/retry states and Graph/Review project controls remain separate. Tests
retain the local Player file across project changes and cover the first-edit
surface. Full UI JS suite: 164 passed. Production build passes; the existing
large Editor/Studio chunk warnings remain, so no startup improvement is claimed.

Working style/UI/UX guidance was verified across all four repositories: Desk
and Mooncast already matched; Gate and Proj received the missing sections with
local style paths. Gate's native suite passed 1,209 tests; Desk UI 839; Proj UI
536 with its required plan fixture directory. A failed first pass exposed the
missing fixture environment, not a product regression. Generated interfaces
were reviewed, and formatter-only churn outside changed UI files was removed.
For individual files prefer `moonfmt -w` over module-wide `moon fmt`.

The four signed macOS 15 apps and rebuilt resources are installed on the Mac.
Rollback bundles and receipts are in the remote user's
`moonsuite-install-20261124` directory. Existing projects, Books, databases,
credentials and external model storage were preserved. Remote native windows
can outlive SIGTERM after their services stop; verify process exit before
replacement. This pass changes presentation and first-use navigation, not
caption-model integration, provider binding, database setup, or every advanced
workflow's acceptance. Direct remote WKWebView interaction remains unverified.

Final browser checks covered the installed resource paths, Player ↔ Editor,
Desk's empty-name/ID availability and one-row destination bar, product search
and read-only selection, collapsed assessment groups, and Gate's next-action
route to App Bindings. No binding/configuration or company transaction was
submitted. Gate's 375px navigation now scrolls locally without horizontal page
overflow (document width 375px); other desktop screens were checked at 1280px.
Remaining existing mixed-language labels and advanced workflow acceptance are
not represented as completed by this focused presentation pass.

### Cluster Launchpad follow-up

The installed ICNS hashes were rechecked on 192.168.2.195 and still match the
transparent outputs. LaunchServices had indexed staged/rollback `.app` copies
and old disk-image paths. Launchpad's read-only database inspection found an
extra MoonGate entry bookmarked to `backups/MoonGate.app` and two MoonDesk
entries bookmarked to `/Applications/MoonDesk.app`. Unregistered only these
products' noncanonical copies, touched and force-registered the four canonical
`/Applications` bundles, and restarted the user's Dock. LaunchServices now
lists only the four canonical apps. Launchpad still retained its duplicate
database rows at the follow-up check; do not claim that unregistering alone
removed them or that its rendered icons were visually verified. Requested a
cluster Launchpad screenshot. No Launchpad database reset, layout deletion,
backup removal, app-data change or local-Mac installation was performed.
The icon artwork remains the same family; transparency changes outer padding,
not the intentional dark face or white product glyph.

The user's MoonDesk follow-up exposed a missed padding mismatch: its macOS SVG
was full-bleed despite passing transparent-corner checks. Corrected it to the
same 1024px/inset geometry as the other three icons, regenerated the ICNS and
installed it on the cluster Mac using the new `AppIcon-padded-20261124` basename
to invalidate the prior icon cache key. Strict signing verification passes.
Preserved the entire prior Desk bundle with a `.bundle` backup suffix to avoid
creating another registered `.app`. The decoded final ICNS was visually checked;
do not substitute corner transparency for silhouette/inset verification or
claim remote Launchpad visual acceptance without confirmation.
