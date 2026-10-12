# Prebuild named-cut marking

On the Studio Delivery tab, add a named cut and choose **Mark range for cut-name**.
The player verifies the currently promoted master before opening its retained MP4.
Seek using the native video controls, choose **Mark in** and **Mark out**, then
**Preview selected range**. Preview seeks to the in point and pauses at the out
point. **Close range player** pauses playback, cancels the preview frame callback,
removes listeners, and releases the video source. Retry obtains a fresh verified
projection and starts the same master from its beginning.

This is a promoted-master timing preview. It does not show an unbuilt crop or
variant. A horizontal or vertical source selection remains a delivery setting.
The existing completed-build inspector continues to play the saved historical
variant/cut and matching SRT after a build.

## Drafts and precision

- Marking only changes the corresponding `DeliveryCutDraft` start or end field
  through the existing browser-local autosave. It does not submit any build POST
- Browser times round to the nearest millisecond, with half milliseconds rounding
  up, and are displayed as three-decimal seconds. For example, 1.2345 becomes 1.235
- Manual decimal strings retain their original spelling and precision until that
  specific boundary is marked. No floating-point normalization is applied to them
- The existing `delivery_cut_range` / `delivery_cut_selection` rules remain
  authoritative: both boundaries, positive duration, at most 180 seconds, within
  the promoted duration, a current master binding, and valid named selections
- A reversed or equal pair may remain as an incomplete autosaved draft. The
  error is visible and range preview/build remains blocked. Preview also rejects
  an end beyond the browser's actual playable duration
- On local-storage failure, marked edits stay in this tab with the existing
  autosave warning and retry control. An unreadable saved draft remains protected

## Identity and failure handling

`GET /api/v2/projects/{project}/promoted-master/playback` is read-only. It joins
the canonical master SHA to exactly one existing promotion/export job binding.
It checks project identity, export kind, completion, export digest, nonempty
retained bytes, their SHA, and promotion size. An unrelated newer export or
latest-promotion index is never substituted. Missing or ambiguous binding fails
closed and directs the operator to repair it in Cut Editor.

The returned URL reuses the existing verified editor MP4 GET/HEAD range route
with a `master_sha256` query guard. The guard compares the requested SHA to both
the current canonical master and the exact route job; it rejects stale-master
range requests. Unqualified historical editor routes retain their behavior.

The player binds the project load generation, selected project, master SHA,
named-cut row key, and a monotonically increasing player/row-selection generation.
Project refresh/change/failure, tab departure, close, row removal, or mismatched
master invalidates playback. Retrying and reselecting create new generations.
Late projection, media, seek, and mark callbacks cannot affect a newer selection,
including A → B → A and remove/re-add of the same numeric row key.

Marking and range preview are unavailable until finite positive metadata loads.
A media error or metadata timeout remains visible and disabled until explicit
retry. Manual ranges are still editable. Failed `play()` calls report an
interruption; retrying preview is safe and cannot submit delivery work.

## Verification

The Studio regression tests cover rounding, preservation of manual decimals,
invalid/edge ranges, stale identities and generations, A/B/A, removed rows,
metadata/error/retry, autosave failure, player cleanup, exact out-point pause,
and preservation of historical inspection/captions. The native regression
generates one synthetic four-second 160×90 MP4 with local ffmpeg, verifies the
exact projection and GET/HEAD/range behavior, rejects incomplete/corrupt/stale
media, and confirms projection/playback reads leave the store and builds unchanged.
It performs no provider request or delivery build.
