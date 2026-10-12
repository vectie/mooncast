#!/usr/bin/env python3
"""Focused real CLI journey. All generated media are synthetic and local."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import wave

p = argparse.ArgumentParser()
p.add_argument("--source", type=Path, required=True)
p.add_argument("--target", type=Path, required=True)
p.add_argument("--output", type=Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=False)
exe = a.target / "native/debug/build/cmd/project_collect/project_collect.exe"
chapters = a.target / "native/debug/build/cmd/chapters/chapters.exe"
checks = []

def command(name, argv, success=True):
    proc = subprocess.run([str(x) for x in argv], text=True, capture_output=True, timeout=120)
    (a.output / (name + ".stdout")).write_text(proc.stdout)
    (a.output / (name + ".stderr")).write_text(proc.stderr)
    checks.append({"name": name, "command": [str(x) for x in argv], "exit": proc.returncode,
                   "expected_success": success})
    assert (proc.returncode == 0) == success, (name, proc.stdout, proc.stderr)
    return proc.stdout

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(name, value):
    path = a.output / name
    path.write_text(json.dumps(value, indent=2) + "\n")
    return path

root = a.output / "source media café"
(root / "camera").mkdir(parents=True)
(root / "sound").mkdir()
video = root / "camera/a.mp4"
command("create-synthetic-video", ["ffmpeg", "-v", "error", "-nostdin", "-n",
        "-f", "lavfi", "-i", "color=c=blue:s=160x90:r=24:d=10",
        "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", video])
shutil.copyfile(video, root / "camera/b.mp4")
unused = root / "sound/unused.wav"
with wave.open(str(unused), "wb") as out:
    out.setnchannels(1); out.setsampwidth(2); out.setframerate(48000)
    out.writeframes(b"\0" * (48000 * 2 * 12))
caption = root / "captions.srt"
caption.write_text("1\n00:00:00,000 --> 00:00:01,000\nSynthetic café\n", encoding="utf-8")
source = json.loads((a.source / "fixtures/edit-decisions.project.json").read_text())
for i, media in enumerate(source["media_refs"]):
    path = video if i == 0 else root / "camera/b.mp4"
    media["locator"]["uri"] = str(path.relative_to(root))
    media["metadata"]["sha256"] = sha(path)
    media["metadata"]["size_bytes"] = path.stat().st_size
for mid, path, mime, duration in [("unused.audio", unused, "audio/wav", 12000),
                                  ("unused.captions", caption, "application/x-subrip", 1000)]:
    media = copy.deepcopy(source["media_refs"][0])
    media["media_ref_id"] = mid
    media["locator"]["uri"] = str(path.relative_to(root))
    media["metadata"] = {"sha256": sha(path), "size_bytes": path.stat().st_size,
                         "mime_type": mime, "duration_ticks": duration}
    source["media_refs"].append(media)
project = save("input project.json", source)
original_hashes = {str(x): sha(x) for x in [project, video, root / "camera/b.mp4", unused, caption]}
preview = json.loads(command("preview", [exe, "preview", project, root]))
assert preview["media_references"] == 4 and preview["unique_files"] == 3
assert int(preview["copy_bytes"]) == sum(x.stat().st_size for x in [video, unused, caption])
bundle = a.output / "editable bundle café"
result = json.loads(command("collect", [exe, "collect", project, root, bundle]))
assert result["unique_files"] == 3
for path, digest in original_hashes.items():
    assert sha(Path(path)) == digest
native = json.loads((bundle / "project.json").read_text())
assert native["revision"] == source["revision"] + 1
def present(value):
    if isinstance(value, dict):
        return {k: present(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [present(v) for v in value]
    return value
assert present(native["timeline"]) == present(source["timeline"])
assert native["identity_graph"] == source["identity_graph"]
assert len(list((bundle / "media").iterdir())) == 3
for media in native["media_refs"]:
    assert sha(bundle / media["locator"]["uri"]) == media["metadata"]["sha256"]
assert native["media_refs"][0]["locator"] == native["media_refs"][1]["locator"]
command("refuse-existing-destination", [exe, "collect", project, root, bundle], False)
occupied = a.output / "dangling-output"
occupied.symlink_to("absent-target")
command("refuse-dangling-destination", [exe, "collect", project, root, occupied], False)

bad = copy.deepcopy(source)
bad["media_refs"][0]["metadata"]["sha256"] = "0" * 64
bad_path = save("wrong-digest.json", bad)
bad_out = a.output / "bad-digest-output"
command("refuse-wrong-source-hash", [exe, "collect", bad_path, root, bad_out], False)
assert not bad_out.exists()
# Repeated-content aliases are verified individually before deduplication.
(root / "camera/alias.mp4").symlink_to("a.mp4")
bad = copy.deepcopy(source); bad["media_refs"][1]["locator"]["uri"] = "camera/alias.mp4"
bad_path = save("symlink-input.json", bad)
command("refuse-symlink-source", [exe, "collect", bad_path, root, a.output / "symlink-output"], False)
assert not (a.output / "symlink-output").exists()
(root / "linked-camera").symlink_to("camera", target_is_directory=True)
bad["media_refs"][1]["locator"]["uri"] = "linked-camera/b.mp4"
bad_path = save("symlink-directory.json", bad)
command("refuse-symlink-directory", [exe, "preview", bad_path, root], False)
bad = copy.deepcopy(source); bad["media_refs"][1]["locator"]["uri"] = "camera/missing.mp4"
bad_path = save("missing-alias.json", bad)
command("refuse-missing-alias", [exe, "collect", bad_path, root, a.output / "missing-output"], False)
assert not (a.output / "missing-output").exists()

moved = a.output / "relocated editable bundle"
bundle.rename(moved)
root.rename(a.output / "original media retained")
command("verify-after-relocation", [exe, "verify", moved])
command("reopen-through-chapter-authoring", [chapters, "seed", moved / "project.json", "video", a.output / "reopened.chapters.json"])
chapter_draft = json.loads((a.output / "reopened.chapters.json").read_text())
assert chapter_draft["duration_ticks"] == 20000
probe = json.loads(command("decode-collected-video", ["ffprobe", "-v", "error", "-show_streams", "-of", "json", moved / native["media_refs"][0]["locator"]["uri"]]))
assert probe["streams"][0]["codec_name"] == "h264"
command("decode-collected-stream", ["ffmpeg", "-v", "error", "-nostdin", "-i", moved / native["media_refs"][0]["locator"]["uri"], "-f", "null", "-"])
command("decode-collected-audio", ["ffprobe", "-v", "error", "-show_streams", "-of", "json", moved / native["media_refs"][2]["locator"]["uri"]])
# Tamper with private test copies; retain every fixture and failed output.
tampered = a.output / "tampered-copy"
shutil.copytree(moved, tampered)
media = tampered / native["media_refs"][0]["locator"]["uri"]
with media.open("r+b") as f:
    f.write(b"X")
command("refuse-tampered-media", [exe, "verify", tampered], False)
manifest_bad = a.output / "manifest-bad"
manifest_bad.mkdir(); shutil.copyfile(moved / "project.json", manifest_bad / "project.json")
manifest = json.loads((moved / "collection.json").read_text())
manifest["members"] = manifest["members"][:-1]
(manifest_bad / "collection.json").write_text(json.dumps(manifest))
command("refuse-incomplete-manifest", [exe, "verify", manifest_bad], False)
partial = a.output / "partial-bundle"; partial.mkdir()
shutil.copyfile(moved / "project.json", partial / "project.json")
command("refuse-incomplete-collection", [exe, "verify", partial], False)
(a.output / "checks.json").write_text(json.dumps(checks, indent=2) + "\n")
print(json.dumps({"status": "passed", "checks": len(checks), "unique_media": 3,
                  "native_media_references": 4, "portable_bundle": str(moved)}, indent=2))
