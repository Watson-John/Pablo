#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Phase-2 preprocessing sanity gate.

A cheap, fast guard that catches the classic preprocessing bugs that *don't*
crash but quietly wreck a model: feeding BGR where the net wants RGB, the wrong
input normalization, a bad alignment template, etc. Symptoms of all of these are
the same — the embedding space collapses and a SAME-person pair no longer scores
higher than a DIFFERENT-person pair.

So for each configured model we load its cached embeddings
(``eval_out/embeddings_<name>.npz``, produced by ``run.py`` phase 2) plus the
ground-truth labels from the faces_db ``manifest.csv``, then assert:

    pair_score(faceA_personX, faceB_personX) > pair_score(faceA_personX, face_personY)

i.e. two faces of the SAME person are more similar than a face of a DIFFERENT
person — using that model's own ``metric`` (``common.pair_score`` is defined so
HIGHER == more similar for both cosine and L2).

If a model has no cache yet, we SKIP it (this is a sanity gate, not a coverage
gate) — so the suite is meaningful the moment any embeddings exist and harmless
before then.

Runnable two ways::

    pytest eval/tests/test_sanity.py -v
    python  eval/tests/test_sanity.py            # plain stdout, no pytest needed

Dependency-light by design: only numpy + pyyaml + the harness ``common`` module.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import yaml

# --- make the harness importable flat (ROOT on sys.path), as run.py does ------
ROOT = Path(__file__).resolve().parent.parent          # .../eval
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from common import load_face_db, pair_score  # noqa: E402


# ----------------------------------------------------------------- path helpers

def _resolve(base: Path, p: str) -> Path:
    """Resolve a config path relative to ``base`` (eval/), mirroring run.py."""
    q = Path(p)
    return q if q.is_absolute() else (base / q)


def load_config() -> dict:
    with open(ROOT / "config.yaml", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _out_dir(cfg: dict) -> Path:
    return _resolve(ROOT, cfg["eval"]["output_dir"])


def _manifest_path(cfg: dict) -> Path:
    # Honour a FACES_DB override (same DB run.py was pointed at via --faces-db)
    # so the sanity gate uses the labels the cached embeddings were built from.
    db = os.environ.get("FACES_DB") or cfg["ingest"]["faces_db"]
    return _resolve(ROOT, db) / "manifest.csv"


def _model_names_and_metrics(cfg: dict) -> List[Tuple[str, str]]:
    """(name, metric) for every model row in config.yaml."""
    return [(m["name"], m.get("metric", "cosine")) for m in cfg["models"]]


# ----------------------------------------------------------------- core checker

def _load_labels(cfg: dict) -> Optional[Dict[str, str]]:
    """face_id -> person_name from the faces_db manifest, or None if absent."""
    manifest = _manifest_path(cfg)
    if not manifest.exists():
        return None
    return {e.face_id: e.person_name for e in load_face_db(manifest)}


def _load_cache(cfg: dict, name: str) -> Optional[Tuple[np.ndarray, List[str]]]:
    """(X, ids) from eval_out/embeddings_<name>.npz, or None if not cached."""
    cache = _out_dir(cfg) / f"embeddings_{name}.npz"
    if not cache.exists():
        return None
    z = np.load(cache, allow_pickle=True)
    # run.py saves X (float32, one row per face) and ids (object array of face_id).
    return z["X"], [str(i) for i in z["ids"]]


def _pick_pairs(
    X: np.ndarray, ids: List[str], labels: Dict[str, str]
) -> Optional[Tuple[np.ndarray, np.ndarray, np.ndarray, str, str]]:
    """Pick a SAME-person pair and a DIFFERENT-person face from the cache.

    Returns (anchor_vec, same_vec, diff_vec, same_person, diff_person), or None if
    the cache doesn't contain two faces of one person + one face of another (in
    which case there's simply nothing to assert and the caller should skip).
    """
    # Bucket the embedded face_ids by their ground-truth person.
    by_person: Dict[str, List[int]] = {}
    for row, fid in enumerate(ids):
        person = labels.get(fid)
        if person is None:            # face in cache but not in manifest — ignore
            continue
        by_person.setdefault(person, []).append(row)

    # A SAME pair needs a person with >= 2 embedded faces.
    same_person = next((p for p, rows in by_person.items() if len(rows) >= 2), None)
    if same_person is None:
        return None
    anchor_row, same_row = by_person[same_person][0], by_person[same_person][1]

    # A DIFFERENT face is any face whose person differs from same_person.
    diff_person = next((p for p in by_person if p != same_person), None)
    if diff_person is None:
        return None
    diff_row = by_person[diff_person][0]

    return (X[anchor_row], X[same_row], X[diff_row], same_person, diff_person)


def _check_model(
    cfg: dict, name: str, metric: str, labels: Dict[str, str]
) -> Tuple[bool, str]:
    """Run the sanity assertion for one model.

    Returns (ok, message). ``ok`` is True on PASS, False on SKIP *or* FAIL — the
    caller distinguishes those via the message prefix ("SKIP" vs anything else).
    Raising is reserved for the genuine FAIL case under pytest.
    """
    cache = _load_cache(cfg, name)
    if cache is None:
        return True, f"SKIP {name}: no cache (eval_out/embeddings_{name}.npz)"
    X, ids = cache
    if X.size == 0 or not ids:
        return True, f"SKIP {name}: empty cache"

    picked = _pick_pairs(X, ids, labels)
    if picked is None:
        return True, (f"SKIP {name}: need >=2 faces of one labeled person and "
                      f">=1 of another in the cache")
    anchor, same, diff, same_person, diff_person = picked

    same_score = pair_score(anchor, same, metric)
    diff_score = pair_score(anchor, diff, metric)
    msg = (f"{name} [{metric}]: same('{same_person}')={same_score:+.4f} "
           f"vs diff('{diff_person}')={diff_score:+.4f}")

    if not (same_score > diff_score):
        raise AssertionError(
            f"FAIL {msg} — same-person pair did NOT score higher than the "
            f"different-person pair. Likely a preprocessing bug for '{name}' "
            f"(BGR/RGB swap, wrong input normalization, or bad alignment).")
    return True, f"PASS {msg}"


# ------------------------------------------------------------------- pytest API
#
# We parametrize over every model row, so pytest reports one PASS/SKIP/FAIL line
# per model. Importing pytest is optional (the __main__ path below works without
# it), so we guard the decorator.

try:
    import pytest

    _CFG = load_config()
    _LABELS = _load_labels(_CFG)
    _MODELS = _model_names_and_metrics(_CFG)

    @pytest.mark.parametrize("name,metric", _MODELS,
                             ids=[m[0] for m in _MODELS])
    def test_same_beats_different(name: str, metric: str) -> None:
        if _LABELS is None:
            pytest.skip(f"no faces_db manifest at {_manifest_path(_CFG)} "
                        f"(run ingest first)")
        ok, msg = _check_model(_CFG, name, metric, _LABELS)
        if msg.startswith("SKIP"):
            pytest.skip(msg)
        print(msg)              # surfaced with -s; assertion already happened
        assert ok

except ImportError:             # pytest not installed — __main__ path still runs
    pass


# --------------------------------------------------------------------- __main__

def _main() -> int:
    """Plain-stdout runner: PASS/SKIP/FAIL per model, exit 1 only on a real FAIL."""
    cfg = load_config()
    labels = _load_labels(cfg)
    if labels is None:
        print(f"SKIP all: no faces_db manifest at {_manifest_path(cfg)} "
              f"(run ingest first)")
        return 0

    failed = False
    for name, metric in _model_names_and_metrics(cfg):
        try:
            _, msg = _check_model(cfg, name, metric, labels)
        except AssertionError as ex:
            failed = True
            msg = str(ex)
        print(msg)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(_main())
