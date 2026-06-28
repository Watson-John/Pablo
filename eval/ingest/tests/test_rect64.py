# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""The eval harness's mandatory rect64 fixture (Phase 0 acceptance gate).

    decode_rect64("3f845bcb59418507", 1000, 1000) ~= (248.1, 358.6, 348.6, 519.6)

Run: `python -m pytest` or `python tests/test_rect64.py`.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from picasa_ini import decode_rect64  # noqa: E402


def test_rect64_fixture():
    box = decode_rect64("3f845bcb59418507", 1000, 1000)
    expected = (248.1, 358.6, 348.6, 519.6)
    assert all(abs(a - b) < 0.1 for a, b in zip(box, expected)), box


def test_rect64_leading_zero_stripped():
    # Picasa strips leading zeros — a short hex must left-pad to 16 first.
    assert decode_rect64("8507", 1000, 1000) == decode_rect64("0000000000008507", 1000, 1000)
    l, t, r, _b = decode_rect64("8507", 1000, 1000)
    assert (l, t, r) == (0.0, 0.0, 0.0)   # only `bottom` is set


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  PASS {name}")
            except AssertionError as e:
                failed += 1
                print(f"  FAIL {name}: {e}")
    raise SystemExit(1 if failed else 0)
