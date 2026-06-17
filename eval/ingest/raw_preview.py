# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Extract the largest embedded preview from a RAW file via exiftool.

Pillow only exposes a RAW file's tiny thumbnail (a .nef decodes to 160x120), so
RAW faces would be useless. RAW files DO embed a larger JPEG preview — often
full-size (a Nikon .nef carries a 6000x4000 ``JpgFromRaw``; a Pixel .dng a
~548x412 ``PreviewImage``). We pull the largest one and return it together with
the file's EXIF orientation, so the caller can decode the rect against the
preview's raw dimensions and rotate the resulting crop upright — the same
coordinate handling as a regular JPEG.

Avoids a heavyweight RAW decoder (rawpy/LibRaw): exiftool is already a dependency
for the XMP fallback, and we never need a full demosaic for a face crop.
"""

from __future__ import annotations

import io
import shutil
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from PIL import Image

# Tried in turn; the largest-by-area decodable image wins (order is a hint, not
# a guarantee — a .dng has only PreviewImage, a .nef a full-size JpgFromRaw).
_PREVIEW_TAGS = ("JpgFromRaw", "PreviewImage", "OtherImage")


def exiftool_available(exiftool: str = "exiftool") -> bool:
    return shutil.which(exiftool) is not None


def exiftool_orientation(path: Path, exiftool: str = "exiftool") -> int:
    """EXIF Orientation (1..8) per exiftool's authoritative read, or 1.

    exiftool resolves the RAW's main-IFD orientation correctly where Pillow
    (which may latch onto a sub-IFD) disagrees.
    """
    try:
        r = subprocess.run(
            [exiftool, "-n", "-s3", "-Orientation", str(path)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=30,
        )
        return int(r.stdout.strip())
    except (OSError, ValueError, subprocess.SubprocessError):
        return 1


def extract_raw_preview(
    path: Path, exiftool: str = "exiftool"
) -> Optional[Tuple[Image.Image, int]]:
    """Return (largest embedded preview as RGB, EXIF orientation), or None.

    The preview is returned WITHOUT applying orientation (the caller decides,
    matching the regular-image path). None if exiftool is absent or no preview
    decodes.
    """
    if not exiftool_available(exiftool):
        return None
    best: Optional[Image.Image] = None
    for tag in _PREVIEW_TAGS:
        try:
            r = subprocess.run(
                [exiftool, "-b", "-" + tag, str(path)],
                capture_output=True, timeout=60,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if not r.stdout:
            continue
        try:
            im = Image.open(io.BytesIO(r.stdout))
            im.load()
            im = im.convert("RGB")
        except Exception:  # noqa: BLE001 — any decode failure -> try next tag
            continue
        if best is None or im.size[0] * im.size[1] > best.size[0] * best.size[1]:
            best = im
    if best is None:
        return None
    return best, exiftool_orientation(path, exiftool)
