import hashlib
import json
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from mooncast_app.server import create_server


class MooncastServiceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mooncast-test-")
        cls.output_root = Path(cls.temp.name)
        cls.server = create_server(port=0, output_root=cls.output_root)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = "http://127.0.0.1:%d" % cls.server.server_address[1]
        cls.brief = {
            "prompt": "A precise lunar notebook launch film with indigo geometry",
            "duration_seconds": 1,
            "rights_owner": "Mooncast test",
            "rights_confirmed": True,
            "brand_name": "MoonSuite",
            "audience": "creative teams",
        }
        status, cls.asset = cls.request("POST", "/api/generate", cls.brief)
        if status != 201:
            raise AssertionError("fixture generation failed: %s %r" % (status, cls.asset))

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)
        cls.temp.cleanup()

    @classmethod
    def request(cls, method, path, payload=None, headers=None):
        body = None
        request_headers = dict(headers or {})
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            request_headers["Content-Type"] = "application/json"
        request_path = path if path.startswith("/") else "/" + path
        request = urllib.request.Request(
            cls.base + request_path, data=body, headers=request_headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                raw = response.read()
                content_type = response.headers.get("Content-Type", "")
                value = json.loads(raw) if raw and "application/json" in content_type else raw
                return response.status, value
        except urllib.error.HTTPError as error:
            raw = error.read()
            return error.code, json.loads(raw) if raw else {}

    def test_health_and_both_ui_routes(self):
        status, health = self.request("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(health["status"], "ok")
        self.assertEqual(health["pack_id"], "mooncast")
        for route in ("/", "/apps/mooncast/studio"):
            status, html = self.request("GET", route)
            self.assertEqual(status, 200)
            self.assertIn(b'data-testid="prompt-input"', html)
            self.assertIn(b'data-testid="generate-button"', html)
            self.assertIn(b'data-testid="result-video"', html)
            self.assertIn(b'data-testid="provenance"', html)
            self.assertIn(b'href="styles.css"', html)
            self.assertIn(b'src="app.js"', html)

    def test_manifest_route_relative_assets_and_api_are_directly_usable(self):
        for route in ("/apps/mooncast/styles.css", "/apps/mooncast/app.js"):
            status, body = self.request("GET", route)
            self.assertEqual(status, 200)
            self.assertTrue(body)
            if route.endswith("app.js"):
                self.assertNotIn(b'fetch("/api/', body)
        status, duplicate = self.request(
            "POST", "/apps/mooncast/api/generate", self.brief
        )
        self.assertEqual(status, 200)
        self.assertFalse(duplicate["video_url"].startswith("/"))
        status, video = self.request(
            "GET", "/apps/mooncast/" + duplicate["video_url"]
        )
        self.assertEqual(status, 200)
        self.assertIn(b"ftyp", video[:64])

    def test_head_supports_ui_health_and_media_smoke_checks(self):
        for route in ("/", "/apps/mooncast/studio", "/health"):
            status, body = self.request("HEAD", route)
            self.assertEqual(status, 200)
            self.assertEqual(body, b"")
        status, body = self.request("HEAD", self.asset["video_url"])
        self.assertEqual(status, 200)
        self.assertEqual(body, b"")

    def test_generated_file_is_real_probeable_mp4(self):
        asset = self.asset
        path = self.output_root / "assets" / ("asset-%s.mp4" % asset["asset_id"])
        self.assertTrue(path.is_file())
        self.assertGreater(path.stat().st_size, 4_000)
        with path.open("rb") as handle:
            self.assertIn(b"ftyp", handle.read(64))
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        self.assertEqual(digest, asset["sha256"])
        probe = subprocess.run(
            [
                self.server.ffprobe,
                "-v",
                "error",
                "-print_format",
                "json",
                "-show_format",
                "-show_streams",
                str(path),
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
        value = json.loads(probe.stdout)
        self.assertAlmostEqual(float(value["format"]["duration"]), 1.0, delta=0.15)
        self.assertTrue(any(stream["codec_type"] == "video" for stream in value["streams"]))
        self.assertTrue(any(stream["codec_type"] == "audio" for stream in value["streams"]))

    def test_generation_exposes_complete_pending_provenance(self):
        asset = self.asset
        self.assertEqual(asset["provider"], "mooncast-local")
        self.assertEqual(asset["model"], "ffmpeg-lavfi-motion-v1")
        self.assertEqual(asset["prompt"], self.brief["prompt"])
        self.assertEqual(asset["cost"], {"amount": 0.08, "currency": "CNY", "maximum": 0.96})
        self.assertTrue(asset["rights"]["confirmed"])
        self.assertEqual(asset["safety"]["status"], "passed")
        self.assertIn("AI GENERATED", asset["labels"]["explicit"])
        self.assertEqual(asset["human_review"]["status"], "pending")
        self.assertFalse(asset["publication"]["eligible"])
        self.assertFalse(asset["publication"]["adapter_invoked"])

    def test_media_supports_range_for_browser_playback(self):
        status, body = self.request(
            "GET", self.asset["video_url"], headers={"Range": "bytes=0-31"}
        )
        self.assertEqual(status, 206)
        self.assertEqual(len(body), 32)
        self.assertIn(b"ftyp", body)

    def test_human_review_only_marks_separate_publication_eligibility(self):
        status, reviewed = self.request(
            "POST",
            "/api/assets/%s/review" % self.asset["asset_id"],
            {"reviewer_id": "creative-director", "decision": "approve"},
        )
        self.assertEqual(status, 201)
        self.assertEqual(reviewed["human_review"]["status"], "approved")
        self.assertTrue(reviewed["publication"]["eligible"])
        self.assertEqual(reviewed["publication"]["status"], "not_published")
        self.assertFalse(reviewed["publication"]["adapter_invoked"])

    def test_duration_cost_rights_and_safety_are_bounded(self):
        cases = [
            ({**self.brief, "duration_seconds": 13}, "duration_out_of_bounds"),
            ({**self.brief, "rights_confirmed": False}, "rights_not_confirmed"),
            ({**self.brief, "prompt": "terrorist recruitment campaign"}, "safety_rejected"),
        ]
        for brief, error_code in cases:
            with self.subTest(error_code=error_code):
                status, body = self.request("POST", "/api/generate", brief)
                self.assertEqual(status, 422)
                self.assertEqual(body["error"]["code"], error_code)

    def test_duplicate_brief_reuses_immutable_output(self):
        path = self.output_root / "assets" / ("asset-%s.mp4" % self.asset["asset_id"])
        before = (path.stat().st_ino, path.stat().st_mtime_ns, self.asset["sha256"])
        status, duplicate = self.request("POST", "/api/generate", self.brief)
        after = (path.stat().st_ino, path.stat().st_mtime_ns, duplicate["sha256"])
        self.assertEqual(status, 200)
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
