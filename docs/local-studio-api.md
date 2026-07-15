# Mooncast local studio API

Start from the repository root:

```bash
python3 -m mooncast_app.server --port 4302
```

On Apple Silicon, the first run downloads a pinned ffmpeg/ffprobe archive,
verifies its SHA-256, and caches the two executables under ignored `.tools/`.
On other systems, put `ffmpeg` and `ffprobe` on `PATH` or set
`MOONCAST_FFMPEG` and `MOONCAST_FFPROBE`.

The UI is available at `/` and the declared pack entrypoint
`/apps/mooncast/studio`.

## Endpoints

### `GET /health`

Returns service, pack, provider, model, and executable status.

### `GET /api/config`

Returns prompt, duration, cost, and publication bounds.

### `POST /api/generate`

Request:

```json
{
  "prompt": "A calm indigo launch film for a lunar notebook",
  "duration_seconds": 4,
  "rights_owner": "Mooncast operator",
  "rights_confirmed": true,
  "brand_name": "MoonSuite",
  "audience": "creative teams"
}
```

The duration must be 1–12 seconds. A successful new render returns `201`; an
identical brief reuses the immutable output and returns `200`. The response
includes the mount-relative playable `video_url`, output and request SHA-256, provider, model,
prompt, bounded CNY cost, media probe, rights, safety, labels, pending human
review, and an explicitly non-published publication state.

### `GET /api/assets` and `GET /api/assets/{asset_id}`

List or retrieve composed asset provenance and the latest append-only review.

### `GET /media/{immutable_name}.mp4`

Streams the MP4 with byte-range support for browser playback.

### `POST /api/assets/{asset_id}/review`

Request:

```json
{"reviewer_id": "creative-director", "decision": "approve", "note": "Approved"}
```

An approval makes the asset eligible for a separate publishing adapter. This
service intentionally has no publishing endpoint and never treats generation
as approval.
