"""Read immutable asset evidence and append-only human reviews."""

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

from .render import RenderError


_ASSET_ID = re.compile(r"^[0-9a-f]{20}$")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class AssetStore:
    def __init__(self, output_root: Path) -> None:
        self.output_root = output_root
        self.records_dir = output_root / "records"
        self.reviews_dir = output_root / "reviews"

    def _validate_id(self, asset_id: str) -> None:
        if not _ASSET_ID.fullmatch(asset_id):
            raise RenderError("asset_not_found", "asset does not exist", 404)

    def _record_path(self, asset_id: str) -> Path:
        self._validate_id(asset_id)
        return self.records_dir / ("asset-%s.json" % asset_id)

    def _reviews(self, asset_id: str) -> List[Dict[str, Any]]:
        self._validate_id(asset_id)
        if not self.reviews_dir.is_dir():
            return []
        reviews = []
        for path in sorted(self.reviews_dir.glob("review-%s-*.json" % asset_id)):
            with path.open("r", encoding="utf-8") as handle:
                reviews.append(json.load(handle))
        return reviews

    def get(self, asset_id: str) -> Dict[str, Any]:
        path = self._record_path(asset_id)
        if not path.is_file():
            raise RenderError("asset_not_found", "asset does not exist", 404)
        with path.open("r", encoding="utf-8") as handle:
            record = json.load(handle)
        reviews = self._reviews(asset_id)
        latest = reviews[-1] if reviews else {
            "status": "pending",
            "required": True,
            "reviewer_id": None,
            "decided_at": None,
        }
        record["human_review"] = latest
        record["publication"] = {
            "status": "not_published",
            "adapter_invoked": False,
            "eligible": latest.get("status") == "approved",
            "note": "Publication is a separate reviewed provider operation.",
        }
        return record

    def list_assets(self) -> List[Dict[str, Any]]:
        if not self.records_dir.is_dir():
            return []
        items = []
        for path in sorted(self.records_dir.glob("asset-*.json"), reverse=True):
            asset_id = path.stem.removeprefix("asset-")
            items.append(self.get(asset_id))
        return items

    def review(self, asset_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        record = self.get(asset_id)
        reviewer_id = " ".join(str(payload.get("reviewer_id", "")).split())
        if not reviewer_id or len(reviewer_id) > 100:
            raise RenderError("reviewer_required", "reviewer_id is required")
        decision = str(payload.get("decision", "")).casefold()
        if decision not in ("approve", "reject"):
            raise RenderError("decision_invalid", "decision must be approve or reject")
        note = " ".join(str(payload.get("note", "")).split())[:500]
        decided_at = _utc_now()
        review = {
            "asset_id": asset_id,
            "asset_sha256": record["sha256"],
            "reviewer_id": reviewer_id,
            "status": "approved" if decision == "approve" else "rejected",
            "note": note,
            "decided_at": decided_at,
            "required": True,
        }
        digest = hashlib.sha256(
            json.dumps(review, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()[:10]
        stamp = decided_at.replace(":", "").replace("-", "").replace(".", "")
        self.reviews_dir.mkdir(parents=True, exist_ok=True)
        path = self.reviews_dir / ("review-%s-%s-%s.json" % (asset_id, stamp, digest))
        with path.open("x", encoding="utf-8") as handle:
            json.dump(review, handle, ensure_ascii=False, sort_keys=True, indent=2)
            handle.write("\n")
        return self.get(asset_id)
