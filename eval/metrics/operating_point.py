# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Operating-point metric: the *product* view of a verification model.

Verification AUC/EER tell you how well a model ranks pairs; they don't tell you
what the user actually experiences. The People feature works like this: when a
new face arrives we score it against a known identity and either

  * auto-accept it (score clearly above threshold),
  * auto-reject it (score clearly below threshold), or
  * *prompt the user* ("Is this Alice?") when the score is close to the line.

This module turns a model into those three buckets and measures the two numbers
the product cares about:

  * ``prompt_rate``      — how often we bother the user (lower is better), and
  * ``auto_accept_error``— how often the auto path is WRONG (the silent errors
                           the user never gets to correct; lower is better).

Method
------
1. Calibrate a decision threshold ``T`` on the CALIB identity split so that the
   false-accept rate (FAR) on calib impostor pairs equals ``far_target``. This
   is exactly the threshold verification would pick at that FAR — re-derived
   here so this module stands alone (no import-time coupling to verification).
2. Define an uncertain band ``[T - uncertain_band, T + uncertain_band]`` in
   score units. Pairs whose score lands in the band get *prompted*.
3. On HELD-OUT genuine+impostor pairs:
     - ``prompt_rate``       = (# pairs inside band) / (# held-out pairs)
     - auto-decided pairs    = pairs OUTSIDE the band; accept if score > T else
                               reject.
     - ``auto_accept_error`` = (# false-accepts + # false-rejects)
                               / (# auto-decided pairs)

Scores come from ``common.pair_score`` (higher == more similar for both cosine
and negative-L2), so a single ``score > T`` rule works for every model.

Everything is robust to tiny splits: empty calib/held pairs, a band that
swallows all held-out pairs, or a far_target finer than the calib impostor
count all degrade to sensible NaN/edge values rather than raising.
"""

from __future__ import annotations

import itertools
from typing import Dict, List, Tuple

import numpy as np

from common import pair_score

# Cap on the number of genuine / impostor pairs we materialize, so a large held
# split (O(n^2) impostor candidates) stays bounded. Matched to the kind of
# budget verification uses; plenty for a stable FAR estimate.
_MAX_GENUINE = 20000
_MAX_IMPOSTOR = 200000


# ----------------------------------------------------------------- pair sampling

def _genuine_pairs(y: np.ndarray, rng: np.random.Generator) -> List[Tuple[int, int]]:
    """All within-identity index pairs (subsampled if there are too many)."""
    pairs: List[Tuple[int, int]] = []
    order = np.arange(len(y))
    for label in np.unique(y):
        idx = order[y == label]
        if len(idx) < 2:
            continue
        pairs.extend(itertools.combinations(idx.tolist(), 2))
    if len(pairs) > _MAX_GENUINE:
        sel = rng.choice(len(pairs), size=_MAX_GENUINE, replace=False)
        pairs = [pairs[i] for i in sel]
    return pairs


def _impostor_pairs(y: np.ndarray, n_target: int,
                    rng: np.random.Generator) -> List[Tuple[int, int]]:
    """Sample ``n_target`` cross-identity index pairs (each i<j, different label).

    Rejection sampling with a dedup guard; for small splits we just enumerate
    every valid cross pair and (sub)sample from it deterministically.
    """
    n = len(y)
    n_target = min(int(n_target), _MAX_IMPOSTOR)
    if n_target <= 0 or n < 2:
        return []

    # Small split: enumerate exhaustively (cheap and exact), then subsample.
    if n <= 400:
        all_imp = [(i, j) for i in range(n) for j in range(i + 1, n)
                   if y[i] != y[j]]
        if not all_imp:
            return []
        if len(all_imp) <= n_target:
            return all_imp
        sel = rng.choice(len(all_imp), size=n_target, replace=False)
        return [all_imp[i] for i in sel]

    # Large split: rejection-sample random pairs.
    seen: set[Tuple[int, int]] = set()
    out: List[Tuple[int, int]] = []
    attempts = 0
    max_attempts = n_target * 20 + 1000
    while len(out) < n_target and attempts < max_attempts:
        attempts += 1
        i, j = int(rng.integers(n)), int(rng.integers(n))
        if i == j or y[i] == y[j]:
            continue
        key = (i, j) if i < j else (j, i)
        if key in seen:
            continue
        seen.add(key)
        out.append(key)
    return out


def _scores(X: np.ndarray, pairs: List[Tuple[int, int]], metric: str) -> np.ndarray:
    """Score a list of index pairs (higher == more similar)."""
    if not pairs:
        return np.empty(0, dtype=np.float64)
    return np.array([pair_score(X[i], X[j], metric) for i, j in pairs],
                    dtype=np.float64)


# --------------------------------------------------------------- threshold calib

def _threshold_at_far(impostor_scores: np.ndarray, far_target: float) -> float:
    """Pick T so that FAR(impostors >= T) ~= far_target.

    With higher==more-similar, FAR is the fraction of impostor scores at or
    above T. We want the smallest T whose tail mass is <= far_target, i.e. the
    (1 - far_target) quantile of the impostor-score distribution. ``higher``
    interpolation gives a threshold that does not under-shoot the target FAR.
    """
    s = np.asarray(impostor_scores, dtype=np.float64)
    if s.size == 0:
        return float("nan")
    far_target = min(max(float(far_target), 0.0), 1.0)
    q = 1.0 - far_target
    return float(np.quantile(s, q, method="higher"))


# --------------------------------------------------------------------- evaluate

def evaluate(Xc: np.ndarray, yc: List[str], Xh: np.ndarray, yh: List[str], *,
             metric: str, far_target: float, uncertain_band: float,
             seed: int) -> Dict[str, object]:
    """Product operating point: threshold + prompt-rate + silent error.

    Parameters
    ----------
    Xc, yc : CALIB split embeddings (L2-normalized) and identity labels — used
             only to calibrate the threshold ``T`` at ``far_target``.
    Xh, yh : HELD-OUT split embeddings and labels — the pairs we actually
             measure prompt-rate and auto-error on (disjoint identities from
             calib, per run.py's identity-level split).
    metric : "cosine" | "l2" (passed straight to ``common.pair_score``).
    far_target     : target false-accept rate used to set ``T`` (e.g. 1e-3).
    uncertain_band : half-width of the prompt zone, in score units.
    seed   : RNG seed for reproducible impostor sampling.

    Returns
    -------
    dict with keys: ``threshold``, ``auto_accept_error``, ``prompt_rate``,
    ``n_auto``, ``n_prompt``. Degenerate inputs yield NaN rates with the
    corresponding counts at 0 rather than raising.
    """
    rng = np.random.default_rng(seed)
    yc_arr = np.asarray(yc)
    yh_arr = np.asarray(yh)
    band = abs(float(uncertain_band))

    nan_result: Dict[str, object] = {
        "threshold": float("nan"),
        "auto_accept_error": float("nan"),
        "prompt_rate": float("nan"),
        "n_auto": 0,
        "n_prompt": 0,
    }

    # --- 1. calibrate T on the calib split -------------------------------------
    if Xc.shape[0] < 2 or yc_arr.size < 2:
        return nan_result
    calib_imp = _impostor_pairs(yc_arr, _MAX_IMPOSTOR, rng)
    calib_imp_scores = _scores(Xc, calib_imp, metric)
    if calib_imp_scores.size == 0:
        # No cross-identity pairs in calib (e.g. a single identity) -> cannot
        # calibrate a FAR-based threshold.
        return nan_result
    T = _threshold_at_far(calib_imp_scores, far_target)
    if not np.isfinite(T):
        return nan_result

    # --- 2. build held-out genuine + impostor pairs ----------------------------
    gen_pairs = _genuine_pairs(yh_arr, rng)
    n_gen = len(gen_pairs)
    # Mirror verification's impostor:genuine balance loosely — sample impostors
    # proportional to genuine count so prompt_rate/error are not dominated by a
    # single class. Fall back to a fixed budget when there are no genuine pairs.
    imp_target = n_gen * 10 if n_gen > 0 else _MAX_IMPOSTOR
    imp_pairs = _impostor_pairs(yh_arr, imp_target, rng)

    gen_scores = _scores(Xh, gen_pairs, metric)   # ground truth: should ACCEPT
    imp_scores = _scores(Xh, imp_pairs, metric)   # ground truth: should REJECT
    all_scores = np.concatenate([gen_scores, imp_scores])
    n_pairs = all_scores.size
    if n_pairs == 0:
        # No held-out pairs at all: threshold is valid but nothing to measure.
        return {**nan_result, "threshold": T}

    # --- 3. partition into prompt (in band) vs auto (outside band) -------------
    lo, hi = T - band, T + band
    in_band = (all_scores >= lo) & (all_scores <= hi)
    n_prompt = int(in_band.sum())
    auto_mask = ~in_band
    n_auto = int(auto_mask.sum())

    prompt_rate = n_prompt / n_pairs

    # Auto-decided error: among the pairs we did NOT prompt on, how many did the
    # accept-if-score>T rule get wrong (false-accepts + false-rejects)?
    if n_auto == 0:
        auto_accept_error = float("nan")
    else:
        # is_genuine aligns with the concatenation order above.
        is_genuine = np.concatenate([
            np.ones(gen_scores.size, dtype=bool),
            np.zeros(imp_scores.size, dtype=bool),
        ])
        accepted = all_scores > T
        # false-accept: impostor auto-accepted; false-reject: genuine auto-rejected.
        wrong = (accepted & ~is_genuine) | (~accepted & is_genuine)
        auto_wrong = int((wrong & auto_mask).sum())
        auto_accept_error = auto_wrong / n_auto

    return {
        "threshold": T,
        "auto_accept_error": auto_accept_error,
        "prompt_rate": prompt_rate,
        "n_auto": n_auto,
        "n_prompt": n_prompt,
    }
