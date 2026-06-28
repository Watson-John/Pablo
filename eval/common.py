# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Shared contracts for the face-model evaluation harness.

This is the seam that binds the harness to the labeled face DB produced by
``eval/ingest/build_face_db.py``. Everything downstream (detect, embed, metrics,
report) consumes ``FaceEntry`` records loaded from that ``manifest.csv`` — the
exact columns we already write:

    face_id, person_name, contact_hash, source_image, folder,
    bbox_px, bbox_norm, source, crop_path
"""

from __future__ import annotations

import csv
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np

# ---------------------------------------------------------------- face database

@dataclass
class FaceEntry:
    """One labeled, cropped face — a row of our faces_db/manifest.csv."""
    face_id: str
    person_name: str          # ground-truth label (the Picasa contact name)
    crop_path: str            # upright, EXIF-corrected face crop on disk
    source_image: str = ""
    contact_hash: str = ""
    folder: str = ""
    source: str = "ini"       # ini | raw | xmp
    bbox_px: str = ""
    bbox_norm: str = ""


def load_face_db(manifest_csv: str | Path) -> List[FaceEntry]:
    """Load every face from a faces_db ``manifest.csv``.

    Tolerant of extra/missing columns so the loader and the ingester can evolve
    independently — only ``face_id``, ``person_name`` and ``crop_path`` are
    required.
    """
    manifest_csv = Path(manifest_csv)
    out: List[FaceEntry] = []
    with manifest_csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        required = {"face_id", "person_name", "crop_path"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"{manifest_csv}: manifest missing columns {missing}")
        for row in reader:
            out.append(FaceEntry(
                face_id=row["face_id"],
                person_name=row["person_name"],
                crop_path=row["crop_path"],
                source_image=row.get("source_image", ""),
                contact_hash=row.get("contact_hash", ""),
                folder=row.get("folder", ""),
                source=row.get("source", "ini"),
                bbox_px=row.get("bbox_px", ""),
                bbox_norm=row.get("bbox_norm", ""),
            ))
    return out


def group_by_person(entries: List[FaceEntry]) -> Dict[str, List[FaceEntry]]:
    groups: Dict[str, List[FaceEntry]] = {}
    for e in entries:
        groups.setdefault(e.person_name, []).append(e)
    return groups


def load_image_bgr(path: str | Path) -> Optional[np.ndarray]:
    """Read a crop as BGR uint8 (the crops are already upright — no EXIF needed)."""
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    return img if img is not None and img.size else None


# --------------------------------------------------------------- detection type

@dataclass
class Detection:
    """A YuNet face detection. ``row`` is YuNet's native 15-float output
    (bbox[4] + 5 landmarks[10] + score[1]) — SFace's alignCrop consumes it
    directly; the ArcFace embedders use ``landmarks``; dlib uses ``bbox``."""
    bbox: Tuple[float, float, float, float]      # x, y, w, h (pixels)
    landmarks: np.ndarray                        # (5, 2) float32: eyes, nose, mouth corners
    score: float
    row: np.ndarray = field(default_factory=lambda: np.zeros(15, np.float32))


# ----------------------------------------------------- ArcFace alignment (112²)

# Canonical 5-point destination template for 112x112 ArcFace-family inputs
# (buffalo_l, AdaFace). Order: left eye, right eye, nose, left mouth, right mouth.
ARCFACE_5PT = np.array([
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
], dtype=np.float32)


def align_arcface(image_bgr: np.ndarray, landmarks: np.ndarray,
                  size: int = 112) -> np.ndarray:
    """Similarity-warp a face to the canonical ArcFace 112x112 frame.

    Uses a partial-affine (rotation + uniform scale + translation, no shear) fit
    from the 5 detected landmarks to ARCFACE_5PT — the standard insightface
    alignment. Returns BGR uint8 of shape (size, size, 3).
    """
    src = np.asarray(landmarks, dtype=np.float32).reshape(5, 2)
    dst = ARCFACE_5PT.copy()
    if size != 112:
        dst = dst * (size / 112.0)
    M, _ = cv2.estimateAffinePartial2D(src, dst, method=cv2.LMEDS)
    if M is None:
        # Degenerate landmarks — fall back to a plain resize of the crop.
        return cv2.resize(image_bgr, (size, size), interpolation=cv2.INTER_AREA)
    return cv2.warpAffine(image_bgr, M, (size, size), flags=cv2.INTER_LINEAR,
                          borderValue=0.0)


# ------------------------------------------------------------------- math utils

def l2_normalize(v: np.ndarray, axis: int = -1, eps: float = 1e-10) -> np.ndarray:
    v = np.asarray(v, dtype=np.float32)
    norm = np.linalg.norm(v, axis=axis, keepdims=True)
    return v / np.maximum(norm, eps)


def pair_score(a: np.ndarray, b: np.ndarray, metric: str) -> float:
    """Similarity for a pair of (L2-normalized) embeddings.

    Returns a value where HIGHER == more similar for both metrics, so the same
    thresholding logic works everywhere: cosine similarity, or negative L2.
    """
    if metric == "cosine":
        return float(np.dot(a, b))
    if metric == "l2":
        return float(-np.linalg.norm(a - b))
    raise ValueError(f"unknown metric: {metric}")
