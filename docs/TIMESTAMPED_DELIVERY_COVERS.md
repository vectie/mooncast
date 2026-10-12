# Timestamped delivery covers

## What you can do

In Studio → Delivery, add up to eight named JPG or PNG cover images alongside
the existing named cuts. Choose the master, horizontal variant or vertical
variant, then enter a time such as `12.250` seconds. Images use the selected
source's actual framing and dimensions.

Create the delivery build and choose **Build / resume**. The completed build
shows a cover gallery with the actual images, their source and requested time,
and an individual download link. A preview or image download is a local read;
it does not record client acceptance or grant publication authority. The same
image bytes are included in the existing delivery ZIP.

## Short walkthrough

1. Open a project with a promoted master and versioned delivery intent
2. Under **Timestamped covers**, choose **Add named cover**
3. Set a unique name, source, frame time and image format
4. Add more covers if useful, or exclude a row to retain it without packaging it
5. Choose **Create delivery build**, then **Build / resume** on that build
6. Inspect the **Cover preview** gallery and download the images you want

The existing exact-master caption flow, up to twelve named cuts, variants,
rights/provenance, AI labels, and separate delivery acceptance remain in place.
The full ZIP retains its existing acceptance behavior; individual local cover
inspection does not require that acceptance.

## Practical limits and recovery

- Up to eight cover draft rows; selected rows only enter the build
- Names use 1–80 letters, digits, dots, hyphens or underscores, beginning with
  a letter or digit. Names must differ from selected cut names and reserved
  master/variant names, ignoring letter case
- Time is non-negative decimal seconds with at most three decimal places,
  strictly before the master's end. Frame extraction follows the encoded
  video's frame cadence; retaining millisecond input does not invent an
  intermediate frame
- Source is the full master or a generated horizontal/vertical variant;
  cover-from-cut chains and automatic frame ranking are outside this slice
- Drafts autosave in the current browser per project, preserving incomplete
  input and excluded rows. Refresh and project switches retain those values
- A changed master keeps the draft but blocks selected covers until you check
  the timestamps and choose **Use current master for covers**. It then validates
  the times against the new duration
- Storage failures are visible. Retry saving after a write failure. Unreadable
  stored drafts are left untouched, with autosave paused for that project
- Completed builds retain their own cover images and digests. Editing a draft
  never silently substitutes images in an earlier build

## Implementation and read boundary

The UI submits the existing `mooncast.delivery-build-profile.v1` cover shape:
`cover_id`, `source_variant`, `timestamp_seconds`, and `format`. Existing
FFmpeg cover generation remains the materialization path. Completed build
projections additionally expose `cover_frames`, described by
`schemas/delivery-cover-frame.schema.json`.

Preview and download routes are bound to project, build, cover ID and SHA-256:

`GET /api/v2/projects/{project}/delivery-builds/{build}/covers/{cover}/{sha256}`

Append `/download` for attachment disposition. Reads require a completed build,
the exact cover artifact, matching content digest and byte length, and PNG/JPEG
media type. Missing, non-cover, cross-project, changed or corrupt content is
rejected rather than replaced. Responses are `no-store` and `nosniff`.

## Qualification

This is cloud-local synthetic qualification, with no provider, paid episode,
live browser, deployed customer access, Mac bundle, or publication claim.

- UI reducer, serialization, browser-storage FFI fixture and rendered-HTML tests
  cover bounded rows, exact milliseconds, invalid values, project switches,
  refresh/reload, changed master, repeated submission, incomplete excluded rows,
  quota/read errors, cut-name collisions, gallery escaping and historical builds
- A real changing `testsrc2` clip produces PNG/JPG covers from master and portrait
  sources. An independent FFmpeg extraction at each requested time matches the
  output bytes. Every image is compared with its actual ZIP member
- Native regressions reject end-of-video/nonfinite timestamps, nonfinite master
  duration, cut-timing fields on covers, unsupported sources/formats, duplicate
  names, wrong project/digest/type and tampered bytes
- A focused real-image HTTP test exercises inline and attachment responses
  before acceptance and confirms unchanged bytes and no acceptance side effect

The test host uses explicit Linux FFmpeg paths. This is not evidence that the
separately packaged Mac media tools or a live browser have been qualified.
