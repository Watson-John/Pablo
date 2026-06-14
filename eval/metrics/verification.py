# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Phase-3 verification metric: 1:1 face matching quality.

We turn each split's embeddings into labelled *pairs* — genuine (same person)
and impostor (different people) — score every pair with the model's own
``common.pair_score`` (higher == more similar for cosine OR negative-L2 alike),
and summarise the separability of the two score distributions.

Calibration discipline (why two splits):
  Thresholds are picked on the CALIB split (identities the harness "saw") and
  then *applied* to the HELD-OUT split (unseen identities). That keeps the
  reported operating point (TAR @ a fixed FAR) honest — it's the FAR we'd
  actually get from a threshold we could have chosen without peeking at the
  test identities. AUC / EER are reported on the held-out split directly.

Everything returned is JSON-friendly (plain floats / lists), and the whole
thing is robust to tiny / degenerate splits: when a quantity is undefined
(no genuine pairs, no impostor pairs, single-class ROC, …) we return NaN rather
than raising, so the harness can still tabulate the rest of the models.
"""

from __future__ import annotations

import math
from typing import Dict, List, Sequence, Tuple

import numpy as np
from sklearn.metrics import auc as sk_auc
from sklearn.metrics import roc_curve

from common import pair_score

NAN = float("nan")


# --------------------------------------------------------------------- pairing

def _build_pairs(
    X: np.ndarray,
    y: Sequence[str],
    metric: str,
    impostor_ratio: float,
    rng: np.random.Generator,
) -> Tuple[np.ndarray, np.ndarray]:
    """Build genuine + impostor pair scores for one split.

    genuine  : every unordered same-label pair (i < j).
    impostor : a random sample of different-label pairs, capped at
               ``impostor_ratio * n_genuine`` (so the score sets stay balanced
               and the ROC's FAR axis is well-populated where we need it).

    Returns ``(scores, labels)`` where ``labels`` is 1 for genuine, 0 for
    impostor. Either array may be empty when the split can't form that kind of
    pair — callers must tolerate empties.
    """
    y = np.asarray(list(y))
    n = len(y)

    # ---- genuine pairs: all same-label combinations -------------------------
    gen_idx: List[Tuple[int, int]] = []
    # Group row indices by label, then take intra-group combinations.
    by_label: Dict[str, List[int]] = {}
    for i, lab in enumerate(y):
        by_label.setdefault(lab, []).append(i)
    for idxs in by_label.values():
        m = len(idxs)
        for a in range(m):
            for b in range(a + 1, m):
                gen_idx.append((idxs[a], idxs[b]))

    n_gen = len(gen_idx)

    # ---- impostor pairs: sample cross-label pairs, capped -------------------
    # Total possible different-label pairs.
    n_all = n * (n - 1) // 2
    n_diff_possible = n_all - n_gen
    cap = int(math.floor(impostor_ratio * n_gen)) if n_gen > 0 else 0
    n_imp_target = min(cap, n_diff_possible)

    imp_idx: List[Tuple[int, int]] = []
    if n_imp_target > 0:
        # Rejection sampling of unordered index pairs is efficient here because
        # impostor pairs vastly outnumber genuine ones in any realistic split.
        # We oversample (request > target) to absorb collisions/genuine hits,
        # dedup, then trim to the target count.
        seen: set[Tuple[int, int]] = set()
        # Hard ceiling on draws so a pathological split can never spin forever.
        max_draws = 20 * n_imp_target + 1000
        draws = 0
        while len(imp_idx) < n_imp_target and draws < max_draws:
            # Draw a batch for vectorised speed.
            batch = max(n_imp_target - len(imp_idx), 1) * 2
            ia = rng.integers(0, n, size=batch)
            ib = rng.integers(0, n, size=batch)
            for a, b in zip(ia.tolist(), ib.tolist()):
                draws += 1
                if a == b or y[a] == y[b]:
                    continue
                key = (a, b) if a < b else (b, a)
                if key in seen:
                    continue
                seen.add(key)
                imp_idx.append(key)
                if len(imp_idx) >= n_imp_target:
                    break

    # ---- score every selected pair -----------------------------------------
    def _score_pairs(pairs: List[Tuple[int, int]]) -> np.ndarray:
        if not pairs:
            return np.empty(0, dtype=np.float64)
        out = np.empty(len(pairs), dtype=np.float64)
        for k, (a, b) in enumerate(pairs):
            out[k] = pair_score(X[a], X[b], metric)
        return out

    gen_scores = _score_pairs(gen_idx)
    imp_scores = _score_pairs(imp_idx)

    scores = np.concatenate([gen_scores, imp_scores])
    labels = np.concatenate([
        np.ones(gen_scores.size, dtype=np.int8),
        np.zeros(imp_scores.size, dtype=np.int8),
    ])
    return scores, labels


# ----------------------------------------------------------- threshold helpers

def _threshold_for_far(
    imp_scores: np.ndarray, far: float
) -> float:
    """Smallest threshold ``t`` (decision: score >= t => accept) whose false
    accept rate on ``imp_scores`` is <= ``far``.

    With "higher == more similar", FAR(t) = mean(imp_scores >= t) is
    monotonically non-increasing in t, so the (1-far) empirical quantile of the
    impostor scores is the lowest threshold meeting the target. Returns +inf if
    even the most permissive non-trivial threshold can't hit the FAR (i.e. far
    smaller than 1/n_imp resolution); returns NaN if there are no impostors.
    """
    n = imp_scores.size
    if n == 0:
        return NAN
    # We want the (1 - far) quantile: the value above which only `far` fraction
    # of impostors lie. Sort ascending; pick index ceil((1-far)*n) - 1 ... but
    # to guarantee FAR <= target we walk to the score whose tail mass <= far.
    s = np.sort(imp_scores)
    # Number of impostors we are allowed to (falsely) accept.
    k_allowed = int(math.floor(far * n))
    if k_allowed >= n:
        # FAR target so loose it admits everyone: threshold below all scores.
        return float(s[0]) - 1.0
    if k_allowed <= 0:
        # Accept zero impostors: threshold just above the largest impostor.
        return float(np.nextafter(s[-1], np.inf))
    # Accept exactly the top k_allowed impostors: threshold is just above the
    # (n - k_allowed - 1)-th smallest, i.e. above the largest *rejected* score.
    return float(np.nextafter(s[n - k_allowed - 1], np.inf))


def _tar_at_threshold(gen_scores: np.ndarray, thr: float) -> float:
    """True accept rate = fraction of genuine pairs scoring >= threshold."""
    if gen_scores.size == 0 or not math.isfinite(thr):
        return NAN
    return float(np.mean(gen_scores >= thr))


def _auc_eer(
    scores: np.ndarray, labels: np.ndarray
) -> Tuple[float, float, float, List[float], List[float]]:
    """ROC-derived AUC, EER and EER threshold from held-out pair scores.

    Returns ``(auc, eer, eer_threshold, fpr_list, tpr_list)``. All NaN / empty
    when the ROC is undefined (need both a genuine and an impostor present).
    """
    pos = int(np.sum(labels == 1))
    neg = int(np.sum(labels == 0))
    if pos == 0 or neg == 0:
        return NAN, NAN, NAN, [], []

    # roc_curve treats higher score as more "positive" — exactly our convention.
    fpr, tpr, thr = roc_curve(labels, scores, pos_label=1)
    try:
        roc_auc = float(sk_auc(fpr, tpr))
    except ValueError:
        roc_auc = NAN

    # EER: where FPR == FNR (1 - TPR). Find the crossing of (fnr - fpr).
    fnr = 1.0 - tpr
    diff = fnr - fpr
    # Index just before the sign change of diff (diff is non-increasing along
    # the curve). Interpolate EER + its threshold for a stable estimate.
    idx = int(np.nanargmin(np.abs(diff)))
    eer = float((fpr[idx] + fnr[idx]) / 2.0)
    eer_thr = float(thr[idx])
    # roc_curve prepends an inf threshold for the (0,0) point; guard against it.
    if not math.isfinite(eer_thr):
        # Fall back to the next finite threshold if available.
        finite = [t for t in thr if math.isfinite(t)]
        eer_thr = float(finite[0]) if finite else NAN

    return roc_auc, eer, eer_thr, fpr.tolist(), tpr.tolist()


# --------------------------------------------------------------- bootstrap CIs

def _percentile_ci(samples: List[float], lo: float = 2.5, hi: float = 97.5
                   ) -> List[float]:
    """95% percentile interval over bootstrap samples, NaNs dropped."""
    arr = np.asarray([s for s in samples if s is not None and math.isfinite(s)],
                     dtype=np.float64)
    if arr.size == 0:
        return [NAN, NAN]
    return [float(np.percentile(arr, lo)), float(np.percentile(arr, hi))]


# --------------------------------------------------------------------- public

def evaluate(
    Xc: np.ndarray,
    yc: Sequence[str],
    Xh: np.ndarray,
    yh: Sequence[str],
    *,
    metric: str,
    far_targets: Sequence[float],
    impostor_ratio: float,
    seed: int,
    bootstrap_ci: bool = False,
) -> dict:
    """Verification (1:1) metrics for one model.

    Parameters
    ----------
    Xc, yc : calibration-split embeddings (N_c, D) and their person labels.
             Used only to *choose* thresholds for the FAR targets.
    Xh, yh : held-out-split embeddings and labels. AUC / EER / TAR are reported
             here.
    metric : "cosine" | "l2" — passed straight to ``common.pair_score``.
    far_targets : iterable of target false-accept rates, e.g. [1e-3, 1e-4].
    impostor_ratio : cap impostor pairs at this multiple of genuine pairs.
    seed : seeds the numpy Generator for reproducible impostor sampling.
    bootstrap_ci : if True, add 95% percentile CIs (key ``"ci"``).

    Returns a JSON-friendly dict; undefined quantities are NaN.
    """
    Xc = np.asarray(Xc, dtype=np.float32)
    Xh = np.asarray(Xh, dtype=np.float32)
    yc = list(yc)
    yh = list(yh)

    rng = np.random.default_rng(seed)

    # ---- build pair scores for each split ----------------------------------
    # Distinct child generators so calib/held sampling don't correlate.
    c_scores, c_labels = _build_pairs(
        Xc, yc, metric, impostor_ratio, np.random.default_rng(seed))
    h_scores, h_labels = _build_pairs(
        Xh, yh, metric, impostor_ratio, np.random.default_rng(seed + 1))

    c_gen = c_scores[c_labels == 1]
    c_imp = c_scores[c_labels == 0]
    h_gen = h_scores[h_labels == 1]
    h_imp = h_scores[h_labels == 0]

    # ---- AUC / EER on held-out ---------------------------------------------
    roc_auc, eer, eer_thr, fpr, tpr = _auc_eer(h_scores, h_labels)

    # ---- TAR @ FAR: threshold from CALIB, TAR/realized-FAR on HELD ----------
    tar_at_far: Dict[str, float] = {}
    thr_at_far: Dict[str, float] = {}
    far_at_far: Dict[str, float] = {}   # actually-realized FAR on held-out
    for far in far_targets:
        key = "%g" % float(far)
        thr = _threshold_for_far(c_imp, float(far))
        thr_at_far[key] = thr
        tar_at_far[key] = _tar_at_threshold(h_gen, thr)
        # Diagnostic: the FAR this calib threshold actually produces on held-out.
        far_at_far[key] = (
            float(np.mean(h_imp >= thr))
            if (h_imp.size and math.isfinite(thr)) else NAN
        )

    result: dict = {
        "metric": metric,
        "auc": roc_auc,
        "eer": eer,
        "eer_threshold": eer_thr,
        "tar_at_far": tar_at_far,
        "thr_at_far": thr_at_far,
        "far_at_far": far_at_far,
        "roc": {"fpr": fpr, "tpr": tpr},
        "gen_scores": h_gen.astype(np.float64).tolist(),
        "imp_scores": h_imp.astype(np.float64).tolist(),
        "n_gen": int(h_gen.size),
        "n_imp": int(h_imp.size),
    }

    # ---- optional bootstrap CIs --------------------------------------------
    if bootstrap_ci:
        result["ci"] = _bootstrap(
            c_gen, c_imp, h_gen, h_imp,
            far_targets=far_targets, seed=seed)

    return result


def _bootstrap(
    c_gen: np.ndarray,
    c_imp: np.ndarray,
    h_gen: np.ndarray,
    h_imp: np.ndarray,
    *,
    far_targets: Sequence[float],
    seed: int,
    n_boot: int = 1000,
) -> dict:
    """95% percentile CIs for auc / eer / tar_at_far via paired resampling.

    Each replicate resamples (with replacement) the genuine and impostor score
    *pools* of each split independently, then recomputes the same statistics.
    This is a fast approximation to a pair-level bootstrap that is more than
    adequate for ranking models and drawing error bars. Returns NaN intervals
    when a quantity was undefined on the full data.
    """
    rng = np.random.default_rng(seed + 7)

    auc_s: List[float] = []
    eer_s: List[float] = []
    tar_s: Dict[str, List[float]] = {"%g" % float(f): [] for f in far_targets}

    # Nothing to resample from -> NaN intervals for everything.
    have_held = h_gen.size > 0 and h_imp.size > 0
    have_calib = c_imp.size > 0

    for _ in range(n_boot):
        if have_held:
            hg = h_gen[rng.integers(0, h_gen.size, size=h_gen.size)]
            hi = h_imp[rng.integers(0, h_imp.size, size=h_imp.size)]
            scores = np.concatenate([hg, hi])
            labels = np.concatenate([
                np.ones(hg.size, np.int8), np.zeros(hi.size, np.int8)])
            b_auc, b_eer, _, _, _ = _auc_eer(scores, labels)
            auc_s.append(b_auc)
            eer_s.append(b_eer)
        else:
            hg = np.empty(0)
            hi = np.empty(0)

        # TAR@FAR replicate: resample calib impostors for the threshold, held
        # genuine for the TAR estimate.
        ci = (c_imp[rng.integers(0, c_imp.size, size=c_imp.size)]
              if have_calib else np.empty(0))
        for far in far_targets:
            key = "%g" % float(far)
            if have_held and have_calib:
                thr = _threshold_for_far(ci, float(far))
                tar_s[key].append(_tar_at_threshold(hg, thr))
            else:
                tar_s[key].append(NAN)

    return {
        "auc": _percentile_ci(auc_s),
        "eer": _percentile_ci(eer_s),
        "tar_at_far": {k: _percentile_ci(v) for k, v in tar_s.items()},
        "n_boot": n_boot,
    }
