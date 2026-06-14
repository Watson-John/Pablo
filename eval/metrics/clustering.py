# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Phase-3 clustering metric: how well do embeddings group into people?

The People feature ultimately *clusters* unlabeled faces into per-person piles,
so clustering quality is the closest proxy we have to the shipped experience.
Given the held-out embeddings ``Xh`` (already L2-normalized, see
``embed.base.Embedder``) and their ground-truth labels ``yh``, we run one or
more unsupervised clustering methods and score the predicted partition against
the true identities.

Two methods are supported (configured in ``config.yaml`` ``eval.clustering``):

  * ``dbscan`` — density clustering via ``sklearn.cluster.DBSCAN``. We cluster in
    *cosine-distance* space (1 - cosine sim) for cosine models and in plain
    Euclidean space for L2 models — i.e. the same notion of "near" that
    ``common.pair_score`` uses. ``eps`` is chosen by a small seeded sweep that
    maximizes the mean silhouette (a label-free quality score); if the sweep
    can't score anything we fall back to a documented sensible default. DBSCAN's
    ``-1`` noise label is treated as "unclustered" — those points are excluded
    from ``n_clusters`` and counted as singleton clusters for the pair metrics.

  * ``chinese_whispers`` — a from-scratch implementation (no dlib / networkx) of
    the randomized graph label-propagation algorithm (Biemann 2006), the same
    one dlib uses for face clustering. We build a kNN similarity graph, keep only
    edges whose ``pair_score`` clears a threshold, then iterate: each node (in a
    seeded random order) adopts the label that carries the most edge weight among
    its neighbours. ~20 iterations or convergence.

Scoring (predicted labels vs. ground-truth ``yh``):
  * ``ari``         — adjusted Rand index (sklearn), chance-corrected agreement.
  * ``nmi``         — normalized mutual information (sklearn).
  * ``pairwise_f1`` — precision / recall / F1 over the set of *same-cluster*
                      index pairs vs. *same-label* pairs (the BCubed-flavoured
                      pair view; robust and directly interpretable).
  * ``n_clusters``  — number of predicted clusters, excluding DBSCAN noise (-1).

Everything returned is JSON-friendly (plain floats / ints) and robust to tiny or
degenerate splits: undefined quantities return NaN / 0 rather than raising, so
the harness can still tabulate the rest of the models.
"""

from __future__ import annotations

from typing import Dict, List, Sequence

import numpy as np
from sklearn.cluster import DBSCAN
from sklearn.metrics import adjusted_rand_score, normalized_mutual_info_score
from sklearn.metrics import silhouette_score

NAN = float("nan")

# DBSCAN eps sweep — searched values per distance space. For cosine we work in
# cosine-DISTANCE units (1 - cos sim), where two embeddings of the same identity
# typically sit < ~0.4 apart; for L2 (unit vectors) the equivalent Euclidean gap
# is sqrt(2 * cosdist). Defaults are used only if the silhouette sweep is empty.
_COS_EPS_GRID = (0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60)
_COS_EPS_DEFAULT = 0.40
_L2_EPS_GRID = (0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00, 1.10, 1.20)
_L2_EPS_DEFAULT = 0.80
_DBSCAN_MIN_SAMPLES = 2          # smallest density that still forms a cluster

# Chinese-whispers graph parameters.
_CW_K = 10                        # neighbours per node in the kNN graph
_CW_ITERS = 20                    # label-propagation sweeps (or convergence)
# Edge-keep threshold in pair_score units (higher == more similar). Same-identity
# embeddings of modern models score well above these; cross-identity pairs fall
# below, so the threshold sparsifies the graph into per-person components. The L2
# threshold is the cosine threshold mapped through the unit-vector identity
# ||a-b|| = sqrt(2 - 2*cos), so both spaces keep the *same* pairs: keeping
# cos >= 0.40 is equivalent to keeping ||a-b|| <= sqrt(2 - 2*0.40) ~= 1.095.
_CW_COS_THRESH = 0.40             # cosine similarity
_CW_L2_THRESH = -float(np.sqrt(2.0 - 2.0 * _CW_COS_THRESH))   # negative L2 distance


# --------------------------------------------------------------- shared geometry

def _distance_matrix(X: np.ndarray, metric: str) -> np.ndarray:
    """Dense N x N DISTANCE matrix (lower == more similar) matching pair_score.

    cosine -> 1 - cos_sim   (vectors are unit-norm so the Gram matrix is cos).
    l2     -> Euclidean distance ||a - b||.
    """
    Xd = np.asarray(X, dtype=np.float64)
    sq = np.einsum("ij,ij->i", Xd, Xd)                    # (N,) row squared norms
    # ||a-b||^2 = ||a||^2 + ||b||^2 - 2 a.b ; clamp round-off negatives.
    d2 = sq[:, None] + sq[None, :] - 2.0 * (Xd @ Xd.T)
    np.maximum(d2, 0.0, out=d2)
    if metric == "cosine":
        gram = Xd @ Xd.T                                  # cosine similarity
        return np.clip(1.0 - gram, 0.0, 2.0)              # cosine distance
    if metric == "l2":
        return np.sqrt(d2)                                # Euclidean distance
    raise ValueError(f"unknown metric: {metric}")


def _similarity_matrix(X: np.ndarray, metric: str) -> np.ndarray:
    """Dense N x N SIMILARITY matrix (higher == more similar) == pair_score(i, j)."""
    if metric == "cosine":
        Xd = np.asarray(X, dtype=np.float64)
        return Xd @ Xd.T                                  # cosine similarity
    if metric == "l2":
        return -_distance_matrix(X, "l2")                 # negative L2 distance
    raise ValueError(f"unknown metric: {metric}")


# ----------------------------------------------------------------------- scoring

def _pairwise_f1(pred: np.ndarray, true: np.ndarray) -> Dict[str, float]:
    """Precision / recall / F1 over the set of same-cluster vs same-label PAIRS.

    A pair (i, j), i < j, is "predicted positive" if both land in the same
    predicted cluster, and "actually positive" if they share a ground-truth
    label. We count these without materializing O(N^2) pairs by using the
    per-cluster / per-label group sizes:

        #same-cluster pairs   = sum_c  C(|cluster c|, 2)
        #same-label pairs     = sum_l  C(|label l|, 2)
        #true-positive pairs  = sum over (cluster, label) cells C(|cell|, 2)

    Precision = TP / pred-positive, Recall = TP / actual-positive.
    """
    n = pred.shape[0]
    if n < 2:
        return {"precision": NAN, "recall": NAN, "f1": NAN}

    def _n_pairs(counts: np.ndarray) -> float:
        c = counts.astype(np.float64)
        return float(np.sum(c * (c - 1.0) / 2.0))

    # Same-cluster pairs (TP + FP).
    _, pred_counts = np.unique(pred, return_counts=True)
    pred_pairs = _n_pairs(pred_counts)
    # Same-label pairs (TP + FN).
    _, true_counts = np.unique(true, return_counts=True)
    true_pairs = _n_pairs(true_counts)
    # True-positive pairs: agree on BOTH cluster and label. Count co-occurrences
    # in each (cluster, label) cell of the contingency table.
    _, pred_idx = np.unique(pred, return_inverse=True)
    _, true_idx = np.unique(true, return_inverse=True)
    # Flatten the (cluster, label) cell id and tally cell sizes.
    n_true_groups = int(true_idx.max()) + 1
    cell = pred_idx.astype(np.int64) * n_true_groups + true_idx.astype(np.int64)
    cell_counts = np.bincount(cell)
    tp_pairs = _n_pairs(cell_counts)

    precision = tp_pairs / pred_pairs if pred_pairs > 0 else NAN
    recall = tp_pairs / true_pairs if true_pairs > 0 else NAN
    if (precision is NAN or recall is NAN
            or not np.isfinite(precision) or not np.isfinite(recall)
            or (precision + recall) == 0.0):
        f1 = 0.0 if (np.isfinite(precision) and np.isfinite(recall)) else NAN
    else:
        f1 = 2.0 * precision * recall / (precision + recall)
    return {"precision": float(precision), "recall": float(recall),
            "f1": float(f1)}


def _relabel_noise(labels: np.ndarray) -> np.ndarray:
    """Turn DBSCAN noise (-1) into distinct singleton clusters for pair scoring.

    Each noise point is genuinely "its own cluster" from the product's point of
    view (an unmatched face), so for ARI/NMI/pairwise we give every -1 a unique
    fresh label instead of lumping them into one giant cluster.
    """
    out = labels.astype(np.int64).copy()
    noise = out == -1
    n_noise = int(noise.sum())
    if n_noise:
        nxt = (out.max() + 1) if out.size and out.max() >= 0 else 0
        out[noise] = np.arange(nxt, nxt + n_noise, dtype=np.int64)
    return out


def _score_partition(pred_labels: np.ndarray, true_labels: np.ndarray,
                     n_clusters: int) -> Dict[str, object]:
    """Bundle ari / nmi / pairwise_f1 / n_clusters for one predicted partition."""
    # ARI / NMI handle the noise-as-singletons relabelling so a model that dumps
    # everything to noise is not rewarded.
    pred = _relabel_noise(pred_labels)
    true = np.asarray(true_labels)
    if pred.shape[0] < 2:
        return {"ari": NAN, "nmi": NAN, "pairwise_f1": NAN,
                "pairwise_precision": NAN, "pairwise_recall": NAN,
                "n_clusters": int(n_clusters)}
    ari = float(adjusted_rand_score(true, pred))
    nmi = float(normalized_mutual_info_score(true, pred))
    prf = _pairwise_f1(pred, true)
    return {
        "ari": ari,
        "nmi": nmi,
        # pairwise_f1 is the scalar F1 (precision/recall kept under separate keys)
        # so the reporter and decision rule can read it directly.
        "pairwise_f1": prf["f1"],
        "pairwise_precision": prf["precision"],
        "pairwise_recall": prf["recall"],
        "n_clusters": int(n_clusters),
    }


def _count_clusters(labels: np.ndarray) -> int:
    """Number of real clusters, excluding the DBSCAN noise label (-1)."""
    uniq = set(int(v) for v in np.unique(labels))
    uniq.discard(-1)
    return len(uniq)


# ------------------------------------------------------------------------ DBSCAN

def _run_dbscan(X: np.ndarray, metric: str, seed: int) -> np.ndarray:
    """DBSCAN in the model's native distance space; eps via a seeded silhouette
    sweep (best mean silhouette wins), falling back to a documented default.

    We precompute the dense distance matrix once and pass ``metric='precomputed'``
    so cosine and L2 share one code path and ``eps`` is always in true distance
    units.
    """
    n = X.shape[0]
    if n < _DBSCAN_MIN_SAMPLES:
        return np.full(n, -1, dtype=np.int64)

    D = _distance_matrix(X, metric)
    grid = _COS_EPS_GRID if metric == "cosine" else _L2_EPS_GRID
    default_eps = _COS_EPS_DEFAULT if metric == "cosine" else _L2_EPS_DEFAULT

    best_labels: np.ndarray | None = None
    best_score = -np.inf
    for eps in grid:
        labels = DBSCAN(eps=float(eps), min_samples=_DBSCAN_MIN_SAMPLES,
                        metric="precomputed").fit_predict(D)
        # Silhouette needs >=2 clusters and not-all-noise to be defined. Score on
        # the non-noise points only, in the same precomputed distance space.
        mask = labels != -1
        n_lbl = len(set(labels[mask].tolist()))
        if n_lbl < 2 or mask.sum() < 3:
            continue
        try:
            sil = silhouette_score(D[np.ix_(mask, mask)], labels[mask],
                                   metric="precomputed",
                                   random_state=seed)
        except ValueError:
            continue
        if sil > best_score:
            best_score = sil
            best_labels = labels

    if best_labels is None:
        # Sweep never produced a scorable (>=2 cluster) partition — use the
        # documented default eps so we still emit *a* partition.
        best_labels = DBSCAN(eps=float(default_eps),
                             min_samples=_DBSCAN_MIN_SAMPLES,
                             metric="precomputed").fit_predict(D)
    return np.asarray(best_labels, dtype=np.int64)


# --------------------------------------------------------------- Chinese whispers

def _knn_graph(S: np.ndarray, k: int, thresh: float):
    """Build a sparse symmetric kNN similarity graph as an adjacency list.

    For each node we keep its ``k`` most-similar neighbours (excluding itself)
    whose similarity clears ``thresh``; edges are made undirected. Returns a list
    where ``adj[i]`` is a list of ``(neighbour, weight)`` tuples.

    Edge weights are STRICTLY POSITIVE: ``(similarity - thresh) + eps``. This is
    essential — Chinese Whispers sums neighbour weights per class and takes the
    heaviest, which is only meaningful for non-negative weights. ``pair_score``
    similarities can be negative (negative-L2 metric is always < 0), so we shift
    every kept edge by the threshold; since kept edges have ``sim >= thresh`` the
    result is >= eps > 0, and a stronger edge still carries a larger vote.
    """
    n = S.shape[0]
    adj: List[List] = [[] for _ in range(n)]
    if n < 2:
        return adj
    Sm = S.copy()
    np.fill_diagonal(Sm, -np.inf)                          # never self-link
    kk = min(k, n - 1)
    # Top-k neighbours per row by similarity (unsorted partition is enough).
    nbr_idx = np.argpartition(-Sm, kk - 1, axis=1)[:, :kk]
    eps = 1e-6
    # Collect directed edges that clear the threshold, then symmetrize via a set.
    edges: Dict[tuple, float] = {}
    for i in range(n):
        for j in nbr_idx[i]:
            j = int(j)
            sim = float(Sm[i, j])
            if not np.isfinite(sim) or sim < thresh:
                continue
            w = (sim - thresh) + eps                       # strictly positive vote
            a, b = (i, j) if i < j else (j, i)
            # Keep the strongest weight if both directions propose the edge.
            prev = edges.get((a, b))
            if prev is None or w > prev:
                edges[(a, b)] = w
    for (a, b), w in edges.items():
        adj[a].append((b, w))
        adj[b].append((a, w))
    return adj


def _run_chinese_whispers(X: np.ndarray, metric: str, seed: int) -> np.ndarray:
    """From-scratch Chinese Whispers (Biemann 2006) — no dlib / networkx.

    1. Every node starts in its own singleton class.
    2. Build a thresholded kNN similarity graph (edges weighted by pair_score).
    3. For ~20 sweeps, visit nodes in a fresh seeded-random order; each node
       adopts the class with the greatest summed edge weight among its
       neighbours (ties broken by a seeded random pick, per the original
       algorithm — deterministic tie-breaks make cliques lock into stable
       oscillating 2-colourings instead of merging). Isolated nodes keep their
       own class. Stop early once a full sweep changes nothing.

    Connected components of the kept graph fall into a single class, so a clean
    per-identity graph yields one cluster per person automatically.
    """
    n = X.shape[0]
    labels = np.arange(n, dtype=np.int64)                  # step 1: unique labels
    if n < 2:
        return labels

    S = _similarity_matrix(X, metric)
    thresh = _CW_COS_THRESH if metric == "cosine" else _CW_L2_THRESH
    adj = _knn_graph(S, _CW_K, thresh)

    rng = np.random.default_rng(seed)
    order = np.arange(n)
    for _ in range(_CW_ITERS):
        rng.shuffle(order)                                 # fresh random order
        changed = False
        for i in order:
            neigh = adj[i]
            if not neigh:
                continue                                   # isolated -> unchanged
            # Sum edge weights per neighbouring class; pick the heaviest class.
            weight_by_label: Dict[int, float] = {}
            for j, w in neigh:
                lbl = int(labels[j])
                weight_by_label[lbl] = weight_by_label.get(lbl, 0.0) + w
            # Heaviest class wins; ties broken by a seeded random choice among
            # the maxima (the canonical CW rule — see docstring).
            top_w = max(weight_by_label.values())
            winners = [lb for lb, w in weight_by_label.items()
                       if w >= top_w - 1e-12]
            best_lbl = (winners[0] if len(winners) == 1
                        else int(rng.choice(winners)))
            if best_lbl != labels[i]:
                labels[i] = best_lbl
                changed = True
        if not changed:
            break                                          # converged

    # Compact label ids to a contiguous 0..K-1 range (purely cosmetic).
    _, compact = np.unique(labels, return_inverse=True)
    return compact.astype(np.int64)


# --------------------------------------------------------------------- evaluate

def evaluate(Xh: np.ndarray, yh: Sequence[str], *, metric: str,
             methods: Sequence[str], seed: int) -> Dict[str, object]:
    """Run the requested clustering ``methods`` and score each vs ground truth.

    Parameters
    ----------
    Xh : (N, D) float array of L2-normalized embeddings (held-out split).
    yh : length-N sequence of ground-truth identity labels.
    metric : 'cosine' or 'l2' — must match the model's scoring metric so the
             clustering geometry agrees with ``common.pair_score``.
    methods : subset of {'chinese_whispers', 'dbscan'} to run.
    seed : RNG seed for reproducible eps sweeps and CW node ordering.

    Returns
    -------
    {
      '<method>': {'ari', 'nmi', 'pairwise_f1': {precision, recall, f1},
                   'n_clusters'},
      ...,
      'n_true_clusters': len(set(yh)),
    }
    Unknown methods are skipped; degenerate inputs yield NaN metrics with
    ``n_clusters`` reflecting whatever partition was produced.
    """
    X = np.asarray(Xh, dtype=np.float32)
    true = np.asarray(list(yh))
    out: Dict[str, object] = {"n_true_clusters": int(len(set(true.tolist())))}

    runners = {
        "dbscan": _run_dbscan,
        "chinese_whispers": _run_chinese_whispers,
    }
    for method in methods:
        run = runners.get(method)
        if run is None:
            continue                                       # ignore unknown method
        pred = run(X, metric, seed)
        out[method] = _score_partition(pred, true, _count_clusters(pred))
    return out
