"""Bounded local video generation using ffmpeg and immutable evidence."""

import hashlib
import json
import os
import re
import subprocess
import tempfile
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Tuple


MAX_DURATION_SECONDS = 12.0
DEFAULT_DURATION_SECONDS = 4.0
MAX_PROMPT_CHARS = 1000
COST_PER_SECOND_CNY = 0.08
MAX_COST_CNY = MAX_DURATION_SECONDS * COST_PER_SECOND_CNY
PROVIDER_ID = "mooncast-local"
MODEL_ID = "ffmpeg-lavfi-motion-v1"
_RENDER_LOCK = threading.Lock()
_UNSAFE_TERMS = ("child sexual", "credit card dump", "terrorist recruitment")


class RenderError(Exception):
    """A user-facing render or validation failure."""

    def __init__(self, code: str, message: str, status: int = 422) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _canonical_json(value: Dict[str, Any]) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _font_path() -> str:
    candidates = [
        os.environ.get("MOONCAST_FONT", ""),
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise RenderError(
        "font_unavailable",
        "A TrueType font is required to render the visible AI GENERATED label.",
        503,
    )


def _normalize_brief(payload: Dict[str, Any]) -> Dict[str, Any]:
    prompt = " ".join(str(payload.get("prompt", "")).split())
    if not prompt:
        raise RenderError("prompt_required", "prompt is required")
    if len(prompt) > MAX_PROMPT_CHARS:
        raise RenderError(
            "prompt_too_long", "prompt must be at most %d characters" % MAX_PROMPT_CHARS
        )
    lowered = prompt.casefold()
    if any(term in lowered for term in _UNSAFE_TERMS):
        raise RenderError("safety_rejected", "prompt failed the local safety policy")

    try:
        duration = float(payload.get("duration_seconds", DEFAULT_DURATION_SECONDS))
    except (TypeError, ValueError):
        raise RenderError("duration_invalid", "duration_seconds must be a number")
    if duration < 1.0 or duration > MAX_DURATION_SECONDS:
        raise RenderError(
            "duration_out_of_bounds",
            "duration_seconds must be between 1 and %g" % MAX_DURATION_SECONDS,
        )

    rights_owner = " ".join(str(payload.get("rights_owner", "")).split())
    if not rights_owner:
        raise RenderError("rights_owner_required", "rights_owner is required")
    if payload.get("rights_confirmed") is not True:
        raise RenderError(
            "rights_not_confirmed",
            "rights_confirmed must be true before generation",
        )

    return {
        "prompt": prompt,
        "duration_seconds": round(duration, 3),
        "rights_owner": rights_owner[:200],
        "rights_confirmed": True,
        "brand_name": " ".join(str(payload.get("brand_name", "Mooncast")).split())[:100],
        "audience": " ".join(str(payload.get("audience", "general")).split())[:200],
    }


def _probe_video(ffprobe: str, path: Path) -> Dict[str, Any]:
    command = [
        ffprobe,
        "-v",
        "error",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
        str(path),
    ]
    try:
        result = subprocess.run(
            command, check=True, capture_output=True, text=True, timeout=15
        )
        probe = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        raise RenderError("ffprobe_failed", "Generated video validation failed: %s" % error, 500)
    video_streams = [
        stream for stream in probe.get("streams", []) if stream.get("codec_type") == "video"
    ]
    if not video_streams:
        raise RenderError("video_stream_missing", "Generated MP4 has no video stream", 500)
    duration = float(probe.get("format", {}).get("duration", 0.0))
    if duration <= 0 or duration > MAX_DURATION_SECONDS + 0.25:
        raise RenderError("video_duration_invalid", "Generated MP4 duration is invalid", 500)
    return {
        "format_name": probe.get("format", {}).get("format_name", ""),
        "duration_seconds": round(duration, 3),
        "video_codec": video_streams[0].get("codec_name", ""),
        "width": video_streams[0].get("width"),
        "height": video_streams[0].get("height"),
        "has_audio": any(
            stream.get("codec_type") == "audio" for stream in probe.get("streams", [])
        ),
    }


def render_video(
    payload: Dict[str, Any], output_root: Path, ffmpeg: str, ffprobe: str
) -> Tuple[Dict[str, Any], bool]:
    """Render or reuse an immutable MP4 and return its provenance record."""

    brief = _normalize_brief(payload)
    request_digest = hashlib.sha256(_canonical_json(brief)).hexdigest()
    asset_id = request_digest[:20]
    assets_dir = output_root / "assets"
    records_dir = output_root / "records"
    assets_dir.mkdir(parents=True, exist_ok=True)
    records_dir.mkdir(parents=True, exist_ok=True)
    video_path = assets_dir / ("asset-%s.mp4" % asset_id)
    record_path = records_dir / ("asset-%s.json" % asset_id)

    with _RENDER_LOCK:
        if video_path.is_file() and record_path.is_file():
            with record_path.open("r", encoding="utf-8") as handle:
                record = json.load(handle)
                record["video_url"] = record["video_url"].lstrip("/")
                record["metadata_url"] = record["metadata_url"].lstrip("/")
                return record, False

        primary = request_digest[0:6]
        accent = request_digest[6:12]
        tone_hz = 180 + int(request_digest[12:16], 16) % 360
        duration = brief["duration_seconds"]
        font = _font_path()
        video_filter = ",".join(
            [
                "drawbox=x='mod(t*150,iw+280)-280':y=90:w=280:h=96:color=0x%s@0.72:t=fill" % accent,
                "drawbox=x='iw-mod(t*110,iw+360)':y=320:w=360:h=120:color=white@0.14:t=fill",
                "drawtext=fontfile='%s':text='MOONCAST / LOCAL PREVIEW':x=48:y=48:fontsize=28:fontcolor=white@0.92" % font,
                "drawtext=fontfile='%s':text='AI GENERATED':x=w-tw-40:y=h-th-32:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.62:boxborderw=10" % font,
                "format=yuv420p",
            ]
        )
        fd, temp_name = tempfile.mkstemp(prefix="mooncast-", suffix=".mp4", dir=str(assets_dir))
        os.close(fd)
        temp_path = Path(temp_name)
        command = [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "color=c=0x%s:s=960x540:r=24:d=%s" % (primary, duration),
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=%d:sample_rate=44100:duration=%s" % (tone_hz, duration),
            "-vf",
            video_filter,
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "24",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "96k",
            "-shortest",
            "-movflags",
            "+faststart",
            "-metadata",
            "title=Mooncast AI-generated local preview",
            "-metadata",
            "comment=prompt_sha256:%s" % request_digest,
            str(temp_path),
        ]
        try:
            subprocess.run(command, check=True, capture_output=True, text=True, timeout=45)
            probe = _probe_video(ffprobe, temp_path)
            video_sha256 = _sha256_file(temp_path)
            os.replace(str(temp_path), str(video_path))
        except subprocess.CalledProcessError as error:
            temp_path.unlink(missing_ok=True)
            detail = (error.stderr or "ffmpeg failed").strip()[-800:]
            raise RenderError("ffmpeg_failed", detail, 500)
        finally:
            temp_path.unlink(missing_ok=True)

        record = {
            "asset_id": asset_id,
            "created_at": _utc_now(),
            "video_url": "media/%s" % video_path.name,
            "metadata_url": "api/assets/%s" % asset_id,
            "sha256": video_sha256,
            "request_sha256": request_digest,
            "provider": PROVIDER_ID,
            "model": MODEL_ID,
            "prompt": brief["prompt"],
            "creative_brief": brief,
            "cost": {
                "currency": "CNY",
                "amount": round(duration * COST_PER_SECOND_CNY, 2),
                "maximum": MAX_COST_CNY,
            },
            "rights": {
                "owner": brief["rights_owner"],
                "scope": "local generation and reviewed campaign delivery",
                "confirmed": True,
                "source_assets": [],
            },
            "safety": {
                "status": "passed",
                "checks": ["bounded-input", "local-denylist", "rights-attestation"],
            },
            "labels": {
                "explicit": "AI GENERATED visible in every frame",
                "implicit": "prompt and output SHA-256 in this provenance record",
            },
            "media": probe,
        }
        temp_record = record_path.with_suffix(".json.tmp")
        with temp_record.open("w", encoding="utf-8") as handle:
            json.dump(record, handle, ensure_ascii=False, sort_keys=True, indent=2)
            handle.write("\n")
        os.replace(str(temp_record), str(record_path))
        return record, True
