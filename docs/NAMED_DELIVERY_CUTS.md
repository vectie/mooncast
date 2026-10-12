# Named multi-cut delivery builder

This bounded slice of MOONCAST-R02 and MOONCAST-N05 exposes the delivery
factory's existing multi-output and exact-caption capabilities. It retains the
MOONCAST-B07 / MOONCAST-N02 source and revision lineage. It does not qualify
recipient access, live playback, commercial production or publication.

## Use

1. Open a project in Studio → Delivery after promoting a reviewed master and
   recording delivery intent. Preview the selected master captions first.
2. Choose **Add named cut**. Supply a file-safe name, intended channel label,
   source variant and start/end seconds. Repeat for up to 12 rows.
3. Use **Included / Excluded** to choose which rows enter this package. Excluded
   rows, including incomplete edits, stay in the draft. Remove only deletes a
   row from the draft; it never edits an existing delivery build.
4. Review each included row's exact source and millisecond interval. Its caption
   preview uses the promoted master's clock, which spatial variants preserve.
5. Choose **Create delivery build**, then use the existing build/review/download
   controls. All selected cuts belong to that one immutable build and ZIP.
   Client acceptance and publication authority remain separate.

Names are 1–80 ASCII letters/digits/dot/hyphen/underscore, starting with a
letter or digit. Selected names are unique ignoring case; `master`,
`horizontal-1080p` and `vertical-1080p` are reserved in every letter case.
Channel labels are 1–120 characters and describe intended use only.

Sources are `master`, `horizontal-1080p` (1920×1080 scale) or
`vertical-1080p` (1080×1920 crop). Boundaries are nonnegative decimal seconds
with up to three decimal places. Every interval has positive duration, is at
most 180 seconds, and remains inside the known master duration. The same range
may intentionally appear under different names/channels. Cuts are independent;
they are not concatenated or retimed.

## Draft continuity and recovery

Drafts autosave in this browser's local storage, separately for each project.
Refresh, A→B→A navigation and reopening preserve names, channels, source variants,
selection state, precise input strings and the master SHA-256. They are not
server-saved or synced between browsers. Concurrent browser tabs have ordinary
last-save-wins storage semantics; use one editing tab per project.

A newly promoted master does not silently retarget included cuts. The UI blocks
creation until **Use current master** is chosen after reviewing the ranges;
duration validation still applies afterward. Each queued build also carries
the existing exact project revision, master SHA, delivery version and digest.

If autosave fails, the latest edits remain in the current tab and a warning is
shown for that project. **Retry saving cut draft** retries a write. If a saved
draft cannot be read, is malformed, is oversized, or identifies another project,
autosave is paused for that project rather than replacing the saved bytes.
Keep the tab open and preserve any current edits before repairing browser
storage or reloading. No migration from the old single-cut form is needed:
that form had no browser-persisted cut drafts.

## Package contents and caption rules

The UI continues to include the master and both full-length spatial variants,
verified subtitle sidecars, metadata, rights/provenance and AI labels. It adds
one named MP4 and one independently derived SRT for every selected cut. Existing
build manifests and subtitle mappings identify each output and its source
variant. Packaged metadata now also retains the complete submitted profile,
including human-readable channel labels and exact source intervals.

SRT derivation uses half-open intersections: clip crossing cues to the range,
omit zero-length intersections, subtract the cut start, and renumber retained
cues. Unicode and multiline text stay unchanged. Required captions with no
overlapping cues fail the build rather than disappearing. Arbitrary reordering,
speed changes or cut chains require a corrected Cut Editor export. Media frames
remain subject to the source frame rate; precise SRT boundaries do not promise
sub-frame video sampling.

The original master, original SRT and earlier archives are not overwritten.
This feature adds no provider calls, publishing route or cover UI.

## Verification boundary

Verification uses the cached MoonBit toolchain, pure reducer/HTML tests, mocked
browser storage, native host tests and local FFmpeg synthetic fixtures. Browser
interaction, keyboard/screen-reader use, real customer access, macOS integration,
live providers and commercial qualification are not claimed.

Both delivered module manifests are unchanged. Root direct dependencies are
async 0.19.4, x 0.4.50 and MoonLib 0.1.19; the UI uses Rabbita 0.12.4 and exact
x 0.4.40. Final UI checks run against a fresh build with that exact declared
version, not the x 0.4.50 copy used during early development. Physical dependency
copies come from the previously checksum-verified cache. Root x 0.4.50 also
satisfies MoonLib's transitive x 0.4.40 requirement. Host fixture tests
use owned Linux FFmpeg/ffprobe copies at the legacy bundle-shaped path under
ignored `.tools`; that path does not imply a macOS bundle was built or tested.

The retained synthetic fixture proves that a 3–6 second master cut and a
6–10 second portrait cut yield distinct media and independently exact SRTs in
one ZIP; it checks output durations/dimensions, Unicode/multiline text, ZIP
member bytes and unchanged master/SRT/prior archive hashes. The host-route
regression additionally covers submitted named profiles and packaged channel
metadata. Final commands and test receipts accompany the delivery outside this
source tree.
