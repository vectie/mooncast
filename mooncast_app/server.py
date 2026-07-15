"""Mooncast local HTTP API and campaign studio."""

import argparse
import json
import mimetypes
import os
import re
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Optional
from urllib.parse import unquote, urlparse

from .render import (
    DEFAULT_DURATION_SECONDS,
    MAX_COST_CNY,
    MAX_DURATION_SECONDS,
    MAX_PROMPT_CHARS,
    MODEL_ID,
    PROVIDER_ID,
    RenderError,
    render_video,
)
from .store import AssetStore
from .runtime import resolve_ffmpeg


_ROOT = Path(__file__).resolve().parent
_STATIC = _ROOT / "static"
_MEDIA_NAME = re.compile(r"^asset-[0-9a-f]{20}\.mp4$")
_ASSET_API = re.compile(r"^/api/assets/([0-9a-f]{20})$")
_REVIEW_API = re.compile(r"^/api/assets/([0-9a-f]{20})/review$")
MAX_BODY_BYTES = 16 * 1024


def _direct_mount_path(path: str) -> str:
    """Map relative URLs from the manifest route back to service routes."""
    prefix = "/apps/mooncast/"
    if path.startswith(prefix) and path != "/apps/mooncast/studio":
        return "/" + path.removeprefix(prefix)
    return path


class MooncastServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: Any,
        handler: Any,
        output_root: Path,
        ffmpeg: str,
        ffprobe: str,
    ) -> None:
        super().__init__(address, handler)
        self.output_root = output_root
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.store = AssetStore(output_root)


class MooncastHandler(BaseHTTPRequestHandler):
    server_version = "Mooncast/0.1"

    @property
    def app(self) -> MooncastServer:
        return self.server  # type: ignore[return-value]

    def log_message(self, message: str, *args: Any) -> None:
        print("%s - %s" % (self.address_string(), message % args))

    def _security_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; media-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'",
        )

    def _send_json(
        self, status: int, value: Dict[str, Any], head_only: bool = False
    ) -> None:
        body = json.dumps(value, ensure_ascii=False, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self._security_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head_only:
            self.wfile.write(body)

    def _send_error(self, error: RenderError) -> None:
        self._send_json(error.status, {"error": {"code": error.code, "message": error.message}})

    def _read_json(self) -> Dict[str, Any]:
        body = self._read_body()
        try:
            value = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise RenderError("json_invalid", "request body must be valid UTF-8 JSON", 400)
        if not isinstance(value, dict):
            raise RenderError("json_object_required", "request body must be a JSON object", 400)
        return value

    def _read_exactly(self, length: int) -> bytes:
        chunks = []
        remaining = length
        while remaining:
            chunk = self.rfile.read(remaining)
            if not chunk:
                raise RenderError("body_truncated", "request body ended unexpectedly", 400)
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def _read_chunked_body(self) -> bytes:
        body = bytearray()
        while True:
            size_line = self.rfile.readline(130)
            if not size_line or len(size_line) > 129 or not size_line.endswith(b"\r\n"):
                raise RenderError("chunk_header_invalid", "chunk header is invalid", 400)
            size_text = size_line[:-2].split(b";", 1)[0].strip()
            try:
                size = int(size_text, 16)
            except ValueError:
                raise RenderError("chunk_size_invalid", "chunk size is invalid", 400)
            if size < 0 or len(body) + size > MAX_BODY_BYTES:
                raise RenderError(
                    "body_size_invalid",
                    "JSON body must be between 1 and %d bytes" % MAX_BODY_BYTES,
                    400,
                )
            if size == 0:
                trailer_bytes = 0
                while True:
                    trailer = self.rfile.readline(1026)
                    trailer_bytes += len(trailer)
                    if not trailer or len(trailer) > 1025 or trailer_bytes > 8192:
                        raise RenderError("chunk_trailer_invalid", "chunk trailer is invalid", 400)
                    if trailer == b"\r\n":
                        break
                break
            body.extend(self._read_exactly(size))
            if self._read_exactly(2) != b"\r\n":
                raise RenderError("chunk_terminator_invalid", "chunk terminator is invalid", 400)
        if not body:
            raise RenderError("body_size_invalid", "JSON body must not be empty", 400)
        return bytes(body)

    def _read_body(self) -> bytes:
        transfer_encoding = self.headers.get("Transfer-Encoding", "").strip().casefold()
        content_length = self.headers.get("Content-Length")
        if transfer_encoding and content_length is not None:
            raise RenderError(
                "body_framing_conflict",
                "Transfer-Encoding and Content-Length cannot be combined",
                400,
            )
        if transfer_encoding:
            if transfer_encoding != "chunked":
                raise RenderError(
                    "transfer_encoding_unsupported",
                    "only chunked Transfer-Encoding is supported",
                    400,
                )
            return self._read_chunked_body()
        try:
            length = int(content_length or "0")
        except ValueError:
            raise RenderError("content_length_invalid", "Content-Length is invalid", 400)
        if length <= 0 or length > MAX_BODY_BYTES:
            raise RenderError(
                "body_size_invalid",
                "JSON body must be between 1 and %d bytes" % MAX_BODY_BYTES,
                400,
            )
        return self._read_exactly(length)

    def _send_static(self, name: str, head_only: bool = False) -> None:
        path = _STATIC / name
        if not path.is_file():
            self._send_json(404, {"error": {"code": "not_found", "message": "not found"}})
            return
        body = path.read_bytes()
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_response(200)
        self._security_headers()
        self.send_header("Content-Type", content_type + ("; charset=utf-8" if content_type.startswith("text/") or content_type == "application/javascript" else ""))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head_only:
            self.wfile.write(body)

    def _send_media(self, name: str, head_only: bool = False) -> None:
        name = unquote(name)
        if not _MEDIA_NAME.fullmatch(name):
            self._send_json(404, {"error": {"code": "not_found", "message": "video not found"}})
            return
        path = self.app.output_root / "assets" / name
        if not path.is_file():
            self._send_json(404, {"error": {"code": "not_found", "message": "video not found"}})
            return
        size = path.stat().st_size
        start, end = 0, size - 1
        status = 200
        range_header = self.headers.get("Range")
        if range_header:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header.strip())
            if not match:
                self.send_error(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                return
            if match.group(1):
                start = int(match.group(1))
            if match.group(2):
                end = int(match.group(2))
            if start > end or start >= size:
                self.send_error(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                return
            end = min(end, size - 1)
            status = 206
        length = end - start + 1
        self.send_response(status)
        self._security_headers()
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.end_headers()
        if head_only:
            return
        with path.open("rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining:
                chunk = handle.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def _health(self) -> Dict[str, Any]:
        return {
            "status": "ok",
            "pack_id": "mooncast",
            "provider": PROVIDER_ID,
            "model": MODEL_ID,
            "ffmpeg": self.app.ffmpeg,
            "ffprobe": self.app.ffprobe,
        }

    def do_HEAD(self) -> None:
        path = _direct_mount_path(urlparse(self.path).path)
        if path in ("/", "/index.html", "/apps/mooncast/studio"):
            self._send_static("index.html", head_only=True)
        elif path == "/app.js":
            self._send_static("app.js", head_only=True)
        elif path == "/styles.css":
            self._send_static("styles.css", head_only=True)
        elif path == "/health":
            self._send_json(200, self._health(), head_only=True)
        elif path.startswith("/media/"):
            self._send_media(path.removeprefix("/media/"), head_only=True)
        else:
            self._send_json(
                404,
                {"error": {"code": "not_found", "message": "not found"}},
                head_only=True,
            )

    def do_GET(self) -> None:
        path = _direct_mount_path(urlparse(self.path).path)
        try:
            if path in ("/", "/index.html", "/apps/mooncast/studio"):
                self._send_static("index.html")
            elif path == "/app.js":
                self._send_static("app.js")
            elif path == "/styles.css":
                self._send_static("styles.css")
            elif path == "/health":
                self._send_json(200, self._health())
            elif path == "/api/config":
                self._send_json(
                    200,
                    {
                        "max_duration_seconds": MAX_DURATION_SECONDS,
                        "default_duration_seconds": DEFAULT_DURATION_SECONDS,
                        "max_prompt_chars": MAX_PROMPT_CHARS,
                        "max_cost": {"currency": "CNY", "amount": MAX_COST_CNY},
                        "publication_enabled": False,
                    },
                )
            elif path == "/api/assets":
                self._send_json(200, {"assets": self.app.store.list_assets()})
            elif _ASSET_API.fullmatch(path):
                asset_id = _ASSET_API.fullmatch(path).group(1)  # type: ignore[union-attr]
                self._send_json(200, self.app.store.get(asset_id))
            elif path.startswith("/media/"):
                self._send_media(path.removeprefix("/media/"))
            else:
                self._send_json(404, {"error": {"code": "not_found", "message": "not found"}})
        except RenderError as error:
            self._send_error(error)

    def do_POST(self) -> None:
        path = _direct_mount_path(urlparse(self.path).path)
        try:
            if path == "/api/generate":
                record, created = render_video(
                    self._read_json(),
                    self.app.output_root,
                    self.app.ffmpeg,
                    self.app.ffprobe,
                )
                self._send_json(201 if created else 200, self.app.store.get(record["asset_id"]))
                return
            review_match = _REVIEW_API.fullmatch(path)
            if review_match:
                self._send_json(
                    201, self.app.store.review(review_match.group(1), self._read_json())
                )
                return
            self._send_json(404, {"error": {"code": "not_found", "message": "not found"}})
        except RenderError as error:
            self._send_error(error)
        except BrokenPipeError:
            pass


def create_server(
    host: str = "127.0.0.1",
    port: int = 8765,
    output_root: Optional[Path] = None,
    ffmpeg: Optional[str] = None,
    ffprobe: Optional[str] = None,
) -> MooncastServer:
    root = output_root or Path(os.environ.get("MOONCAST_OUTPUT_DIR", "var/mooncast"))
    ffmpeg_path, ffprobe_path = resolve_ffmpeg(ffmpeg, ffprobe)
    return MooncastServer(
        (host, port),
        MooncastHandler,
        Path(root).resolve(),
        ffmpeg_path,
        ffprobe_path,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Mooncast local studio")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--output-dir", default=os.environ.get("MOONCAST_OUTPUT_DIR", "var/mooncast"))
    args = parser.parse_args()
    server = create_server(args.host, args.port, Path(args.output_dir))
    print("Mooncast Studio: http://%s:%d/apps/mooncast/studio" % (args.host, args.port))
    print("Health: http://%s:%d/health" % (args.host, args.port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping Mooncast")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
