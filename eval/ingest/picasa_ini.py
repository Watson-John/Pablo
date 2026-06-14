# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Parse Picasa ``.picasa.ini`` sidecars into labeled face records.

This is the **primary** face source (Source A). Picasa writes one INI per folder
with a ``[Contacts2]`` map (hash -> name) and a per-image ``faces=`` line listing
``rect64(HEX),contacthash`` pairs.

``decode_rect64`` and ``parse_picasa_ini`` are pure and carry the project's
highest risk of *silent* error (a wrong rectangle still "looks like a number"),
so they ship with unit tests (see tests/test_picasa_ini.py).
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Dict, List, Tuple

# Picasa ran on Windows; the sidecar name varies in case. Match case-insensitively.
INI_NAMES = {".picasa.ini", "picasa.ini"}

# Detected-but-unnamed face. Has no label -> excluded from ground truth.
UNNAMED_HASH = "f" * 16

# One ``rect64(HEX),HASH`` pair. Hex is 1-16 digits (Picasa strips leading
# zeros). The contact hash is optional in malformed entries.
_FACE_PART = re.compile(
    r"rect64\(([0-9a-fA-F]{1,16})\)\s*(?:,\s*([0-9a-fA-F]{1,16}))?"
)
_SECTION = re.compile(r"^\[(.+)\]$")


def decode_rect64_norm(hex_str: str) -> Tuple[float, float, float, float]:
    """Decode a Picasa ``rect64`` hex string to a *normalized* box.

    The 16-hex-digit value is four 16-bit unsigned ints (left, top, right,
    bottom), each divided by 65535 -> [0, 1].

    CRITICAL: Picasa strips leading zeros, so the hex may be 1-16 digits.
    Left-pad to 16 before decoding or short rectangles silently corrupt.
    """
    h = hex_str.strip().lower().zfill(16)  # <-- the #1 gotcha
    v = int(h, 16)
    left = ((v >> 48) & 0xFFFF) / 65535.0
    top = ((v >> 32) & 0xFFFF) / 65535.0
    right = ((v >> 16) & 0xFFFF) / 65535.0
    bottom = (v & 0xFFFF) / 65535.0
    return (left, top, right, bottom)


def decode_rect64(hex_str: str, img_w: int, img_h: int) -> Tuple[float, float, float, float]:
    """Decode a Picasa ``rect64`` to a pixel bbox (left, top, right, bottom).

    Scale the normalized box by the **oriented** image dimensions (apply EXIF
    orientation to the image first — see build_face_db.py).
    """
    l, t, r, b = decode_rect64_norm(hex_str)
    return (l * img_w, t * img_h, r * img_w, b * img_h)


def find_picasa_ini(folder: Path) -> Path | None:
    """Return the Picasa INI in ``folder`` (case-insensitive name match), or None."""
    try:
        for entry in folder.iterdir():
            if entry.is_file() and entry.name.lower() in INI_NAMES:
                return entry
    except (OSError, PermissionError):
        return None
    return None


def parse_picasa_ini(
    ini_path: Path,
) -> Tuple[Dict[str, str], Dict[str, List[Tuple[str, str]]]]:
    """Parse one Picasa INI.

    Returns ``(contacts, faces_by_file)`` where:
      * ``contacts``: ``{hash: name}`` from ``[Contacts2]`` (or legacy
        ``[Contacts]`` if a Google-synced library was used).
      * ``faces_by_file``: ``{filename: [(contact_hash, rect64_hex), ...]}`` —
        the section header IS the image filename. The unnamed hash is preserved
        here; callers decide whether to drop it.

    Picasa INIs can carry a UTF-8 BOM and non-ASCII / HTML-escaped names, so we
    read tolerantly and parse line by line rather than with configparser (whose
    duplicate-key and ``;``-comment handling both trip on this format).
    """
    contacts: Dict[str, str] = {}
    faces_by_file: Dict[str, List[Tuple[str, str]]] = {}
    section: str | None = None

    try:
        text = ini_path.read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return contacts, faces_by_file

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = _SECTION.match(line)
        if m:
            section = m.group(1)
            continue
        if section in ("Contacts2", "Contacts"):
            if "=" in line:
                h, rest = line.split("=", 1)
                # name;modified;... -> take the name field; unescape nothing here
                name = rest.split(";", 1)[0].strip()
                if name:
                    contacts[h.strip().lower()] = name
        elif section and line.lower().startswith("faces="):
            entries = line.split("=", 1)[1]
            recs: List[Tuple[str, str]] = []
            for part in entries.split(";"):
                part = part.strip()
                if not part:
                    continue
                fm = _FACE_PART.match(part)
                if fm:
                    rect_hex = fm.group(1)
                    chash = (fm.group(2) or UNNAMED_HASH).lower()
                    recs.append((chash, rect_hex))
            if recs:
                # Accumulate — a filename can appear in more than one section /
                # have more than one faces= line; replacing would drop earlier faces.
                faces_by_file.setdefault(section, []).extend(recs)

    return contacts, faces_by_file
