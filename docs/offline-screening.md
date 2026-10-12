# Offline screening bundles

`cmd/screening` packages a real local video with a searchable, seekable transcript,
selectable caption overlay, and chapter navigation. Open `index.html` with the
whole folder beside it. Nothing is uploaded, and no server, package installation,
network request, provider, or account is needed to use the generated player.

This complements `review_sheet`'s still-image contact sheets. Screening keeps the
full-motion video and its audio, so an editor can hear a line, find its text, and
jump back to the relevant chapter without rebuilding a cut or running Studio.
Existing `caption_edit`, `caption_conform`, and `chapters` JSON drafts are accepted.

## Build and use

In this retained R359 workspace, the pinned environment and exact commands are
in the sibling `BUILD.md`. Every Moon command must use an absolute external
build target. With the pinned environment already sourced:

```sh
SOURCE=/workspace/scratch/665adc5202cf/.moonsuite-background/r356-360/work/r359-mooncast/source
TARGET=/workspace/scratch/665adc5202cf/.moonsuite-background/r356-360/work/r359-mooncast/build
flock "$MOON_NATIVE_LOCK" moon -C "$SOURCE" --target-dir "$TARGET" build cmd/screening --target native --frozen --strip -j 1
"$TARGET/native/debug/build/cmd/screening/screening.exe" preview /path/to/cut.mp4 /path/to/captions.json /path/to/chapters.json 'Episode screening'
"$TARGET/native/debug/build/cmd/screening/screening.exe" export /path/to/cut.mp4 /path/to/captions.json /path/to/chapters.json 'Episode screening' /path/to/new-screening-folder
```

Replace either draft argument with `-` when that sidecar is absent. The preview
reports media identity, included cues/chapters, duration and the operator-selected
sidecar boundary. Export creates a fresh folder; an existing destination is never
overwritten. The destination's parent must already exist. Use paths to local
regular files, not URLs or symlink files. A colon in a local path is outside this
bounded profile.

The exact accepted media profile is MP4, one H.264 video stream in 8-bit yuv420p,
16–4096 pixels per dimension, at most one AAC audio stream, start at zero,
no HDR transfer curve, no embedded subtitle streams, maximum two hours and
2,147,483,647 bytes. Audio is optional. This is a browser-oriented profile,
not a claim that every device supports every H.264 level. It never transcodes
or selects an audio language silently. Prepare an appropriate review copy with
your existing media workflow if the original is outside this profile. Existing
`caption_media extract` can recover an embedded text track into a draft; the
screening input itself must have no embedded subtitle streams to avoid ambiguous
or duplicate caption presentation. The exported video is byte-for-byte identical
to the selected video, including any visible rights/AI labels already in it.
No labels, permissions or approvals are synthesized.

## Review controls

- Play/pause, audio, timeline seeking and fullscreen use the browser's native
  video controls. Playback never starts automatically.
- Select a chapter or transcript cue to seek to its start. If playback is already
  running, it continues; seeking a paused video keeps it paused. A selection made
  before metadata loads is applied when metadata arrives. A newer selection
  replaces a pending older selection.
- Back/forward move five seconds, clamped to the available duration. Speed choices
  range from 0.75× to 2×.
- Search filters supplied caption text, case-insensitively. Clear the search to
  show every cue again. It is literal text search, not semantic transcription.
- Current chapters and every overlapping active cue are highlighted. Gaps stay
  gaps. Caption intervals are half-open: the end time is not active.
- Captions start enabled when supplied. The button toggles an in-memory native
  text track. Embedded data avoids browser restrictions on reading WebVTT from
  `file://` URLs. If the text-track API is unavailable, plain caption text appears
  below the video. The original WebVTT remains available as a download.
- The controls are native buttons, labeled inputs, and a select, with a visible
  keyboard-focus outline. No keyboard shortcuts interfere with transcript input.
  Actual browser and assistive-technology qualification remains separate.

No full-page navigation is needed for seeking or searching. Current playback,
searches and caption choice are session-only and are not stored. With JavaScript
disabled, native video controls, the readable transcript, and all downloads remain
available; seek buttons, searching, and the caption overlay require JavaScript.
If the browser reports a codec/file error, use the direct video and sidecar links
with an appropriate local player. No silent conversion or network fallback occurs.

## Repeat a bounded review range

To hear a difficult line or inspect a transition repeatedly, load the video,
seek to the desired beginning and choose **Mark A here**. Seek to a later
position and choose **Mark B here**, then choose **Repeat off** to turn repeat
on. The button changes to **Repeat on**. Press the native Play control when
ready. Marking and enabling repeat never start paused playback. A/B positions
are shown in seconds with millisecond precision and are session-only.

While playing, reaching B rewinds to A. At the physical media end, an enabled
range requests continued playback, including when the final time update overshoots B; a denied playback request stops
repeat and asks you to press Play. Browser time-update scheduling can overshoot
B, so this is an editorial listening/review aid, not frame-accurate cutting or
sample-accurate audio looping. It does not modify the video or any caption draft.

- Turn repeat off to continue normal playback, or **Clear range** to remove A/B.
- Marking a new endpoint turns repeat off. A new A at or beyond B clears B.
- B must follow A. Invalid B marks preserve the prior range.
- Seeking outside A/B stops repeat. Seeking within it keeps the range active.
- Pausing keeps the range without rewinding. A media error, invalidated duration
  or failed seek stops repeat. Search, chapters, speed and caption controls stay
  available; a chapter outside the range exits repeat.

The R447 focused check is `node scripts/test-screening-repeat.cjs`. It extracts
all lines of the exact production `player_script` JavaScript, verifies the HTML
calls that function and includes the controls, then exercises its handlers using
DOM/media doubles. It covers native-caption and fallback modes, repeated range
selection, boundary/overshoot, pause, manual seek, changed duration, clear, media
errors and rejected or stale repeat-playback promises, plus existing controls.
This source-level check does not qualify MoonBit compilation, native HTML export,
real codecs, browser rendering, actual playback or external client review.

## Clocks and source selection

Caption drafts must validate under `mooncast.caption-draft.v1`; overlapping
speakers and multiline Unicode text are retained. Draft/media total durations
may differ by at most 50 ms, but every cue must actually end inside the video's
reported duration. There is no trimming, sorting or retiming.

Chapter drafts use `mooncast.chapter-draft.v1`. Chapter starts are floored from
their exact tick clock to whole milliseconds for browser seeking and WebVTT.
The original editable draft is preserved unchanged. A chapter shorter than the
WebVTT clock can represent is rejected, as is any start outside the video.
Total duration must match within 50 ms. An opening before the first chapter is
left unlabelled; the tool does not invent a chapter.

The user selects the matching drafts. Matching durations and stored hashes do
not prove that their text belongs to the selected media. Preview and watch the
result to check editorial alignment. Probe validation checks metadata, not every
frame of arbitrary input. The generated example is fully decoded in the retained
workflow tests, while unrelated user media still needs actual viewing/listening.

## Folder layout and recovery

```text
index.html       self-contained player, transcript, controls, embedded data
media.mp4        exact source bytes, never transcoded
captions.json    original caption draft, when supplied
captions.vtt     plain WebVTT export, when supplied
chapters.json    original chapter draft, when supplied
chapters.vtt     millisecond chapter navigation export, when supplied
plan.json        preview, exact source/sidecar digests, and plan
result.json      completion manifest with relative artifact paths and SHA-256
```

All resource links are relative. Copy the complete folder to relocate it. A
successful `result.json` is written last; interrupted exports can leave a partial
folder without it. Retain the partial folder for diagnosis and choose a new name
for a retry. Do not treat a partial folder as a completed bundle. The CLI checks
source stability while copying and rechecks source/draft identities before
completion. The original inputs are not modified.

## Scope and verification

This is a local editorial review aid, not a secure sharing portal. Anyone who
receives the folder can read it; the utility adds no access controls, expiry or
identity checks. Packaging does not send files, record client acceptance, provide
rights clearance, approve publication, or satisfy the PRD's external-delivery
criteria. No provider or paid production was exercised.

Focused tests cover caption/chapter joins, browser-oriented media restrictions,
clock conversion, no-sidecar behavior and safe HTML/data embedding. The native
CLI journey creates actual H.264/AAC video, exports and decodes the copied video,
checks every digest, relocates the folder and resolves its links. It executes the
emitted JavaScript in Node with DOM/media API test doubles, exercising pending
and repeated seeking, overlap and boundary highlighting, chapter navigation,
Unicode search, clearing/no matches, caption toggles/fallback, playback speed,
clamped nudges and media errors. No browser rendering engine, physical playback
device, screen reader, external recipient, or deployment is qualified by that
harness. Cumulative fully verified product qualification remains R50.

## Keep timecoded editorial feedback

Use the [review notebook](screening-review-notebook.md) to capture point or A–B
issues while screening, edit them, resolve/reopen them and jump to their times.
Download and reopen the exact-source notebook to continue later. It is local
feedback only: issue status does not record client acceptance. Notes have no
automatic storage; download before closing or replacing the notebook.

## Combine timecoded screening feedback

The player supports local point/range issue notebooks and previewed merging of
one to ten matching reviewer notebooks. Inspect duplicate counts and explicit
ID conflicts, then merge while retaining current notes and editor drafts. Read
[screening review notebooks](screening-review-notebook.md) for merge, replacement,
download/restore behavior and the limits of this local workflow. Previously
exported folders need a new export to receive these controls.

## Review a returned notebook revision

Use [selected notebook revisions](screening-notebook-revisions.md) to accept
chosen corrections from a deliberately revised copy without replacing your
entire working notebook. Inspect each exact before/after, select the intended
updates and additions, then download the combined result. Every choice starts
unchecked; active edits and changed saved notes require reconciliation.

## Recover a saved notebook edit

[Notebook Undo/Redo](screening-notebook-history.md) restores recent saved feedback
states, including merges, replacements and selected revisions. Save or cancel
editor drafts first, then download again to keep the restored notes. History is
bounded and session-only; existing downloaded files never change.

## Correct supplied caption wording

Choose **Edit caption N** beside a transcript cue to correct its wording while
watching the cut. Save to preview with unchanged timing, then download a corrected
caption draft or WebVTT sidecar. The original folder and notebook binding remain
unchanged. Read [caption correction](screening-caption-correction.md) for draft
protection, restoration, continuing with existing caption tools and limitations.
