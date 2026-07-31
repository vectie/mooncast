# Utility video concat: UI journey and handoff

Status: completed, 2026-07-23

## Requested outcome

Use Mooncast's user interface to combine every video in
`~/Downloads/47` into one video, without using a command-line media operation.
Any product gaps discovered during the journey must be fixed in MoonBit and
recorded here.

## Source set

- 44 MP4 files
- deterministic order: safe file name, ascending
- approximately 625 MiB of source media
- approximately 132 minutes total duration
- portrait 720×1280 HEVC video
- HE-AAC stereo audio; 40 sources at 44.1 kHz and four at 48 kHz
- 43 sources at 30 fps and one source at 60 fps

The source inspection is evidence for implementation bounds only. The final
selection, upload, concat, and download must be driven from Mooncast's UI.

## Journey log

### 1. Studio was not running

The first browser navigation to
`http://127.0.0.1:4302/apps/mooncast/studio` failed with connection refused.

Resolution: start the checked-in native MoonBit Studio host with the built
Rabbita release. This is application bootstrap, not a command-line media edit.

### 2. A utility edit was forced through commercial production intake

Studio would not create the test project with a zero budget. It required a
3–8 minute duration and a positive budget, even though the requested operation
only combines existing local clips.

Temporary observation: the smallest accepted budget was CNY 1.

Product resolution: do not weaken the governed G0–G7 production contract.
Provide a separate, explicitly named utility-concat workflow that creates no
commercial quote, production gate, master promotion, delivery acceptance, or
publication authority.

### 3. The Editor could not open the new project

The Cut Editor accepts an existing editor project or imports a production
project at G4. The newly created Studio project was still at G0. The UI reported
an unsupported workspace response because the failed production import was
followed by a project read whose typed error envelope was decoded as an editor
workspace.

Resolution:

- utility concat must be available without a production project;
- failed production imports must remain typed errors and must not be presented
  as workspace-contract incompatibility.

### 4. Local media intake did not select or upload video bytes

The existing local-media drawer:

- offered only voice, music, SFX, subtitle, image, and logo roles;
- accepted only audio, image, and text file types;
- allowed one file;
- recorded the browser file input's display value;
- uploaded the text-area value instead of the selected Blob bytes.

Resolution: add a MoonBit/Rabbita multi-file video picker, retain the selected
Blobs as opaque browser values, upload exact binary bodies one at a time, show
ordered progress, and expose the completed artifact as a UI download.

### 5. The domain intake rejected video

`editor/media` rejected `video/*`, did not define a video role, and mapped all
non-overlay local media to an audio track.

Resolution: add explicit video MIME validation and video-track binding. Keep
rights/source evidence requirements for governed editor intake; utility concat
uses its own narrower immutable source manifest.

### 6. Governed export is intentionally unsuitable for this source set

The existing production export requires:

- 180–480 seconds;
- audio;
- subtitle cues;
- a governed production source;
- a render path with a 30-minute process timeout.

The requested source set is roughly 7,924 seconds with mixed audio sample
rates. Relaxing these rules globally would damage the production authority
boundary.

Resolution: utility concat is a separate contract. It preserves source order,
computes source and output digests, verifies stream compatibility, uses an
argv-only operation, stream-copies compatible H.264/HEVC video, normalizes
audio to AAC-LC 48 kHz stereo when required, and grants no promotion, delivery,
or publication authority.

### 7. Large-output handling needs a bounded path

The normal editor render path reads completed artifacts into memory and has a
1 GiB read ceiling. Long transcoding would also make the current 30-minute
timeout risky.

Resolution: the utility path operates on store-owned files, verifies and hashes
the completed output, and serves the result through a range-capable media route.
It does not materialize the entire combined video in a JSON response.

### 8. Release packaging had no Mooncast desktop contract

Mooncast currently documents a localhost browser release but has no checked-in
Lepusa application manifest or Lepusa release verification path.

Resolution: add a Lepusa 0.1.4 manifest and MoonBit contract tests. The package
uses supervised localhost startup and readiness, grants only localhost and
file-dialog capabilities, bundles the Studio executable, Rabbita release, and
ffmpeg/ffprobe executables, and writes state under Lepusa's external app-data
directory. Strict macOS verification and bundle-write checks pass. Public
distribution still requires Developer ID signing and notarization.

### 9. The first real run exposed mixed audio and HEVC metadata

The synthetic backend fixture was silent H.264. The real sources all contained
HE-AAC audio with two sample rates, and their compatible HEVC streams reported
different codec extradata sizes. The initial implementation rejected the audio
before concat.

Resolution: compare stable video decode parameters rather than extradata byte
count, preserve video with `-c:v copy`, normalize every audible input to AAC-LC
48 kHz stereo, synthesize canonical silence only when a mixed job needs it, and
verify the final video, audio, and aggregate duration. Mixed 30/60 fps,
44.1/48 kHz, and audible/silent MoonBit tests now cover the real pattern.

### 10. Relative manifest paths were resolved twice

The first compatibility retry created all 44 normalized files, then ffmpeg
resolved entries such as `var/native/editor/render-files/...` relative to the
manifest's own directory, duplicating the path.

Resolution: canonicalize every stored input and normalized output with
`realpath` before writing the concat manifest. A regression test now runs the
whole service from a relative data root.

### 11. Large browser download handoff was not deterministic

The HTML `download` attribute was treated as inline navigation by the in-app
browser, and its download-event bridge did not expose a host path for the
729 MiB response.

Resolution: the media route now sends an explicit attachment filename and the
header is covered by the HTTP range test. For this run, Finder's UI copied the
verified artifact into `~/Downloads`; no command-line media or file-copy
operation was used.

### 12. Long media execution held the Studio-wide mutation lock

The first working implementation persisted the `running` state and performed
all probing, audio normalization, and final concat while still holding the
service's global mutation lock. A long utility job could therefore delay
unrelated Studio mutations.

Resolution: acquire the lock only to validate and persist the `running` state,
execute the media process outside the lock, then reacquire it to compare the
unchanged running snapshot and commit the terminal result. A concurrent run
still fails closed because the durable job is already `running`.

### 13. Resume assumed uploads were contiguous

The first UI retry path used `uploaded_count` as the next input index. The API
allows exact inputs to arrive in any order, so a durable job with input 1
uploaded before input 0 could repeatedly upload input 1.

Resolution: inspect the frozen job inputs for the first `uploaded: false`
entry, use its explicit index, and require its name, MIME type, size, and digest
to match the locally selected file before uploading. MoonBit regression tests
cover the non-contiguous and fully uploaded cases.

## Authority boundary

Utility concat may:

- accept an ordered set of user-selected local video files;
- persist immutable source names, sizes, MIME types, and SHA-256 digests;
- build and verify one local combined artifact;
- provide a local download.

Utility concat may not:

- claim G0–G7 readiness;
- promote a production master;
- approve rights beyond the operator's local utility request;
- create a delivery acceptance;
- publish, pay, email, or transmit the artifact;
- infer Bookkeeper or MoonFlow closure.

## Final handoff

- UI-selected sources: 44 files, 655,460,186 bytes, safe-file-name ascending
- uploaded sources: 44/44, with browser-computed SHA-256 for every Blob
- utility job: `utility-concat-f5b43cebdb8b6badf2cb`
- frozen request digest:
  `sha256:8d061cd0be5b97cf77ead3c4aeb93252642cb34c5c669a2fdce825b21f7f73ce`
- delivered file: `~/Downloads/mooncast-combined-47-20260723.mp4`
- output size: 764,850,469 bytes
- output SHA-256:
  `b2c39e5246afd5477cbadd61435488eeb06ed7e9bd1cc4d275dea8488010e331`
- probed duration: 7,924.186333 seconds (`02:12:04`)
- output streams: HEVC Main 720×1280 video; AAC-LC 48 kHz stereo audio
- output access: range-capable UI media route with explicit attachment filename
- authority: publication and provider authority are both false
