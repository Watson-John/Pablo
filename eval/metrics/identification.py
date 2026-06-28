# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Closed-set 1:N identification metrics (leave-one-out).

Given the held-out embeddings ``Xh`` (already L2-normalized, see
``embed.base.Embedder``) and their ground-truth labels ``yh``, we treat every
face in turn as a probe and the *rest* of the set as the gallery. Each probe is
ranked against all OTHER faces by ``common.pair_score`` (higher == more similar
for both 'cosine' and 'l2'), and we report:

  rank1 : fraction of probes whose top-1 gallery neighbour shares the probe's
          label (Cumulative Match Characteristic at rank 1).
  mAP   : mean Average Precision — for each probe, AP of its ranked gallery list
          where a "relevant" hit is a gallery face of the same label; averaged
          over probes. Probes whose label is a singleton (no other face of that
          identity exists, so AP is undefined) are excluded from the mAP mean.
  n_probes : number of probes contributing to mAP (i.e. non-singleton probes).

Everything is computed from one full N x N similarity matrix:
  * cosine : S = Xh @ Xh.T   (valid because the vectors are unit-norm).
  * l2     : S = -pairwise_L2(Xh, Xh)  (negative distance, so higher == closer),
             matching ``common.pair_score(a, b, 'l2') == -||a - b||``.
The diagonal (a face vs. itself) is masked out with -inf so a probe never
retrieves itself — this is the "leave-one-out" gallery.

Robust to tiny N and all-singleton sets: undefined quantities return NaN.
"""

from __future__ import annotations

from typing import Dict, List, Sequence

import numpy as np


def _similarity_matrix(Xh: np.ndarray, metric: str) -> np.ndarray:
    """Full N x N similarity matrix where higher == more similar.

    Mirrors ``common.pair_score`` exactly so ranking here agrees with pairwise
    scoring used elsewhere in the harness.
    """
    X = np.asarray(Xh, dtype=np.float32)
    if metric == "cosine":
        # Vectors are already L2-normalized, so the Gram matrix IS cosine sim.
        return X @ X.T
    if metric == "l2":
        # Negative Euclidean distance: ||a-b||^2 = ||a||^2 + ||b||^2 - 2 a.b.
        # Use float64 for the expansion to avoid catastrophic cancellation, then
        # clamp tiny negatives from round-off before the sqrt.
        Xd = X.astype(np.float64)
        sq = np.einsum("ij,ij->i", Xd, Xd)                 # (N,) row sq-norms
        d2 = sq[:, None] + sq[None, :] - 2.0 * (Xd @ Xd.T)
        np.maximum(d2, 0.0, out=d2)
        return (-np.sqrt(d2)).astype(np.float32)
    raise ValueError(f"unknown metric: {metric}")


def evaluate(Xh: np.ndarray, yh: Sequence[str], *, metric: str) -> Dict[str, float]:
    """Leave-one-out closed-set identification.

    Parameters
    ----------
    Xh : (N, D) float array of L2-normalized embeddings (held-out split).
    yh : length-N sequence of ground-truth identity labels.
    metric : 'cosine' or 'l2' — must match the model's scoring metric.

    Returns
    -------
    {"rank1": float, "mAP": float, "n_probes": int}
    NaN is returned for rank1 / mAP where they are undefined (e.g. N < 2 or no
    non-singleton identities exist).
    """
    X = np.asarray(Xh, dtype=np.float32)
    labels = np.asarray(list(yh))
    n = X.shape[0]

    # Degenerate: need at least 2 faces for any probe to have a gallery.
    if n < 2 or labels.shape[0] != n:
        return {"rank1": float("nan"), "mAP": float("nan"), "n_probes": 0}

    # Per-identity counts -> a probe is a "singleton" if no OTHER face shares its
    # label (its own count is 1), in which case it has no relevant gallery item.
    uniq, inv, counts = np.unique(labels, return_inverse=True, return_counts=True)
    rel_per_probe = counts[inv] - 1               # # of same-label faces excl. self

    S = _similarity_matrix(X, metric)
    # Leave-one-out: a face can never retrieve itself.
    np.fill_diagonal(S, -np.inf)

    # Rank the gallery for every probe at once: descending similarity.
    # order[i] = gallery indices for probe i, most-similar first (self is last,
    # pinned there by the -inf diagonal, and never enters the top ranks).
    order = np.argsort(-S, axis=1, kind="stable")

    # Same-label boolean, gathered in ranked order. hits[i, k] == True iff the
    # k-th retrieved gallery face for probe i shares probe i's identity.
    same = labels[:, None] == labels[None, :]     # (N, N) bool
    np.fill_diagonal(same, False)                 # never count the probe itself
    hits = np.take_along_axis(same, order, axis=1)  # (N, N) bool, ranked

    # ---- rank-1 accuracy (CMC@1): top retrieved neighbour is a genuine match.
    # Every probe with n >= 2 has a non-empty gallery, so rank1 is always defined.
    rank1 = float(np.mean(hits[:, 0]))

    # ---- mean Average Precision over non-singleton probes only.
    valid = rel_per_probe > 0                     # probes with >=1 relevant item
    n_probes = int(np.count_nonzero(valid))
    if n_probes == 0:
        mAP = float("nan")
    else:
        h = hits[valid].astype(np.float64)        # (P, N) ranked hits
        rel = rel_per_probe[valid].astype(np.float64)  # (P,) total relevants
        # Precision@k along the ranked list: cumulative hits / position.
        csum = np.cumsum(h, axis=1)
        positions = np.arange(1, n + 1, dtype=np.float64)[None, :]
        precision_at_k = csum / positions
        # AP = mean of precision@k taken only AT the ranks where a hit occurs,
        # normalized by the number of relevant items: sum(P@k * hit_k) / R.
        ap = (precision_at_k * h).sum(axis=1) / rel
        mAP = float(np.mean(ap))

    return {"rank1": rank1, "mAP": mAP, "n_probes": n_probes}
