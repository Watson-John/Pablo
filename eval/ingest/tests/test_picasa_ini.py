# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Unit tests for the pure, high-silent-risk Picasa parsing functions.

Run with `python -m pytest` OR directly: `python test_picasa_ini.py`.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from picasa_ini import (  # noqa: E402
    UNNAMED_HASH,
    decode_rect64,
    decode_rect64_norm,
    find_picasa_ini,
    parse_picasa_ini,
)


def _approx(a, b, tol=1e-9):
    return abs(a - b) <= tol


def test_decode_rect64_worked_example():
    # rect64(3f845bcb59418507) -> the spec's worked-example fixture.
    l, t, r, b = decode_rect64_norm("3f845bcb59418507")
    assert _approx(l, 0x3F84 / 65535.0)
    assert _approx(t, 0x5BCB / 65535.0)
    assert _approx(r, 0x5941 / 65535.0)
    assert _approx(b, 0x8507 / 65535.0)
    # Rounded, the spec's documented values.
    assert (round(l, 3), round(t, 3), round(r, 3), round(b, 3)) == (0.248, 0.359, 0.349, 0.520)


def test_decode_rect64_left_pad_gotcha():
    # Picasa strips leading zeros. "8507" must left-pad to 16 -> only `bottom`
    # is set. Without zfill, int("8507",16) would land in the high bits and
    # silently corrupt the box.
    l, t, r, b = decode_rect64_norm("8507")
    assert (l, t, r) == (0.0, 0.0, 0.0)
    assert _approx(b, 0x8507 / 65535.0)
    # zfill is applied even on already-padded input (idempotent).
    assert decode_rect64_norm("0000000000008507") == decode_rect64_norm("8507")


def test_decode_rect64_pixel_scaling():
    l, t, r, b = decode_rect64("3f845bcb59418507", 1000, 2000)
    assert _approx(l, 0x3F84 / 65535.0 * 1000)
    assert _approx(t, 0x5BCB / 65535.0 * 2000)
    assert _approx(r, 0x5941 / 65535.0 * 1000)
    assert _approx(b, 0x8507 / 65535.0 * 2000)


def _write(tmp: Path, name: str, text: str) -> Path:
    p = tmp / name
    p.write_text(text, encoding="utf-8")
    return p


def test_parse_picasa_ini_contacts_and_faces():
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        # Leading BOM, a named + an unnamed face on one multi-face line.
        ini = _write(
            tmp,
            ".picasa.ini",
            "﻿[Contacts2]\n"
            "4df561a1c3920266=Roy Avery;;\n"
            "47d06f0716518784=Kenyatta Folkers;;\n"
            "[IMG_0001.JPG]\n"
            "faces=rect64(3f845bcb59418507),4df561a1c3920266;"
            "rect64(9eb15e89b6b584c1),ffffffffffffffff\n"
            "backuphash=11776\n",
        )
        contacts, faces = parse_picasa_ini(ini)
        assert contacts["4df561a1c3920266"] == "Roy Avery"
        assert contacts["47d06f0716518784"] == "Kenyatta Folkers"
        recs = faces["IMG_0001.JPG"]
        assert len(recs) == 2
        assert recs[0] == ("4df561a1c3920266", "3f845bcb59418507")
        # Unnamed face is preserved (caller decides to drop it).
        assert recs[1] == (UNNAMED_HASH, "9eb15e89b6b584c1")


def test_parse_picasa_ini_legacy_contacts_section():
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        ini = _write(
            tmp,
            ".picasa.ini",
            "[Contacts]\nabc123=Synced Person;;\n[a.jpg]\nfaces=rect64(ff),abc123\n",
        )
        contacts, faces = parse_picasa_ini(ini)
        assert contacts["abc123"] == "Synced Person"
        assert faces["a.jpg"] == [("abc123", "ff")]


def test_parse_picasa_ini_accumulates_split_entries():
    # A filename split across two sections (or two faces= lines) must keep BOTH
    # faces, not just the last.
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        ini = _write(
            tmp, ".picasa.ini",
            "[Contacts2]\na1=A;;\nb2=B;;\n"
            "[a.jpg]\nfaces=rect64(11),a1\n"
            "[a.jpg]\nfaces=rect64(22),b2\n",
        )
        _contacts, faces = parse_picasa_ini(ini)
        assert faces["a.jpg"] == [("a1", "11"), ("b2", "22")]


def test_find_picasa_ini_case_insensitive():
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        (tmp / "Picasa.ini").write_text("[Contacts2]\n", encoding="utf-8")
        found = find_picasa_ini(tmp)
        assert found is not None and found.name == "Picasa.ini"


def _run_all():
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = 0
    for fn in fns:
        try:
            fn()
            print(f"  PASS {fn.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"  FAIL {fn.__name__}: {e}")
    print(f"\n{len(fns) - failed}/{len(fns)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(_run_all())
