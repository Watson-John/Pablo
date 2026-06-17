# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Read embedded XMP face regions via exiftool (Source B — fallback).

Used ONLY for images with no ``.picasa.ini`` entry, so faces are never
double-counted. Two schemas are supported:

  * MWG Regions   (XMP-mwg-rs:RegionList) — normalized, CENTER-based Area
    (X, Y = center; W, H = size) + Name + Type.
  * MS People     (XMP-MP:RegionInfoMP / MPReg) — Windows Live Photo Gallery
    rectangles "x, y, w, h" (normalized, TOP-LEFT based) + PersonDisplayName.

All boxes are returned **normalized** (left, top, right, bottom in [0, 1])
relative to the displayed (EXIF-oriented) image — matching rect64 output so the
orchestrator can scale every source the same way.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple


@dataclass(frozen=True)
class XmpRegion:
    name: str
    box_norm: Tuple[float, float, float, float]  # (left, top, right, bottom)
    rtype: str       # "Face", "Pet", ... ("" if unknown)
    schema: str      # "mwg" | "mp"


def exiftool_available(exiftool: str = "exiftool") -> bool:
    return shutil.which(exiftool) is not None


def _clamp01(v: float) -> float:
    return 0.0 if v < 0.0 else 1.0 if v > 1.0 else v


def _norm_box(l: float, t: float, r: float, b: float) -> Tuple[float, float, float, float]:
    l, t, r, b = _clamp01(l), _clamp01(t), _clamp01(r), _clamp01(b)
    if r < l:
        l, r = r, l
    if b < t:
        t, b = b, t
    return (l, t, r, b)


def _as_list(x):
    if x is None:
        return []
    return x if isinstance(x, list) else [x]


def _parse_mwg(region_info: dict) -> List[XmpRegion]:
    """MWG RegionInfo -> regions. Area is center-based (X, Y, W, H)."""
    out: List[XmpRegion] = []
    for item in _as_list(region_info.get("RegionList")):
        area = item.get("Area") or {}
        try:
            cx, cy = float(area["X"]), float(area["Y"])
            w, h = float(area["W"]), float(area["H"])
        except (KeyError, TypeError, ValueError):
            continue
        box = _norm_box(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
        out.append(XmpRegion(
            name=str(item.get("Name", "")).strip(),
            box_norm=box,
            rtype=str(item.get("Type", "")).strip(),
            schema="mwg",
        ))
    return out


def _parse_mp(region_info_mp: dict) -> List[XmpRegion]:
    """MS People RegionInfoMP -> regions. Rectangle is "x, y, w, h" top-left."""
    out: List[XmpRegion] = []
    for item in _as_list(region_info_mp.get("Regions")):
        rect = item.get("Rectangle")
        if not rect:
            continue
        try:
            x, y, w, h = (float(p) for p in str(rect).split(","))
        except (ValueError, TypeError):
            continue
        box = _norm_box(x, y, x + w, y + h)
        out.append(XmpRegion(
            name=str(item.get("PersonDisplayName", "")).strip(),
            box_norm=box,
            rtype="Face",
            schema="mp",
        ))
    return out


def read_xmp_regions(image_path: Path, exiftool: str = "exiftool") -> List[XmpRegion]:
    """Return XMP face regions embedded in ``image_path`` (empty list if none).

    Requires exiftool on PATH; returns [] (not an error) when it is absent so the
    pipeline degrades gracefully.
    """
    if not exiftool_available(exiftool):
        return []
    try:
        # exiftool emits UTF-8; decode it explicitly (and tolerantly) so a
        # non-ASCII name under a C/POSIX locale can't raise UnicodeDecodeError
        # (a ValueError, which the generic except below would NOT catch).
        proc = subprocess.run(
            [exiftool, "-j", "-struct", "-n", "-q", "-q", str(image_path)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=60,
        )
    except (OSError, ValueError, subprocess.SubprocessError):
        return []
    if proc.returncode != 0 or not proc.stdout.strip():
        return []
    try:
        meta = json.loads(proc.stdout)[0]
    except (json.JSONDecodeError, IndexError):
        return []

    regions: List[XmpRegion] = []
    if isinstance(meta.get("RegionInfo"), dict):
        regions += _parse_mwg(meta["RegionInfo"])
    # exiftool exposes the MS schema as RegionInfoMP (XMP-MP).
    for key in ("RegionInfoMP", "RegionInfo MP"):
        if isinstance(meta.get(key), dict):
            regions += _parse_mp(meta[key])
    return regions


def named_face_regions(regions: List[XmpRegion]) -> List[XmpRegion]:
    """Keep only named Face/empty-type regions (drop unnamed + non-face)."""
    keep: List[XmpRegion] = []
    for r in regions:
        if not r.name:
            continue
        if r.rtype and r.rtype.lower() not in ("face", ""):
            continue
        keep.append(r)
    return keep
