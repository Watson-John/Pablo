# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Resolve unresolved contact hashes via Picasa's ``contacts.xml`` (db3 dir).

Fallback for hashes that appear in a folder's ``faces=`` line but not in that
folder's ``[Contacts2]`` map. Picasa keeps a global contact list at
``<Local AppData>/Google/Picasa2/db3/contacts.xml``:

    <contacts>
      <contact id="b8e4117cf1d6615b" name="Roy Avery" .../>
    </contacts>

The db3 dir lives with the Picasa *install* (typically Windows), so it is often
not present alongside an exported photo tree — this resolver is best-effort.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, Iterable, Optional


def load_contacts_xml(path: Path) -> Dict[str, str]:
    """Parse ``contacts.xml`` -> ``{hash_lower: name}``. Empty dict on any error."""
    out: Dict[str, str] = {}
    try:
        tree = ET.parse(path)
    except (ET.ParseError, OSError):
        return out
    for contact in tree.getroot().iter("contact"):
        cid = (contact.get("id") or "").strip().lower()
        name = (contact.get("name") or "").strip()
        if cid and name:
            out[cid] = name
    return out


def find_contacts_xml(search_roots: Iterable[Path]) -> Optional[Path]:
    """Look for a ``contacts.xml`` (case-insensitive) under the given roots.

    Checks each root directly and a nested ``db3/`` subdir before walking.
    """
    for root in search_roots:
        if root is None:
            continue
        root = Path(root)
        for candidate in (root / "contacts.xml", root / "db3" / "contacts.xml"):
            if candidate.is_file():
                return candidate
        if root.is_dir():
            try:
                for p in root.rglob("*"):
                    if p.is_file() and p.name.lower() == "contacts.xml":
                        return p
            except (OSError, PermissionError):
                continue
    return None
