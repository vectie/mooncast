"""Resolve ffmpeg/ffprobe, bootstrapping a pinned local pair on Apple Silicon."""

import hashlib
import os
import platform
import shutil
import stat
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from typing import Optional, Tuple


_DARWIN_ARM64_URL = "https://github.com/zackees/ffmpeg_bins/raw/main/v8.0/darwin_arm64.zip"
_DARWIN_ARM64_SHA256 = "b2da44a8169c4d09a97db996250690c3346f72e4795521d23d3dbb1e72421207"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _executable(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    path = shutil.which(value) or value
    return str(Path(path).resolve()) if Path(path).is_file() else None


def resolve_ffmpeg(
    ffmpeg: Optional[str] = None, ffprobe: Optional[str] = None
) -> Tuple[str, str]:
    ffmpeg_path = _executable(ffmpeg or os.environ.get("MOONCAST_FFMPEG") or "ffmpeg")
    ffprobe_path = _executable(ffprobe or os.environ.get("MOONCAST_FFPROBE") or "ffprobe")
    if ffmpeg_path and ffprobe_path:
        return ffmpeg_path, ffprobe_path

    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit(
            "ffmpeg and ffprobe are required. Install them or set MOONCAST_FFMPEG and MOONCAST_FFPROBE."
        )

    root = Path(__file__).resolve().parents[1] / ".tools" / "ffmpeg" / "darwin_arm64"
    local_ffmpeg = root / "ffmpeg"
    local_ffprobe = root / "ffprobe"
    if local_ffmpeg.is_file() and local_ffprobe.is_file():
        return str(local_ffmpeg), str(local_ffprobe)

    root.mkdir(parents=True, exist_ok=True)
    print("Mooncast: downloading pinned ffmpeg/ffprobe runtime (one-time, ~40 MB)…")
    with tempfile.TemporaryDirectory(prefix="mooncast-ffmpeg-") as temp_dir:
        archive = Path(temp_dir) / "darwin_arm64.zip"
        urllib.request.urlretrieve(_DARWIN_ARM64_URL, str(archive))
        if _sha256(archive) != _DARWIN_ARM64_SHA256:
            raise SystemExit("Downloaded ffmpeg archive failed SHA-256 verification")
        with zipfile.ZipFile(str(archive)) as bundle:
            expected = {
                "darwin_arm64/ffmpeg": local_ffmpeg,
                "darwin_arm64/ffprobe": local_ffprobe,
            }
            if not set(expected).issubset(set(bundle.namelist())):
                raise SystemExit("Downloaded ffmpeg archive is missing required executables")
            for member, destination in expected.items():
                with bundle.open(member) as source, destination.open("wb") as target:
                    shutil.copyfileobj(source, target)
                destination.chmod(destination.stat().st_mode | stat.S_IXUSR)
    return str(local_ffmpeg), str(local_ffprobe)
