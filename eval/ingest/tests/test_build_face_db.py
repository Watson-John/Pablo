# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Unit tests for build_face_db helpers (slugify / crop / orientation)."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from PIL import Image  # noqa: E402

from build_face_db import (  # noqa: E402
    apply_orientation,
    content_key,
    crop_face,
    slugify,
)


def test_slugify():
    assert slugify("Roy Avery") == "Roy Avery"             # spaces/case preserved
    assert slugify("Anne-Marie O'Neil") == "Anne-Marie O'Neil"
    assert slugify('bad/name:with*chars') == "bad_name_with_chars"
    assert slugify("   ...   ") == "_unnamed"              # empty after cleaning
    assert "/" not in slugify("a/b/c") and "\\" not in slugify("a\\b")


def test_slugify_length_cap():
    long_a = "Z" * 400
    long_b = "Z" * 399 + "Y"            # differs only at the tail
    sa, sb = slugify(long_a), slugify(long_b)
    assert len(sa) <= 120 and len(sb) <= 120
    assert sa != sb                     # distinct long names stay distinct
    assert slugify("Roy Avery") == "Roy Avery"   # short names untouched


def test_crop_face_basic_and_clamp():
    img = Image.new("RGB", (100, 100))
    # Centered box, no padding -> exact 20x20.
    c = crop_face(img, (0.4, 0.4, 0.6, 0.6), pad=0.0)
    assert c is not None and c.size == (20, 20)
    # Padding expands symmetrically: 0.5 * 20px = 10px each side -> 40x40.
    c = crop_face(img, (0.4, 0.4, 0.6, 0.6), pad=0.5)
    assert c.size == (40, 40)
    # Box at the corner with big pad must clamp to image bounds, not crash.
    c = crop_face(img, (0.0, 0.0, 0.1, 0.1), pad=2.0)
    assert c is not None and c.width > 0 and c.height > 0
    # Degenerate box -> None.
    assert crop_face(img, (0.5, 0.5, 0.5, 0.5), pad=0.0) is None


def test_apply_orientation_swaps_dims_for_rotations():
    img = Image.new("RGB", (10, 4))            # wide
    assert apply_orientation(img, 1).size == (10, 4)   # identity
    assert apply_orientation(img, 3).size == (10, 4)   # 180 keeps dims
    assert apply_orientation(img, 6).size == (4, 10)   # 90 CW swaps dims
    assert apply_orientation(img, 8).size == (4, 10)   # 90 CCW swaps dims
    # A face crop that is wider-than-tall in raw space becomes upright after
    # orientation 6 — this is the heart of the raw-coord-space fix.


def test_content_key_stable_and_distinct():
    with tempfile.TemporaryDirectory() as d:
        a = Path(d) / "a.bin"
        b = Path(d) / "b.bin"
        a.write_bytes(b"hello world" * 1000)
        b.write_bytes(b"different bytes" * 1000)
        assert content_key(a) == content_key(a)     # stable
        assert content_key(a) != content_key(b)     # distinct
        assert content_key(Path(d) / "missing") == ""  # graceful


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
